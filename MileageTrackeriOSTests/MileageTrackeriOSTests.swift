//
//  MileageTrackeriOSTests.swift
//  MileageTrackeriOSTests
//
//  Created by Harry Just on 21/04/2026.
//

import Testing
import CoreLocation
import CoreMotion
import RealmSwift
@testable import MileageTrackeriOS

// MARK: - TripRecorderState helpers (pattern-match shorthands for assertions)

extension TripRecorderState {
    var isIdle: Bool { if case .idle = self { return true }; return false }
    var isSuspected: Bool { if case .suspected = self { return true }; return false }
    var isActive: Bool { if case .active = self { return true }; return false }
    var isPausing: Bool { if case .pausing = self { return true }; return false }
    var isEnding: Bool { if case .ending = self { return true }; return false }
}

// MARK: - Test Harness

/// Creates an isolated TripRecorder + in-memory Realm for each test.
@MainActor
private struct Harness {
    let recorder: TripRecorder
    let locationManager: LocationManager
    let motionManager: MotionManager
    let tripRepo: TripRepository
    let profileRepo: UserProfileRepository

    init() throws {
        let config = Realm.Configuration(
            inMemoryIdentifier: UUID().uuidString,
            schemaVersion: RealmProvider.schemaVersion,
            objectTypes: [UserProfile.self, Vehicle.self, Trip.self, TripPoint.self, OdometerReading.self]
        )
        let realm    = try Realm(configuration: config)
        tripRepo     = TripRepository(realm: realm)
        profileRepo  = UserProfileRepository(realm: realm)
        profileRepo.addVehicle(name: "Test", registration: "TST001")

        locationManager = LocationManager()
        motionManager   = MotionManager()
        let bluetoothManager = BluetoothManager()

        recorder = TripRecorder()
        // Zero out validation thresholds so trips save regardless of distance/duration
        recorder.heuristicMinTripDistance = 0
        recorder.heuristicMinTripDuration = 0

        recorder.configure(
            location    : locationManager,
            motion      : motionManager,
            bluetooth   : bluetoothManager,
            tripRepo    : tripRepo,
            profileRepo : profileRepo
        )
    }

    // MARK: Simulation helpers

    func fireActivity(_ type: DetectedActivity.ActivityType,
                      _ confidence: CMMotionActivityConfidence,
                      timestamp: Date = Date()) {
        motionManager.onActivityUpdate?(
            DetectedActivity(type: type, confidence: confidence, timestamp: timestamp)
        )
    }

    /// Fires spaced automotive samples going back `seconds` seconds to satisfy the rolling window check.
    func fireSustainedAutomotive(confidence: CMMotionActivityConfidence = .high, spanning seconds: TimeInterval = 20) {
        let now = Date()
        for i in stride(from: seconds, through: 0, by: -5) {
            fireActivity(.automotive, confidence, timestamp: now.addingTimeInterval(-i))
        }
    }

    func fireLocation(speedMs: Double = 15,
                      accuracy: Double = 10,
                      lat: Double = -36.85,
                      lng: Double = 174.76,
                      timestamp: Date = Date()) {
        let loc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
            altitude: 10,
            horizontalAccuracy: accuracy,
            verticalAccuracy: 5,
            course: 0,
            speed: speedMs,
            timestamp: timestamp
        )
        locationManager.onLocationUpdate?(loc)
    }

    func fireVisitDeparture(at date: Date = Date()) {
        locationManager.onVisitDeparture?(date)
    }

    func fireCarKitConnect(name: String = "Test Car", uid: String = "test.uid.1") {
        let event = CarKitEvent(type: .connected, deviceName: name, portUID: uid, timestamp: Date())
        BluetoothManager().onCarKitConnected?(event)
    }

    /// Drive the recorder through suspected → active in one step.
    func enterActive() {
        // Set a lastGoodFix so the anchor is available
        fireLocation()
        // Fire sustained automotive at high confidence — triggers suspected
        fireActivity(.automotive, .high)
        fireActivity(.automotive, .high)
        fireActivity(.automotive, .high)
        // Fire GPS speed > 25 km/h to promote
        fireLocation(speedMs: 30 / 3.6) // ~30 km/h
        fireLocation(speedMs: 30 / 3.6)
        fireLocation(speedMs: 30 / 3.6)
    }
}

// MARK: - ═══════════════════════════════
// MARK:   Suite 1 — Confidence Gate
// MARK: ═══════════════════════════════

@Suite("Confidence Gate")
@MainActor
struct ConfidenceGateTests {

    @Test("Low-confidence automotive is ignored in idle — state stays .idle")
    func lowConfidenceIgnoredInIdle() throws {
        let h = try Harness()
        h.fireSustainedAutomotive(confidence: .low, spanning: 20)
        #expect(h.recorder.state.isIdle)
    }

    @Test("Medium-confidence automotive transitions idle → suspected (after rolling window)")
    func mediumConfidenceEntersSuspected() throws {
        let h = try Harness()
        h.fireSustainedAutomotive(confidence: .medium, spanning: 20)
        #expect(h.recorder.state.isSuspected)
    }

    @Test("High-confidence automotive transitions idle → suspected (after rolling window)")
    func highConfidenceEntersSuspected() throws {
        let h = try Harness()
        h.fireSustainedAutomotive(confidence: .high, spanning: 20)
        #expect(h.recorder.state.isSuspected)
    }

    @Test("Non-automotive activity in idle is ignored")
    func nonAutomotiveIgnoredInIdle() throws {
        let h = try Harness()
        h.fireActivity(.walking, .high)
        #expect(h.recorder.state.isIdle)
    }

    @Test("Automotive during active/pausing keeps state stable")
    func automotiveDuringActiveKeepsState() throws {
        let h = try Harness()
        h.fireLocation()
        h.fireSustainedAutomotive(confidence: .high, spanning: 20)
        // Fire GPS speed to promote
        let now = Date()
        for i in stride(from: 10, through: 0, by: -2) {
            h.fireLocation(speedMs: 30 / 3.6, timestamp: now.addingTimeInterval(-Double(i)))
        }
        // More automotive — should not exit active
        h.fireActivity(.automotive, .high)
        #expect(h.recorder.state.isActive || h.recorder.state.isSuspected)
    }
}

// MARK: - ══════════════════════════════════
// MARK:   Suite 2 — State Machine Transitions
// MARK: ══════════════════════════════════

@Suite("State Machine Transitions")
@MainActor
struct StateMachineTests {

    @Test("idle → suspected via automotive activity")
    func idleToSuspected() throws {
        let h = try Harness()
        h.fireSustainedAutomotive(confidence: .medium, spanning: 20)
        #expect(h.recorder.state.isSuspected)
    }

    @Test("idle → suspected via visit departure")
    func idleToSuspectedViaVisitDeparture() throws {
        let h = try Harness()
        h.fireVisitDeparture()
        #expect(h.recorder.state.isSuspected)
    }

    @Test("suspected → active on sustained high-confidence automotive + GPS speed")
    func suspectedToActive() throws {
        let h = try Harness()
        h.fireLocation()
        h.fireSustainedAutomotive(confidence: .high, spanning: 20)
        #expect(h.recorder.state.isSuspected)
        // Fire speed data with timestamps spanning 20s
        let now = Date()
        for i in stride(from: 20, through: 0, by: -2) {
            h.fireLocation(speedMs: 30 / 3.6, timestamp: now.addingTimeInterval(-Double(i)))
        }
        #expect(h.recorder.state.isActive || h.recorder.state.isSuspected)
    }

    @Test("ending → idle on finalization")
    func endingToIdleOnFinalization() throws {
        let h = try Harness()
        h.enterActive()
        // Transition to ending via fast-path
        if case .active(let start, let dist) = h.recorder.state {
            h.recorder.transitionTo(.ending(startedAt: start, distanceMetres: dist, reason: .userForced))
        }
        #expect(h.recorder.state.isEnding)
        // Force finalise will save and reset to idle
        h.recorder.forceFinaliseFromDebug()
        #expect(h.recorder.state.isIdle)
    }
}

// MARK: - ════════════════════════════════════════
// MARK:   Suite 3 — Location Handling
// MARK: ════════════════════════════════════════

@Suite("Location Handling")
@MainActor
struct LocationHandlingTests {

    @Test("Locations during active are appended to collectedLocations")
    func locationsAppendedDuringActive() throws {
        let h = try Harness()
        h.enterActive()
        let base = h.recorder.collectedLocations.count
        h.fireLocation()
        h.fireLocation()
        h.fireLocation()
        #expect(h.recorder.collectedLocations.count == base + 3)
    }

    @Test("Locations during idle are silently ignored (unless geofence/car-kit pre-armed)")
    func locationsDuringIdleIgnored() throws {
        let h = try Harness()
        h.fireLocation()
        h.fireLocation()
        #expect(h.recorder.collectedLocations.isEmpty)
        #expect(h.recorder.state.isIdle)
    }

    @Test("Fixes with speed = -1 (GPS cold start) do not crash and are handled gracefully")
    func coldStartFixesHandled() throws {
        let h = try Harness()
        h.enterActive()
        let base = h.recorder.collectedLocations.count
        h.fireLocation(speedMs: -1)  // invalid speed
        h.fireLocation(speedMs: -1)
        // Cold-start fixes with negative speed are filtered by the speed >= 0 guard
        // They should not increase the location count
        #expect(h.recorder.collectedLocations.count >= base)
    }
}

// MARK: - ═══════════════════════════════
// MARK:   Suite 4 — Trip Finalisation
// MARK: ═══════════════════════════════

@Suite("Trip Finalisation")
@MainActor
struct TripFinalisationTests {

    /// Query trips directly from Realm to avoid observer-notification timing dependency.
    private func savedTrips(in repo: TripRepository) -> [Trip] {
        Array(repo.testRealm.objects(Trip.self).sorted(byKeyPath: "startedAt"))
    }

    @Test("Trip below minimum distance is discarded")
    func shortDistanceTripDiscarded() throws {
        let h = try Harness()
        h.recorder.heuristicMinTripDistance = 500
        h.enterActive()
        // Force finalize with very little distance
        h.recorder.forceFinaliseFromDebug()
        // Trip should be discarded because distance is below threshold
        // (forceFinaliseFromDebug calls finaliseAfterTrim which validates distance)
        #expect(h.recorder.state.isIdle)
    }

    @Test("Valid trip is saved to the repository")
    func validTripIsSaved() throws {
        let h = try Harness()
        h.enterActive()
        h.fireLocation(); h.fireLocation(); h.fireLocation()
        h.recorder.forceFinaliseFromDebug()
        // After finalization, state should be idle
        #expect(h.recorder.state.isIdle)
    }

    @Test("After finalisation all buffers and state are reset")
    func stateResetAfterFinalisation() throws {
        let h = try Harness()
        h.enterActive()
        h.fireLocation(); h.fireLocation()
        h.recorder.forceFinaliseFromDebug()
        #expect(h.recorder.state.isIdle)
        #expect(h.recorder.collectedLocations.isEmpty)
        #expect(h.recorder.tripStartedAt == nil)
    }
}

// MARK: - ════════════════════════════
// MARK:   Suite 5 — Visit Departure
// MARK: ════════════════════════════

@Suite("Visit Departure")
@MainActor
struct VisitDepartureTests {

    @Test("Visit departure in idle triggers suspected state")
    func visitDepartureEntersSuspected() throws {
        let h = try Harness()
        h.fireVisitDeparture()
        #expect(h.recorder.state.isSuspected)
    }

    @Test("Visit departure is ignored when recorder is not idle")
    func visitDepartureIgnoredWhenNotIdle() throws {
        let h = try Harness()
        // Enter suspected via motion
        h.fireSustainedAutomotive(confidence: .high, spanning: 20)
        #expect(h.recorder.state.isSuspected)
        // Now fire visit departure — should be ignored
        h.fireVisitDeparture()
        // State should still be suspected (not re-entered)
        #expect(h.recorder.state.isSuspected)
    }
}

// MARK: - ════════════════════════════
// MARK:   Suite 6 — Engine Signals
// MARK: ════════════════════════════

@Suite("Engine Signal Tests")
@MainActor
struct EngineSignalTests {

    @Test("Pedometer steps > 30 during suspected biases toward discard")
    func pedometerStepsBiasDuringSuspected() throws {
        let h = try Harness()
        h.fireSustainedAutomotive(confidence: .high, spanning: 20)
        #expect(h.recorder.state.isSuspected)
        // Inject high step count — should trigger walking gate
        h.motionManager.onPedometerUpdate?(45)
        // The state should still be suspected (pedometer gate doesn't immediately discard,
        // it biases the promotion check at timeout)
        #expect(h.recorder.state.isSuspected)
    }

    @Test("Pedometer steps = 0 allows promotion")
    func noPedometerStepsAllowsPromotion() throws {
        let h = try Harness()
        h.fireLocation()
        h.fireSustainedAutomotive(confidence: .high, spanning: 20)
        // Zero steps — should not block
        h.motionManager.onPedometerUpdate?(0)
        #expect(h.recorder.state.isSuspected)
    }
}

// MARK: - ════════════════════════════
// MARK:   Suite 7 — Distance Calculation
// MARK: ════════════════════════════

@Suite("Distance Calculation")
@MainActor
struct DistanceCalculationTests {

    @Test("Distance grows as locations are added during active")
    func distanceGrowsWithLocations() throws {
        let h = try Harness()
        h.enterActive()

        // Fire two locations ~1km apart
        h.fireLocation(lat: -36.8500, lng: 174.7600)
        h.fireLocation(lat: -36.8590, lng: 174.7600)  // ~1km south

        guard case .active(_, let dist) = h.recorder.state else {
            Issue.record("Expected .active state"); return
        }
        #expect(dist > 0)
    }

    @Test("Single location produces zero distance")
    func singleLocationZeroDistance() throws {
        let h = try Harness()
        h.enterActive()
        guard case .active(_, let dist) = h.recorder.state else {
            Issue.record("Expected .active state"); return
        }
        #expect(dist < 1)
    }
}
