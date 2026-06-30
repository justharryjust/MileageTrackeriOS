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
    static let tunnelToleranceLong  : TimeInterval = 300  // §2.4: extended tolerance when last fix was >40 km/h automotive

    // Distances (metres)
    static let promoteDistanceM     : Double = 250    // Suspected → Active promotion
    static let pauseProgressM       : Double = 50     // Max distance in pause window
    static let minTripDistanceM     : Double = 200    // Minimum trip distance
    static let minTripDuration      : TimeInterval = 60

    // Pedometer
    static let maxStepsDuringPromotion: Int = 40     // "not clearly walking" threshold (main: tightened from 50)
    static let walkingEndStepThreshold: Int = 30     // §6.1: single threshold for walking-end across all paths

    // Pause limits (dynamic)
    static func pauseLimitVisitNoSignal() -> TimeInterval { 0 }
    static func pauseLimitWalking() -> TimeInterval { 30 }
    static func pauseLimitDefault() -> TimeInterval { 3 * 60 }
    static func pauseLimitEngineSoft() -> TimeInterval { 8 * 60 }
    static func pauseLimitMultiStopBusiness() -> TimeInterval { 15 * 60 }  // §2.5: longer pause for known business stops

    // BT learning
    static let btCorroborationThreshold = 3
    static let btSustainedAutomotiveSeconds: TimeInterval = 60   // §1.F: must observe UID during ≥60s automotive

    // Battery soft signal — §1.G: only true when charging started AND remains charging within window
    static let batterySoftSignalWindow: TimeInterval = 5 * 60   // 5 min rolling window

    // Recovery
    static let recoveryMaxGap       : TimeInterval = 120                  // Auto-resume cutoff
    static let recoveryUserPromptMaxGap: TimeInterval = 30 * 60           // §1.E: above this, user is prompted instead of force-finalised

    // Walking suppression after promotion — gives soft engine signal time to build up
    // before the pedometer walking gate can end the trip. Solves fragments where
    // pre-trip walking steps trigger immediate trip ending.
    static let walkingSuppressionWindow: TimeInterval = 60

    // §3.2: discard fixes worse than this unless they're the only data we have
    static let maxAcceptableHorizontalAccuracy: Double = 50
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
    private var odometerRepo: OdometerReadingRepository?
    private var savedAddressRepo: SavedAddressRepository?
    private weak var scheduleManager: TrackingScheduleManager?
    private var mileageCalculator: MileageCalculator?

    // MARK: §3.1 Full polyline snapping toggle
    /// UserDefaults key for opt-in full-polyline MKDirections snapping (§3.1).
    /// Default off — burns more MKDirections quota; valuable for tax-conscious users.
    /// `nonisolated` because the Task in saveTrip reads it from a non-MainActor context.
    nonisolated static let fullPolylineSnappingKey = "com.mileagetracker.fullPolylineSnapping"
    nonisolated static var isFullPolylineSnappingEnabled: Bool {
        UserDefaults.standard.bool(forKey: fullPolylineSnappingKey)
    }

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
    /// §1.G: timestamps of every "started charging" event during the trip.
    /// Soft signal is only true when concurrent with automotive in the last `batterySoftSignalWindow`.
    private var batteryChargingHistory: [Date] = []
    private var batteryWasUnpluggedAtTripStart = false
    /// §1.F: how long each observed BT UID has been active concurrently with automotive motion.
    /// A UID only counts toward learning once it crosses `btSustainedAutomotiveSeconds`.
    private var btObservationStart: [String: Date] = [:]
    private var btObservationAutomotiveSeconds: [String: TimeInterval] = [:]

    // MARK: BT learning (persisted via LearnedStore)
    private var knownCarBTUIDs: Set<String> = []
    private var btCorrelations: [String: Int] = [:]
    /// BT UIDs observed during the current trip (for learning on commit).
    private var currentTripBTObservations: Set<String> = []

    // MARK: Parking hint geofences (LRU, persisted via LearnedStore)
    private var parkingHintsLRU: [CLLocationCoordinate2D] = []
    private let maxParkingHints = 50

    /// §1.D: disk-backed persistence for the learning sets above.
    /// All read on configure(), all written on every mutation.
    private let learnedStore = LearnedStore.shared

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
                   tripRepo: TripRepository, profileRepo: UserProfileRepository,
                   odometerRepo: OdometerReadingRepository,
                   savedAddressRepo: SavedAddressRepository? = nil,
                   scheduleManager: TrackingScheduleManager? = nil,
                   mileageCalculator: MileageCalculator? = nil) {
        self.locationManager     = location
        self.motionManager       = motion
        self.bluetoothManager    = bluetooth
        self.liveActivityManager = liveActivity
        self.notificationManager = notifications
        self.tripRepo            = tripRepo
        self.profileRepo         = profileRepo
        self.odometerRepo        = odometerRepo
        self.savedAddressRepo    = savedAddressRepo
        self.scheduleManager     = scheduleManager
        self.mileageCalculator   = mileageCalculator

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
        // §1.C: re-arm parking hint regions whenever LocationManager drops back to idle
        location.onIdleRecentred = { [weak self] in
            self?.rearmParkingHintRegions()
        }
        bluetooth.onCarKitConnected = { [weak self] event in
            self?.handleCarKitConnected(event)
        }
        bluetooth.onCarKitDisconnected = { [weak self] event in
            self?.handleCarKitDisconnected(event)
        }
        // §1.D: hydrate persisted learning state from disk
        let snapshot = learnedStore.load()
        knownCarBTUIDs    = snapshot.knownCarBTUIDs
        btCorrelations    = snapshot.btCorrelations
        parkingHintsLRU   = snapshot.parkingHints
        logger.log("Learned state loaded — known cars:\(knownCarBTUIDs.count) parking hints:\(parkingHintsLRU.count)", category: .trip)

        // §1.C / §2.1: re-arm multi-region geofences (parking hints + lastGoodFix anchor)
        rearmParkingHintRegions()

        logger.log("TripRecorder configured (v2 state machine)", category: .trip)
        recoverInflightTrip()
    }

    /// §6.8: invariant. Every external trigger handler short-circuits if this fails
    /// — silently swallowing missed config is worse than a noisy log.
    private var isConfigured: Bool {
        locationManager != nil && motionManager != nil && bluetoothManager != nil &&
        tripRepo != nil && profileRepo != nil
    }

    /// Returns true when the user's tracking schedule currently allows new trip detection.
    /// Falls open (true) if no schedule manager is wired — tests + early launch paths.
    /// Only consulted for Idle → Suspected transitions; in-progress trips run regardless.
    private func isWithinTrackingHours() -> Bool {
        guard let scheduler = scheduleManager else { return true }
        return scheduler.isAllowed()
    }

    /// §1.C / §2.1: start monitoring the top N most-frequently-used parking
    /// hints as additional geofences alongside the rolling departure anchor.
    /// iOS allows up to 20 regions per app; we use min(15, hints) and leave
    /// 5 slots for the departure anchor + system reserves.
    private func rearmParkingHintRegions() {
        guard let location = locationManager else { return }
        let topN = Array(parkingHintsLRU.suffix(15))  // most recent are highest-priority
        location.startParkingHintRegions(topN)
    }

    // MARK: - Crash Recovery (Realm-backed)

    /// On launch, looks for an in-flight trip left in Realm from a previous run.
    /// §1.E: three-way recovery — auto-resume <2 min, user-prompt 2–30 min,
    /// finalise-or-discard >30 min.
    /// §6.6: when auto-resuming, also re-attach the Live Activity that the previous
    /// run owned but ended on app exit.
    private func recoverInflightTrip() {
        guard let tripRepo, let inflight = tripRepo.inflightTrip else { return }

        let pts = tripRepo.tripPoints(for: inflight)
        let locations = pts.map { pt in
            CLLocation(coordinate: CLLocationCoordinate2D(latitude: pt.latitude, longitude: pt.longitude),
                       altitude: pt.altitude, horizontalAccuracy: pt.horizontalAccuracy,
                       verticalAccuracy: -1, course: -1, speed: pt.speedMs, timestamp: pt.recordedAt)
        }
        let lastFixAt = locations.last?.timestamp ?? inflight.startedAt
        let gap = Date().timeIntervalSince(lastFixAt)
        let dist = inflight.distanceMetres > 0 ? inflight.distanceMetres : recomputeDistance(from: locations)
        let duration = lastFixAt.timeIntervalSince(inflight.startedAt)

        if gap < Heuristic.recoveryMaxGap {
            // Auto-resume — short gap, likely watchdog/foreground transition
            collectedLocations = locations
            tripStartedAt = inflight.startedAt
            suspectedAt = inflight.startedAt
            inflightTripId = inflight.id
            activeCarKitName = inflight.carKitName
            logger.log("Recovery: resuming inflight trip — gap \(Int(gap))s, \(locations.count) pts, \(Int(dist))m", category: .trip)
            transitionTo(.active(startedAt: inflight.startedAt, distanceMetres: dist))
            locationManager?.startHighAccuracyUpdates()
            motionManager?.startPedometerUpdates(from: inflight.startedAt)
            motionManager?.startAltimeterUpdates()
            startEvaluationTimer()
            // §6.6: re-attach Live Activity — old run terminated without endTrip().
            let vehicle = profileRepo?.defaultVehicle?.name ?? ""
            liveActivityManager?.startTrip(vehicleName: vehicle, startedAt: inflight.startedAt)
            liveActivityManager?.updateTrip(distanceMetres: dist, startedAt: inflight.startedAt)
        } else if gap < Heuristic.recoveryUserPromptMaxGap,
                  dist >= heuristicMinTripDistance,
                  duration >= heuristicMinTripDuration {
            // Long gap but the trip looks real — ask the user instead of force-finalising
            // (a 5-min force-finalise of an in-progress 90-min commute can lose 80+ km).
            logger.log("Recovery: gap \(Int(gap))s exceeds auto-resume, prompting user — \(Int(dist))m \(Int(duration))s", category: .trip)
            notificationManager?.sendTripRecoveryPrompt(distanceMetres: dist, durationSec: duration, inflightId: inflight.id)
            // Stay idle — user decides via notification actions: Resume / Save-as-of-now / Discard
            reset()
        } else if dist >= heuristicMinTripDistance, duration >= heuristicMinTripDuration {
            // >30min gap or fresh app open — save what we have rather than lose it
            collectedLocations = locations
            tripStartedAt = inflight.startedAt
            activeCarKitName = inflight.carKitName
            inflightTripId = inflight.id
            saveTrip(endedAt: lastFixAt, distance: dist, startedAt: inflight.startedAt)
            // saveTrip already detaches inflightTripId; reset() is safe
            reset()
        } else {
            // Below minimums — discard
            tripRepo.discardInflightTrip(inflight)
            reset()
        }
    }

    private func recomputeDistance(from locations: [CLLocation]) -> Double {
        guard locations.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<locations.count {
            total += locations[i].distance(from: locations[i - 1])
        }
        return total
    }

    // MARK: - Activity Handler

    private func handleActivityUpdate(_ activity: DetectedActivity) {
        // Track motion history for rolling window queries
        motionHistory.append((Date(), activity))
        while let first = motionHistory.first, Date().timeIntervalSince(first.timestamp) > Heuristic.softSignalWindow {
            motionHistory.removeFirst()
        }
        lastMotionActivity = activity
        // §1.F: accumulate concurrent automotive-seconds per BT UID
        tickBTAutomotiveAccumulator(activity: activity)

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
                if case .pausing = state, let startedAt = tripStartedAt {
                    logger.log("Automotive resumed during pause — back to active", category: .trip)
                    pauseStart = nil
                    transitionTo(.active(startedAt: startedAt, distanceMetres: calculateTotalDistance()))
                }
            }

            // Motion-only pause trigger — bridges the gap when GPS is silent.
            if !inGracePeriod, case .active = state,
               activity.isStationary && activity.confidence == .high,
               sustainedStationary(window: 45),
               !softEngineSignal(),
               let startedAt = tripStartedAt {
                let ps = Date()
                pauseStart = ps
                let dist = calculateTotalDistance()
                logger.log("Entering pausing — sustained stationary (motion-only)", category: .trip)
                transitionTo(.pausing(startedAt: startedAt, distanceMetres: dist, pauseStart: ps))
            }

        case .ending:
            break
        }
    }

    // MARK: - Location Handler

    private func handleLocationUpdate(_ location: CLLocation) {
        // §3.2: filter low-accuracy fixes — they inflate distance and pollute
        // map matching. Allow when it's the only data we have OR we're stale enough
        // that a poor fix beats none at all (tunnel exit, cold start).
        let acceptByAccuracy: Bool = {
            if location.horizontalAccuracy < 0 { return true }
            if location.horizontalAccuracy <= Heuristic.maxAcceptableHorizontalAccuracy { return true }
            // Last-resort acceptance: no fix at all in last 30s
            let lastFix = collectedLocations.last?.timestamp ?? locationManager?.lastGoodFix?.timestamp
            let staleEnough = lastFix.map { Date().timeIntervalSince($0) > 30 } ?? true
            return staleEnough
        }()
        if !acceptByAccuracy {
            logger.log("Discarding fix — accuracy ±\(Int(location.horizontalAccuracy))m exceeds \(Int(Heuristic.maxAcceptableHorizontalAccuracy))m threshold", category: .location)
            return
        }

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

    /// Single choke-point for every Idle → Suspected transition. Every wake path
    /// (CarPlay, BT, region, visit, motion, SLC) funnels through here, so a guard
    /// at the top reliably enforces the tracking-hours schedule for new trip starts.
    ///
    /// In-progress trips are NEVER affected — they're in `.active`/`.pausing`/`.ending`
    /// and never re-enter this function. `forceStartManualTrip()` also bypasses this gate.
    /// Defence-in-depth: callers that start GPS before this fn (handleRegionDeparture,
    /// handleCarKitConnected) also check `isWithinTrackingHours()` themselves to keep
    /// the blue indicator off when out-of-hours.
    private func enterSuspected(reason: TripRecorderState.SuspectedReason) {
        // Schedule gate: only block FROM .idle. If we're somehow re-entering Suspected
        // from another state, let it through to avoid weird edge cases.
        if case .idle = state, !isWithinTrackingHours() {
            logger.log("Trip start blocked — outside tracking hours (reason was \(reason))", category: .trip)
            return
        }

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
            // §1.G: seed history with the current moment so the soft-signal predicate
            // sees the charging-already-active state.
            batteryChargingHistory.append(Date())
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
        guard let startedAt = tripStartedAt else { return }

        // GPS stale tolerance — don't pause if probably in a tunnel.
        // §2.4: extend tolerance to 5min when last fix was high-speed automotive
        // (suggests we entered a tunnel mid-highway and motion is still automotive).
        if case .active = state,
           let lastLoc = collectedLocations.last,
           lastMotionActivity?.isAutomotive == true {
            let age = now.timeIntervalSince(lastLoc.timestamp)
            let lastSpeedKmh = lastLoc.speed >= 0 ? lastLoc.speed * 3.6 : 0
            let tolerance: TimeInterval = lastSpeedKmh > 40 ? Heuristic.tunnelToleranceLong : Heuristic.gpsStaleTolerance
            if age > tolerance { return }
        }

        switch state {
        case .active:
            let speedBelowPause = isSpeedBelow(speedKmh, for: Heuristic.pauseSpeedWindow)
            let noProgress = distanceProgress(window: Heuristic.pauseProgressWindow) < Heuristic.pauseProgressM

            // Active → Pausing (combined speed + distance stall)
            if !inGracePeriod && speedBelowPause && noProgress {
                if !softEngineSignal() || pedometerStepsInWindow > 30 {
                    let ps = now
                    pauseStart = ps
                    logger.log("Entering pausing — speed stall + no progress", category: .trip)
                    transitionTo(.pausing(startedAt: startedAt, distanceMetres: distance, pauseStart: ps))
                }
            }

            // Active → Ending fast-path (v2: requires no soft signal AND corroborator)
            if !inGracePeriod && !softEngineSignal() && speedKmh < Heuristic.pauseSpeedKmh && isSpeedBelow(Heuristic.pauseSpeedKmh, for: Heuristic.fastPathStationary) {
                let hasCorroborator = pedometerStepsInWindow > 0
                    || visitArrivalRecent(window: Heuristic.softSignalWindow)
                    || stationaryMotionHighConf(window: Heuristic.stationeryMotionConf)
                if hasCorroborator {
                    logger.log("Fast-path ending — no soft signal + corroborator", category: .trip)
                    transitionTo(.ending(startedAt: startedAt, distanceMetres: distance, reason: .fastPath))
                    finaliseAfterTrim()
                }
            }

        case .pausing:
            // Pausing → Active
            if speedKmh > Heuristic.resumeSpeedKmh && isSpeedAbove(Heuristic.resumeSpeedKmh, for: Heuristic.resumeSpeedWindow) {
                logger.log("Speed resumed — back to active", category: .trip)
                pauseStart = nil
                transitionTo(.active(startedAt: startedAt, distanceMetres: distance))
                return
            }

            // Automotive resumed while pausing
            if sustainedAutomotive(window: Heuristic.automotiveRolling, confidence: .medium) {
                logger.log("Automotive resumed during pause — back to active", category: .trip)
                pauseStart = nil
                transitionTo(.active(startedAt: startedAt, distanceMetres: distance))
                return
            }

            // Pausing → Ending (pause limit exceeded)
            if let ps = pauseStart {
                let limit = computePauseLimit()
                if now.timeIntervalSince(ps) >= limit {
                    logger.log("Pause limit exceeded (\(Int(limit))s) — ending trip", category: .trip)
                    transitionTo(.ending(startedAt: startedAt, distanceMetres: distance, reason: .pauseLimitExceeded))
                    finaliseAfterTrim()
                }
            }

        default:
            break
        }

        // §6.1: walking-end rejection consolidated into evaluateWalkingEnd() — single source of truth.
        evaluateWalkingEnd(distance: distance)
    }

    /// Single source of truth for walking-end detection (§6.1). Called from
    /// `evaluateTransitions` (GPS-driven) AND `evaluatePedometerEndTrigger` (pedometer-driven).
    /// Both call sites used to duplicate this logic with subtly different guards.
    private func evaluateWalkingEnd(distance: Double) {
        guard case .active = state, !inGracePeriod, !softEngineSignal() else { return }
        guard pedometerStepsInWindow > Heuristic.walkingEndStepThreshold else { return }
        guard let startedAt = tripStartedAt else { return }
        logger.log("Walking detected without engine signal — ending trip", category: .trip)
        transitionTo(.ending(startedAt: startedAt, distanceMetres: distance, reason: .walkingDetected))
        finaliseAfterTrim()
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
    /// §6.1: delegates to evaluateWalkingEnd() so both GPS- and pedometer-driven
    /// detection paths converge on a single threshold + guard set.
    private func evaluatePedometerEndTrigger(_ steps: Int) {
        guard let promo = promotedAt,
              Date().timeIntervalSince(promo) >= Heuristic.walkingSuppressionWindow else { return }
        evaluateWalkingEnd(distance: calculateTotalDistance())
    }

    // MARK: - Trip Finalisation

    private func finaliseAfterTrim() {
        trimLeadingWalkingFromPolyline()
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

        saveTrip(endedAt: endedAt, distance: dist, startedAt: startedAt)
        reset()
    }

    private func saveTrip(endedAt: Date, distance: Double, startedAt: Date) {
        guard let tripRepo, let profileRepo else { return }

        // Capture EVERYTHING the Task needs into locals BEFORE reset() nils
        // them and discardInflightTrip() deletes the in-flight Realm row.
        // The Task reads only locals — never self.* state that reset() will clear.
        let vehicleId         = profileRepo.defaultVehicle?.id ?? ""
        let vehicleCategory   = profileRepo.defaultVehicle?.defaultCategory ?? .uncategorised
        let locations         = collectedLocations
        let startCoord        = locations.first
        let endCoord          = locations.last
        let capturedInflight  = inflightTripId
        let capturedVisit     = visitDepartureAt
        let capturedCarKit    = activeCarKitName
        let btObservations    = currentTripBTObservations

        // Detach the in-flight ID so reset() does NOT discard the row out from under us
        inflightTripId = nil

        // Learn from this trip (gated by sustained automotive observation — §1.F)
        learnBTCorrelations(observations: btObservations)
        addParkingHintGeofence(endCoord?.coordinate)

        Task { [weak self] in
            guard let self else { return }
            // 30s outer timeout (§6.3) — never let geocoding hang Tasks indefinitely
            let result: (start: String, end: String, filled: [CLLocation])? = await withTaskTimeout(seconds: 30) {
                async let startAddr = self.resolveAddress(for: startCoord)
                async let endAddr   = self.resolveAddress(for: endCoord)
                // §3.3: simplify before further processing — removes 2-5% GPS jitter
                let simplified = await MainActor.run { PolylineProcessor.simplify(locations, epsilonMetres: 4) }
                // §3.1: opt-in full-polyline map matching when user has enabled it.
                // Default to gap-fill only (current behaviour) to preserve quota for casual users.
                let snapped: [CLLocation]
                if TripRecorder.isFullPolylineSnappingEnabled {
                    snapped = await PolylineProcessor.mapMatch(simplified)
                } else {
                    snapped = await self.fillGaps(in: simplified)
                }
                return (await startAddr ?? "", await endAddr ?? "", snapped)
            }
            let startAddress = result?.start ?? ""
            let endAddress   = result?.end ?? ""
            let filled       = result?.filled ?? locations

            // If addresses are empty or gaps couldn't be filled (snap count ≤ raw count),
            // mark the trip as pending so it gets re-processed when connectivity returns.
            let needsReprocess = startAddress.isEmpty || endAddress.isEmpty || filled.count <= locations.count
            let status: TripProcessingStatus = needsReprocess ? .pending : .complete

            // Use the captured ID — never self.inflightTripId (already nil)
            if let inflight = capturedInflight.flatMap({ tripRepo.trip(id: $0) }) {
                tripRepo.commitTrip(
                    inflight, endedAt: endedAt, distanceMetres: distance,
                    locations: filled, startAddress: startAddress, endAddress: endAddress,
                    visitDepartureAt: capturedVisit, carKitName: capturedCarKit,
                    processingStatus: status
                )
                self.applyTripCategorisationAndHash(trip: inflight, vehicleDefault: vehicleCategory, locations: filled)
            } else {
                tripRepo.saveTrip(
                    vehicleId: vehicleId, startedAt: startedAt, endedAt: endedAt,
                    distanceMetres: distance, locations: filled,
                    startAddress: startAddress, endAddress: endAddress,
                    visitDepartureAt: capturedVisit, carKitName: capturedCarKit,
                    processingStatus: status
                )
                if let trip = tripRepo.mostRecentTrip(vehicleId: vehicleId) {
                    self.applyTripCategorisationAndHash(trip: trip, vehicleDefault: vehicleCategory, locations: filled)
                }
            }
            logger.log("Trip saved ✅ dist:\(Int(distance))m pts:\(filled.count) status:\(status.rawValue)", category: .trip)
        }
    }

    /// Applies the categorisation rules engine (§4.1) and writes a tamper-evident
    /// commit hash (§5.2) to a freshly-saved trip. Also runs the odometer
    /// cross-check (§3.4) and same-day stitching pass (§2.5).
    private func applyTripCategorisationAndHash(trip: Trip, vehicleDefault: TripCategory, locations: [CLLocation]) {
        let categoriser = TripCategoriser(
            tripRepo: tripRepo,
            profileRepo: profileRepo,
            savedAddressRepo: savedAddressRepo
        )
        categoriser?.categorise(trip: trip, vehicleDefault: vehicleDefault)
        if let odometerRepo = odometerRepo {
            tripRepo?.crossCheckOdometer(trip: trip, gpsDistanceMetres: trip.distanceMetres, odometerRepo: odometerRepo)
        }
        tripRepo?.writeCommitHash(for: trip, locations: locations)
        tripRepo?.stitchSameDayFragments(around: trip)
    }

    // MARK: - Gap Filling (MKDirections road-snapping)

    /// Scans `locations` for implausible gaps and fills them with road-snapped
    /// intermediate points via MKDirections. §6.4: issues requests concurrently
    /// via TaskGroup, capped by `MKDirectionsRateLimiter` (§6.5). Falls back
    /// gracefully if offline / rate-limited.
    ///
    /// Thresholds are tuned to only fire on genuine data loss (cold-start GPS delay,
    /// tunnel exits) — not on normal stop-and-go or momentary signal loss.
    private func fillGaps(in locations: [CLLocation]) async -> [CLLocation] {
        guard locations.count >= 2 else { return locations }

        // Identify gap indices first — single pass, no MKDirections work
        struct Gap { let index: Int; let from: CLLocation; let to: CLLocation }
        var gaps: [Gap] = []
        for i in 1..<locations.count {
            let prev = locations[i - 1]
            let curr = locations[i]
            let timeDelta = curr.timestamp.timeIntervalSince(prev.timestamp)
            let spatialGap = curr.distance(from: prev)
            if spatialGap > 500 && timeDelta > 30 && (spatialGap / max(timeDelta, 1)) > 50 {
                gaps.append(Gap(index: i, from: prev, to: curr))
            }
        }
        guard !gaps.isEmpty else { return locations }

        // §6.4: dispatch all gap fetches concurrently, preserving order via index.
        // §6.5: each call goes through the shared rate limiter; over-quota calls bail to nil.
        var snapped: [Int: [CLLocation]] = [:]
        await withTaskGroup(of: (Int, [CLLocation]?).self) { group in
            for gap in gaps {
                group.addTask { [gap] in
                    let snap = await self.requestSnappedRoute(from: gap.from, to: gap.to)
                    return (gap.index, snap)
                }
            }
            for await (idx, snap) in group {
                if let snap = snap { snapped[idx] = snap }
            }
        }

        // Stitch back together, inserting snapped runs before the boundary index
        var result: [CLLocation] = []
        result.reserveCapacity(locations.count * 2)
        result.append(locations[0])
        for i in 1..<locations.count {
            if let snap = snapped[i] {
                result.append(contentsOf: snap)
            }
            result.append(locations[i])
        }
        return result
    }

    /// Requests a road-snapped route between two locations and returns evenly-spaced
    /// intermediate CLLocation points with interpolated timestamps.
    /// §6.5: gated through `MKDirectionsRateLimiter` — returns nil when over quota.
    private func requestSnappedRoute(from start: CLLocation, to end: CLLocation) async -> [CLLocation]? {
        guard await MKDirectionsRateLimiter.shared.tryAcquire() else {
            logger.log("MKDirections quota exhausted — skipping snap", category: .trip)
            return nil
        }
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

    /// §1.F: a UID only counts toward learning if it was observed during ≥60s of
    /// concurrent automotive motion. Passenger rides and walk-past BT discovery
    /// no longer "learn" someone else's car. Caller passes the captured snapshot
    /// so this can run after reset() without race.
    private func learnBTCorrelations(observations: Set<String>) {
        var promoted = false
        for uid in observations {
            let auto = btObservationAutomotiveSeconds[uid] ?? 0
            guard auto >= Heuristic.btSustainedAutomotiveSeconds else {
                logger.log("BT UID \(uid.prefix(8))… skipped — only \(Int(auto))s automotive concurrent", category: .trip)
                continue
            }
            btCorrelations[uid, default: 0] += 1
            if btCorrelations[uid, default: 0] >= Heuristic.btCorroborationThreshold {
                knownCarBTUIDs.insert(uid)
                promoted = true
                logger.log("BT UID \(uid.prefix(8))… promoted to known car after \(Heuristic.btCorroborationThreshold) corroborated trips", category: .trip)
            }
        }
        currentTripBTObservations.removeAll()
        btObservationStart.removeAll()
        btObservationAutomotiveSeconds.removeAll()
        if promoted || !observations.isEmpty {
            persistLearnedState()
        }
    }

    /// §1.F: tick the automotive-second counter for every observed BT UID
    /// while motion confirms automotive activity. Called from handleActivityUpdate.
    private func tickBTAutomotiveAccumulator(activity: DetectedActivity) {
        guard activity.isAutomotive, activity.confidence != .low else {
            // Reset open observation windows — automotive paused
            btObservationStart.removeAll()
            return
        }
        guard let uid = activeBTRouteUID else { return }
        let now = Date()
        if let start = btObservationStart[uid] {
            btObservationAutomotiveSeconds[uid, default: 0] += now.timeIntervalSince(start)
            btObservationStart[uid] = now
        } else {
            btObservationStart[uid] = now
        }
    }

    // MARK: - Parking Hint Geofences (§1.C / §2.1 / §1.D)

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
        // §1.D: persist so it survives app kill
        persistLearnedState()
        // §1.C / §2.1: re-arm geofences with the new entry included
        rearmParkingHintRegions()
        logger.log("Parking hint added — LRU now \(parkingHintsLRU.count) entries", category: .trip)
    }

    private func persistLearnedState() {
        learnedStore.save(.init(
            knownCarBTUIDs: knownCarBTUIDs,
            btCorrelations: btCorrelations,
            parkingHints: parkingHintsLRU
        ))
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
        // §1.G: tied to rolling window AND concurrent automotive — see batterySoftSignalActive()
        if batterySoftSignalActive() { return true }
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

        // §2.3: visit departures fire whenever you leave a "place" — including walking out
        // of a building. Suppress automotive-promoting Suspected entry unless we have a
        // corroborating signal: recent automotive motion, hard engine signal, or proximity
        // to a known parking hint within ~150m.
        let recentlyAutomotive = automotiveInLast(120)
        let hasHardEngine = hardEngineSignal()
        let nearKnownParkingHint = isNearKnownParkingHint()
        if !recentlyAutomotive && !hasHardEngine && !nearKnownParkingHint {
            logger.log("CLVisit departure — no automotive corroboration, ignoring (was \(label(state)))", category: .trip)
            return
        }
        logger.log("CLVisit departure — pre-armed for 600s (auto:\(recentlyAutomotive) hard:\(hasHardEngine) hint:\(nearKnownParkingHint))", category: .trip)

        // Visit departure alone can trigger Suspected
        enterSuspected(reason: .visitDeparture)
    }

    /// §2.3 helper: are we currently within ~150m of any saved parking hint?
    /// Used to corroborate visit departures (walking out of a known parking spot is OK).
    private func isNearKnownParkingHint() -> Bool {
        guard let fix = locationManager?.lastGoodFix else { return false }
        let here = CLLocation(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude)
        return parkingHintsLRU.contains { hint in
            let there = CLLocation(latitude: hint.latitude, longitude: hint.longitude)
            return here.distance(from: there) < 150
        }
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
        // Schedule gate — bail BEFORE starting GPS so the blue indicator never flashes outside hours.
        guard isWithinTrackingHours() else {
            logger.log("Region departure outside tracking hours — anchor stored but GPS not started", category: .trip)
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
            // Schedule gate — bail BEFORE starting GPS so the blue indicator never flashes outside hours.
            guard isWithinTrackingHours() else {
                logger.log("Car kit connected outside tracking hours — GPS not started", category: .trip)
                return
            }
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
            // §6.7: when the connect arrives mid-Suspected and it's a known-car BT
            // (hard engine signal), re-evaluate promotion immediately rather than
            // waiting for the 60s window to expire or another GPS fix.
            if case .suspected = state, shouldPromote() {
                promoteToActive()
                return
            }
            if case .pausing = state, let startedAt = tripStartedAt {
                pauseStart = nil
                transitionTo(.active(startedAt: startedAt, distanceMetres: calculateTotalDistance()))
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
                // §1.G: record event timestamp; soft signal predicate intersects with automotive recency.
                batteryChargingHistory.append(Date())
                // Trim history to keep memory bounded
                let cutoff = Date().addingTimeInterval(-Heuristic.batterySoftSignalWindow * 2)
                batteryChargingHistory.removeAll { $0 < cutoff }
                logger.log("Battery began charging at \(Date()) — soft signal eligible if automotive concurrent", category: .trip)
            }
        case .unplugged:
            break
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    /// §1.G: battery counts toward soft signal only if a charging event AND
    /// automotive motion both happened in the last `batterySoftSignalWindow`.
    /// Plugging in at a café after parking no longer holds the trip alive past
    /// the 8-min soft pause limit.
    private func batterySoftSignalActive() -> Bool {
        let cutoff = Date().addingTimeInterval(-Heuristic.batterySoftSignalWindow)
        let recentCharging = batteryChargingHistory.contains { $0 >= cutoff }
        guard recentCharging else { return false }
        return automotiveInLast(Heuristic.batterySoftSignalWindow)
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
        // Discard in-flight Realm trip if it never met minimum thresholds.
        // §1.A: saveTrip() now detaches inflightTripId before reset() runs,
        // so this only fires for paths that bypass saveTrip (suspected discards,
        // recovery discards). The captured trip survives untouched.
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
        batteryChargingHistory.removeAll()
        batteryWasUnpluggedAtTripStart = false
        currentTripBTObservations.removeAll()
        btObservationStart.removeAll()
        btObservationAutomotiveSeconds.removeAll()
        carPlayConnected     = false
        locationManager?.stopHighAccuracyUpdates()
        motionManager?.stopPedometerUpdates()
        motionManager?.stopAltimeterUpdates()
        transitionTo(.idle)
    }

    // MARK: - §3.5 Trim leading walking

    /// Walk forward from index 0, removing points classified as walking
    /// (speed < 5 km/h AND step <20m to the next). Stops at the first driving point.
    /// Mirrors `trimTrailingWalkingFromPolyline()` for symmetry — cold starts often
    /// capture walking-to-the-car which inflates apparent distance.
    private func trimLeadingWalkingFromPolyline() {
        guard collectedLocations.count > 3 else { return }
        var splitIdx = 0
        while splitIdx < collectedLocations.count - 2 {
            let curr = collectedLocations[splitIdx]
            let next = collectedLocations[splitIdx + 1]
            let speedKmh = curr.speed >= 0 ? curr.speed * 3.6 : 0
            let stepDist = curr.distance(from: next)
            if speedKmh > 10 || stepDist > 20 { break } // driving — stop here
            splitIdx += 1
        }
        if splitIdx > 0 {
            collectedLocations.removeFirst(splitIdx)
            // Re-anchor tripStartedAt to the new first point so duration stays accurate
            tripStartedAt = collectedLocations.first?.timestamp ?? tripStartedAt
            logger.log("Trimmed \(splitIdx) leading walking pts from polyline", category: .trip)
        }
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
    /// Dispatches manual trips through a dedicated route-snapping path.
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

                if trip.source == .manual {
                    await self.reprocessManualTrip(trip)
                    continue
                }

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

    /// Re-processes a pending manual trip by chaining road-snapped routes between
    /// each consecutive pair of waypoints, then updating the stored TripPoints.
    private func reprocessManualTrip(_ trip: Trip) async {
        guard let tripRepo else { return }

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
        guard locations.count >= 2 else {
            tripRepo.bumpTripRetry(trip)
            return
        }

        // Re-resolve addresses
        let startAddr = await self.resolveAddress(for: locations.first) ?? trip.startAddress
        let endAddr   = await self.resolveAddress(for: locations.last) ?? trip.endAddress

        // Chain snapped routes through each consecutive pair
        var snappedLocations: [CLLocation] = []
        var totalDistance: Double = 0

        for i in 0..<(locations.count - 1) {
            guard let legSnapped = await requestSnappedRoute(from: locations[i], to: locations[i + 1]),
                  !legSnapped.isEmpty else {
                tripRepo.bumpTripRetry(trip)
                logger.log("Manual trip reprocess: leg \(i) failed — retrying later", category: .trip)
                return
            }
            totalDistance += legSnapped.last?.distance(from: legSnapped.first ?? locations[i]) ?? 0
            if snappedLocations.isEmpty {
                snappedLocations = legSnapped
            } else {
                snappedLocations.append(contentsOf: legSnapped.dropFirst())
            }
        }

        guard !snappedLocations.isEmpty else {
            tripRepo.bumpTripRetry(trip)
            return
        }

        // Update the trip with road-snapped data and corrected distance
        tripRepo.updateTrip(trip, startAddress: startAddr, endAddress: endAddr, locations: snappedLocations)
        // Override the distance with the true driving distance from route data
        tripRepo.storeDistance(totalDistance, for: trip)

        // Recalculate dollar value using the corrected road-snapped distance
        if let profile = profileRepo?.profile {
            let fuelType = profileRepo?.defaultVehicle?.fuelType ?? .petrol
            let cumulativeKm = tripRepo.cumulativeBusinessKm(before: trip)
            let value = mileageCalculator?.dollarValue(
                for: trip,
                profile: profile,
                fuelType: fuelType,
                cumulativeKm: cumulativeKm
            ) ?? 0
            tripRepo.storeDollarValue(value, for: trip)
        }

        logger.log("Manual trip reprocessed ✅ id:\(trip.id.prefix(8)) dist:\(Int(totalDistance))m pts:\(snappedLocations.count)", category: .trip)
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
        let started = anchor?.timestamp ?? now
        tripStartedAt = started

        // Create inflight Realm trip
        let vehicleId = profileRepo?.defaultVehicle?.id ?? ""
        let firstLoc = collectedLocations.first
        let trip = tripRepo?.beginTrip(
            vehicleId: vehicleId, startedAt: started,
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
        transitionTo(.active(startedAt: started, distanceMetres: dist))
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

    // MARK: - §6.3 Task Timeout

    /// Runs `body` with a hard timeout. Returns nil if the work doesn't finish in time.
    /// Used to bound the Task in `saveTrip` so reverse-geocoding or MKDirections hangs
    /// can't leak Task lifetime across app foreground/background cycles.
    private func withTaskTimeout<T: Sendable>(seconds: Double, _ body: @escaping @Sendable () async -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask {
                await body()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            // Take whichever finishes first; cancel the rest
            let first = await group.next()
            group.cancelAll()
            return first ?? nil
        }
    }
}
