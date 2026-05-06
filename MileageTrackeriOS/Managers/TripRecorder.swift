// TripRecorder — Core trip detection state machine
//
// STATE TRANSITIONS:
//  idle ──► detecting ──► recording ──► ending ──► idle (trip saved)
//
// TRIP START — three independent paths (no single signal required):
//
//  Path A  CMMotion      handleActivityUpdate: automotive (med/high conf, or low when backed by
//                        geofence/car-kit) → .detecting → GPS peak-speed gate → .recording
//                        Primary path. Confidence filter blocks buses/trams/elevators.
//
//  Path B  Geofence+GPS  handleRegionDeparture starts high-accuracy GPS immediately;
//                        handleLocationUpdate(idle): speed ≥ minSpeedKmh + live region anchor
//                        → .detecting. Works without CMMotion (e.g. parking garages).
//
//  Path C  CarKit+GPS    handleCarKitConnected starts high-accuracy GPS immediately;
//                        handleLocationUpdate(idle): speed ≥ minSpeedKmh + live car-kit expiry
//                        → .detecting. GPS speed confirms movement before CMMotion wakes up.
//
// TRIP END — two independent paths:
//
//  Path A  CMMotion      handleActivityUpdate(recording): stationary/non-automotive (med/high)
//                        → 60 s stationary timer → .ending. Primary path.
//
//  Path B  GPS speed     handleLocationUpdate(recording): tracks lastMovingAt; if speed stays
//                        below threshold for stationaryEndWindowSeconds → stationary timer.
//                        Fires when CMMotion is delayed or stuck on automotive.
//
//  Path C  CarKit disc.  handleCarKitDisconnected(recording) → immediate stationary timer.
//                        Engine off / exiting the car typically drops Bluetooth first.
//                        Disconnect during .detecting or .idle does NOT end — user may be
//                        changing audio source mid-drive.

import Foundation
import CoreLocation
import CoreMotion
import MapKit

// MARK: - Heuristic Constants

private enum Heuristic {
 static let minSpeedKmh               : Double       = 8
 static let detectionWindowSeconds    : TimeInterval = 30
 static let stationaryEndWindowSeconds: TimeInterval = 60
 static let resumeWindowSeconds       : TimeInterval = 90
 static let minimumTripDistanceMetres : Double       = 1000
 static let minimumTripDurationSeconds: TimeInterval = 60
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

    enum Phase: String, Codable { case detecting, recording, ending }

    let phase: Phase
    let tripStartedAt: Date
    let stoppedAt: Date?
    let distanceMetres: Double
    let locations: [StoredLocation]
    let visitDepartureAt: Date?
    let activeCarKitName: String?
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
 /// Timestamp of the last GPS fix with speed ≥ minSpeedKmh during .recording — drives the GPS-speed end path
 private var lastMovingAt: Date?
 private var locationsSinceLastCheckpoint = 0

 /// Set when a CLVisit departure fires — used as a secondary confirmation signal
 var visitDepartureAt: Date?
 var visitDepartureExpiry: Date?
 private let visitDepartureWindowSeconds: TimeInterval = 600

 /// Set when a region exit fires — the region center is the authoritative trip start point.
 /// Prepended to collectedLocations when the trip is confirmed.
 var departureAnchorLocation: CLLocation?
 private var departureAnchorExpiry: Date?

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
        logger.log("TripRecorder configured with repositories", category: .trip)
        recoverFromCheckpoint()
 }

 // MARK: - Car Kit Handlers

 private func handleCarKitConnected(_ event: CarKitEvent) {
     // Store the name regardless of state so it's available at trip save time
     activeCarKitName = event.deviceName

     switch state {
     case .idle:
         carKitConnectExpiry = Date().addingTimeInterval(carKitPreArmWindowSeconds)
         logger.log("Car kit connected (\"\(event.deviceName)\") — pre-armed for \(Int(carKitPreArmWindowSeconds))s, starting GPS", category: .trip)
         // Start GPS immediately so we have speed data before CMMotion wakes up
         locationManager?.startHighAccuracyUpdates()

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

 // MARK: - Region Departure Anchor

 private func handleRegionDeparture(_ anchor: CLLocation) {
     guard case .idle = state else {
         logger.log("Region departure anchor ignored — not idle (state: \(label(state)))", category: .trip)
         return
     }
     departureAnchorLocation = anchor
     departureAnchorExpiry   = Date().addingTimeInterval(visitDepartureWindowSeconds)
     logger.log("Region departure anchor stored at (\(String(format:"%.5f", anchor.coordinate.latitude)), \(String(format:"%.5f", anchor.coordinate.longitude))) — starting GPS", category: .trip)
     // Geofence exit is strong geographic evidence — start GPS immediately so the
     // GPS-speed path can confirm movement without waiting for CMMotion
     locationManager?.startHighAccuracyUpdates()
 }

 private func consumeDepartureAnchor() -> CLLocation? {
     guard let expiry = departureAnchorExpiry, Date() < expiry else {
         departureAnchorLocation = nil
         departureAnchorExpiry   = nil
         return nil
     }
     let loc = departureAnchorLocation
     departureAnchorLocation = nil
     departureAnchorExpiry   = nil
     return loc
 }

 // MARK: - Activity Handler

  private func handleActivityUpdate(_ activity: DetectedActivity) {
      switch state {
      case .idle:
          guard activity.isAutomotive else {
              logger.log("Not automotive, ignored — not entering detecting", category: .trip)
              return
          }
          let visitBacked  = visitDepartureExpiry.map { Date() < $0 } ?? false
          let carKitBacked = carKitConnectExpiry.map { Date() < $0 } ?? false
          // regionBacked uses departureAnchorExpiry — set only by geofence exits, not plain CLVisit
          let regionBacked = departureAnchorExpiry.map { Date() < $0 } ?? false
          // Geofence exit or car-kit connect is strong enough evidence to accept low-confidence
          // automotive (e.g. slow parking-lot exit or garage start where CMMotion is uncertain)
          let acceptLowConf = regionBacked || carKitBacked
          guard acceptLowConf || activity.confidence != .low else {
              logger.log("Low-confidence automotive, no geofence/car-kit pre-arm — ignored", category: .trip)
              return
          }
          fastTrackDetection = visitBacked || carKitBacked || regionBacked
          let confLabel = activity.confidence == .high ? "high" : activity.confidence == .medium ? "medium" : "low"
          logger.log("Automotive detected (conf:\(confLabel), visitBacked:\(visitBacked), carKitBacked:\(carKitBacked), regionBacked:\(regionBacked), fastTrack:\(fastTrackDetection)) — entering detecting", category: .trip)
          transitionTo(.detecting(since: Date()))
          startDetectionTimer()
          if locationManager?.isHighAccuracyActive != true {
              locationManager?.startHighAccuracyUpdates()
          }

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
             let anchor = consumeDepartureAnchor()
             let anchorDesc = anchor != nil ? "region anchor + " : ""
             logger.log("Trip start confirmed ✅ — peak speed \(String(format:"%.1f",peakSpeedKmhDuringDetection)) km/h over \(Int(elapsed))s, prepending \(anchorDesc)\(detectionBuffer.count) detection pts", category: .trip)
             cancelDetectionTimer()
             collectedLocations = (anchor.map { [$0] } ?? []) + detectionBuffer + [location]
             detectionBuffer.removeAll()
             tripStartedAt = collectedLocations.first?.timestamp ?? Date()
             lastMovingAt  = Date()
             transitionTo(.recording(startedAt: tripStartedAt!, distanceMetres: calculateTotalDistance()))
         } else {
             detectionBuffer.append(location)
         }

     case .recording(let startedAt, _):
         collectedLocations.append(location)
         let dist = calculateTotalDistance()
         // GPS-speed end path: track last confirmed movement; trigger end timer if prolonged stop
         if location.speed >= 0 {
             if location.speed * 3.6 >= heuristicMinSpeedKmh {
                 lastMovingAt = location.timestamp
             } else {
                 let reference = lastMovingAt ?? Date()
                 if Date().timeIntervalSince(reference) > Heuristic.stationaryEndWindowSeconds {
                     logger.log("GPS-speed end path: no movement for \(Int(Date().timeIntervalSince(reference)))s — starting end timer", category: .trip)
                     startStationaryTimer(recordingStartedAt: startedAt, distance: dist)
                 }
             }
         }
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
         let regionLive = departureAnchorExpiry.map { Date() < $0 } ?? false
         let carKitLive = carKitConnectExpiry.map { Date() < $0 } ?? false
         // No live pre-arm — if GPS was running for a pre-arm that has since expired, stop it
         guard regionLive || carKitLive else {
             if locationManager?.isHighAccuracyActive == true {
                 logger.log("GPS-speed path: pre-arm expired — stopping high-accuracy GPS", category: .trip)
                 locationManager?.stopHighAccuracyUpdates()
             }
             break
         }
         guard location.speed >= 0, location.speed * 3.6 >= heuristicMinSpeedKmh else { break }
         let source = regionLive ? "region anchor" : "car-kit"
         logger.log("GPS-speed path: \(String(format:"%.1f", location.speed * 3.6)) km/h with \(source) pre-arm — entering detecting without CMMotion", category: .trip)
         fastTrackDetection = true
         transitionTo(.detecting(since: Date()))
         startDetectionTimer()
         // GPS already running from handleRegionDeparture / handleCarKitConnected
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
     detectionTimer?.invalidate()
     detectionTimer = nil
 }

   private func startStationaryTimer(recordingStartedAt: Date, distance: Double) {
       if stationaryTimer != nil {
           return
       }
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

        let departure = consumeVisitDeparture()
        let kitName   = activeCarKitName
        if let dep = departure { logger.log("Trip anchored to visit departure at \(dep)", category: .trip) }
        if let kit = kitName   { logger.log("Trip associated with car kit: \"\(kit)\"", category: .trip) }

        let startCoordinate = collectedLocations.first
        let endCoordinate   = collectedLocations.last
        let vehicleId       = profileRepo?.defaultVehicle?.id ?? ""

        Task { [weak self] in
            guard let self else { return }

            let startAddress = await resolveAddress(for: startCoordinate) ?? ""
            let endAddress   = await resolveAddress(for: endCoordinate) ?? ""

            tripRepo?.saveTrip(
                vehicleId        : vehicleId,
                startedAt        : startedAt,
                endedAt          : endedAt,
                distanceMetres   : distance,
                locations        : collectedLocations,
                startAddress     : startAddress,
                endAddress       : endAddress,
                visitDepartureAt : departure,
                carKitName       : kitName
            )
            reset()
        }
    }

    private func resolveAddress(for coordinate: CLLocation?) async -> String? {
        guard let coordinate,
              let request = MKReverseGeocodingRequest(location: coordinate) else { return nil }
        let mapItem = try? await request.mapItems.first
        return mapItem?.address?.fullAddress
    }

    private func reset() {
        clearCheckpoint()
        collectedLocations.removeAll()
        detectionBuffer.removeAll()
        peakSpeedKmhDuringDetection = 0
        fastTrackDetection          = false
        tripStartedAt        = nil
        visitDepartureAt        = nil
        visitDepartureExpiry    = nil
        departureAnchorLocation = nil
        departureAnchorExpiry   = nil
        activeCarKitName        = nil
        carKitConnectExpiry     = nil
        lastMovingAt            = nil
        locationManager?.stopHighAccuracyUpdates()
        transitionTo(.idle)
    }

 // MARK: - State transition helper

 func transitionTo(_ newState: TripRecorderState) {
     let old = state
     state = newState
     logger.log("State: \(label(old)) → \(label(newState))", category: .trip)
     checkpointIfNeeded(from: old, to: newState)
 }

 private func label(_ s: TripRecorderState) -> String {
     switch s {
     case .idle:                       return "idle"
     case .detecting(let d):           return "detecting(\(Int(abs(d.timeIntervalSinceNow)))s ago)"
     case .recording(let d, let dist): return "recording(\(Int(dist))m since \(Int(abs(d.timeIntervalSinceNow)))s)"
     case .ending(let d, _, let dist): return "ending(\(Int(dist))m started \(Int(abs(d.timeIntervalSinceNow)))s)"
     }
 }

 // MARK: - Checkpoint persistence

 private static let checkpointURL: URL = {
     let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
     return dir.appendingPathComponent("trip_checkpoint.json")
 }()

 private func checkpointIfNeeded(from old: TripRecorderState, to new: TripRecorderState) {
     switch new {
     case .idle:
         break  // reset() calls clearCheckpoint()
     case .recording:
         if case .recording = old {
             // Same phase — throttle to every 10 location updates to avoid constant I/O
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

     switch state {
     case .recording(let s, let d):     phase = .recording; startedAt = s; stoppedAt = nil; distance = d
     case .ending(let s, let t, let d): phase = .ending;    startedAt = s; stoppedAt = t;   distance = d
     case .detecting(let s):            phase = .detecting; startedAt = s; stoppedAt = nil; distance = 0
     case .idle: return
     }

     let checkpoint = TripCheckpoint(
         phase: phase,
         tripStartedAt: startedAt,
         stoppedAt: stoppedAt,
         distanceMetres: distance,
         locations: collectedLocations.map { TripCheckpoint.StoredLocation($0) },
         visitDepartureAt: visitDepartureAt,
         activeCarKitName: activeCarKitName
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

 private func recoverFromCheckpoint() {
     guard let data = try? Data(contentsOf: Self.checkpointURL),
           let checkpoint = try? JSONDecoder().decode(TripCheckpoint.self, from: data) else { return }
     clearCheckpoint()
     guard checkpoint.phase != .detecting else {
         logger.log("Checkpoint: detecting phase discarded — no confirmed trip", category: .trip)
         return
     }
     logger.log("Checkpoint: recovering \(checkpoint.locations.count)-pt \(checkpoint.phase.rawValue) trip from \(checkpoint.tripStartedAt)", category: .trip)
     saveRecoveredTrip(from: checkpoint)
 }

 private func saveRecoveredTrip(from checkpoint: TripCheckpoint) {
     let locations = checkpoint.locations.map { $0.clLocation }
     let endedAt   = checkpoint.stoppedAt ?? locations.last?.timestamp ?? Date()
     let duration  = endedAt.timeIntervalSince(checkpoint.tripStartedAt)

     guard checkpoint.distanceMetres >= heuristicMinTripDistance,
           duration >= heuristicMinTripDuration else {
         logger.log("Checkpoint: recovered trip too short (dist:\(Int(checkpoint.distanceMetres))m dur:\(Int(duration))s) — discarded", category: .trip)
         return
     }

     let vehicleId = profileRepo?.defaultVehicle?.id ?? ""
     Task { [weak self] in
         guard let self else { return }
         let startAddress = await resolveAddress(for: locations.first) ?? ""
         let endAddress   = await resolveAddress(for: locations.last) ?? ""
         tripRepo?.saveTrip(
             vehicleId:        vehicleId,
             startedAt:        checkpoint.tripStartedAt,
             endedAt:          endedAt,
             distanceMetres:   checkpoint.distanceMetres,
             locations:        locations,
             startAddress:     startAddress,
             endAddress:       endAddress,
             visitDepartureAt: checkpoint.visitDepartureAt,
             carKitName:       checkpoint.activeCarKitName
         )
         logger.log("Checkpoint: recovered trip saved ✅ dist:\(Int(checkpoint.distanceMetres))m dur:\(Int(duration))s", category: .trip)
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
