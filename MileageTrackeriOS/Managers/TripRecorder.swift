// TripRecorder — Core trip detection state machine
// See DevelopmentPlan §3.1 for heuristics rationale.
//
// STATE TRANSITIONS:
//  idle ──► detecting ──► recording ──► ending ──► idle (trip saved)
//
// DETECTION IMPROVEMENTS:
//  • Only medium/high confidence automotive activity triggers state transitions (item 1)
//  • CLVisit departure pre-arms a "visit departed" flag used as a secondary confirmation (item 2)
//  • GPS drops to significant-location during .ending resume window (item 6)
//  • visitDepartureAt is stored in the saved Trip for accurate start anchoring (item 7)

import Foundation
import CoreLocation
import CoreMotion

// MARK: - Heuristic Constants

private enum Heuristic {
 static let minSpeedKmh               : Double       = 8
 static let detectionWindowSeconds    : TimeInterval = 30
 static let stationaryEndWindowSeconds: TimeInterval = 120
 static let resumeWindowSeconds       : TimeInterval = 90
 static let minimumTripDistanceMetres : Double       = 200
 static let minimumTripDurationSeconds: TimeInterval = 60
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

 // MARK: Private tracking
 var collectedLocations: [CLLocation] = []
 /// Locations buffered during .detecting — prepended to collectedLocations on trip confirmation
 var detectionBuffer: [CLLocation] = []
 var stationaryTimer: Timer?
 private var detectionTimer: Timer?
 var tripStartedAt: Date?
 /// Highest valid speed seen during the current detection window — used as the
 /// confirmation gate instead of instantaneous speed to survive traffic lights and cold starts.
 var peakSpeedKmhDuringDetection: Double = 0
 /// When true, the detection window is halved because a strong pre-arm signal is present
 private var fastTrackDetection: Bool = false

 /// Set when a CLVisit departure fires — used as a secondary confirmation signal
 var visitDepartureAt: Date?
 var visitDepartureExpiry: Date?
 private let visitDepartureWindowSeconds: TimeInterval = 600

 /// Name of the car kit that pre-armed or is active during this trip, stored on save
 var activeCarKitName: String?
 /// Pre-arm expiry for car-kit connect signal (same window as visit departure)
 var carKitConnectExpiry: Date?
 private let carKitPreArmWindowSeconds: TimeInterval = 600

 /// Heuristic overrides — set to lower values in tests to bypass timing constraints
 var heuristicDetectionWindow: TimeInterval  = Heuristic.detectionWindowSeconds
 var heuristicMinSpeedKmh: Double            = Heuristic.minSpeedKmh
 var heuristicMinTripDistance: Double        = Heuristic.minimumTripDistanceMetres
 var heuristicMinTripDuration: TimeInterval  = Heuristic.minimumTripDurationSeconds

 private let logger = TripLogger.shared

 /// Designated init — use TripRecorder.shared in production.
 /// An internal init() allows tests to create isolated instances.
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
        location.onVisitDeparture = { [weak self] departureDate in
            self?.handleVisitDeparture(departureDate)
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
        logger.log("TripRecorder configured with repositories", category: .trip)
 }

 // MARK: - Car Kit Handlers

 private func handleCarKitConnected(_ event: CarKitEvent) {
     // Store the name regardless of state so it's available at trip save time
     activeCarKitName = event.deviceName

     switch state {
     case .idle:
         // Pre-arm: set a 10-minute window. If automotive motion arrives within
         // that window the trip start is anchored to the connect time.
         carKitConnectExpiry = Date().addingTimeInterval(carKitPreArmWindowSeconds)
         logger.log("Car kit connected (\"\(event.deviceName)\") — pre-armed for \(Int(carKitPreArmWindowSeconds))s", category: .trip)

     case .detecting, .recording, .ending:
         logger.log("Car kit connected (\"\(event.deviceName)\") mid-trip — name recorded", category: .trip)
     }
 }

 private func handleCarKitDisconnected(_ event: CarKitEvent) {
     logger.log("Car kit disconnected (\"\(event.deviceName)\")", category: .trip)
     carKitConnectExpiry = nil

     switch state {
     case .recording(let startedAt, let distance):
         // Engine off / left the car — immediately start the end window rather
         // than waiting for the motion heuristic to catch up.
         logger.log("Car kit disconnect during recording — starting end timer immediately", category: .trip)
         cancelStationaryTimer()
         startStationaryTimer(recordingStartedAt: startedAt, distance: distance)

     case .detecting:
         // User connected then immediately disconnected without a confirmed trip —
         // abort detection.
         logger.log("Car kit disconnect during detecting — aborting detection", category: .trip)
         cancelDetectionTimer()
         detectionBuffer.removeAll()
         peakSpeedKmhDuringDetection = 0
         fastTrackDetection          = false
         locationManager?.stopHighAccuracyUpdates()
         transitionTo(.idle)

     default:
         break
     }
 }

 // MARK: - Visit Departure Handler (item 2)

 private func handleVisitDeparture(_ departureDate: Date) {
     guard case .idle = state else {
         logger.log("CLVisit departure ignored — not idle (state: \(label(state)))", category: .trip)
         return
     }
     visitDepartureAt     = departureDate
     visitDepartureExpiry = Date().addingTimeInterval(visitDepartureWindowSeconds)
     logger.log("CLVisit departure recorded at \(departureDate) — pre-armed for \(Int(visitDepartureWindowSeconds))s", category: .trip)
 }

 /// Returns the current visit departure if still within the validity window, then clears it.
 private func consumeVisitDeparture() -> Date? {
     guard let expiry = visitDepartureExpiry, Date() < expiry else {
         visitDepartureAt     = nil
         visitDepartureExpiry = nil
         return nil
     }
     let departure = visitDepartureAt
     visitDepartureAt     = nil
     visitDepartureExpiry = nil
     return departure
 }

 // MARK: - Activity Handler

  private func handleActivityUpdate(_ activity: DetectedActivity) {
      switch state {
      case .idle:
          // Item 1: require at least medium confidence to avoid buses/trams/elevators
          guard activity.isAutomotive, activity.confidence != .low else {
              if activity.isAutomotive {
                  logger.log("Low-confidence automotive, ignored — not entering detecting", category: .trip)
              } else {
                  logger.log("Not automotive, ignored — not entering detecting", category: .trip)
              }
              return
          }
          // Log whether a visit departure or car-kit is backing this signal
          let visitBacked  = visitDepartureExpiry.map { Date() < $0 } ?? false
          let carKitBacked = carKitConnectExpiry.map { Date() < $0 } ?? false
          // Fast-track: halve the detection window when a strong pre-arm signal is present
          fastTrackDetection = visitBacked || carKitBacked
          logger.log("Automotive detected (conf:\(activity.confidence == .high ? "high" : "medium"), visitBacked:\(visitBacked), carKitBacked:\(carKitBacked), fastTrack:\(fastTrackDetection)) — entering detecting", category: .trip)
          transitionTo(.detecting(since: Date()))
          startDetectionTimer()
          locationManager?.startHighAccuracyUpdates()

      case .detecting(let since):
          if !activity.isAutomotive && activity.isStationary && activity.confidence != .low {
              let elapsed = Date().timeIntervalSince(since)
              if elapsed < Heuristic.detectionWindowSeconds {
                  logger.log("Automotive lost during detection (\(Int(elapsed))s) — back to idle", category: .trip)
                  cancelDetectionTimer()
                  detectionBuffer.removeAll()
                  peakSpeedKmhDuringDetection = 0
                  fastTrackDetection          = false
                  locationManager?.stopHighAccuracyUpdates()
                  transitionTo(.idle)
              }
          }

      case .recording(let startedAt, let distance):
          // Item 1: only act on stationary/non-automotive if confidence is not low
          if activity.confidence != .low &&
             (activity.isStationary || (!activity.isAutomotive)) {
              logger.log("Non-automotive in recording (conf:\(activity.confidence == .high ? "high" : "medium")) — starting end timer", category: .trip)
              cancelStationaryTimer()
              startStationaryTimer(recordingStartedAt: startedAt, distance: distance)
          } else if activity.isAutomotive {
              cancelStationaryTimer()
          }

      case .ending(let recordingStart, _, let distance):
          // Item 1: only resume on medium/high confidence
          if activity.isAutomotive && activity.confidence != .low {
              logger.log("Automotive resumed — back to recording", category: .trip)
              cancelStationaryTimer()
              // Item 6: re-enable high accuracy now that we're recording again
              locationManager?.startHighAccuracyUpdates()
              transitionTo(.recording(startedAt: recordingStart, distanceMetres: distance))
          }
      }
  }

 // MARK: - Location Handler

 private func handleLocationUpdate(_ location: CLLocation) {
     switch state {
     case .detecting(let since):
         // Option C: guard against invalid/cold-start speed values.
         // CLLocation returns speed = -1 when unavailable (GPS warming up).
         // These fixes are not useful for speed tracking or route buffering.
         guard location.speed >= 0 else {
             logger.log("Detecting — skipping fix with unknown speed (GPS cold start)", category: .trip)
             return
         }

         let speedKmh = location.speed * 3.6
         let elapsed  = Date().timeIntervalSince(since)

         // Option A: track peak speed across all fixes, not just the current one.
         // This survives traffic lights, slow-start, and the 30s boundary falling mid-stop.
         if speedKmh > peakSpeedKmhDuringDetection {
             peakSpeedKmhDuringDetection = speedKmh
         }

         // Option B: fast-track halves the required window when a strong pre-arm is present
         let requiredWindow = fastTrackDetection ? heuristicDetectionWindow / 2 : heuristicDetectionWindow

         logger.log("Detecting — speed: \(String(format:"%.1f",speedKmh)) km/h, peak: \(String(format:"%.1f",peakSpeedKmhDuringDetection)) km/h, elapsed: \(Int(elapsed))s/\(Int(requiredWindow))s, buffered: \(detectionBuffer.count) pts", category: .trip)

         if peakSpeedKmhDuringDetection >= heuristicMinSpeedKmh && elapsed >= requiredWindow {
             logger.log("Trip start confirmed ✅ — peak speed \(String(format:"%.1f",peakSpeedKmhDuringDetection)) km/h over \(Int(elapsed))s, prepending \(detectionBuffer.count) detection pts", category: .trip)
             cancelDetectionTimer()
             collectedLocations = detectionBuffer + [location]
             detectionBuffer.removeAll()
             tripStartedAt = collectedLocations.first?.timestamp ?? Date()
             transitionTo(.recording(startedAt: tripStartedAt!, distanceMetres: calculateTotalDistance()))
         } else {
             detectionBuffer.append(location)
         }

     case .recording(let startedAt, _):
         collectedLocations.append(location)
         let dist = calculateTotalDistance()
         transitionTo(.recording(startedAt: startedAt, distanceMetres: dist))

     case .ending:
         // Item 3: GPS has been dropped — only significant-location fixes arrive here.
         // These have ~100–300m accuracy and would create a zigzag cluster at the trip end.
         // Discard them. If the motion signal resumes driving, handleActivityUpdate
         // re-enables high-accuracy GPS before we care about location again.
         if let isHighAccuracy = locationManager?.isHighAccuracyActive, isHighAccuracy {
             // A rare case where high-accuracy is still on (e.g. woken by another source)
             collectedLocations.append(location)
             logger.log("Ending — accepted high-accuracy fix", category: .trip)
         } else {
             logger.log("Ending — discarding low-accuracy fix (significant-location) to prevent end cluster", category: .trip)
         }

     case .idle:
         break
     }
 }

 // MARK: - Timers

 private func startDetectionTimer() {
     cancelDetectionTimer()
     detectionTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in
         Task { @MainActor [weak self] in
             guard let self, case .detecting = self.state else { return }
             self.logger.log("Detection timed out — back to idle", category: .trip)
             self.detectionBuffer.removeAll()
             self.peakSpeedKmhDuringDetection = 0
             self.fastTrackDetection          = false
             self.locationManager?.stopHighAccuracyUpdates()
             self.transitionTo(.idle)
         }
     }
 }

 private func cancelDetectionTimer() {
     detectionTimer?.invalidate(); detectionTimer = nil
 }

   private func startStationaryTimer(recordingStartedAt: Date, distance: Double) {
       cancelStationaryTimer()
       stationaryTimer = Timer.scheduledTimer(withTimeInterval: Heuristic.stationaryEndWindowSeconds, repeats: false) { [weak self] _ in
           Task { @MainActor [weak self] in
               guard let self, case .recording = self.state else { return }
               self.logger.log("Stationary timer fired — entering ending state", category: .trip)
               self.transitionTo(.ending(recordingStartedAt: recordingStartedAt, stoppedAt: Date(), distanceMetres: distance))
               // Item 6: drop to significant-location to save battery during resume window
               self.locationManager?.stopHighAccuracyUpdates()
               self.locationManager?.startSignificantLocationMonitoring()
               self.logger.log("GPS dropped to significant-location during ending window", category: .trip)
               self.startResumeTimer(recordingStartedAt: recordingStartedAt, distance: distance)
           }
       }
   }

   private func startResumeTimer(recordingStartedAt: Date, distance: Double) {
       Timer.scheduledTimer(withTimeInterval: Heuristic.resumeWindowSeconds, repeats: false) { [weak self] _ in
           Task { @MainActor [weak self] in
               guard let self, case .ending = self.state else { return }
               self.logger.log("Resume window elapsed — saving trip", category: .trip)
               self.finaliseTripAndReset(startedAt: recordingStartedAt, distance: distance)
           }
       }
   }

 private func cancelStationaryTimer() {
     stationaryTimer?.invalidate(); stationaryTimer = nil
 }

 // MARK: - Trip Finalisation

    func finaliseTripAndReset(startedAt: Date, distance: Double) {
        let duration = Date().timeIntervalSince(startedAt)
        let endedAt  = Date()

        guard distance >= heuristicMinTripDistance,
              duration >= heuristicMinTripDuration else {
            logger.log("Trip too short (dist:\(Int(distance))m dur:\(Int(duration))s) — discarded", category: .trip)
            reset()
            return
        }

        let departure    = consumeVisitDeparture()
        let kitName      = activeCarKitName   // snapshot — reset() clears it
        if let dep = departure { logger.log("Trip anchored to visit departure at \(dep)", category: .trip) }
        if let kit = kitName   { logger.log("Trip associated with car kit: \"\(kit)\"", category: .trip) }

        let vehicleId = profileRepo?.defaultVehicle?.id ?? ""
        tripRepo?.saveTrip(
            vehicleId        : vehicleId,
            startedAt        : startedAt,
            endedAt          : endedAt,
            distanceMetres   : distance,
            locations        : collectedLocations,
            visitDepartureAt : departure,
            carKitName       : kitName
        )

        reset()
    }

    private func reset() {
        collectedLocations.removeAll()
        detectionBuffer.removeAll()
        peakSpeedKmhDuringDetection = 0
        fastTrackDetection          = false
        tripStartedAt        = nil
        visitDepartureAt     = nil
        visitDepartureExpiry = nil
        activeCarKitName     = nil
        carKitConnectExpiry  = nil
        locationManager?.stopHighAccuracyUpdates()
        transitionTo(.idle)
    }

 // MARK: - State transition helper

 func transitionTo(_ newState: TripRecorderState) {
     let old = state
     state = newState
     logger.log("State: \(label(old)) → \(label(newState))", category: .trip)
 }

 private func label(_ s: TripRecorderState) -> String {
     switch s {
     case .idle:                       return "idle"
     case .detecting(let d):           return "detecting(\(Int(abs(d.timeIntervalSinceNow)))s ago)"
     case .recording(let d, let dist): return "recording(\(Int(dist))m since \(Int(abs(d.timeIntervalSinceNow)))s)"
     case .ending(let d, _, let dist): return "ending(\(Int(dist))m started \(Int(abs(d.timeIntervalSinceNow)))s)"
     }
 }

 // MARK: - Distance (CLLocation built-in Haversine)

 private func calculateTotalDistance() -> Double {
     guard collectedLocations.count > 1 else { return 0 }
     var total = 0.0
     for i in 1..<collectedLocations.count {
         total += collectedLocations[i].distance(from: collectedLocations[i-1])
     }
     return total
 }
}
