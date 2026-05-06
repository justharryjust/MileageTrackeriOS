// TripRecorder — Core trip detection state machine (v2)
//
// STATE MACHINE:
//  Idle → Suspected → Active ↔ Pausing → Ending → (Committed | Discarded) → Idle
//
// SIGNAL FUSION:
//  • Hard engine signal: CarPlay connected OR learned-car BT audio route active.
//  • Soft engine signal: hard signal OR (automotive ≥ high + speed > 15 km/h within 60s)
//    OR battery state became charging during trip.
//  • The state machine reads soft signal almost everywhere; hard signal is only
//    needed for the cold-start primary trigger (Idle → Suspected).
//
// TRIP START (Idle → Suspected — any one trigger):
//  1. CarPlay connected
//  2. Learned-car BT audio route activated
//  3. CLMonitor exit of home/work or learned parking-hint geofence
//  4. CLVisit departure
//  5. CMMotionActivity automotive ≥ medium for 15s rolling
//  6. SLC fix with speed > 22 km/h and motion not stationary
//
// TRIP END:
//  • Active → Pausing: speed < 5 km/h for 30s AND distance < 50m in 60s
//  • Pausing → Ending: dynamic pauseLimit (0s–8 min based on context)
//  • Active → Ending fast-path: no soft signal + speed < 5 + corroborator
//  • Pedometer steps > 30 in 30s → force Ending (walking detected)

import Foundation
import CoreLocation
import CoreMotion
import MapKit
import UIKit

// MARK: - Heuristic Constants (v2)

private enum Heuristic {
    // Speed gates (km/h)
    static let slcSpeedKmh          : Double = 22   // SLC wake → Suspected
    static let promotionSpeedKmh    : Double = 25   // Suspected → Active promotion
    static let pauseSpeedKmh        : Double = 5    // Active → Pausing threshold
    static let resumeSpeedKmh       : Double = 15   // Pausing → Active resume
    static let softSignalSpeedKmh   : Double = 15   // Minimum for soft engine signal

    // Windows (seconds)
    static let suspectedWindow      : TimeInterval = 60
    static let automotiveRolling    : TimeInterval = 15   // Idle → Suspected
    static let automotiveSustained  : TimeInterval = 30   // Suspected → Active promotion
    static let softSignalWindow     : TimeInterval = 60   // Recency for soft engine signal
    static let pauseSpeedWindow     : TimeInterval = 30   // Speed < threshold for pause
    static let pauseProgressWindow  : TimeInterval = 60   // Distance progress check
    static let resumeSpeedWindow    : TimeInterval = 10   // Speed > threshold for resume
    static let fastPathStationary   : TimeInterval = 5    // Stationary before fast-path
    static let stationeryMotionConf : TimeInterval = 15   // Motion = stationary high-conf
    static let gpsStaleTolerance    : TimeInterval = 60   // Don't pause if GPS silent but automotive

    // Distances (metres)
    static let promoteDistanceM     : Double = 250    // Suspected → Active promotion
    static let pauseProgressM       : Double = 50     // Max distance in pause window
    static let minTripDistanceM     : Double = 200    // Minimum trip distance
    static let minTripDuration      : TimeInterval = 60

    // Pause limits (dynamic)
    static func pauseLimitVisitNoSignal() -> TimeInterval { 0 }
    static func pauseLimitWalking() -> TimeInterval { 30 }
    static func pauseLimitDefault() -> TimeInterval { 3 * 60 }
    static func pauseLimitEngineSoft() -> TimeInterval { 8 * 60 }

    // BT learning
    static let btCorroborationThreshold = 3

    // Recovery
    static let recoveryMaxGap       : TimeInterval = 120
}

// MARK: - Trip Checkpoint (crash / kill recovery)

private struct TripCheckpoint: Codable {
    struct StoredLocation: Codable {
        let latitude: Double
        let longitude: Double
        let altitude: Double
        let speedMs: Double
        let horizontalAccuracy: Double
        let timestamp: Date

        var clLocation: CLLocation {
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                altitude: altitude,
                horizontalAccuracy: horizontalAccuracy,
                verticalAccuracy: -1,
                course: -1,
                speed: speedMs,
                timestamp: timestamp
            )
        }

        init(_ loc: CLLocation) {
            latitude           = loc.coordinate.latitude
            longitude          = loc.coordinate.longitude
            altitude           = loc.altitude
            speedMs            = loc.speed
            horizontalAccuracy = loc.horizontalAccuracy
            timestamp          = loc.timestamp
        }
    }

    enum Phase: String, Codable { case suspected, active, pausing, ending }

    let phase: Phase
    let tripStartedAt: Date
    let suspectedAt: Date?
    let pauseStart: Date?
    let stoppedAt: Date?
    let distanceMetres: Double
    let locations: [StoredLocation]
    let visitDepartureAt: Date?
    let activeCarKitName: String?
    let knownCarBTUIDs: [String]
    let btCorrelations: [String: Int]
    let parkingHintLats: [Double]
    let parkingHintLngs: [Double]
    let batteryChargingDuringTrip: Bool
}

// MARK: - TripRecorder

@Observable
@MainActor
final class TripRecorder {
    static let shared = TripRecorder()

    // MARK: Public state
    private(set) var state: TripRecorderState = .idle

    // MARK: Injected dependencies
    private weak var locationManager: LocationManager?
    private weak var motionManager: MotionManager?
    private weak var bluetoothManager: BluetoothManager?
    private var tripRepo: TripRepository?
    private var profileRepo: UserProfileRepository?

    // MARK: Trip buffer
    var collectedLocations: [CLLocation] = []
    var tripStartedAt: Date?

    // MARK: Suspected state tracking
    private var suspectedAt: Date?
    private var suspectedReason: TripRecorderState.SuspectedReason = .motion
    private var promotionTimer: Timer?

    // MARK: Pausing state tracking
    private var pauseStart: Date?

    // MARK: Signal state
    private var carPlayConnected = false
    private var activeBTRouteUID: String?
    private var lastMotionActivity: DetectedActivity?
    private var motionHistory: [(timestamp: Date, activity: DetectedActivity)] = []
    private var batteryChargingDuringTrip = false
    private var batteryWasUnpluggedAtTripStart = false

    // MARK: BT learning
    private var knownCarBTUIDs: Set<String> = []
    private var btCorrelations: [String: Int] = [:]
    /// BT UIDs observed during the current trip (for learning on commit).
    private var currentTripBTObservations: Set<String> = []

    // MARK: Parking hint geofences (LRU)
    private var parkingHintsLRU: [CLLocationCoordinate2D] = []
    private let maxParkingHints = 50

    // MARK: Pedometer / altimeter
    private var pedometerStepsInWindow: Int = 0

    // MARK: Checkpoint
    private var locationsSinceLastCheckpoint = 0

    /// Heuristic overrides for testing
    var heuristicMinTripDistance: Double   = Heuristic.minTripDistanceM
    var heuristicMinTripDuration: TimeInterval = Heuristic.minTripDuration

    private let logger = TripLogger.shared

    init() {}

    // MARK: - Setup

    func configure(location: LocationManager, motion: MotionManager,
                   bluetooth: BluetoothManager,
                   tripRepo: TripRepository, profileRepo: UserProfileRepository) {
        self.locationManager  = location
        self.motionManager    = motion
        self.bluetoothManager = bluetooth
        self.tripRepo         = tripRepo
        self.profileRepo      = profileRepo

        location.onLocationUpdate = { [weak self] loc in
            self?.handleLocationUpdate(loc)
        }
        motion.onActivityUpdate = { [weak self] activity in
            self?.handleActivityUpdate(activity)
        }
        motion.onPedometerUpdate = { [weak self] steps in
            self?.pedometerStepsInWindow = steps
            self?.evaluatePedometerGate(steps)
        }
        motion.onAltimeterUpdate = { _ in
            // Altimeter data is logged but not yet used for gating.
            // Reserved for future garage/elevator false-start rejection.
        }
        motion.onBatteryStateChange = { [weak self] state in
            self?.handleBatteryStateChange(state)
        }
        location.onVisitDeparture = { [weak self] departureDate in
            self?.handleVisitDeparture(departureDate)
        }
        location.onVisitArrival = { [weak self] in
            self?.handleVisitArrival()
        }
        location.onRegionDeparture = { [weak self] anchor in
            self?.handleRegionDeparture(anchor)
        }
        location.onBackgroundWake = { [weak self] since in
            self?.motionManager?.queryRecentActivity(since: since)
        }
        bluetooth.onCarKitConnected = { [weak self] event in
            self?.handleCarKitConnected(event)
        }
        bluetooth.onCarKitDisconnected = { [weak self] event in
            self?.handleCarKitDisconnected(event)
        }
        logger.log("TripRecorder configured (v2 state machine)", category: .trip)
        recoverFromCheckpoint()
    }

    // MARK: - Bootstrap / Recovery

    private func recoverFromCheckpoint() {
        guard let data = try? Data(contentsOf: Self.checkpointURL),
              let checkpoint = try? JSONDecoder().decode(TripCheckpoint.self, from: data) else { return }

        // Restore learned state
        knownCarBTUIDs = Set(checkpoint.knownCarBTUIDs)
        btCorrelations  = checkpoint.btCorrelations
        parkingHintsLRU = zip(checkpoint.parkingHintLats, checkpoint.parkingHintLngs).map {
            CLLocationCoordinate2D(latitude: $0, longitude: $1)
        }
        batteryChargingDuringTrip = checkpoint.batteryChargingDuringTrip

        let locations = checkpoint.locations.map { $0.clLocation }
        let gap = Date().timeIntervalSince(checkpoint.tripStartedAt)

        switch checkpoint.phase {
        case .suspected:
            clearCheckpoint()
            logger.log("Checkpoint: suspected phase discarded — no confirmed trip", category: .trip)

        case .active, .pausing:
            if gap < Heuristic.recoveryMaxGap {
                // Resume the in-flight trip
                collectedLocations = locations
                tripStartedAt = checkpoint.tripStartedAt
                suspectedAt = checkpoint.suspectedAt
                pauseStart = checkpoint.pauseStart
                activeCarKitName = checkpoint.activeCarKitName
                let dist = calculateTotalDistance()
                logger.log("Checkpoint: resuming trip — gap \(Int(gap))s, \(locations.count) pts, \(Int(dist))m", category: .trip)

                if checkpoint.phase == .pausing {
                    transitionTo(.pausing(startedAt: checkpoint.tripStartedAt, distanceMetres: dist, pauseStart: checkpoint.pauseStart ?? Date()))
                } else {
                    transitionTo(.active(startedAt: checkpoint.tripStartedAt, distanceMetres: dist))
                }
                // Re-start GPS and sensors
                locationManager?.startHighAccuracyUpdates()
                motionManager?.startPedometerUpdates(from: checkpoint.tripStartedAt)
                motionManager?.startAltimeterUpdates()
            } else {
                // Gap too long — force-finalize
                logger.log("Checkpoint: gap \(Int(gap))s exceeds recovery window — force-finalizing", category: .trip)
                forceFinalize(checkpoint: checkpoint, locations: locations)
            }

        case .ending:
            // Trip was already ending — finalize it
            forceFinalize(checkpoint: checkpoint, locations: locations)
        }
    }

    private func forceFinalize(checkpoint: TripCheckpoint, locations: [CLLocation]) {
        let dist = checkpoint.distanceMetres
        let endedAt = checkpoint.stoppedAt ?? locations.last?.timestamp ?? Date()
        let duration = endedAt.timeIntervalSince(checkpoint.tripStartedAt)

        guard dist >= heuristicMinTripDistance, duration >= heuristicMinTripDuration else {
            logger.log("Checkpoint: recovered trip too short — discarded", category: .trip)
            clearCheckpoint()
            reset()
            return
        }

        collectedLocations = locations
        tripStartedAt = checkpoint.tripStartedAt
        activeCarKitName = checkpoint.activeCarKitName
        saveTrip(endedAt: endedAt, distance: dist)
        clearCheckpoint()
        reset()
    }

    // MARK: - Activity Handler

    private func handleActivityUpdate(_ activity: DetectedActivity) {
        // Track motion history for rolling window queries
        motionHistory.append((Date(), activity))
        while let first = motionHistory.first, Date().timeIntervalSince(first.timestamp) > Heuristic.softSignalWindow {
            motionHistory.removeFirst()
        }
        lastMotionActivity = activity

        switch state {
        case .idle:
            guard activity.isAutomotive else { return }
            let geofenceArmed = departureAnchorExpiry.map { Date() < $0 } ?? false
            let carKitArmed   = carKitConnectExpiry.map { Date() < $0 } ?? false

            // Low-confidence automotive is accepted when backed by geofence/car-kit
            if activity.confidence == .low && !geofenceArmed && !carKitArmed { return }

            // Require 15s rolling automotive at ≥ medium
            guard rollingAutomotiveDuration(confidence: .medium) >= Heuristic.automotiveRolling else { return }

            let reason: TripRecorderState.SuspectedReason = carKitArmed ? .carPlay : geofenceArmed ? .geofenceExit : .motion
            enterSuspected(reason: reason)

        case .suspected:
            // If automotive drops to stationary/other during suspected, let the 60s timer handle it
            break

        case .active, .pausing:
            if activity.isAutomotive && activity.confidence != .low {
                // Automotive resumed — if pausing, go back to active
                if case .pausing = state {
                    logger.log("Automotive resumed during pause — back to active", category: .trip)
                    pauseStart = nil
                    transitionTo(.active(startedAt: tripStartedAt!, distanceMetres: calculateTotalDistance()))
                }
            }

        case .ending:
            break
        }
    }

    // MARK: - Location Handler

    private func handleLocationUpdate(_ location: CLLocation) {
        switch state {
        case .idle:
            // Check for SLC-speed trigger with pre-arm
            let geofenceLive = departureAnchorExpiry.map { Date() < $0 } ?? false
            let carKitLive   = carKitConnectExpiry.map { Date() < $0 } ?? false
            guard geofenceLive || carKitLive else {
                if locationManager?.isHighAccuracyActive == true {
                    locationManager?.stopHighAccuracyUpdates()
                }
                return
            }
            guard location.speed >= 0, location.speed * 3.6 >= Heuristic.slcSpeedKmh else { return }
            guard lastMotionActivity?.isStationary != true else { return }
            let reason: TripRecorderState.SuspectedReason = geofenceLive ? .geofenceExit : .carPlay
            enterSuspected(reason: reason)

        case .suspected:
            guard location.speed >= 0 else { return }
            // Buffer locations during suspected window
            detectionBuffer.append(location)
            // Re-evaluate promotion on each fix
            if shouldPromote() {
                promoteToActive()
            }

        case .active, .pausing:
            collectedLocations.append(location)
            let dist = calculateTotalDistance()
            evaluateTransitions(location, distance: dist)
            updateStateDistance(dist)

        case .ending:
            // Only accept high-accuracy fixes during ending
            if locationManager?.isHighAccuracyActive == true {
                collectedLocations.append(location)
            }
        }
    }

    /// Locations buffered during .suspected — prepended to collectedLocations on promotion.
    private var detectionBuffer: [CLLocation] = []

    // MARK: - Suspected

    private func enterSuspected(reason: TripRecorderState.SuspectedReason) {
        suspectedAt = Date()
        suspectedReason = reason
        detectionBuffer.removeAll()

        // Anchor start to the departure anchor (geofence/visit), lastGoodFix, or request a one-shot.
        // Don't request a one-shot if we already have a departure anchor — it's wasteful and
        // the anchor is more authoritative than whatever GPS returns cold.
        let hasAnchor = departureAnchorLocation != nil || locationManager?.lastGoodFix != nil
        if !hasAnchor {
            locationManager?.requestOneShotLocation()
        }

        transitionTo(.suspected(since: suspectedAt!, reason: reason))
        logger.log("Entering suspected — reason: \(reason)", category: .trip)

        // Start high-frequency GPS
        locationManager?.startHighAccuracyUpdates()

        // Start pedometer & altimeter
        motionManager?.startPedometerUpdates(from: suspectedAt!)
        motionManager?.startAltimeterUpdates()

        // Schedule promotion check at 60s
        promotionTimer = Timer.scheduledTimer(withTimeInterval: Heuristic.suspectedWindow, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.promotionCheck()
            }
        }
    }

    private func promotionCheck() {
        guard case .suspected = state else { return }
        if shouldPromote() {
            promoteToActive()
        } else {
            logger.log("Suspected window expired — discarding", category: .trip)
            discardCurrent()
        }
    }

    private func shouldPromote() -> Bool {
        // Hard engine signal + primary trigger → immediate promote
        if (suspectedReason == .carPlay || suspectedReason == .knownCarBT) && hardEngineSignal() {
            return true
        }
        // Sustained automotive at high confidence for 30s
        if sustainedAutomotive(window: Heuristic.automotiveSustained, confidence: .high) {
            return true
        }
        // GPS speed > 25 km/h sustained 20s with automotive in last 60s
        if recentGPSSpeedExceeded(window: 20, thresholdKmh: Heuristic.promotionSpeedKmh)
            && automotiveInLast(Heuristic.softSignalWindow) {
            return true
        }
        // Distance from suspected start > 250m and no walking
        if distanceFromSuspectedStart() > Heuristic.promoteDistanceM && pedometerStepsInWindow == 0 {
            return true
        }
        return false
    }

    private func promoteToActive() {
        guard let started = suspectedAt else { return }
        promotionTimer?.invalidate()
        promotionTimer = nil

        // Prefer the departure anchor (geofence center / visit departure coordinate)
        // over lastGoodFix. GPS needs warm-up time, so lastGoodFix can be well after
        // the actual trip start. The departure anchor is where the car was parked.
        let anchor = departureAnchorLocation ?? locationManager?.lastGoodFix
        departureAnchorLocation = nil
        departureAnchorExpiry = nil
        collectedLocations = (anchor.map { [$0] } ?? []) + detectionBuffer
        detectionBuffer.removeAll()
        tripStartedAt = collectedLocations.first?.timestamp ?? started

        let dist = calculateTotalDistance()
        logger.log("Promoted to active — \(collectedLocations.count) pts, \(Int(dist))m", category: .trip)
        transitionTo(.active(startedAt: tripStartedAt!, distanceMetres: dist))

        // Track battery state for "became charging during trip" signal
        if let motion = motionManager, motion.isCharging {
            batteryChargingDuringTrip = true
        } else {
            batteryWasUnpluggedAtTripStart = true
        }
    }

    private func discardCurrent() {
        promotionTimer?.invalidate()
        promotionTimer = nil
        detectionBuffer.removeAll()
        locationManager?.stopHighAccuracyUpdates()
        motionManager?.stopPedometerUpdates()
        motionManager?.stopAltimeterUpdates()
        clearTripState()
        transitionTo(.idle)
    }

    // MARK: - Transition Evaluation (Active / Pausing / Ending)

    private func evaluateTransitions(_ location: CLLocation, distance: Double) {
        let speedKmh = location.speed >= 0 ? location.speed * 3.6 : 0
        let now = Date()

        // GPS stale tolerance — don't pause if probably in a tunnel
        if case .active = state,
           let lastLoc = collectedLocations.last,
           now.timeIntervalSince(lastLoc.timestamp) > Heuristic.gpsStaleTolerance,
           lastMotionActivity?.isAutomotive == true {
            return
        }

        switch state {
        case .active:
            let speedBelowPause = isSpeedBelow(speedKmh, for: Heuristic.pauseSpeedWindow)
            let noProgress = distanceProgress(window: Heuristic.pauseProgressWindow) < Heuristic.pauseProgressM

            // Active → Pausing (combined speed + distance stall)
            if speedBelowPause && noProgress {
                if !softEngineSignal() || pedometerStepsInWindow > 30 {
                    pauseStart = now
                    logger.log("Entering pausing — speed stall + no progress", category: .trip)
                    transitionTo(.pausing(startedAt: tripStartedAt!, distanceMetres: distance, pauseStart: pauseStart!))
                }
            }

            // Active → Ending fast-path (v2: requires no soft signal AND corroborator)
            if !softEngineSignal() && speedKmh < Heuristic.pauseSpeedKmh && isSpeedBelow(Heuristic.pauseSpeedKmh, for: Heuristic.fastPathStationary) {
                let hasCorroborator = pedometerStepsInWindow > 0
                    || visitArrivalRecent(window: Heuristic.softSignalWindow)
                    || stationaryMotionHighConf(window: Heuristic.stationeryMotionConf)
                if hasCorroborator {
                    logger.log("Fast-path ending — no soft signal + corroborator", category: .trip)
                    transitionTo(.ending(startedAt: tripStartedAt!, distanceMetres: distance, reason: .fastPath))
                    finaliseAfterTrim()
                }
            }

        case .pausing:
            // Pausing → Active
            if speedKmh > Heuristic.resumeSpeedKmh && isSpeedAbove(Heuristic.resumeSpeedKmh, for: Heuristic.resumeSpeedWindow) {
                logger.log("Speed resumed — back to active", category: .trip)
                pauseStart = nil
                transitionTo(.active(startedAt: tripStartedAt!, distanceMetres: distance))
                return
            }

            // Automotive resumed while pausing
            if sustainedAutomotive(window: Heuristic.automotiveRolling, confidence: .medium) {
                logger.log("Automotive resumed during pause — back to active", category: .trip)
                pauseStart = nil
                transitionTo(.active(startedAt: tripStartedAt!, distanceMetres: distance))
                return
            }

            // Pausing → Ending (pause limit exceeded)
            if let ps = pauseStart {
                let limit = computePauseLimit()
                if now.timeIntervalSince(ps) >= limit {
                    logger.log("Pause limit exceeded (\(Int(limit))s) — ending trip", category: .trip)
                    transitionTo(.ending(startedAt: tripStartedAt!, distanceMetres: distance, reason: .pauseLimitExceeded))
                    finaliseAfterTrim()
                }
            }

        default:
            break
        }

        // Pedometer rejection — walking after parking (applies in both active and pausing)
        if case .active = state, pedometerStepsInWindow > 30, !softEngineSignal() {
            logger.log("Walking detected without engine signal — ending trip", category: .trip)
            transitionTo(.ending(startedAt: tripStartedAt!, distanceMetres: distance, reason: .walkingDetected))
            finaliseAfterTrim()
        }
    }

    private func evaluatePedometerGate(_ steps: Int) {
        // Called on every pedometer update. If walking is detected during suspected
        // and we have no engine signal, bias toward discard at promotion check.
        guard case .suspected = state else { return }
        if steps > 30 && !hardEngineSignal() {
            logger.log("Pedometer steps > 30 during suspected, no hard engine — may discard at timeout", category: .trip)
        }
    }

    // MARK: - Pause Limit (Dynamic)

    private func computePauseLimit() -> TimeInterval {
        if visitArrivalRecent(window: 60) && !softEngineSignal() {
            return Heuristic.pauseLimitVisitNoSignal()
        }
        if pedometerStepsInWindow > 30 {
            return Heuristic.pauseLimitWalking()
        }
        if softEngineSignal() {
            return Heuristic.pauseLimitEngineSoft()
        }
        return Heuristic.pauseLimitDefault()
    }

    // MARK: - Trip Finalisation

    private func finaliseAfterTrim() {
        trimTrailingWalkingFromPolyline()
        guard let startedAt = tripStartedAt else { return }
        let dist = calculateTotalDistance()
        let endedAt = collectedLocations.last?.timestamp ?? Date()
        let duration = endedAt.timeIntervalSince(startedAt)

        guard dist >= heuristicMinTripDistance, duration >= heuristicMinTripDuration else {
            logger.log("Trip too short after trim (dist:\(Int(dist))m dur:\(Int(duration))s) — discarded", category: .trip)
            reset()
            return
        }

        saveTrip(endedAt: endedAt, distance: dist)
        reset()
    }

    private func saveTrip(endedAt: Date, distance: Double) {
        guard let startedAt = tripStartedAt, let tripRepo, let profileRepo else { return }

        let vehicleId = profileRepo.defaultVehicle?.id ?? ""
        let startCoord = collectedLocations.first
        let endCoord   = collectedLocations.last
        // Capture a copy now — reset() clears collectedLocations before the Task runs
        let locations  = collectedLocations

        // Learn from this trip
        learnBTCorrelations()
        addParkingHintGeofence(endCoord?.coordinate)

        Task { [weak self] in
            guard let self else { return }
            let startAddress = await resolveAddress(for: startCoord) ?? ""
            let endAddress   = await resolveAddress(for: endCoord) ?? ""

            tripRepo.saveTrip(
                vehicleId:        vehicleId,
                startedAt:        startedAt,
                endedAt:          endedAt,
                distanceMetres:   distance,
                locations:        locations,
                startAddress:     startAddress,
                endAddress:       endAddress,
                visitDepartureAt: visitDepartureAt,
                carKitName:       activeCarKitName
            )
            logger.log("Trip saved ✅ dist:\(Int(distance))m pts:\(locations.count)", category: .trip)
        }
    }

    // MARK: - Walking Trim

    private func trimTrailingWalkingFromPolyline() {
        // Remove trailing locations that were recorded while the user was walking
        // after parking. Walk backward from the end, removing any location where
        // the motion was classified as walking.
        guard collectedLocations.count > 2 else { return }
        var splitIdx = collectedLocations.count - 1
        // Look for the last non-walking activity in the motion history
        if let lastNonWalking = motionHistory.last(where: { !$0.activity.isAutomotive && $0.activity.type != .walking }) {
            // Keep everything up to and including the last non-walking timestamp
            while splitIdx > 0 && collectedLocations[splitIdx].timestamp > lastNonWalking.timestamp {
                splitIdx -= 1
            }
        }
        if splitIdx < collectedLocations.count - 1 && splitIdx > 0 {
            let removed = collectedLocations.count - 1 - splitIdx
            collectedLocations.removeLast(removed)
            logger.log("Trimmed \(removed) trailing walking pts from polyline", category: .trip)
        }
    }

    // MARK: - Validation

    private func validate(distance: Double, duration: TimeInterval) -> Bool {
        guard distance >= heuristicMinTripDistance else { return false }
        guard duration >= heuristicMinTripDuration else { return false }
        // Dominant activity must not be cycling or walking
        let automotiveCount = motionHistory.filter { $0.activity.isAutomotive }.count
        let cyclingCount    = motionHistory.filter { $0.activity.type == .cycling }.count
        let walkingCount    = motionHistory.filter { $0.activity.type == .walking }.count
        if cyclingCount > automotiveCount || walkingCount > automotiveCount { return false }
        // Check for implausible speeds (> 250 km/h)
        let maxSpeed = collectedLocations.map { $0.speed >= 0 ? $0.speed * 3.6 : 0 }.max() ?? 0
        if maxSpeed > 250 { return false }
        return true
    }

    // MARK: - BT Learning

    private func learnBTCorrelations() {
        for uid in currentTripBTObservations {
            btCorrelations[uid, default: 0] += 1
            if btCorrelations[uid, default: 0] >= Heuristic.btCorroborationThreshold {
                knownCarBTUIDs.insert(uid)
                logger.log("BT UID \(uid.prefix(8))… promoted to known car after \(Heuristic.btCorroborationThreshold) corroborated trips", category: .trip)
            }
        }
        currentTripBTObservations.removeAll()
    }

    // MARK: - Parking Hint Geofences

    private func addParkingHintGeofence(_ coordinate: CLLocationCoordinate2D?) {
        guard let coord = coordinate, CLLocationCoordinate2DIsValid(coord) else { return }
        // Avoid duplicates within ~50m
        let tooClose = parkingHintsLRU.contains {
            let loc1 = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let loc2 = CLLocation(latitude: $0.latitude, longitude: $0.longitude)
            return loc1.distance(from: loc2) < 50
        }
        guard !tooClose else { return }

        parkingHintsLRU.append(coord)
        while parkingHintsLRU.count > maxParkingHints {
            parkingHintsLRU.removeFirst()
        }
        logger.log("Parking hint added — LRU now \(parkingHintsLRU.count) entries", category: .trip)
    }

    // MARK: - Engine Signal Predicates

    private func hardEngineSignal() -> Bool {
        return carPlayConnected || knownCarBTRouteActive()
    }

    private func softEngineSignal() -> Bool {
        if hardEngineSignal() { return true }
        if sustainedAutomotive(window: Heuristic.softSignalWindow, confidence: .high)
            && recentGPSSpeedAverage(window: Heuristic.softSignalWindow) > Heuristic.softSignalSpeedKmh {
            return true
        }
        if batteryChargingDuringTrip { return true }
        return false
    }

    private func knownCarBTRouteActive() -> Bool {
        guard let uid = activeBTRouteUID else { return false }
        return knownCarBTUIDs.contains(uid)
    }

    // MARK: - Motion Window Helpers

    private func rollingAutomotiveDuration(confidence: CMMotionActivityConfidence = .medium) -> TimeInterval {
        // Return how long ago the oldest automotive sample in the rolling window was recorded.
        // If the oldest is from ≥15s ago, automotive has been sustained for at least 15s.
        let cutoff = Date().addingTimeInterval(-Heuristic.automotiveRolling)
        let relevant = motionHistory.filter {
            $0.timestamp >= cutoff
            && $0.activity.isAutomotive
            && $0.activity.confidence.rawValue >= confidence.rawValue
        }
        guard let oldest = relevant.first?.timestamp else { return 0 }
        return Date().timeIntervalSince(oldest)
    }

    private func sustainedAutomotive(window: TimeInterval, confidence: CMMotionActivityConfidence) -> Bool {
        let cutoff = Date().addingTimeInterval(-window)
        let recent = motionHistory.filter { $0.timestamp >= cutoff }
        guard !recent.isEmpty else { return false }
        let automotiveSamples = recent.filter { $0.activity.isAutomotive && $0.activity.confidence.rawValue >= confidence.rawValue }
        return automotiveSamples.count >= max(1, recent.count / 2) // majority of samples
    }

    private func automotiveInLast(_ window: TimeInterval) -> Bool {
        let cutoff = Date().addingTimeInterval(-window)
        return motionHistory.contains { $0.timestamp >= cutoff && $0.activity.isAutomotive }
    }

    private func stationaryMotionHighConf(window: TimeInterval) -> Bool {
        let cutoff = Date().addingTimeInterval(-window)
        let recent = motionHistory.filter { $0.timestamp >= cutoff }
        guard !recent.isEmpty else { return false }
        return recent.allSatisfy { $0.activity.isStationary && $0.activity.confidence == .high }
    }

    // MARK: - GPS Window Helpers

    private func recentGPSSpeedExceeded(window: TimeInterval, thresholdKmh: Double) -> Bool {
        let cutoff = Date().addingTimeInterval(-window)
        let recent = collectedLocations.filter { $0.timestamp >= cutoff && $0.speed >= 0 }
        guard !recent.isEmpty else {
            // Check detection buffer during suspected
            let buf = detectionBuffer.filter { $0.timestamp >= cutoff && $0.speed >= 0 }
            return buf.contains { $0.speed * 3.6 >= thresholdKmh }
        }
        return recent.contains { $0.speed * 3.6 >= thresholdKmh }
    }

    private func recentGPSSpeedAverage(window: TimeInterval) -> Double {
        let cutoff = Date().addingTimeInterval(-window)
        let recent = collectedLocations.filter { $0.timestamp >= cutoff && $0.speed >= 0 }
        guard !recent.isEmpty else { return 0 }
        return recent.map { $0.speed * 3.6 }.reduce(0, +) / Double(recent.count)
    }

    private func isSpeedBelow(_ thresholdKmh: Double, for window: TimeInterval) -> Bool {
        let cutoff = Date().addingTimeInterval(-window)
        let recent = collectedLocations.filter { $0.timestamp >= cutoff && $0.speed >= 0 }
        guard !recent.isEmpty else { return true } // no data = assume stopped
        return recent.allSatisfy { $0.speed * 3.6 < thresholdKmh }
    }

    private func isSpeedAbove(_ thresholdKmh: Double, for window: TimeInterval) -> Bool {
        let cutoff = Date().addingTimeInterval(-window)
        let recent = collectedLocations.filter { $0.timestamp >= cutoff && $0.speed >= 0 }
        guard !recent.isEmpty else { return false }
        return recent.contains { $0.speed * 3.6 > thresholdKmh }
    }

    private func distanceProgress(window: TimeInterval) -> Double {
        let cutoff = Date().addingTimeInterval(-window)
        let recent = collectedLocations.filter { $0.timestamp >= cutoff }
        guard recent.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<recent.count {
            total += recent[i].distance(from: recent[i-1])
        }
        return total
    }

    private func distanceFromSuspectedStart() -> Double {
        guard suspectedAt != nil else { return 0 }
        let relevant = detectionBuffer + collectedLocations
        guard relevant.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<relevant.count {
            total += relevant[i].distance(from: relevant[i-1])
        }
        return total
    }

    // MARK: - Visit / Region Handlers

    private var visitDepartureAt: Date?
    private var visitDepartureExpiry: Date?
    private var visitArrivedAt: Date?

    private func handleVisitDeparture(_ departureDate: Date) {
        guard case .idle = state else { return }
        visitDepartureAt     = departureDate
        visitDepartureExpiry = Date().addingTimeInterval(600) // 10 min window
        logger.log("CLVisit departure — pre-armed for 600s", category: .trip)

        // Visit departure alone can trigger Suspected
        enterSuspected(reason: .visitDeparture)
    }

    private func handleVisitArrival() {
        visitArrivedAt = Date()
        logger.log("CLVisit arrival recorded", category: .trip)
    }

    private func visitArrivalRecent(window: TimeInterval) -> Bool {
        guard let arrival = visitArrivedAt else { return false }
        return Date().timeIntervalSince(arrival) <= window
    }

    private var departureAnchorLocation: CLLocation?
    private var departureAnchorExpiry: Date?

    private func handleRegionDeparture(_ anchor: CLLocation) {
        guard case .idle = state else {
            logger.log("Region departure ignored — not idle", category: .trip)
            return
        }
        departureAnchorLocation = anchor
        departureAnchorExpiry   = Date().addingTimeInterval(600)
        logger.log("Region departure anchor stored — starting GPS", category: .trip)
        locationManager?.startHighAccuracyUpdates()
        enterSuspected(reason: .geofenceExit)
    }

    // MARK: - Car Kit Handlers

    var activeCarKitName: String?
    private var carKitConnectExpiry: Date?

    private func handleCarKitConnected(_ event: CarKitEvent) {
        activeCarKitName = event.deviceName
        carPlayConnected = true

        // Track BT UID for learning
        if let uid = event.portUID {
            activeBTRouteUID = uid
            currentTripBTObservations.insert(uid)
        }

        switch state {
        case .idle:
            carKitConnectExpiry = Date().addingTimeInterval(600)
            logger.log("Car kit connected (\"\(event.deviceName)\") — pre-armed, starting GPS", category: .trip)
            locationManager?.startHighAccuracyUpdates()
            // If this is a known car BT, trigger immediately
            if knownCarBTUIDs.contains(event.portUID ?? "") {
                enterSuspected(reason: .knownCarBT)
            } else {
                enterSuspected(reason: .carPlay)
            }

        case .suspected, .active, .pausing:
            logger.log("Car kit connected mid-trip — refreshing hard signal", category: .trip)
            if case .pausing = state {
                // Car came back — resume
                pauseStart = nil
                transitionTo(.active(startedAt: tripStartedAt!, distanceMetres: calculateTotalDistance()))
            }

        case .ending:
            break
        }
    }

    private func handleCarKitDisconnected(_ event: CarKitEvent) {
        logger.log("Car kit disconnected (\"\(event.deviceName)\")", category: .trip)
        carPlayConnected = false
        activeBTRouteUID = nil
        carKitConnectExpiry = nil

        // v2: do NOT collapse pause limit on disconnect alone.
        // Soft signal (motion + speed recency, charging) may still hold the trip alive.
        // Fast-path Ending will only fire if speed drops AND no soft signal remains.
        // No explicit action needed here.
    }

    // MARK: - Battery State Handler

    private func handleBatteryStateChange(_ state: UIDevice.BatteryState) {
        switch state {
        case .charging, .full:
            if batteryWasUnpluggedAtTripStart {
                batteryChargingDuringTrip = true
                logger.log("Battery began charging during trip — soft engine signal activated", category: .trip)
            }
        case .unplugged:
            break
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    // MARK: - State Transition

    func transitionTo(_ newState: TripRecorderState) {
        let old = state
        state = newState
        logger.log("State: \(label(old)) → \(label(newState))", category: .trip)
        checkpointIfNeeded(from: old, to: newState)
    }

    private func updateStateDistance(_ dist: Double) {
        switch state {
        case .active(let s, _):
            state = .active(startedAt: s, distanceMetres: dist)
        case .pausing(let s, _, let ps):
            state = .pausing(startedAt: s, distanceMetres: dist, pauseStart: ps)
        case .ending(let s, _, let r):
            state = .ending(startedAt: s, distanceMetres: dist, reason: r)
        default:
            break
        }
    }

    private func label(_ s: TripRecorderState) -> String {
        switch s {
        case .idle:                                    return "idle"
        case .suspected(let d, let r):                 return "suspected(\(Int(abs(d.timeIntervalSinceNow)))s \(r))"
        case .active(_, let dist):                     return "active(\(Int(dist))m)"
        case .pausing(_, let dist, let ps):            return "pausing(\(Int(dist))m paused \(Int(abs(ps.timeIntervalSinceNow)))s)"
        case .ending(_, let dist, let r):              return "ending(\(Int(dist))m \(r))"
        }
    }

    // MARK: - Reset

    private func reset() {
        clearCheckpoint()
        collectedLocations.removeAll()
        detectionBuffer.removeAll()
        tripStartedAt        = nil
        suspectedAt          = nil
        pauseStart           = nil
        visitDepartureAt     = nil
        visitDepartureExpiry = nil
        visitArrivedAt       = nil
        departureAnchorLocation = nil
        departureAnchorExpiry   = nil
        activeCarKitName     = nil
        carKitConnectExpiry  = nil
        activeBTRouteUID     = nil
        batteryChargingDuringTrip = false
        batteryWasUnpluggedAtTripStart = false
        currentTripBTObservations.removeAll()
        carPlayConnected     = false
        locationManager?.stopHighAccuracyUpdates()
        motionManager?.stopPedometerUpdates()
        motionManager?.stopAltimeterUpdates()
        transitionTo(.idle)
    }

    private func clearTripState() {
        suspectedAt = nil
        pauseStart = nil
        tripStartedAt = nil
        detectionBuffer.removeAll()
        collectedLocations.removeAll()
        visitDepartureAt = nil
        visitDepartureExpiry = nil
        visitArrivedAt = nil
        departureAnchorLocation = nil
        departureAnchorExpiry = nil
        activeCarKitName = nil
        carKitConnectExpiry = nil
        batteryChargingDuringTrip = false
        batteryWasUnpluggedAtTripStart = false
        currentTripBTObservations.removeAll()
    }

    // MARK: - Distance

    private func calculateTotalDistance() -> Double {
        guard collectedLocations.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<collectedLocations.count {
            total += collectedLocations[i].distance(from: collectedLocations[i-1])
        }
        return total
    }

    // MARK: - Address Resolution

    private func resolveAddress(for coordinate: CLLocation?) async -> String? {
        guard let coordinate,
              let request = MKReverseGeocodingRequest(location: coordinate) else { return nil }
        let mapItem = try? await request.mapItems.first
        return mapItem?.address?.fullAddress
    }

    // MARK: - Checkpoint Persistence

    private static let checkpointURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("trip_checkpoint.json")
    }()

    private func checkpointIfNeeded(from old: TripRecorderState, to new: TripRecorderState) {
        switch new {
        case .idle:
            break // reset() calls clearCheckpoint()
        case .active, .pausing:
            if case .active = old, case .active = new {
                locationsSinceLastCheckpoint += 1
                if locationsSinceLastCheckpoint >= 10 {
                    locationsSinceLastCheckpoint = 0
                    saveCheckpoint()
                }
            } else {
                locationsSinceLastCheckpoint = 0
                saveCheckpoint()
            }
        default:
            saveCheckpoint()
        }
    }

    private func saveCheckpoint() {
        let phase: TripCheckpoint.Phase
        let startedAt: Date
        let stoppedAt: Date?
        let distance: Double
        let ps: Date?

        switch state {
        case .active(let s, let d):
            phase = .active; startedAt = s; stoppedAt = nil; distance = d; ps = nil
        case .pausing(let s, let d, let p):
            phase = .pausing; startedAt = s; stoppedAt = nil; distance = d; ps = p
        case .ending(let s, let d, _):
            phase = .ending; startedAt = s; stoppedAt = Date(); distance = d; ps = pauseStart
        case .suspected(let s, _):
            phase = .suspected; startedAt = s; stoppedAt = nil; distance = 0; ps = nil
        case .idle: return
        }

        let checkpoint = TripCheckpoint(
            phase: phase,
            tripStartedAt: startedAt,
            suspectedAt: suspectedAt,
            pauseStart: ps,
            stoppedAt: stoppedAt,
            distanceMetres: distance,
            locations: collectedLocations.map { TripCheckpoint.StoredLocation($0) },
            visitDepartureAt: visitDepartureAt,
            activeCarKitName: activeCarKitName,
            knownCarBTUIDs: Array(knownCarBTUIDs),
            btCorrelations: btCorrelations,
            parkingHintLats: parkingHintsLRU.map { $0.latitude },
            parkingHintLngs: parkingHintsLRU.map { $0.longitude },
            batteryChargingDuringTrip: batteryChargingDuringTrip
        )
        do {
            let data = try JSONEncoder().encode(checkpoint)
            try data.write(to: Self.checkpointURL, options: .atomic)
        } catch {
            logger.log("Checkpoint save failed: \(error)", category: .system)
        }
    }

    private func clearCheckpoint() {
        try? FileManager.default.removeItem(at: Self.checkpointURL)
    }

    // MARK: - Force Finalise (Debug)

    func forceFinaliseFromDebug() {
        guard let startedAt = tripStartedAt else { return }
        let dist = calculateTotalDistance()
        logger.log("Force finalise from debug — dist: \(Int(dist))m", category: .trip)
        transitionTo(.ending(startedAt: startedAt, distanceMetres: dist, reason: .userForced))
        finaliseAfterTrim()
    }
}
