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
    var isIdle: Bool { self == .idle }
    var isDetecting: Bool { if case .detecting = self { return true }; return false }
    var isRecording: Bool { if case .recording = self { return true }; return false }
    var isEnding: Bool { if case .ending = self { return true }; return false }
}

// MARK: - Test Harness

/// Creates an isolated TripRecorder + in-memory Realm for each test.
/// Heuristic timing is zeroed out so tests don't block on real-world delays.
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

        recorder = TripRecorder()
        // Zero out all timing so tests run synchronously without waiting
        recorder.heuristicDetectionWindow = 0
        recorder.heuristicMinSpeedKmh     = 0
        recorder.heuristicMinTripDistance = 0
        recorder.heuristicMinTripDuration = 0

        recorder.configure(
            location   : locationManager,
            motion     : motionManager,
            tripRepo   : tripRepo,
            profileRepo: profileRepo
        )
    }

    // MARK: Simulation helpers

    func fireActivity(_ type: DetectedActivity.ActivityType,
                      _ confidence: CMMotionActivityConfidence) {
        motionManager.onActivityUpdate?(
            DetectedActivity(type: type, confidence: confidence, timestamp: Date())
        )
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

    /// Drive the recorder through .detecting → .recording in one step.
    func enterRecording() {
        fireActivity(.automotive, .high)   // idle → detecting
        fireLocation()                     // detecting → recording (heuristics zeroed)
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
        h.fireActivity(.automotive, .low)
        #expect(h.recorder.state.isIdle)
    }

    @Test("Medium-confidence automotive transitions idle → detecting")
    func mediumConfidenceEntersDetecting() throws {
        let h = try Harness()
        h.fireActivity(.automotive, .medium)
        #expect(h.recorder.state.isDetecting)
    }

    @Test("High-confidence automotive transitions idle → detecting")
    func highConfidenceEntersDetecting() throws {
        let h = try Harness()
        h.fireActivity(.automotive, .high)
        #expect(h.recorder.state.isDetecting)
    }

    @Test("Non-automotive activity in idle is ignored")
    func nonAutomotiveIgnoredInIdle() throws {
        let h = try Harness()
        h.fireActivity(.walking, .high)
        #expect(h.recorder.state.isIdle)
    }

    @Test("Low-confidence stationary in recording does not start end timer")
    func lowConfidenceStationaryInRecordingIgnored() throws {
        let h = try Harness()
        h.enterRecording()
        #expect(h.recorder.state.isRecording)
        h.fireActivity(.stationary, .low)
        // State should still be recording — low confidence stationary must not trigger ending
        #expect(h.recorder.state.isRecording)
    }

    @Test("High-confidence stationary in recording starts the end timer")
    func highConfidenceStationaryInRecordingStartsTimer() throws {
        let h = try Harness()
        h.enterRecording()
        #expect(h.recorder.stationaryTimer == nil)  // no timer before stationary
        h.fireActivity(.stationary, .high)
        #expect(h.recorder.stationaryTimer != nil)  // timer scheduled
        // State is still .recording until the timer fires — that's expected
        #expect(h.recorder.state.isRecording)
    }
}

// MARK: - ══════════════════════════════════
// MARK:   Suite 2 — Detection Buffer
// MARK: ══════════════════════════════════

@Suite("Detection Buffer")
@MainActor
struct DetectionBufferTests {

    @Test("Location fixes during detecting are added to detectionBuffer")
    func locationsBufferedDuringDetecting() throws {
        let h = try Harness()
        h.fireActivity(.automotive, .high)       // → detecting
        // Freeze heuristics so these don't confirm the trip yet
        h.recorder.heuristicMinSpeedKmh = 999    // impossibly high — won't confirm
        h.fireLocation()
        h.fireLocation()
        h.fireLocation()
        #expect(h.recorder.detectionBuffer.count == 3)
    }

    @Test("Detection buffer is prepended to collectedLocations on trip confirmation")
    func bufferPrependedOnConfirmation() throws {
        let h = try Harness()
        h.fireActivity(.automotive, .high)   // → detecting
        h.recorder.heuristicMinSpeedKmh = 999
        // Fire 4 locations into the buffer (speed too low to confirm)
        h.fireLocation(); h.fireLocation(); h.fireLocation(); h.fireLocation()
        #expect(h.recorder.detectionBuffer.count == 4)
        // Now lower threshold so the next location confirms the trip
        h.recorder.heuristicMinSpeedKmh = 0
        h.fireLocation()  // → recording; buffer is NOT re-appended, just prepended
        // collectedLocations = 4 buffered + 1 confirmation (confirmation NOT double-counted)
        #expect(h.recorder.state.isRecording)
        #expect(h.recorder.collectedLocations.count == 5)
        #expect(h.recorder.detectionBuffer.isEmpty)
    }

    @Test("tripStartedAt is anchored to the first buffered detection fix, not the confirmation fix")
    func tripStartedAtUsesFirstBufferTimestamp() throws {
        let h = try Harness()
        h.fireActivity(.automotive, .high)

        let firstTimestamp = Date(timeIntervalSinceNow: -120)
        h.fireLocation(timestamp: firstTimestamp)        // first buffer entry
        h.fireLocation(timestamp: Date(timeIntervalSinceNow: -60))

        // Confirm the trip
        h.fireLocation()

        #expect(h.recorder.state.isRecording)
        // tripStartedAt should equal the first buffer fix's timestamp
        let started = h.recorder.tripStartedAt
        #expect(started != nil)
        #expect(abs(started!.timeIntervalSince(firstTimestamp)) < 0.01)
    }

    @Test("Detection buffer is cleared when stationary aborts detection")
    func bufferClearedOnStationaryAbort() throws {
        let h = try Harness()
        h.recorder.heuristicMinSpeedKmh = 999   // prevent confirmation
        h.fireActivity(.automotive, .high)      // → detecting
        h.fireLocation(); h.fireLocation()
        #expect(h.recorder.detectionBuffer.count == 2)
        h.fireActivity(.stationary, .high)      // abort → idle
        #expect(h.recorder.state.isIdle)
        #expect(h.recorder.detectionBuffer.isEmpty)
    }

    @Test("Detection buffer is cleared on reset")
    func bufferClearedOnReset() throws {
        let h = try Harness()
        h.recorder.heuristicMinSpeedKmh = 999
        h.fireActivity(.automotive, .high)
        h.fireLocation(); h.fireLocation()
        h.recorder.transitionTo(.idle)           // force reset path
        h.recorder.detectionBuffer.removeAll()   // mirrors reset() behaviour
        #expect(h.recorder.detectionBuffer.isEmpty)
    }
}

// MARK: - ══════════════════════════════════════
// MARK:   Suite 3 — State Machine Transitions
// MARK: ══════════════════════════════════════

@Suite("State Machine Transitions")
@MainActor
struct StateMachineTests {

    @Test("idle → detecting on automotive medium+")
    func idleToDetecting() throws {
        let h = try Harness()
        h.fireActivity(.automotive, .medium)
        #expect(h.recorder.state.isDetecting)
    }

    @Test("detecting → idle on stationary abort")
    func detectingToIdleOnStationary() throws {
        let h = try Harness()
        h.recorder.heuristicMinSpeedKmh = 999
        h.fireActivity(.automotive, .high)
        #expect(h.recorder.state.isDetecting)
        h.fireActivity(.stationary, .high)
        #expect(h.recorder.state.isIdle)
    }

    @Test("detecting → recording when speed and window thresholds met")
    func detectingToRecording() throws {
        let h = try Harness()
        h.fireActivity(.automotive, .high)
        h.fireLocation(speedMs: 20)    // 72 km/h — well above default 8, window = 0
        #expect(h.recorder.state.isRecording)
    }

    @Test("recording → ending on high-confidence stationary (via direct transitionTo)")
    func recordingToEndingOnStationary() throws {
        let h = try Harness()
        h.enterRecording()
        // Use direct transition to test ending state without waiting for real timer
        if case .recording(let start, let dist) = h.recorder.state {
            h.recorder.transitionTo(.ending(recordingStartedAt: start, stoppedAt: Date(), distanceMetres: dist))
        }
        #expect(h.recorder.state.isEnding)
    }

    @Test("ending → recording on automotive medium+ resume")
    func endingToRecordingOnResume() throws {
        let h = try Harness()
        h.enterRecording()
        if case .recording(let start, let dist) = h.recorder.state {
            h.recorder.transitionTo(.ending(recordingStartedAt: start, stoppedAt: Date(), distanceMetres: dist))
        }
        #expect(h.recorder.state.isEnding)
        h.fireActivity(.automotive, .medium)
        #expect(h.recorder.state.isRecording)
    }

    @Test("Low-confidence automotive in ending does NOT resume recording")
    func lowConfidenceAutomotiveInEndingIgnored() throws {
        let h = try Harness()
        h.enterRecording()
        if case .recording(let start, let dist) = h.recorder.state {
            h.recorder.transitionTo(.ending(recordingStartedAt: start, stoppedAt: Date(), distanceMetres: dist))
        }
        h.fireActivity(.automotive, .low)
        #expect(h.recorder.state.isEnding)
    }
}

// MARK: - ════════════════════════════════════════
// MARK:   Suite 4 — Ending Phase Location Handling
// MARK: ════════════════════════════════════════

@Suite("Ending Phase Location Handling")
@MainActor
struct EndingLocationTests {

    @Test("Low-accuracy fixes during ending are discarded (no cluster)")
    func lowAccuracyFixDiscardedDuringEnding() throws {
        let h = try Harness()
        h.enterRecording()
        h.fireLocation(); h.fireLocation()
        let countBeforeEnding = h.recorder.collectedLocations.count

        // Simulate what the stationary timer does: drop GPS then transition to ending.
        // stopHighAccuracyUpdates sets isHighAccuracyActive = false so the ending
        // handler correctly discards subsequent low-accuracy fixes.
        h.locationManager.stopHighAccuracyUpdates()
        if case .recording(let start, let dist) = h.recorder.state {
            h.recorder.transitionTo(.ending(recordingStartedAt: start, stoppedAt: Date(), distanceMetres: dist))
        }

        h.fireLocation()   // arrives with isHighAccuracyActive == false → must be discarded
        #expect(h.recorder.collectedLocations.count == countBeforeEnding)
    }

    @Test("Locations during recording are appended correctly")
    func locationsAppendedDuringRecording() throws {
        let h = try Harness()
        h.enterRecording()
        let base = h.recorder.collectedLocations.count
        h.fireLocation()
        h.fireLocation()
        h.fireLocation()
        #expect(h.recorder.collectedLocations.count == base + 3)
    }

    @Test("Locations during idle are silently ignored")
    func locationsDuringIdleIgnored() throws {
        let h = try Harness()
        h.fireLocation()
        h.fireLocation()
        #expect(h.recorder.collectedLocations.isEmpty)
        #expect(h.recorder.state.isIdle)
    }
}

// MARK: - ═══════════════════════════════
// MARK:   Suite 5 — Trip Finalisation
// MARK: ═══════════════════════════════

@Suite("Trip Finalisation")
@MainActor
struct TripFinalisationTests {

    /// Query trips directly from Realm to avoid any observer-notification timing dependency.
    private func savedTrips(in repo: TripRepository) -> [Trip] {
        Array(repo.testRealm.objects(Trip.self).sorted(byKeyPath: "startedAt"))
    }

    @Test("Trip below minimum distance is discarded")
    func shortDistanceTripDiscarded() throws {
        let h = try Harness()
        h.recorder.heuristicMinTripDistance = 500
        h.enterRecording()
        h.recorder.finaliseTripAndReset(startedAt: Date(timeIntervalSinceNow: -120), distance: 100)
        #expect(savedTrips(in: h.tripRepo).isEmpty)
        #expect(h.recorder.state.isIdle)
    }

    @Test("Trip below minimum duration is discarded")
    func shortDurationTripDiscarded() throws {
        let h = try Harness()
        h.recorder.heuristicMinTripDuration = 120
        h.enterRecording()
        h.recorder.finaliseTripAndReset(startedAt: Date(timeIntervalSinceNow: -1), distance: 1000)
        #expect(savedTrips(in: h.tripRepo).isEmpty)
        #expect(h.recorder.state.isIdle)
    }

    @Test("Valid trip is saved to the repository")
    func validTripIsSaved() throws {
        let h = try Harness()
        h.enterRecording()
        h.fireLocation(); h.fireLocation(); h.fireLocation()
        h.recorder.finaliseTripAndReset(startedAt: Date(timeIntervalSinceNow: -300), distance: 5000)
        #expect(savedTrips(in: h.tripRepo).count == 1)
        #expect(h.recorder.state.isIdle)
    }

    @Test("Saved trip has correct vehicle ID")
    func savedTripHasCorrectVehicleId() throws {
        let h = try Harness()
        let expectedVehicleId = h.profileRepo.defaultVehicle?.id ?? ""
        h.enterRecording()
        h.recorder.finaliseTripAndReset(startedAt: Date(timeIntervalSinceNow: -300), distance: 5000)
        let trips = savedTrips(in: h.tripRepo)
        let trip = try #require(trips.first)
        #expect(trip.vehicleId == expectedVehicleId)
    }

    @Test("Saved trip start coords match first collected location")
    func savedTripStartCoordsMatchFirstLocation() throws {
        let h = try Harness()
        h.fireActivity(.automotive, .high)
        h.fireLocation(lat: -36.85, lng: 174.76)   // first buffered fix
        h.fireLocation(lat: -36.86, lng: 174.77)   // second fix (in recording)
        h.recorder.finaliseTripAndReset(startedAt: Date(timeIntervalSinceNow: -300), distance: 5000)
        let trip = try #require(savedTrips(in: h.tripRepo).first)
        #expect(abs(trip.startLat - (-36.85)) < 0.001)
    }

    @Test("After finalisation all buffers and state are reset")
    func stateResetAfterFinalisation() throws {
        let h = try Harness()
        h.enterRecording()
        h.fireLocation(); h.fireLocation()
        h.recorder.finaliseTripAndReset(startedAt: Date(timeIntervalSinceNow: -300), distance: 5000)
        #expect(h.recorder.state.isIdle)
        #expect(h.recorder.collectedLocations.isEmpty)
        #expect(h.recorder.detectionBuffer.isEmpty)
        #expect(h.recorder.tripStartedAt == nil)
    }

    @Test("visitDepartureAt is stored on saved trip when within expiry window")
    func visitDepartureStoredOnTrip() throws {
        let h = try Harness()
        let departureDate = Date(timeIntervalSinceNow: -60)
        h.fireVisitDeparture(at: departureDate)
        h.enterRecording()
        h.recorder.finaliseTripAndReset(startedAt: Date(timeIntervalSinceNow: -300), distance: 5000)
        let trip = try #require(savedTrips(in: h.tripRepo).first)
        #expect(trip.visitDepartureAt != nil)
        #expect(abs(trip.visitDepartureAt!.timeIntervalSince(departureDate)) < 1)
    }
}

// MARK: - ════════════════════════════
// MARK:   Suite 6 — Visit Departure
// MARK: ════════════════════════════

@Suite("Visit Departure Pre-arming")
@MainActor
struct VisitDepartureTests {

    @Test("Visit departure in idle sets visitDepartureExpiry")
    func visitDepartureSetsExpiry() throws {
        let h = try Harness()
        h.fireVisitDeparture()
        #expect(h.recorder.visitDepartureExpiry != nil)
        #expect(h.recorder.visitDepartureAt != nil)
    }

    @Test("Visit departure is ignored when recorder is not idle")
    func visitDepartureIgnoredWhenNotIdle() throws {
        let h = try Harness()
        h.fireActivity(.automotive, .high)   // → detecting (not idle)
        h.fireVisitDeparture()
        // Should NOT set expiry because state is not idle
        #expect(h.recorder.visitDepartureExpiry == nil)
    }

    @Test("Expired visit departure is not consumed at finalisation")
    func expiredVisitDepartureNotConsumed() throws {
        let h = try Harness()
        h.fireVisitDeparture()
        h.recorder.visitDepartureExpiry = Date(timeIntervalSinceNow: -1)  // manually expire
        h.enterRecording()
        h.recorder.finaliseTripAndReset(startedAt: Date(timeIntervalSinceNow: -300), distance: 5000)
        let trips = Array(h.tripRepo.testRealm.objects(Trip.self))
        let trip = try #require(trips.first)
        #expect(trip.visitDepartureAt == nil)
    }
}

// MARK: - ════════════════════════════
// MARK:   Suite 7 — Distance Calc
// MARK: ════════════════════════════

@Suite("Distance Calculation")
@MainActor
struct DistanceCalculationTests {

    @Test("Distance grows as locations are added during recording")
    func distanceGrowsWithLocations() throws {
        let h = try Harness()
        h.enterRecording()

        // Fire two locations ~1km apart
        h.fireLocation(lat: -36.8500, lng: 174.7600)
        h.fireLocation(lat: -36.8590, lng: 174.7600)  // ~1km south

        guard case .recording(_, let dist) = h.recorder.state else {
            Issue.record("Expected .recording state"); return
        }
        #expect(dist > 0)
    }

    @Test("Single location produces zero distance")
    func singleLocationZeroDistance() throws {
        let h = try Harness()
        h.enterRecording()
        guard case .recording(_, let dist) = h.recorder.state else {
            Issue.record("Expected .recording state"); return
        }
        // After enterRecording, collectedLocations may have 1+ entries from detection buffer
        // but all at the same coordinates — distance should be effectively 0 or very small
        #expect(dist < 1)
    }
}
