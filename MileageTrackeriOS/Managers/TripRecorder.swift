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

// MARK: - MKPolyline Coordinate Extraction

extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}

// MARK: - Heuristic Constants (v2)

private enum Heuristic {
    // Speed gates (km/h)
    static let slcSpeedKmh          : Double = 15   // SLC wake → Suspected
    static let promotionSpeedKmh    : Double = 15   // Suspected → Active promotion
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

    // Pedometer
    static let maxStepsDuringPromotion: Int = 40     // "not clearly walking" threshold

    // Pause limits (dynamic)
    static func pauseLimitVisitNoSignal() -> TimeInterval { 0 }
    static func pauseLimitWalking() -> TimeInterval { 30 }
    static func pauseLimitDefault() -> TimeInterval { 3 * 60 }
    static func pauseLimitEngineSoft() -> TimeInterval { 8 * 60 }

    // BT learning
    static let btCorroborationThreshold = 3

    // Recovery
    static let recoveryMaxGap       : TimeInterval = 120

    // Walking suppression after promotion — gives soft engine signal time to build up
    // before the pedometer walking gate can end the trip. Solves fragments where
    // pre-trip walking steps trigger immediate trip ending.
    static let walkingSuppressionWindow: TimeInterval = 60
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
    private weak var liveActivityManager: LiveActivityManager?
    private weak var notificationManager: NotificationManager?
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
    private var promotedAt: Date?       // set on promotion; suppresses walking detection briefly
    private var evaluationTimer: Timer?

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

    // MARK: In-flight Realm trip
    private var inflightTripId: String?  // Realm Trip.id while recording; nil when idle
    private var locationsSinceLastFlush = 0

    /// Whether we're within the post-promotion grace period where early-exit
    /// transitions (pausing, fast-path, walking detection) are suppressed.
    private var inGracePeriod: Bool {
        promotedAt.map { Date().timeIntervalSince($0) < Heuristic.walkingSuppressionWindow } ?? false
    }

    /// Heuristic overrides for testing
    var heuristicMinTripDistance: Double   = Heuristic.minTripDistanceM
    var heuristicMinTripDuration: TimeInterval = Heuristic.minTripDuration

    private let logger = TripLogger.shared

    init() {}

    // MARK: - Setup

    func configure(location: LocationManager, motion: MotionManager,
                   bluetooth: BluetoothManager,
                   liveActivity: LiveActivityManager,
                   notifications: NotificationManager,
                   tripRepo: TripRepository, profileRepo: UserProfileRepository) {
        self.locationManager     = location
        self.motionManager       = motion
        self.bluetoothManager    = bluetooth
        self.liveActivityManager = liveActivity
        self.notificationManager = notifications
        self.tripRepo            = tripRepo
        self.profileRepo         = profileRepo

        location.onLocationUpdate = { [weak self] loc in
            self?.handleLocationUpdate(loc)
        }
        motion.onActivityUpdate = { [weak self] activity in
            self?.handleActivityUpdate(activity)
        }
        motion.onPedometerUpdate = { [weak self] steps in
            self?.pedometerStepsInWindow = steps
            self?.evaluatePedometerGate(steps)
            self?.evaluatePedometerEndTrigger(steps)
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
        recoverInflightTrip()
    }

    // MARK: - Crash Recovery (Realm-backed)

    /// On launch, looks for an in-flight trip left in Realm from a previous run.
    /// If the gap is short enough, resumes it; otherwise force-finalizes or discards.
    private func recoverInflightTrip() {
        guard let tripRepo, let inflight = tripRepo.inflightTrip else { return }

        let pts = tripRepo.tripPoints(for: inflight)
        let locations = pts.map { pt in
            CLLocation(coordinate: CLLocationCoordinate2D(latitude: pt.latitude, longitude: pt.longitude),
                       altitude: pt.altitude, horizontalAccuracy: pt.horizontalAccuracy,
                       verticalAccuracy: -1, course: -1, speed: pt.speedMs, timestamp: pt.recordedAt)
        }
        let gap = Date().timeIntervalSince(inflight.startedAt)

        if gap < Heuristic.recoveryMaxGap {
            collectedLocations = locations
            tripStartedAt = inflight.startedAt
            suspectedAt = inflight.startedAt
            inflightTripId = inflight.id
            activeCarKitName = inflight.carKitName
            let dist = calculateTotalDistance()
            logger.log("Recovery: resuming inflight trip — gap \(Int(gap))s, \(locations.count) pts, \(Int(dist))m", category: .trip)
            transitionTo(.active(startedAt: inflight.startedAt, distanceMetres: dist))
            locationManager?.startHighAccuracyUpdates()
            motionManager?.startPedometerUpdates(from: inflight.startedAt)
            motionManager?.startAltimeterUpdates()
            startEvaluationTimer()
        } else {
            let duration = (locations.last?.timestamp ?? inflight.startedAt).timeIntervalSince(inflight.startedAt)
            let dist = inflight.distanceMetres
            if dist >= heuristicMinTripDistance, duration >= heuristicMinTripDuration {
                collectedLocations = locations
                tripStartedAt = inflight.startedAt
                activeCarKitName = inflight.carKitName
                saveTrip(endedAt: locations.last?.timestamp ?? Date(), distance: dist)
            } else {
                tripRepo.discardInflightTrip(inflight)
            }
            reset()
        }
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

            // Motion-only pause trigger — bridges the gap when GPS is silent.
            if !inGracePeriod, case .active = state,
               activity.isStationary && activity.confidence == .high,
               sustainedStationary(window: 45),
               !softEngineSignal() {
                pauseStart = Date()
                let dist = calculateTotalDistance()
                logger.log("Entering pausing — sustained stationary (motion-only)", category: .trip)
                transitionTo(.pausing(startedAt: tripStartedAt!, distanceMetres: dist, pauseStart: pauseStart!))
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
            logger.log("📍 suspected pt \(detectionBuffer.count): \(String(format:"%.5f", location.coordinate.latitude)),\(String(format:"%.5f", location.coordinate.longitude)) | \(String(format:"%.1f", location.speed * 3.6))km/h ±\(Int(location.horizontalAccuracy))m", category: .location)
            // Re-evaluate promotion on each fix
            if shouldPromote() {
                promoteToActive()
            }

        case .active, .pausing:
            collectedLocations.append(location)
            flushToRealmIfNeeded()
            logger.log("📍 active pt \(collectedLocations.count): \(String(format:"%.5f", location.coordinate.latitude)),\(String(format:"%.5f", location.coordinate.longitude)) | \(String(format:"%.1f", location.speed * 3.6))km/h ±\(Int(location.horizontalAccuracy))m", category: .location)
            let dist = calculateTotalDistance()
            evaluateTransitions(location, distance: dist)
            updateStateDistance(dist)
            // Update Live Activity (throttled internally to every 5s)
            liveActivityManager?.updateTrip(distanceMetres: dist, startedAt: tripStartedAt ?? Date())

        case .ending:
            // Only accept high-accuracy fixes during ending
            if locationManager?.isHighAccuracyActive == true {
                collectedLocations.append(location)
                flushToRealmIfNeeded()
                logger.log("📍 ending pt \(collectedLocations.count): \(String(format:"%.5f", location.coordinate.latitude)),\(String(format:"%.5f", location.coordinate.longitude)) | \(String(format:"%.1f", location.speed * 3.6))km/h ±\(Int(location.horizontalAccuracy))m", category: .location)
            }
        }
    }

    /// Locations buffered during .suspected — prepended to collectedLocations on promotion.
    private var detectionBuffer: [CLLocation] = []

    /// Flushes recent locations to Realm every N points so an in-flight trip
    /// survives crashes. Worst case we lose the last batch (N points).
    private func flushToRealmIfNeeded() {
        guard let tid = inflightTripId, let tripRepo else { return }
        locationsSinceLastFlush += 1
        if locationsSinceLastFlush >= 30 {
            let start = max(0, collectedLocations.count - locationsSinceLastFlush)
            let batch = Array(collectedLocations[start...])
            tripRepo.appendPoints(to: tid, locations: batch)
            locationsSinceLastFlush = 0
        }
    }

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
        if suspectedReason == .carPlay || suspectedReason == .knownCarBT {
            if hardEngineSignal() {
                logger.log("Promotion check: hard engine signal ✅", category: .trip)
                return true
            } else {
                logger.log("Promotion check: hard engine — reason is carPlay/knownCarBT but no hard engine signal", category: .trip)
            }
        }
        // Sustained automotive at high confidence for 30s
        if sustainedAutomotive(window: Heuristic.automotiveSustained, confidence: .high) {
            logger.log("Promotion check: sustained automotive (high) ✅", category: .trip)
            return true
        } else {
            logger.log("Promotion check: sustained automotive (high) — not met", category: .trip)
        }
        // GPS speed > threshold in 20s window + automotive in last 60s
        let speedGate = recentGPSSpeedExceeded(window: 20, thresholdKmh: Heuristic.promotionSpeedKmh)
        let hasAutomotive = automotiveInLast(Heuristic.softSignalWindow)
        if speedGate && hasAutomotive {
            logger.log("Promotion check: speed gate + automotive ✅", category: .trip)
            return true
        } else if speedGate && !hasAutomotive {
            logger.log("Promotion check: speed gate + automotive — speed met but no automotive in window", category: .trip)
        } else if !speedGate && hasAutomotive {
            logger.log("Promotion check: speed gate + automotive — automotive present but speed not met", category: .trip)
        } else {
            logger.log("Promotion check: speed gate + automotive — neither speed nor automotive met", category: .trip)
        }
        // GPS speed > threshold for 2 consecutive readings in 20s window. No pedometer
        // check — pre-trip walking steps contaminate the window, and sustained speed at
        // this level is physically impossible on foot. Requiring 2 consecutive readings
        // filters single-sample GPS noise spikes that briefly breach the threshold.
        let speedGateSustained = recentGPSSpeedExceededConsecutive(window: 20, thresholdKmh: Heuristic.promotionSpeedKmh, count: 2)
        if speedGateSustained {
            logger.log("Promotion check: speed gate (sustained) ✅", category: .trip)
            return true
        } else {
            logger.log("Promotion check: speed gate (sustained) — \(speedGate ? "single reading met but not consecutive" : "no readings above \(Int(Heuristic.promotionSpeedKmh)) km/h")", category: .trip)
        }
        // Distance from suspected start > 250m. Requires "not clearly walking"
        // (< 50 steps / 30s) to avoid promoting cycling or running. Uses a generous
        // threshold because pre-trip walking steps carry into the suspected window.
        let dist = distanceFromSuspectedStart()
        let distMet = dist > Heuristic.promoteDistanceM
        let stepsMet = pedometerStepsInWindow < Heuristic.maxStepsDuringPromotion
        if distMet && stepsMet {
            let d = Int(dist)
            logger.log("Promotion check: distance gate (\(d)m) ✅", category: .trip)
            return true
        } else {
            let d = Int(dist)
            logger.log("Promotion check: distance gate — \(distMet ? "\(d)m ok but" : "\(d)m < \(Int(Heuristic.promoteDistanceM))m")\(stepsMet ? "" : ", steps \(pedometerStepsInWindow) >= \(Heuristic.maxStepsDuringPromotion)")", category: .trip)
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

        promotedAt = Date()
        // Restart pedometer from trip start so pre-trip walking steps
        // don't immediately trigger the 30-step walking gate.
        motionManager?.stopPedometerUpdates()
        motionManager?.startPedometerUpdates(from: tripStartedAt ?? started)
        pedometerStepsInWindow = 0

        // Create the in-flight Realm trip so data survives crashes
        let vehicleId = profileRepo?.defaultVehicle?.id ?? ""
        let firstLoc = collectedLocations.first
        let trip = tripRepo?.beginTrip(
            vehicleId: vehicleId,
            startedAt: tripStartedAt ?? started,
            startLat: firstLoc?.coordinate.latitude ?? 0,
            startLng: firstLoc?.coordinate.longitude ?? 0
        )
        inflightTripId = trip?.id
        // Write initial location batch to Realm
        if let tid = inflightTripId, !collectedLocations.isEmpty {
            tripRepo?.appendPoints(to: tid, locations: collectedLocations)
            locationsSinceLastFlush = 0
        }

        let dist = calculateTotalDistance()
        logger.log("Promoted to active — \(collectedLocations.count) pts, \(Int(dist))m", category: .trip)
        transitionTo(.active(startedAt: tripStartedAt!, distanceMetres: dist))
        beginActiveTripSession()
    }

    /// Shared setup after entering .active — Live Activity, evaluation timer,
    /// battery state tracking, pedometer. Called from both auto-promotion and manual start.
    private func beginActiveTripSession() {
        let vehicle = profileRepo?.defaultVehicle?.name ?? ""
        liveActivityManager?.startTrip(vehicleName: vehicle, startedAt: tripStartedAt ?? Date())
        notificationManager?.sendTripStarted(vehicleName: vehicle)
        startEvaluationTimer()
        if let motion = motionManager, motion.isCharging {
            batteryChargingDuringTrip = true
        } else {
            batteryWasUnpluggedAtTripStart = true
        }
        motionManager?.startPedometerUpdates(from: tripStartedAt ?? Date())
        motionManager?.startAltimeterUpdates()
    }

    private func discardCurrent() {
        // Same as reset() — a suspected phase has no committed trip to protect
        reset()
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
            if !inGracePeriod && speedBelowPause && noProgress {
                if !softEngineSignal() || pedometerStepsInWindow > 30 {
                    pauseStart = now
                    logger.log("Entering pausing — speed stall + no progress", category: .trip)
                    transitionTo(.pausing(startedAt: tripStartedAt!, distanceMetres: distance, pauseStart: pauseStart!))
                }
            }

            // Active → Ending fast-path (v2: requires no soft signal AND corroborator)
            if !inGracePeriod && !softEngineSignal() && speedKmh < Heuristic.pauseSpeedKmh && isSpeedBelow(Heuristic.pauseSpeedKmh, for: Heuristic.fastPathStationary) {
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

        // Pedometer rejection — walking after parking.
        if case .active = state, !inGracePeriod, pedometerStepsInWindow > 30, !softEngineSignal() {
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
        // Collapse to 30s when GPS is stale and motion is stationary —
        // we've likely been parked for a while already.
        if let lastLoc = collectedLocations.last,
           Date().timeIntervalSince(lastLoc.timestamp) > Heuristic.gpsStaleTolerance,
           lastMotionActivity?.isStationary == true {
            return Heuristic.pauseLimitWalking()
        }
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

    // MARK: - Evaluation Timer

    private func startEvaluationTimer() {
        stopEvaluationTimer()
        evaluationTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.evaluateTransitionsOnTimer()
            }
        }
    }

    private func stopEvaluationTimer() {
        evaluationTimer?.invalidate()
        evaluationTimer = nil
    }

    /// Fires every 15s during active/pausing so the state machine can detect
    /// trip end even when iOS throttles background GPS delivery.
    private func evaluateTransitionsOnTimer() {
        let loc = collectedLocations.last ?? locationManager?.lastGoodFix
        guard let lastLoc = loc else { return }
        switch state {
        case .active, .pausing:
            evaluateTransitions(lastLoc, distance: calculateTotalDistance())
        default:
            break
        }
    }

    // MARK: - Pedometer End Trigger

    /// Called on every pedometer update. Triggers trip ending directly from
    /// active state when walking is detected without an engine signal —
    /// independent of GPS delivery so it works when iOS throttles background fixes.
    private func evaluatePedometerEndTrigger(_ steps: Int) {
        guard case .active = state, steps > 30, !softEngineSignal(),
              let promo = promotedAt, Date().timeIntervalSince(promo) >= Heuristic.walkingSuppressionWindow else { return }
        guard let startedAt = tripStartedAt else { return }
        let dist = calculateTotalDistance()
        logger.log("Walking detected without engine signal — ending trip (pedometer trigger)", category: .trip)
        transitionTo(.ending(startedAt: startedAt, distanceMetres: dist, reason: .walkingDetected))
        finaliseAfterTrim()
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

            // Fill implausible gaps with road-snapped MKDirections routes.
            // Handles cold-start GPS delay (anchor→first-fix gap) and mid-trip
            // blackspots. Falls back to raw locations if offline / rate-limited.
            let filled = await self.fillGaps(in: locations)

            // If addresses are empty or gaps couldn't be filled (snap count ≤ raw count),
            // mark the trip as pending so it gets re-processed when connectivity returns.
            let needsReprocess = startAddress.isEmpty || endAddress.isEmpty || filled.count <= locations.count
            let status: TripProcessingStatus = needsReprocess ? .pending : .complete

            // If we have an inflight trip, commit it; otherwise create fresh
            if let inflight = inflightTripId.flatMap({ tripRepo.trip(id: $0) }) {
                tripRepo.commitTrip(
                    inflight, endedAt: endedAt, distanceMetres: distance,
                    locations: filled, startAddress: startAddress, endAddress: endAddress,
                    visitDepartureAt: visitDepartureAt, carKitName: activeCarKitName,
                    processingStatus: status
                )
            } else {
                tripRepo.saveTrip(
                    vehicleId: vehicleId, startedAt: startedAt, endedAt: endedAt,
                    distanceMetres: distance, locations: filled,
                    startAddress: startAddress, endAddress: endAddress,
                    visitDepartureAt: visitDepartureAt, carKitName: activeCarKitName,
                    processingStatus: status
                )
            }
            logger.log("Trip saved ✅ dist:\(Int(distance))m pts:\(filled.count) status:\(status.rawValue)", category: .trip)
        }
    }

    // MARK: - Gap Filling (MKDirections road-snapping)

    /// Scans `locations` for implausible gaps and fills them with road-snapped
    /// intermediate points via MKDirections. Falls back gracefully if offline.
    ///
    /// Thresholds are tuned to only fire on genuine data loss (cold-start GPS delay,
    /// tunnel exits) — not on normal stop-and-go or momentary signal loss.
    /// 500m/30s = 60 km/h, which a car can do easily. We require >50 m/s (>180 km/h)
    /// implied speed to be confident this isn't real driving.
    private func fillGaps(in locations: [CLLocation]) async -> [CLLocation] {
        guard locations.count >= 2 else { return locations }

        var result: [CLLocation] = []
        result.reserveCapacity(locations.count * 2)
        result.append(locations[0])

        for i in 1..<locations.count {
            let prev = result.last!
            let curr = locations[i]
            let timeDelta = curr.timestamp.timeIntervalSince(prev.timestamp)
            let spatialGap = curr.distance(from: prev)

            if spatialGap > 500 && timeDelta > 30 && (spatialGap / max(timeDelta, 1)) > 50 {
                if let snapped = await requestSnappedRoute(from: prev, to: curr) {
                    result.append(contentsOf: snapped)
                }
            }
            result.append(curr)
        }

        return result
    }

    /// Requests a road-snapped route between two locations and returns evenly-spaced
    /// intermediate CLLocation points with interpolated timestamps.
    private func requestSnappedRoute(from start: CLLocation, to end: CLLocation) async -> [CLLocation]? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end.coordinate))
        request.transportType = .automobile

        guard let response = try? await MKDirections(request: request).calculate(),
              let route = response.routes.first else { return nil }

        let coords = route.polyline.coordinates
        guard coords.count >= 2 else { return nil }

        // Cumulative distances along the snapped route
        var dists: [Double] = [0]
        for j in 1..<coords.count {
            let d = CLLocation(latitude: coords[j].latitude, longitude: coords[j].longitude)
                .distance(from: CLLocation(latitude: coords[j-1].latitude, longitude: coords[j-1].longitude))
            dists.append(dists[j-1] + d)
        }
        let totalDist = dists.last!

        // Sample at ~1 Hz to match the original GPS density
        let timeGap = end.timestamp.timeIntervalSince(start.timestamp)
        let sampleCount = max(2, min(Int(timeGap), 120)) // cap at 120 pts per gap
        let step = totalDist / Double(sampleCount - 1)

        var snapped: [CLLocation] = []
        var nextTarget = 0.0
        var segIdx = 0

        for _ in 0..<(sampleCount - 1) {
            nextTarget += step
            while segIdx < dists.count - 1 && dists[segIdx + 1] < nextTarget {
                segIdx += 1
            }
            // Linear interpolation between coords[segIdx] and coords[segIdx + 1]
            let segDist = dists[segIdx + 1] - dists[segIdx]
            let t = segDist > 0 ? (nextTarget - dists[segIdx]) / segDist : 0
            let lat = coords[segIdx].latitude + (coords[segIdx + 1].latitude - coords[segIdx].latitude) * t
            let lng = coords[segIdx].longitude + (coords[segIdx + 1].longitude - coords[segIdx].longitude) * t

            let fraction = Double(snapped.count + 1) / Double(sampleCount)
            let ts = start.timestamp.addingTimeInterval(timeGap * fraction)
            snapped.append(CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                altitude: -1,
                horizontalAccuracy: 5,  // road-snapped — high confidence
                verticalAccuracy: -1,
                course: -1,
                speed: -1,
                timestamp: ts
            ))
        }

        return snapped
    }

    // MARK: - Walking Trim

    private func trimTrailingWalkingFromPolyline() {
        // Walk backward from the end, removing points that look like walking:
        // speed < 5 km/h AND very little movement between consecutive points.
        // Stop at the first point that looks like driving (speed > 10 km/h or
        // meaningful distance from the previous point).
        guard collectedLocations.count > 3 else { return }
        var splitIdx = collectedLocations.count - 1
        while splitIdx > 1 {
            let curr = collectedLocations[splitIdx]
            let prev = collectedLocations[splitIdx - 1]
            let speedKmh = curr.speed >= 0 ? curr.speed * 3.6 : 0
            let stepDist = curr.distance(from: prev)
            if speedKmh > 10 || stepDist > 20 { break } // driving — stop here
            splitIdx -= 1
        }
        let removed = collectedLocations.count - 1 - splitIdx
        if removed > 0 {
            collectedLocations.removeLast(removed)
            logger.log("Trimmed \(removed) trailing walking pts from polyline", category: .trip)
        }
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

    private func sustainedStationary(window: TimeInterval) -> Bool {
        let cutoff = Date().addingTimeInterval(-window)
        let recent = motionHistory.filter { $0.timestamp >= cutoff }
        guard recent.count >= 3 else { return false }
        return recent.allSatisfy { $0.activity.isStationary }
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

    private func recentGPSSpeedExceededConsecutive(window: TimeInterval, thresholdKmh: Double, count: Int) -> Bool {
        let cutoff = Date().addingTimeInterval(-window)
        let locations = (collectedLocations + detectionBuffer)
            .filter { $0.timestamp >= cutoff && $0.speed >= 0 }
            .sorted { $0.timestamp < $1.timestamp }
        guard locations.count >= count else { return false }
        var consecutive = 0
        for loc in locations {
            if loc.speed * 3.6 >= thresholdKmh {
                consecutive += 1
                if consecutive >= count { return true }
            } else {
                consecutive = 0
            }
        }
        return false
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
        // Always store the anchor — it survives even if visit departure already entered Suspected.
        // The visit departure fires first from LocationManager.didExitRegion, so the guard below
        // would otherwise discard the anchor. Storing it unconditionally fixes the ~220m cold-start gap.
        departureAnchorLocation = anchor
        departureAnchorExpiry   = Date().addingTimeInterval(600)

        guard case .idle = state else {
            logger.log("Region departure anchor stored (already \(label(state)))", category: .trip)
            return
        }
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
        liveActivityManager?.endTrip()
        stopEvaluationTimer()
        // Discard in-flight Realm trip if it never met minimum thresholds
        if let tid = inflightTripId, let trip = tripRepo?.trip(id: tid) {
            tripRepo?.discardInflightTrip(trip)
        }
        inflightTripId = nil
        locationsSinceLastFlush = 0
        collectedLocations.removeAll()
        detectionBuffer.removeAll()
        tripStartedAt        = nil
        suspectedAt          = nil
        pauseStart           = nil
        promotedAt           = nil
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

    // MARK: - Distance

    private func calculateTotalDistance() -> Double {
        guard collectedLocations.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<collectedLocations.count {
            total += collectedLocations[i].distance(from: collectedLocations[i-1])
        }
        return total
    }

    // MARK: - Offline Retry

    /// Re-processes trips that were saved while offline (empty addresses, raw GPS).
    /// Called when the app foregrounds or network connectivity is restored.
    func reprocessPendingTrips() {
        guard let tripRepo else { return }
        let pending = tripRepo.pendingTrips
        guard !pending.isEmpty else { return }

        logger.log("Reprocessing \(pending.count) pending trip(s)…", category: .trip)
        let maxRetries = 3

        Task { [weak self] in
            guard let self else { return }
            for trip in pending {
                guard trip.processingRetries < maxRetries else { continue }

                // Rebuild locations from stored TripPoints
                let points = tripRepo.tripPoints(for: trip)
                let locations = points.map { pt in
                    CLLocation(
                        coordinate: CLLocationCoordinate2D(latitude: pt.latitude, longitude: pt.longitude),
                        altitude: pt.altitude,
                        horizontalAccuracy: pt.horizontalAccuracy,
                        verticalAccuracy: -1,
                        course: -1,
                        speed: pt.speedMs,
                        timestamp: pt.recordedAt
                    )
                }

                // Re-resolve addresses
                let startLoc = locations.first
                let endLoc   = locations.last
                let startAddr = await self.resolveAddress(for: startLoc) ?? trip.startAddress
                let endAddr   = await self.resolveAddress(for: endLoc) ?? trip.endAddress

                // Re-run gap filling
                let filled = await self.fillGaps(in: locations)

                let success = !startAddr.isEmpty && !endAddr.isEmpty && filled.count >= locations.count
                if success {
                    tripRepo.updateTrip(trip, startAddress: startAddr, endAddress: endAddr, locations: filled)
                    self.logger.log("Reprocessed ✅ trip \(trip.id.prefix(8))…", category: .trip)
                } else {
                    tripRepo.bumpTripRetry(trip)
                    self.logger.log("Reprocess retry #\(trip.processingRetries + 1) for trip \(trip.id.prefix(8))…", category: .trip)
                }
            }
        }
    }

    // MARK: - Address Resolution

    private func resolveAddress(for coordinate: CLLocation?) async -> String? {
        guard let coordinate,
              let request = MKReverseGeocodingRequest(location: coordinate) else { return nil }
        let mapItem = try? await request.mapItems.first
        return mapItem?.address?.fullAddress
    }

    // MARK: - Manual Trip Controls

    /// Force-start a trip directly into `.active` — skips the Suspected window.
    /// Used by the manual Start Trip button on the Home tab.
    func forceStartManualTrip() {
        guard case .idle = state else {
            logger.log("Manual start ignored — not idle", category: .trip)
            return
        }
        let now = Date()
        suspectedAt = now
        suspectedReason = .motion

        // Use lastGoodFix as the anchor — if nil, fall back to request one-shot
        let anchor = locationManager?.lastGoodFix

        // Start GPS if not already running
        if locationManager?.isHighAccuracyActive != true {
            locationManager?.startHighAccuracyUpdates()
        }

        collectedLocations = anchor.map { [$0] } ?? []
        tripStartedAt = anchor?.timestamp ?? now

        // Create inflight Realm trip
        let vehicleId = profileRepo?.defaultVehicle?.id ?? ""
        let firstLoc = collectedLocations.first
        let trip = tripRepo?.beginTrip(
            vehicleId: vehicleId, startedAt: tripStartedAt!,
            startLat: firstLoc?.coordinate.latitude ?? 0,
            startLng: firstLoc?.coordinate.longitude ?? 0,
            source: .manual
        )
        inflightTripId = trip?.id
        if let tid = inflightTripId, !collectedLocations.isEmpty {
            tripRepo?.appendPoints(to: tid, locations: collectedLocations)
            locationsSinceLastFlush = 0
        }

        let dist = calculateTotalDistance()
        logger.log("Manual trip started — anchor: \(anchor != nil ? "yes" : "no"), \(Int(dist))m", category: .trip)
        transitionTo(.active(startedAt: tripStartedAt!, distanceMetres: dist))
        beginActiveTripSession()
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
