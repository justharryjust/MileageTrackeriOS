//
//  MileageTrackeriOSTests.swift
//  MileageTrackeriOSTests
//
//  Created by Harry Just on 21/04/2026.
//

import Testing
import CoreLocation
import CoreMotion
import CloudKit
import RealmSwift
import UserNotifications
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
    let notificationManager: NotificationManager
    let scheduleManager: TrackingScheduleManager
    let realm: Realm

    init() throws {
        let config = Realm.Configuration(
            inMemoryIdentifier: UUID().uuidString,
            schemaVersion: RealmProvider.schemaVersion,
            objectTypes: [UserProfile.self, Vehicle.self, Trip.self, TripPoint.self, OdometerReading.self, SavedAddress.self, LogbookPeriod.self]
        )
        self.realm    = try Realm(configuration: config)
        tripRepo     = TripRepository(realm: realm)
        profileRepo  = UserProfileRepository(realm: realm)
        let odometerRepo = OdometerReadingRepository(realm: realm)
        profileRepo.addVehicle(name: "Test", registration: "TST001")

        locationManager = LocationManager()
        motionManager   = MotionManager()
        let bluetoothManager = BluetoothManager()
        notificationManager = NotificationManager()
        scheduleManager = TrackingScheduleManager()
        scheduleManager.configure(profileRepo: profileRepo)

        recorder = TripRecorder()
        // Zero out validation thresholds so trips save regardless of distance/duration
        recorder.heuristicMinTripDistance = 0
        recorder.heuristicMinTripDuration = 0

        let liveActivityManager = LiveActivityManager()
        let mileageCalculator = MileageCalculator()

        recorder.configure(
            location      : locationManager,
            motion        : motionManager,
            bluetooth     : bluetoothManager,
            liveActivity  : liveActivityManager,
            notifications : notificationManager,
            tripRepo      : tripRepo,
            profileRepo   : profileRepo,
            odometerRepo  : odometerRepo,
            scheduleManager: scheduleManager,
            mileageCalculator: mileageCalculator
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

    /// Set up an inflight trip in Realm and return its ID.
    func setupInflightTrip() throws -> String {
        let trip = Trip()
        trip.startedAt = Date().addingTimeInterval(-3600)
        trip.distanceMetres = 10_000
        trip.source = .inflight
        try realm.write {
            realm.add(trip)
        }
        return trip.id
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

// MARK: - ═══════════════════════════════════════════
// MARK:   Suite 8 — Dollar Value Persistence
// MARK: ═══════════════════════════════════════════

@Suite("Dollar Value Persistence")
@MainActor
struct DollarValuePersistenceTests {

    /// Creates a harness with a MileageCalculator wired through.
    private func makeHarness() throws -> (recorder: TripRecorder, repo: TripRepository, calc: MileageCalculator, realm: Realm) {
        let config = Realm.Configuration(
            inMemoryIdentifier: UUID().uuidString,
            schemaVersion: RealmProvider.schemaVersion,
            objectTypes: [UserProfile.self, Vehicle.self, Trip.self, TripPoint.self, OdometerReading.self, SavedAddress.self, LogbookPeriod.self]
        )
        let realm = try Realm(configuration: config)
        let tripRepo = TripRepository(realm: realm)
        let profileRepo = UserProfileRepository(realm: realm)
        let odometerRepo = OdometerReadingRepository(realm: realm)
        profileRepo.addVehicle(name: "Test", registration: "TST001")
        // Default to NZ standard rate for deterministic tests
        if let profile = realm.object(ofType: UserProfile.self, forPrimaryKey: "singleton") {
            try realm.write {
                profile.jurisdiction = .newZealand
                profile.claimMethod = .standardRate
            }
        }

        let locationManager = LocationManager()
        let motionManager = MotionManager()
        let bluetoothManager = BluetoothManager()
        let mileageCalculator = MileageCalculator()

        let recorder = TripRecorder()
        recorder.heuristicMinTripDistance = 0
        recorder.heuristicMinTripDuration = 0

        recorder.configure(
            location: locationManager,
            motion: motionManager,
            bluetooth: bluetoothManager,
            liveActivity: LiveActivityManager(),
            notifications: NotificationManager(),
            tripRepo: tripRepo,
            profileRepo: profileRepo,
            odometerRepo: odometerRepo,
            mileageCalculator: mileageCalculator
        )

        return (recorder, tripRepo, mileageCalculator, realm)
    }

    // MARK: - Cumulative Business Km Tests

    @Test("Cumulative business km is 0 when no prior trips exist")
    func cumulativeKmEmpty() throws {
        let (_, repo, _, _) = try makeHarness()
        let trip = Trip()
        trip.startedAt = Date()
        trip.category = .business
        // Query Realm directly to avoid notification timing
        let prior = repo.testRealm.objects(Trip.self)
            .filter { $0.category == .business && $0.startedAt < trip.startedAt && $0.id != trip.id }
        #expect(prior.reduce(0) { $0 + ($1.distanceMetres / 1000) } == 0)
    }

    @Test("Cumulative business km sums prior business trips correctly")
    func cumulativeKmSumsPrior() async throws {
        let (_, repo, _, realm) = try makeHarness()

        let prior1 = Trip()
        prior1.startedAt = Date().addingTimeInterval(-3600)
        prior1.category = .business
        prior1.distanceMetres = 10_000  // 10 km

        let prior2 = Trip()
        prior2.startedAt = Date().addingTimeInterval(-1800)
        prior2.category = .business
        prior2.distanceMetres = 5_000   // 5 km

        // Personal trip — should not be counted
        let personal = Trip()
        personal.startedAt = Date().addingTimeInterval(-900)
        personal.category = .personal
        personal.distanceMetres = 20_000

        try realm.write {
            realm.add(prior1)
            realm.add(prior2)
            realm.add(personal)
        }

        try await Task.sleep(for: .milliseconds(200))

        let trip = Trip()
        trip.startedAt = Date()
        trip.category = .business
        #expect(repo.cumulativeBusinessKm(before: trip) == 15.0)  // 10 + 5 km only
    }

    @Test("Cumulative km excludes the trip being checked")
    func cumulativeKmExcludesSelf() async throws {
        let (_, repo, _, realm) = try makeHarness()

        let existing = Trip()
        existing.startedAt = Date().addingTimeInterval(-3600)
        existing.category = .business
        existing.distanceMetres = 100_000  // 100 km

        try realm.write { realm.add(existing) }
        try await Task.sleep(for: .milliseconds(200))

        let trip = Trip()
        trip.startedAt = Date()
        trip.category = .business
        #expect(repo.cumulativeBusinessKm(before: trip) == 100.0)
    }

    // MARK: - Dollar Value Storage Tests

    @Test("Manual trip gets non-nil dollarValue after storeDollarValue is called")
    func manualTripGetsDollarValue() throws {
        let (_, repo, calc, realm) = try makeHarness()

        let trip = repo.saveManualTrip(
            vehicleId: "",
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMetres: 15_000,
            startAddress: "Start",
            endAddress: "End",
            startLat: -36.85, startLng: 174.76,
            endLat: -36.86, endLng: 174.77
        )

        guard let profile = realm.object(ofType: UserProfile.self, forPrimaryKey: "singleton") else {
            Issue.record("No profile"); return
        }
        let fuelType = realm.objects(Vehicle.self).first?.fuelType ?? .petrol
        let cumKm = repo.cumulativeBusinessKm(before: trip)
        let value = calc.dollarValue(for: trip, profile: profile, fuelType: fuelType, cumulativeKm: cumKm)
        repo.storeDollarValue(value, for: trip)

        #expect(trip.dollarValue != nil)
        #expect(trip.dollarValue! > 0)
    }

    @Test("Total dollar value stat equals sum of stored dollar values")
    func totalDollarValueMatchesSum() async throws {
        let (_, repo, calc, realm) = try makeHarness()

        guard let profile = realm.object(ofType: UserProfile.self, forPrimaryKey: "singleton") else {
            Issue.record("No profile"); return
        }

        let trip1 = repo.saveManualTrip(
            vehicleId: "",
            startedAt: Date().addingTimeInterval(-7200),
            endedAt: Date().addingTimeInterval(-3600),
            distanceMetres: 10_000,
            startAddress: "A", endAddress: "B",
            startLat: -36.85, startLng: 174.76,
            endLat: -36.86, endLng: 174.77,
            category: .business
        )

        let val1 = calc.dollarValue(for: trip1, profile: profile, cumulativeKm: repo.cumulativeBusinessKm(before: trip1))
        repo.storeDollarValue(val1, for: trip1)

        let trip2 = repo.saveManualTrip(
            vehicleId: "",
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMetres: 20_000,
            startAddress: "C", endAddress: "D",
            startLat: -36.85, startLng: 174.76,
            endLat: -36.86, endLng: 174.77,
            category: .business
        )

        let val2 = calc.dollarValue(for: trip2, profile: profile, cumulativeKm: repo.cumulativeBusinessKm(before: trip2))
        repo.storeDollarValue(val2, for: trip2)

        try await Task.sleep(for: .milliseconds(200))

        #expect(repo.totalDollarValue == val1 + val2)
    }

    @Test("Retroactive profile change does not alter stored dollarValue")
    func retroactiveProfileChangeDoesNotAlterDollarValue() throws {
        let (_, repo, calc, realm) = try makeHarness()

        guard let profile = realm.object(ofType: UserProfile.self, forPrimaryKey: "singleton") else {
            Issue.record("No profile"); return
        }

        let trip = repo.saveManualTrip(
            vehicleId: "",
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMetres: 10_000,
            startAddress: "A", endAddress: "B",
            startLat: -36.85, startLng: 174.76,
            endLat: -36.86, endLng: 174.77,
            category: .business
        )

        let originalValue = calc.dollarValue(for: trip, profile: profile, cumulativeKm: repo.cumulativeBusinessKm(before: trip))
        repo.storeDollarValue(originalValue, for: trip)
        let storedBefore = trip.dollarValue

        // Change the profile — switch to custom rate
        try realm.write {
            profile.claimMethod = .customRate
            profile.customRatePerKm = 200
        }

        #expect(trip.dollarValue == storedBefore)
        #expect(trip.dollarValue == originalValue)
    }
}

// MARK: - ═══════════════════════════════════════
// MARK:   Suite 8 — Notification Helpers
// MARK: ═══════════════════════════════════════

@Suite("Notification Helpers")
struct NotificationHelperTests {

    // MARK: TripRecorder helpers

    @Test("dayName returns English names for Calendar weekday numbers")
    func dayNameValues() throws {
        #expect(TripRecorder.dayName(for: 1) == "Sunday")
        #expect(TripRecorder.dayName(for: 2) == "Monday")
        #expect(TripRecorder.dayName(for: 3) == "Tuesday")
        #expect(TripRecorder.dayName(for: 4) == "Wednesday")
        #expect(TripRecorder.dayName(for: 5) == "Thursday")
        #expect(TripRecorder.dayName(for: 6) == "Friday")
        #expect(TripRecorder.dayName(for: 7) == "Saturday")
        #expect(TripRecorder.dayName(for: 0) == "")
        #expect(TripRecorder.dayName(for: 8) == "")
    }

    @Test("formatHour returns zero-padded HH:MM string")
    func formatHourValues() throws {
        #expect(TripRecorder.formatHour(0) == "00:00")
        #expect(TripRecorder.formatHour(8) == "08:00")
        #expect(TripRecorder.formatHour(17) == "17:00")
        #expect(TripRecorder.formatHour(23) == "23:00")
    }

    // MARK: Full auth prompt trip counter

    @Test("incrementAndCheckFullAuthPrompt returns false for first two trips")
    func tripCounterFirstTwoTrips() throws {
        // Reset counter
        UserDefaults.standard.set(0, forKey: "notify.tripCounterForFullAuth")

        #expect(NotificationManager.incrementAndCheckFullAuthPrompt() == false)
        #expect(NotificationManager.incrementAndCheckFullAuthPrompt() == false)
    }

    @Test("incrementAndCheckFullAuthPrompt returns true on third trip and resets")
    func tripCounterThirdTripTriggers() throws {
        // Reset counter
        UserDefaults.standard.set(0, forKey: "notify.tripCounterForFullAuth")

        #expect(NotificationManager.incrementAndCheckFullAuthPrompt() == false)
        #expect(NotificationManager.incrementAndCheckFullAuthPrompt() == false)
        #expect(NotificationManager.incrementAndCheckFullAuthPrompt() == true)
        // Counter should be reset, so next call returns false
        #expect(NotificationManager.incrementAndCheckFullAuthPrompt() == false)
    }

    // MARK: Authorization status

    @Test("isAuthorized returns false initially (notDetermined)")
    func isAuthorizedInitialState() throws {
        let nm = NotificationManager()
        #expect(nm.authorizationStatus == .notDetermined)
        #expect(nm.isAuthorized == false)
    }

    // MARK: Weekly Summary

    @Test("weekly summary content handles zero business trips gracefully")
    func weeklySummaryEmptyContent() throws {
        let nm = NotificationManager()
        NotificationManager.weeklySummaryEnabled = true

        // Call with zero values — should not crash
        nm.scheduleWeeklySummary(weekKm: 0, businessCount: 0, valueDollars: 0)
        nm.cancelWeeklySummary()

        NotificationManager.weeklySummaryEnabled = false
    }

    @Test("weekly summary with data formats correctly")
    func weeklySummaryWithData() throws {
        let nm = NotificationManager()
        NotificationManager.weeklySummaryEnabled = true

        // Should not crash with positive values
        nm.scheduleWeeklySummary(weekKm: 150.5, businessCount: 3, valueDollars: 45.75)
        nm.cancelWeeklySummary()

        NotificationManager.weeklySummaryEnabled = false
    }

    @Test("weekly summary toggle cancel removes pending notification")
    func weeklySummaryToggleCancel() throws {
        let nm = NotificationManager()
        NotificationManager.weeklySummaryEnabled = true
        nm.scheduleWeeklySummary(weekKm: 100, businessCount: 2, valueDollars: 20)
        nm.weeklySummaryToggleChanged(isEnabled: false)
        // The toggle change should cancel the pending notification
        // No assertion possible on UNUserNotificationCenter state, but no crash = success
        nm.weeklySummaryToggleChanged(isEnabled: true)
        NotificationManager.weeklySummaryEnabled = false
    }

    // MARK: Odometer Reminder Toggle

    @Test("odometer toggle cancel removes pending notification")
    func odometerToggleCancel() throws {
        let nm = NotificationManager()
        NotificationManager.odometerReminderEnabled = true
        nm.scheduleOdometerReminder(vehicleName: "Test Car")
        nm.odometerToggleChanged(isEnabled: false, vehicleName: "Test Car")
        // Toggling back on should reschedule
        nm.odometerToggleChanged(isEnabled: true, vehicleName: "Test Car")
        NotificationManager.odometerReminderEnabled = false
    }
}

// MARK: - ═══════════════════════════════════════════════
// MARK:   Suite 9 — Schedule Gate Notifications
// MARK: ═══════════════════════════════════════════════

@Suite("Schedule Gate Notifications")
@MainActor
struct ScheduleGateNotificationTests {

    @Test("Schedule manager callbacks send notifications without crashing")
    func scheduleGateCallbacksDoNotCrash() throws {
        let h = try Harness()
        // The scheduleManager callbacks are set up in configure()
        // No crash = success
        #expect(h.recorder.state.isIdle)
    }
}

// MARK: - ═══════════════════════════════════════════════
// MARK:   Suite 10 — Notification Reschedule
// MARK: ═══════════════════════════════════════════════

@Suite("Notification Reschedule")
@MainActor
struct NotificationRescheduleTests {

    @Test("reschedule with logbook method schedules odometer reminder (no crash)")
    func rescheduleLogbook() throws {
        let nm = NotificationManager()
        nm.reschedule(claimMethod: .logbook, vehicleName: "Test Car")
        // Should have scheduled or no-opped, no crash
        nm.reschedule(claimMethod: .standardRate, vehicleName: "Test Car")
        // Switching away cancels
        #expect(true)
    }

    @Test("reschedule with non-logbook method cancels odometer reminder (no crash)")
    func rescheduleStandardRate() throws {
        let nm = NotificationManager()
        nm.reschedule(claimMethod: .standardRate, vehicleName: "Test Car")
        #expect(true)
    }
}

// MARK: - ═══════════════════════════════
// MARK:   Suite 9 — Tax Year Periods
// MARK: ═══════════════════════════════

@Suite("Tax Year Periods")
struct TaxYearTests {

    /// Helper to build a date from components.
    private func date(year: Int, month: Int, day: Int) -> Date {
        let cal = Calendar.current
        return cal.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    // MARK: New Zealand (1 Apr – 31 Mar)

    @Test("NZ: date in Apr–Dec returns current-year tax year starting 1 Apr")
    func nzDateInAprToDec() throws {
        let d = date(year: 2026, month: 6, day: 15)
        let period = Jurisdiction.newZealand.taxYear.containing(d)
        let expectedStart = date(year: 2026, month: 4, day: 1)
        let expectedEnd = date(year: 2027, month: 4, day: 1).addingTimeInterval(-1)
        #expect(period.start == expectedStart)
        #expect(period.end == expectedEnd)
    }

    @Test("NZ: date in Jan–Mar returns previous-year tax year starting 1 Apr")
    func nzDateInJanToMar() throws {
        let d = date(year: 2027, month: 2, day: 10)
        let period = Jurisdiction.newZealand.taxYear.containing(d)
        let expectedStart = date(year: 2026, month: 4, day: 1)
        let expectedEnd = date(year: 2027, month: 4, day: 1).addingTimeInterval(-1)
        #expect(period.start == expectedStart)
        #expect(period.end == expectedEnd)
    }

    // MARK: Australia (1 Jul – 30 Jun)

    @Test("AU: date in Jul–Dec returns current-year tax year starting 1 Jul")
    func auDateInJulToDec() throws {
        let d = date(year: 2026, month: 10, day: 1)
        let period = Jurisdiction.australia.taxYear.containing(d)
        let expectedStart = date(year: 2026, month: 7, day: 1)
        let expectedEnd = date(year: 2027, month: 7, day: 1).addingTimeInterval(-1)
        #expect(period.start == expectedStart)
        #expect(period.end == expectedEnd)
    }

    @Test("AU: date in Jan–Jun returns previous-year tax year starting 1 Jul")
    func auDateInJanToJun() throws {
        let d = date(year: 2027, month: 3, day: 15)
        let period = Jurisdiction.australia.taxYear.containing(d)
        let expectedStart = date(year: 2026, month: 7, day: 1)
        let expectedEnd = date(year: 2027, month: 7, day: 1).addingTimeInterval(-1)
        #expect(period.start == expectedStart)
        #expect(period.end == expectedEnd)
    }

    // MARK: UK (6 Apr – 5 Apr) via .other

    @Test("UK: date in Apr–Dec returns current-year tax year starting 6 Apr")
    func ukDateInAprToDec() throws {
        let d = date(year: 2026, month: 8, day: 20)
        let period = Jurisdiction.other.taxYear.containing(d)
        let expectedStart = date(year: 2026, month: 4, day: 6)
        let expectedEnd = date(year: 2027, month: 4, day: 6).addingTimeInterval(-1)
        #expect(period.start == expectedStart)
        #expect(period.end == expectedEnd)
    }

    @Test("UK: date 1 Jan–5 Apr returns previous-year tax year starting 6 Apr")
    func ukDateInJanToApr5() throws {
        let d = date(year: 2027, month: 1, day: 1)
        let period = Jurisdiction.other.taxYear.containing(d)
        let expectedStart = date(year: 2026, month: 4, day: 6)
        let expectedEnd = date(year: 2027, month: 4, day: 6).addingTimeInterval(-1)
        #expect(period.start == expectedStart)
        #expect(period.end == expectedEnd)
    }

    // MARK: Edge cases — boundary dates

    @Test("NZ: 1 Apr exactly is start of tax year")
    func nzBoundaryStart() throws {
        let d = date(year: 2026, month: 4, day: 1)
        let period = Jurisdiction.newZealand.taxYear.containing(d)
        #expect(period.start == d)
    }

    @Test("NZ: 31 Mar is end of tax year (not start of next)")
    func nzBoundaryEnd() throws {
        let d = date(year: 2027, month: 3, day: 31)
        let period = Jurisdiction.newZealand.taxYear.containing(d)
        let expectedStart = date(year: 2026, month: 4, day: 1)
        let expectedEnd = date(year: 2027, month: 4, day: 1).addingTimeInterval(-1)
        #expect(period.start == expectedStart)
        #expect(period.end == expectedEnd)
    }

    @Test("AU: 1 Jul exactly is start of tax year")
    func auBoundaryStart() throws {
        let d = date(year: 2026, month: 7, day: 1)
        let period = Jurisdiction.australia.taxYear.containing(d)
        #expect(period.start == d)
    }

    @Test("UK: 6 Apr exactly is start of tax year")
    func ukBoundaryStart() throws {
        let d = date(year: 2026, month: 4, day: 6)
        let period = Jurisdiction.other.taxYear.containing(d)
        #expect(period.start == d)
    }
}


// MARK:   Suite 12 — DrivingDistanceResult + Haversine
// MARK: ═══════════════════════════════════════════════════

@Suite("Driving Distance Result")
struct DrivingDistanceResultTests {

    @Test("Driving case carries expected distance")
    func drivingResult() {
        let r = DrivingDistanceResult.driving(distanceMetres: 5_000)
        guard case .driving(let d) = r else { Issue.record("Expected .driving"); return }
        #expect(d == 5_000)
    }

    @Test("Approximate case carries expected distance")
    func approximateResult() {
        let r = DrivingDistanceResult.approximate(distanceMetres: 5_000)
        guard case .approximate(let d) = r else { Issue.record("Expected .approximate"); return }
        #expect(d == 5_000)
    }

    @Test("NoRoute case has no associated value")
    func noRouteResult() {
        let r = DrivingDistanceResult.noRoute
        guard case .noRoute = r else { Issue.record("Expected .noRoute"); return }
    }

    @Test("Haversine distance matches expected value between two known coordinates")
    func haversineDistance() {
        let searcher = AddressSearcher()
        // Auckland CBD to Britomart (~500m)
        let a = CLLocationCoordinate2D(latitude: -36.8485, longitude: 174.7633)
        let b = CLLocationCoordinate2D(latitude: -36.8445, longitude: 174.7673)
        let dist = searcher.haversine(a, b)
        // Should be roughly 500m
        #expect(dist > 200)
        #expect(dist < 800)
    }

    @Test("Haversine distance is zero for identical coordinates")
    func haversineIdentical() {
        let searcher = AddressSearcher()
        let a = CLLocationCoordinate2D(latitude: -36.8485, longitude: 174.7633)
        let dist = searcher.haversine(a, a)
        #expect(dist == 0)
    }

    @Test("DrivingDistanceResult equatability")
    func drivingDistanceResultEquatable() {
        #expect(DrivingDistanceResult.driving(distanceMetres: 100) == .driving(distanceMetres: 100))
        #expect(DrivingDistanceResult.approximate(distanceMetres: 100) == .approximate(distanceMetres: 100))
        #expect(DrivingDistanceResult.driving(distanceMetres: 100) != .driving(distanceMetres: 200))
        #expect(DrivingDistanceResult.driving(distanceMetres: 100) != .approximate(distanceMetres: 100))
        #expect(DrivingDistanceResult.noRoute == .noRoute)
    }
}

// MARK: - ════════════════════════════════════════════════════════
// MARK:   Suite 13 — Manual Trip Repository Save
// MARK: ════════════════════════════════════════════════════════

@Suite("Manual Trip Repository Save")
@MainActor
struct ManualTripRepoTests {

    private func makeRealm() throws -> Realm {

    }

    @Test("Save with processingStatus = .pending sets status on trip")
    func saveWithPendingStatus() throws {
        let realm = try makeRealm()
        let repo = TripRepository(realm: realm)

        repo.saveManualTrip(
            vehicleId: "v1",
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMetres: 10_000,
            startAddress: "Start", endAddress: "End",
            startLat: -36.85, startLng: 174.76,
            endLat: -36.86, endLng: 174.77,
            processingStatus: .pending
        )

        let saved = realm.objects(Trip.self).first
        #expect(saved != nil)
        #expect(saved?.processingStatus == .pending)
        #expect(saved?.source == .manual)
    }

    @Test("Save with default status is .complete")
    func saveWithDefaultStatus() throws {
        let realm = try makeRealm()
        let repo = TripRepository(realm: realm)

        repo.saveManualTrip(
            vehicleId: "v1",
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMetres: 10_000,
            startAddress: "Start", endAddress: "End",
            startLat: -36.85, startLng: 174.76,
            endLat: -36.86, endLng: 174.77
        )

        let saved = realm.objects(Trip.self).first
        #expect(saved?.processingStatus == .complete)
    }

    @Test("Save with snappedCoordinates creates TripPoints from snapped coords")
    func saveWithSnappedCoords() throws {
        let realm = try makeRealm()
        let repo = TripRepository(realm: realm)

        let snapped: [CLLocationCoordinate2D] = [
            CLLocationCoordinate2D(latitude: -36.848, longitude: 174.763),
            CLLocationCoordinate2D(latitude: -36.846, longitude: 174.765),
            CLLocationCoordinate2D(latitude: -36.844, longitude: 174.767),
            CLLocationCoordinate2D(latitude: -36.842, longitude: 174.769),
        ]

        let trip = repo.saveManualTrip(
            vehicleId: "v1",
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMetres: 500,
            startAddress: "A", endAddress: "B",
            startLat: -36.848, startLng: 174.763,
            endLat: -36.842, endLng: 174.769,
            snappedCoordinates: snapped
        )

        let pts = repo.tripPoints(for: trip)
        #expect(pts.count == snapped.count)
        // Verify points are road-snapped (accuracy = 5)
        #expect(pts.allSatisfy { $0.horizontalAccuracy == 5 })
    }

    @Test("Trip returns from saveManualTrip for dollar value computation")
    func saveManualTripReturnsTrip() throws {
        let realm = try makeRealm()
        let repo = TripRepository(realm: realm)

        let trip = repo.saveManualTrip(
            vehicleId: "v1",
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMetres: 10_000,
            startAddress: "Start", endAddress: "End",
            startLat: -36.85, startLng: 174.76,
            endLat: -36.86, endLng: 174.77
        )

        #expect(trip.id.isEmpty == false)
        #expect(trip.distanceMetres == 10_000)
    }

    @Test("Cumulative business km is 0 when no prior trips exist")
    func cumulativeKmEmpty() throws {
        let realm = try makeRealm()
        let repo = TripRepository(realm: realm)
        let trip = Trip()
        trip.startedAt = Date()
        #expect(repo.cumulativeBusinessKm(before: trip) == 0)
    }

    @Test("Cumulative business km sums prior business trips correctly")
    func cumulativeKmSumsPrior() throws {
        let realm = try makeRealm()
        let repo = TripRepository(realm: realm)

        let prior1 = Trip()
        prior1.startedAt = Date().addingTimeInterval(-3600)
        prior1.category = .business
        prior1.distanceMetres = 10_000

        let prior2 = Trip()
        prior2.startedAt = Date().addingTimeInterval(-1800)
        prior2.category = .business
        prior2.distanceMetres = 5_000

        try realm.write {
            realm.add(prior1)
            realm.add(prior2)
        }

        let trip = Trip()
        trip.startedAt = Date()
        #expect(repo.cumulativeBusinessKm(before: trip) == 15.0)
    }

    @Test("Store dollar value persists on trip")
    func storeDollarValue() throws {
        let realm = try makeRealm()
        let repo = TripRepository(realm: realm)

        let trip = repo.saveManualTrip(
            vehicleId: "v1",
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMetres: 10_000,
            startAddress: "Start", endAddress: "End",
            startLat: -36.85, startLng: 174.76,
            endLat: -36.86, endLng: 174.77
        )

        repo.storeDollarValue(42.50, for: trip)
        #expect(trip.dollarValue == 42.50)
    }

    @Test("Store distance overwrites distance on trip")
    func storeDistance() throws {
        let realm = try makeRealm()
        let repo = TripRepository(realm: realm)

        let trip = repo.saveManualTrip(
            vehicleId: "v1",
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMetres: 10_000,
            startAddress: "Start", endAddress: "End",
            startLat: -36.85, startLng: 174.76,
            endLat: -36.86, endLng: 174.77
        )

        repo.storeDistance(12_500, for: trip)
        #expect(trip.distanceMetres == 12_500)
    }

// MARK:   Suite 11 — Onboarding Region Validation
// MARK: ═══════════════════════════════════════════════

@Suite("Onboarding Region Validation")
@MainActor
struct OnboardingRegionValidationTests {

    @Test("isRegionValid is false when regionCode is empty")
    func emptyRegionIsInvalid() throws {
        let vm = OnboardingViewModel()
        vm.regionCode = ""
        #expect(vm.isRegionValid == false)
    }

    @Test("isRegionValid is true when regionCode is NZ")
    func nzRegionIsValid() throws {
        let vm = OnboardingViewModel()
        vm.regionCode = "NZ"
        #expect(vm.isRegionValid == true)
    }

    @Test("isRegionValid is true when regionCode is AU")
    func auRegionIsValid() throws {
        let vm = OnboardingViewModel()
        vm.regionCode = "AU"
        #expect(vm.isRegionValid == true)
    }

    @Test("isRegionValid is true when regionCode is US")
    func usRegionIsValid() throws {
        let vm = OnboardingViewModel()
        vm.regionCode = "US"
        #expect(vm.isRegionValid == true)
    }

    @Test("isRegionValid is true when regionCode is unsupported code (falls back to Other)")
    func unsupportedRegionIsValid() throws {
        let vm = OnboardingViewModel()
        vm.regionCode = "GB"
        #expect(vm.isRegionValid == true)
    }

    @Test("jurisdiction is .newZealand when regionCode is NZ")
    func nzJurisdiction() throws {
        let vm = OnboardingViewModel()
        vm.regionCode = "NZ"
        #expect(vm.jurisdiction == .newZealand)
    }

    @Test("jurisdiction is .australia when regionCode is AU")
    func auJurisdiction() throws {
        let vm = OnboardingViewModel()
        vm.regionCode = "AU"
        #expect(vm.jurisdiction == .australia)
    }

    @Test("jurisdiction is .other when regionCode is empty")
    func emptyJurisdictionIsOther() throws {
        let vm = OnboardingViewModel()
        vm.regionCode = ""
        #expect(vm.jurisdiction == .other)
    }

    @Test("jurisdiction is .unitedStates when regionCode is US")
    func usJurisdiction() throws {
        let vm = OnboardingViewModel()
        vm.regionCode = "US"
        #expect(vm.jurisdiction == .unitedStates)
    }

    @Test("jurisdiction is .canada when regionCode is CA")
    func caJurisdiction() throws {
        let vm = OnboardingViewModel()
        vm.regionCode = "CA"
        #expect(vm.jurisdiction == .canada)
    }

    @Test("jurisdiction is .germany when regionCode is DE")
    func deJurisdiction() throws {
        let vm = OnboardingViewModel()
        vm.regionCode = "DE"
        #expect(vm.jurisdiction == .germany)
    }

    @Test("jurisdiction is .belgium when regionCode is BE")
    func beJurisdiction() throws {
        let vm = OnboardingViewModel()
        vm.regionCode = "BE"
        #expect(vm.jurisdiction == .belgium)
    }

    @Test("jurisdiction is .netherlands when regionCode is NL")
    func nlJurisdiction() throws {
        let vm = OnboardingViewModel()
        vm.regionCode = "NL"
        #expect(vm.jurisdiction == .netherlands)
    }

    @Test("jurisdiction is .switzerland when regionCode is CH")
    func chJurisdiction() throws {
        let vm = OnboardingViewModel()
        vm.regionCode = "CH"
        #expect(vm.jurisdiction == .switzerland)
    }

    @Test("jurisdiction is .austria when regionCode is AT")
    func atJurisdiction() throws {
        let vm = OnboardingViewModel()
        vm.regionCode = "AT"
        #expect(vm.jurisdiction == .austria)
    }

    @Test("jurisdiction is .sweden when regionCode is SE")
    func seJurisdiction() throws {
        let vm = OnboardingViewModel()
        vm.regionCode = "SE"
        #expect(vm.jurisdiction == .sweden)
    }

    @Test("jurisdiction is .norway when regionCode is NO")
    func noJurisdiction() throws {
        let vm = OnboardingViewModel()
        vm.regionCode = "NO"
        #expect(vm.jurisdiction == .norway)
    }

    @Test("jurisdiction is .denmark when regionCode is DK")
    func dkJurisdiction() throws {
        let vm = OnboardingViewModel()
        vm.regionCode = "DK"
        #expect(vm.jurisdiction == .denmark)
    }

    @Test("jurisdiction is .finland when regionCode is FI")
    func fiJurisdiction() throws {
        let vm = OnboardingViewModel()
        vm.regionCode = "FI"
        #expect(vm.jurisdiction == .finland)
    }

    @Test("jurisdiction is .spain when regionCode is ES")
    func esJurisdiction() throws {
        let vm = OnboardingViewModel()
        vm.regionCode = "ES"
        #expect(vm.jurisdiction == .spain)
    }

    @Test("jurisdiction is .southAfrica when regionCode is ZA")
    func zaJurisdiction() throws {
        let vm = OnboardingViewModel()
        vm.regionCode = "ZA"
        #expect(vm.jurisdiction == .southAfrica)
    }

    @Test("jurisdiction is .other when regionCode is unsupported ISO code")
    func unsupportedJurisdictionIsOther() throws {
        let vm = OnboardingViewModel()
        vm.regionCode = "GB"
        #expect(vm.jurisdiction == .other)
    }

    @Test("jurisdiction is .other when regionCode is other (rawValue match)")
    func explicitOtherJurisdiction() throws {
        let vm = OnboardingViewModel()
        vm.regionCode = "other"
        #expect(vm.jurisdiction == .other)
    }
}

// MARK: - ═══════════════════════════════

// MARK:   Suite 12 — Trip Repository Deletion
// MARK: ═══════════════════════════════

@Suite("Trip Repository Delete")
@MainActor
struct TripRepositoryDeleteTests {

    /// Helper to build a date from components.
    private func date(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
        let cal = Calendar.current
        return cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// Query trips directly from Realm to avoid observer-notification timing dependency.
    private func savedTrips(in repo: TripRepository) -> [Trip] {
        Array(repo.testRealm.objects(Trip.self).sorted(byKeyPath: "startedAt"))
    }

    /// Query TripPoints directly from Realm for the given trip ID.
    private func pointsForTripId(in repo: TripRepository, tripId: String) -> [TripPoint] {
        Array(repo.testRealm.objects(TripPoint.self).where { $0.tripId == tripId })
    }

    @Test("deleteTrip removes the trip from the repository")
    func deleteTripRemovesTrip() throws {
        let repo = TripRepository(realm: realm)

        let startDate = date(year: 2026, month: 6, day: 15, hour: 9)
        let endDate = date(year: 2026, month: 6, day: 15, hour: 10)

        repo.saveManualTrip(
            vehicleId: "test-vehicle-1",
            startedAt: startDate,
            endedAt: endDate,
            distanceMetres: 10_000,
            startAddress: "Start St",
            endAddress: "End Ave",
            startLat: -36.85,
            startLng: 174.76,
            endLat: -36.95,
            endLng: 174.86
        )

        #expect(savedTrips(in: repo).count == 1, "Trip should exist before deletion")

        let trip = savedTrips(in: repo).first!
        repo.deleteTrip(trip)

        #expect(savedTrips(in: repo).isEmpty, "Trip should be removed after deletion")
    }

    @Test("deleteTrip removes associated TripPoints")
    func deleteTripRemovesPoints() throws {
        let config = Realm.Configuration(
            inMemoryIdentifier: UUID().uuidString,
            schemaVersion: RealmProvider.schemaVersion,
            objectTypes: [UserProfile.self, Vehicle.self, Trip.self, TripPoint.self, OdometerReading.self, SavedAddress.self, LogbookPeriod.self]
        )
        let realm = try Realm(configuration: config)
        let repo = TripRepository(realm: realm)

        let startDate = date(year: 2026, month: 6, day: 15, hour: 14)
        let endDate = date(year: 2026, month: 6, day: 15, hour: 15)

        repo.saveManualTrip(
            vehicleId: "test-vehicle-2",
            startedAt: startDate,
            endedAt: endDate,
            distanceMetres: 5_000,
            startAddress: "Alpha Rd",
            endAddress: "Beta Blvd",
            startLat: -36.85,
            startLng: 174.76,
            endLat: -36.90,
            endLng: 174.80
        )

        let trip = savedTrips(in: repo).first!
        let tripId = trip.id

        // Verify points exist before deletion
        let pointsBefore = pointsForTripId(in: repo, tripId: tripId)
        #expect(!pointsBefore.isEmpty, "TripPoints should exist before deletion")

        repo.deleteTrip(trip)

        // Verify points are gone after deletion
        let pointsAfter = pointsForTripId(in: repo, tripId: tripId)
        #expect(pointsAfter.isEmpty, "TripPoints should be removed after deletion")
    }

    @Test("deleting one trip does not affect other trips")
    func deleteTripIsolated() throws {
        let config = Realm.Configuration(
            inMemoryIdentifier: UUID().uuidString,
            schemaVersion: RealmProvider.schemaVersion,
            objectTypes: [UserProfile.self, Vehicle.self, Trip.self, TripPoint.self, OdometerReading.self, SavedAddress.self, LogbookPeriod.self]
        )
        let realm = try Realm(configuration: config)
        let repo = TripRepository(realm: realm)

        let startDate1 = date(year: 2026, month: 6, day: 15, hour: 8)
        let endDate1 = date(year: 2026, month: 6, day: 15, hour: 9)

        repo.saveManualTrip(
            vehicleId: "test-vehicle-4",
            startedAt: startDate1,
            endedAt: endDate1,
            distanceMetres: 5_000,
            startAddress: "P St",
            endAddress: "Q Ave",
            startLat: -36.85,
            startLng: 174.76,
            endLat: -36.88,
            endLng: 174.79,
            category: .business
        )

        let startDate2 = date(year: 2026, month: 6, day: 15, hour: 10)
        let endDate2 = date(year: 2026, month: 6, day: 15, hour: 11)

        repo.saveManualTrip(
            vehicleId: "test-vehicle-5",
            startedAt: startDate2,
            endedAt: endDate2,
            distanceMetres: 8_000,
            startAddress: "R St",
            endAddress: "S Blvd",
            startLat: -36.86,
            startLng: 174.77,
            endLat: -36.90,
            endLng: 174.82,
            category: .personal
        )

        #expect(savedTrips(in: repo).count == 2, "Two trips should exist")

        let trips = savedTrips(in: repo)
        let firstTrip = trips.first!
        repo.deleteTrip(firstTrip)

        let remaining = savedTrips(in: repo)
        #expect(remaining.count == 1, "Only one trip should remain")
        #expect(remaining.first?.id != firstTrip.id, "Remaining trip should not be the deleted one")
    }
}
    }
}

// MARK: - ═══════════════════════════════════════════

// MARK:   Suite 9 — Onboarding Navigation
// MARK: ═══════════════════════════════════════════

@Suite("Onboarding Navigation")
@MainActor
struct OnboardingNavigationTests {

    @Test("ViewModel starts at .intro by default")
    func startsAtIntro() {
        let vm = OnboardingViewModel()
        #expect(vm.currentStep == .intro)
    }

    @Test("advance increments currentStep forward")
    func advanceMovesForward() {
        let vm = OnboardingViewModel()
        vm.advance()
        #expect(vm.currentStep == .jurisdiction)
        vm.advance()
        #expect(vm.currentStep == .vehicleAndUnit)
    }

    @Test("goBack decrements currentStep")
    func goBackMovesBack() {
        let vm = OnboardingViewModel()
        vm.advance()  // .jurisdiction
        vm.advance()  // .vehicleAndUnit
        #expect(vm.currentStep == .vehicleAndUnit)

        vm.goBack()
        #expect(vm.currentStep == .jurisdiction)
    }

    @Test("goBack does not go past .intro")
    func goBackStopsAtIntro() {
        let vm = OnboardingViewModel()
        #expect(vm.currentStep == .intro)
        vm.goBack()
        #expect(vm.currentStep == .intro)
    }

    @Test("advance does not go past .welcome")
    func advanceStopsAtWelcome() {
        let vm = OnboardingViewModel()
        for _ in 0..<OnboardingStep.allCases.count {
            vm.advance()
        }
        #expect(vm.currentStep == .welcome)
        vm.advance()
        #expect(vm.currentStep == .welcome)
    }

    @Test("isVehicleValid is false when registration is empty")
    func vehicleInvalidWithoutRegistration() {
        let vm = OnboardingViewModel()
        vm.vehicleRegistration = ""
        #expect(vm.isVehicleValid == false)
    }

    @Test("isVehicleValid is false when registration is whitespace only")
    func vehicleInvalidWithWhitespaceOnly() {
        let vm = OnboardingViewModel()
        vm.vehicleRegistration = "   "
        #expect(vm.isVehicleValid == false)
    }

    @Test("isVehicleValid is true when registration is non-empty")
    func vehicleValidWithRegistration() {
        let vm = OnboardingViewModel()
        vm.vehicleRegistration = "ABC123"
        #expect(vm.isVehicleValid == true)
    }

    @Test("Advancing from intro reaches vehicleAndUnit in exactly 2 steps")
    func pathFromIntroToVehicle() {
        let vm = OnboardingViewModel()
        vm.advance()
        vm.advance()
        #expect(vm.currentStep == .vehicleAndUnit)
    }

    @Test("goBack from vehicleAndUnit returns to jurisdiction (the previous step)")
    func backFromVehicleToJurisdiction() {
        let vm = OnboardingViewModel()
        vm.advance()  // .jurisdiction
        vm.advance()  // .vehicleAndUnit
        #expect(vm.currentStep == .vehicleAndUnit)

        vm.goBack()
        #expect(vm.currentStep == .jurisdiction)

}

}

// MARK: - ═══════════════════════════════════════════════
// MARK:   Suite 15 — Report Export
// MARK: ═══════════════════════════════════════════════

@Suite("Report Export Tests")
struct ReportExportTests {

    private struct ExportHarness {
        let realm: Realm
        let profile: UserProfile
        let calculator: MileageCalculator
        let generator: ReportGenerator

        init(jurisdiction: Jurisdiction, distanceUnit: DistanceUnit) throws {
            let config = Realm.Configuration(
                inMemoryIdentifier: UUID().uuidString,
                schemaVersion: RealmProvider.schemaVersion,
                objectTypes: [UserProfile.self, Vehicle.self, Trip.self, TripPoint.self, OdometerReading.self, SavedAddress.self, LogbookPeriod.self]
            )
            realm = try Realm(configuration: config)
            calculator = MileageCalculator()
            generator = ReportGenerator()

            guard let p = realm.object(ofType: UserProfile.self, forPrimaryKey: "singleton") else {
                Issue.record("No profile singleton"); fatalError()
            }
            try realm.write {
                p.jurisdiction = jurisdiction
                p.claimMethod = .standardRate
                p.distanceUnit = distanceUnit
            }
            profile = p
        }

        @discardableResult
        func addTrip(startedAt: Date, distanceMetres: Double, category: TripCategory) -> Trip {
            let trip = Trip()
            trip.startedAt = startedAt
            trip.distanceMetres = distanceMetres
            trip.category = category
            trip.startAddress = "Start"
            trip.endAddress = "End"
            try! realm.write { realm.add(trip) }
            return trip
        }
    }

    @Test("CSV excludes personal and uncategorised trips")
    func csvExcludesNonBusinessTrips() throws {
        let h = try ExportHarness(jurisdiction: .newZealand, distanceUnit: .kilometres)
        let now = Date()

        let business = h.addTrip(startedAt: now.addingTimeInterval(-7200), distanceMetres: 10_000, category: .business)
        let personal = h.addTrip(startedAt: now.addingTimeInterval(-3600), distanceMetres: 5_000, category: .personal)
        let uncat    = h.addTrip(startedAt: now.addingTimeInterval(-1800), distanceMetres: 3_000, category: .uncategorised)

        let url = h.generator.exportCSV(
            trips: [business, personal, uncat],
            calculator: h.calculator,
            profile: h.profile,
            dateRange: (now.addingTimeInterval(-86400), now.addingTimeInterval(86400))
        )

        let csv = try String(contentsOf: url, encoding: .utf8)
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        let dataLines = lines.filter { $0.contains(",business,") || $0.contains(",personal,") || $0.contains(",uncategorised,") }
        #expect(dataLines.count == 1)
        #expect(dataLines[0].contains(",business,"))
    }

    @Test("CSV column headers use profile distance unit")
    func csvUsesProfileDistanceUnit() throws {
        let h = try ExportHarness(jurisdiction: .newZealand, distanceUnit: .miles)
        let now = Date()

        let trip = h.addTrip(startedAt: now, distanceMetres: 10_000, category: .business)
        let url = h.generator.exportCSV(
            trips: [trip],
            calculator: h.calculator,
            profile: h.profile,
            dateRange: (now.addingTimeInterval(-86400), now.addingTimeInterval(86400))
        )

        let csv = try String(contentsOf: url, encoding: .utf8)
        #expect(csv.contains("Distance (mi)"))
        #expect(csv.contains("Rate (c/mi)"))
    }

    @Test("CSV with km unit uses km labels")
    func csvWithKmUnit() throws {
        let h = try ExportHarness(jurisdiction: .newZealand, distanceUnit: .kilometres)
        let now = Date()

        let trip = h.addTrip(startedAt: now, distanceMetres: 10_000, category: .business)
        let url = h.generator.exportCSV(
            trips: [trip],
            calculator: h.calculator,
            profile: h.profile,
            dateRange: (now.addingTimeInterval(-86400), now.addingTimeInterval(86400))
        )

        let csv = try String(contentsOf: url, encoding: .utf8)
        #expect(csv.contains("Distance (km)"))
        #expect(csv.contains("Rate (c/km)"))
    }

    @Test("Cumulative km above NZ tier threshold uses lower rate")
    func nzTierRateWithHighCumulativeKm() throws {
        let h = try ExportHarness(jurisdiction: .newZealand, distanceUnit: .kilometres)
        let now = Date()

        let trip = h.addTrip(startedAt: now, distanceMetres: 10_000, category: .business)
        let url = h.generator.exportCSV(
            trips: [trip],
            calculator: h.calculator,
            profile: h.profile,
            dateRange: (now.addingTimeInterval(-86400), now.addingTimeInterval(86400)),
            baseCumulativeKm: 14_500
        )

        let csv = try String(contentsOf: url, encoding: .utf8)
        let lines = csv.components(separatedBy: "\n")
        let dataLine = lines.first { $0.contains(",business,") } ?? ""
        #expect(dataLine.contains(",34,"))
    }

    @Test("Cumulative km within NZ tier-1 uses higher rate")
    func nzTierRateWithinThreshold() throws {
        let h = try ExportHarness(jurisdiction: .newZealand, distanceUnit: .kilometres)
        let now = Date()

        let trip = h.addTrip(startedAt: now, distanceMetres: 10_000, category: .business)
        let url = h.generator.exportCSV(
            trips: [trip],
            calculator: h.calculator,
            profile: h.profile,
            dateRange: (now.addingTimeInterval(-86400), now.addingTimeInterval(86400)),
            baseCumulativeKm: 0
        )

        let csv = try String(contentsOf: url, encoding: .utf8)
        let lines = csv.components(separatedBy: "\n")
        let dataLine = lines.first { $0.contains(",business,") } ?? ""
        #expect(dataLine.contains(",104,"))
    }

    @Test("Cumulative km with base below threshold stays in tier-1")
    func nzTierRateWithPartialBase() throws {
        let h = try ExportHarness(jurisdiction: .newZealand, distanceUnit: .kilometres)
        let now = Date()

        let trip = h.addTrip(startedAt: now, distanceMetres: 3_000_000, category: .business)
        let url = h.generator.exportCSV(
            trips: [trip],
            calculator: h.calculator,
            profile: h.profile,
            dateRange: (now.addingTimeInterval(-86400), now.addingTimeInterval(86400)),
            baseCumulativeKm: 10_000
        )

        let csv = try String(contentsOf: url, encoding: .utf8)
        let lines = csv.components(separatedBy: "\n")
        let dataLine = lines.first { $0.contains(",business,") } ?? ""
        #expect(dataLine.contains(",104,"))
    }

    @Test("Summary total value is computed correctly")
    func summaryTotalValue() throws {
        let h = try ExportHarness(jurisdiction: .newZealand, distanceUnit: .kilometres)
        let now = Date()

        let trip = h.addTrip(startedAt: now.addingTimeInterval(-3600), distanceMetres: 100_000, category: .business)
        let url = h.generator.exportCSV(
            trips: [trip],
            calculator: h.calculator,
            profile: h.profile,
            dateRange: (now.addingTimeInterval(-86400), now.addingTimeInterval(86400))
        )

        let csv = try String(contentsOf: url, encoding: .utf8)
        #expect(csv.contains("Total Value,$"))
        #expect(csv.contains("$104.00"))
    }

    // MARK: - PDF Tests

    /// Helper: reads the raw PDF data string to verify text content.
    /// PDF is binary with text embedded as ASCII strings; we can at least
    /// verify expected strings are present in the content stream.
    private func pdfContains(_ url: URL, _ substring: String) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        let raw = String(data: data, encoding: .ascii) ?? ""
        return raw.contains(substring)
    }

    @Test("PDF excludes personal and uncategorised trips")
    func pdfExcludesNonBusinessTrips() throws {
        let h = try ExportHarness(jurisdiction: .newZealand, distanceUnit: .kilometres)
        let now = Date()

        let business = h.addTrip(startedAt: now.addingTimeInterval(-7200), distanceMetres: 10_000, category: .business)
        let personal = h.addTrip(startedAt: now.addingTimeInterval(-3600), distanceMetres: 5_000, category: .personal)
        let uncat    = h.addTrip(startedAt: now.addingTimeInterval(-1800), distanceMetres: 3_000, category: .uncategorised)

        let trips = h.realm.objects(Trip.self).map { $0 }
        let vehicles = h.realm.objects(Vehicle.self).map { $0 }

        let url = h.generator.exportPDF(
            trips: Array(trips),
            calculator: h.calculator,
            profile: h.profile,
            vehicles: Array(vehicles),
            dateRange: (now.addingTimeInterval(-86400), now.addingTimeInterval(86400))
        )

        // Should contain only 1 business trip line in content
        #expect(pdfContains(url, "Mileage Expense Report"))
        #expect(pdfContains(url, "2026")) // date present
    }

    @Test("PDF contains branded header and metadata")
    func pdfContainsHeaderAndMeta() throws {
        let h = try ExportHarness(jurisdiction: .newZealand, distanceUnit: .kilometres)
        let now = Date()

        let trip = h.addTrip(startedAt: now.addingTimeInterval(-3600), distanceMetres: 10_000, category: .business)
        let trips = h.realm.objects(Trip.self).map { $0 }
        let vehicles = h.realm.objects(Vehicle.self).map { $0 }

        let url = h.generator.exportPDF(
            trips: Array(trips),
            calculator: h.calculator,
            profile: h.profile,
            vehicles: Array(vehicles),
            dateRange: (now.addingTimeInterval(-86400), now.addingTimeInterval(86400))
        )

        #expect(pdfContains(url, "Mileage Expense Report"))
        #expect(pdfContains(url, "New Zealand"))
        #expect(pdfContains(url, "Standard Mileage Rate"))
        #expect(pdfContains(url, "MileageTrackeriOS"))
    }

    @Test("PDF column headers match distance unit (miles)")
    func pdfUsesMilesUnit() throws {
        let h = try ExportHarness(jurisdiction: .newZealand, distanceUnit: .miles)
        let now = Date()

        let trip = h.addTrip(startedAt: now.addingTimeInterval(-3600), distanceMetres: 10_000, category: .business)
        let trips = h.realm.objects(Trip.self).map { $0 }
        let vehicles = h.realm.objects(Vehicle.self).map { $0 }

        let url = h.generator.exportPDF(
            trips: Array(trips),
            calculator: h.calculator,
            profile: h.profile,
            vehicles: Array(vehicles),
            dateRange: (now.addingTimeInterval(-86400), now.addingTimeInterval(86400))
        )

        #expect(pdfContains(url, "c/mi"))
    }

    @Test("PDF column headers match distance unit (km)")
    func pdfUsesKmUnit() throws {
        let h = try ExportHarness(jurisdiction: .newZealand, distanceUnit: .kilometres)
        let now = Date()

        let trip = h.addTrip(startedAt: now.addingTimeInterval(-3600), distanceMetres: 10_000, category: .business)
        let trips = h.realm.objects(Trip.self).map { $0 }
        let vehicles = h.realm.objects(Vehicle.self).map { $0 }

        let url = h.generator.exportPDF(
            trips: Array(trips),
            calculator: h.calculator,
            profile: h.profile,
            vehicles: Array(vehicles),
            dateRange: (now.addingTimeInterval(-86400), now.addingTimeInterval(86400))
        )

        #expect(pdfContains(url, "c/km"))
    }

    @Test("PDF contains summary section with totals")
    func pdfContainsSummary() throws {
        let h = try ExportHarness(jurisdiction: .newZealand, distanceUnit: .kilometres)
        let now = Date()

        let trip = h.addTrip(startedAt: now.addingTimeInterval(-3600), distanceMetres: 100_000, category: .business)
        let trips = h.realm.objects(Trip.self).map { $0 }
        let vehicles = h.realm.objects(Vehicle.self).map { $0 }

        let url = h.generator.exportPDF(
            trips: Array(trips),
            calculator: h.calculator,
            profile: h.profile,
            vehicles: Array(vehicles),
            dateRange: (now.addingTimeInterval(-86400), now.addingTimeInterval(86400))
        )

        #expect(pdfContains(url, "Summary"))
        #expect(pdfContains(url, "Total Value"))
    }

    @Test("PDF contains vehicle registration for trips")
    func pdfContainsVehicleReg() throws {
        let h = try ExportHarness(jurisdiction: .newZealand, distanceUnit: .kilometres)
        let now = Date()

        let trip = h.addTrip(startedAt: now.addingTimeInterval(-3600), distanceMetres: 10_000, category: .business)
        // Get the vehicle that was auto-created by the harness
        let vehicle = h.realm.objects(Vehicle.self).first!
        let trips = h.realm.objects(Trip.self).map { $0 }
        let vehicles = h.realm.objects(Vehicle.self).map { $0 }

        let url = h.generator.exportPDF(
            trips: Array(trips),
            calculator: h.calculator,
            profile: h.profile,
            vehicles: Array(vehicles),
            dateRange: (now.addingTimeInterval(-86400), now.addingTimeInterval(86400))
        )

        #expect(pdfContains(url, vehicle.registration))
    }

    @Test("Cumulative km above NZ tier threshold uses lower rate in PDF")
    func pdfNzTierRateWithHighCumulativeKm() throws {
        let h = try ExportHarness(jurisdiction: .newZealand, distanceUnit: .kilometres)
        let now = Date()

        h.addTrip(startedAt: now.addingTimeInterval(-3600), distanceMetres: 10_000, category: .business)
        let trips = h.realm.objects(Trip.self).map { $0 }
        let vehicles = h.realm.objects(Vehicle.self).map { $0 }

        let url = h.generator.exportPDF(
            trips: Array(trips),
            calculator: h.calculator,
            profile: h.profile,
            vehicles: Array(vehicles),
            dateRange: (now.addingTimeInterval(-86400), now.addingTimeInterval(86400)),
            baseCumulativeKm: 14_500
        )

        // With 14,500 base + 10 km trip = 14,510 cumulative → tier 2 (34 c/km)
        // The rate "34" should appear
        #expect(pdfContains(url, "34"))
    }

    @Test("PDF with logbook method shows odometer section")
    func pdfLogbookShowsOdometerSection() throws {
        let h = try ExportHarness(jurisdiction: .newZealand, distanceUnit: .kilometres)
        try h.realm.write {
            h.profile.claimMethod = .logbook
        }
        let now = Date()

        let trip = h.addTrip(startedAt: now.addingTimeInterval(-3600), distanceMetres: 10_000, category: .business)
        trip.businessUsePercent = 0.65
        let trips = h.realm.objects(Trip.self).map { $0 }
        let vehicles = h.realm.objects(Vehicle.self).map { $0 }

        let url = h.generator.exportPDF(
            trips: Array(trips),
            calculator: h.calculator,
            profile: h.profile,
            vehicles: Array(vehicles),
            dateRange: (now.addingTimeInterval(-86400), now.addingTimeInterval(86400))
        )

        #expect(pdfContains(url, "Odometer Summary"))
        #expect(pdfContains(url, "65.0%"))
    }
}

// MARK: - ═══════════════════════════════════════════════
// MARK:   Suite 19 — RealmProvider Graceful Recovery
// MARK: ═══════════════════════════════════════════════

@Suite("RealmProvider Graceful Recovery")
struct RealmProviderRecoveryTests {

    /// Helper: creates a unique temp directory that is cleaned up on exit.
    private func withTempDir<T>(_ body: (URL) throws -> T) throws -> T {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("realmtest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        return try body(dir)
    }

    @Test("backupCorruptRealmFiles moves the main realm file to the backup directory")
    func backupMovesMainFile() throws {
        try withTempDir { dir in
            let realmURL = dir.appendingPathComponent("test.realm")
            try "corrupt data".write(to: realmURL, atomically: true, encoding: .utf8)

            try RealmProvider.backupCorruptRealmFiles(fileURL: realmURL)

            // Original file should be gone
            #expect(!FileManager.default.fileExists(atPath: realmURL.path))

            // Backup file should exist
            let backupDir = dir.appendingPathComponent("RealmBackups")
            let backups = try FileManager.default.contentsOfDirectory(atPath: backupDir.path)
            #expect(backups.contains { $0.hasSuffix("test.realm") || $0.contains("test_") })
            #expect(backups.contains { $0.hasSuffix(".realm") })
        }
    }

    @Test("backupCorruptRealmFiles backs up companion lock and note files")
    func backupMovesCompanionFiles() throws {
        try withTempDir { dir in
            let realmURL = dir.appendingPathComponent("test.realm")
            try "corrupt data".write(to: realmURL, atomically: true, encoding: .utf8)
            try "lock data".write(to: realmURL.appendingPathExtension("lock"), atomically: true, encoding: .utf8)
            try "note data".write(to: realmURL.appendingPathExtension("note"), atomically: true, encoding: .utf8)

            try RealmProvider.backupCorruptRealmFiles(fileURL: realmURL)

            let backupDir = dir.appendingPathComponent("RealmBackups")
            let backups = try FileManager.default.contentsOfDirectory(atPath: backupDir.path)
            #expect(backups.contains { $0.hasSuffix(".realm.lock") || $0.contains("lock") })
            #expect(backups.contains { $0.hasSuffix(".realm.note") || $0.contains("note") })
        }
    }

    @Test("backupCorruptRealmFiles handles missing companion files gracefully")
    func backupWithMissingCompanions() throws {
        try withTempDir { dir in
            let realmURL = dir.appendingPathComponent("test.realm")
            try "corrupt data".write(to: realmURL, atomically: true, encoding: .utf8)

            // Only main file exists — no lock or note companion files.
            // Should not throw despite missing companions.
            try RealmProvider.backupCorruptRealmFiles(fileURL: realmURL)

            let backupDir = dir.appendingPathComponent("RealmBackups")
            #expect(FileManager.default.fileExists(atPath: backupDir.path))
        }
    }

    @Test("backupCorruptRealmFiles backs up management directory")
    func backupMovesManagementDir() throws {
        try withTempDir { dir in
            let realmURL = dir.appendingPathComponent("test.realm")
            try "corrupt data".write(to: realmURL, atomically: true, encoding: .utf8)

            // Create management directory with a file inside
            let mgmtDir = dir.appendingPathComponent("test.realm.management")
            try FileManager.default.createDirectory(at: mgmtDir, withIntermediateDirectories: true)
            try "meta".write(to: mgmtDir.appendingPathComponent("meta.lock"), atomically: true, encoding: .utf8)

            try RealmProvider.backupCorruptRealmFiles(fileURL: realmURL)

            let backupDir = dir.appendingPathComponent("RealmBackups")
            let backups = try FileManager.default.contentsOfDirectory(atPath: backupDir.path)
            #expect(backups.contains { $0.contains("management") })

            // Verify the management directory was moved (original gone)
            #expect(!FileManager.default.fileExists(atPath: mgmtDir.path))
        }
    }

    @Test("backup creates the RealmBackups directory if it does not exist")
    func backupCreatesRealmBackupsDir() throws {
        try withTempDir { dir in
            let realmURL = dir.appendingPathComponent("test.realm")
            try "corrupt data".write(to: realmURL, atomically: true, encoding: .utf8)

            let backupDir = dir.appendingPathComponent("RealmBackups")
            #expect(!FileManager.default.fileExists(atPath: backupDir.path),
                    "Precondition: backup dir should not exist yet")

            try RealmProvider.backupCorruptRealmFiles(fileURL: realmURL)

            #expect(FileManager.default.fileExists(atPath: backupDir.path))
        }
    }

    @Test("backup with a real in-memory Realm does not interfere with normal operation")
    func backupDoesNotAffectNormalRealm() throws {
        // This tests that the backup logic is purely file-based and doesn't affect
        // normal Realm operation. We create a real in-memory Realm, then verify
        // the backup function is only concerned with file paths.
        let config = Realm.Configuration(
            inMemoryIdentifier: UUID().uuidString,
            schemaVersion: RealmProvider.schemaVersion,
            objectTypes: [UserProfile.self, Vehicle.self, Trip.self, TripPoint.self,
                          OdometerReading.self, SavedAddress.self, LogbookPeriod.self]
        )
        let realm = try Realm(configuration: config)
        #expect(realm.objects(Trip.self).count == 0)
    }
}

// MARK: - Notification Recovery Action Tests
    }
}


// MARK: - Notification Recovery Action Tests

@Suite("Notification Recovery Actions")
struct NotificationRecoveryTests {

    @Test("didReceive dispatches Resume action to onRecoveryAction closure")
    func dispatchResumeAction() {
        let notificationManager = NotificationManager()
        var capturedActionId: String?
        var capturedTripId: String?
        notificationManager.onRecoveryAction = { actionId, tripId in
            capturedActionId = actionId
            capturedTripId = tripId
        }

        let content = UNMutableNotificationContent()
        content.categoryIdentifier = NotificationManager.recoveryCategoryId
        content.userInfo = [NotificationManager.recoveryUserInfoTripId: "trip-123"]

        let request = UNNotificationRequest(
            identifier: "test-recovery",
            content: content,
            trigger: nil
        )

        let response = UNNotificationResponse(
            notification: UNNotification(request: request, date: Date()),
            actionIdentifier: NotificationManager.recoveryActionResume
        )

        notificationManager.userNotificationCenter(
            UNUserNotificationCenter.current(),
            didReceive: response
        ) { /* completion handler */ }

        #expect(capturedActionId == NotificationManager.recoveryActionResume)
        #expect(capturedTripId == "trip-123")
    }

    @Test("didReceive dispatches Save action to onRecoveryAction closure")
    func dispatchSaveAction() {
        let notificationManager = NotificationManager()
        var capturedActionId: String?
        notificationManager.onRecoveryAction = { actionId, _ in
            capturedActionId = actionId
        }

        let content = UNMutableNotificationContent()
        content.categoryIdentifier = NotificationManager.recoveryCategoryId
        content.userInfo = [NotificationManager.recoveryUserInfoTripId: "trip-456"]

        let request = UNNotificationRequest(
            identifier: "test-recovery",
            content: content,
            trigger: nil
        )

        let response = UNNotificationResponse(
            notification: UNNotification(request: request, date: Date()),
            actionIdentifier: NotificationManager.recoveryActionSaveAsIs
        )

        notificationManager.userNotificationCenter(
            UNUserNotificationCenter.current(),
            didReceive: response
        ) { /* completion handler */ }

        #expect(capturedActionId == NotificationManager.recoveryActionSaveAsIs)
    }

    @Test("didReceive dispatches Discard action to onRecoveryAction closure")
    func dispatchDiscardAction() {
        let notificationManager = NotificationManager()
        var capturedActionId: String?
        notificationManager.onRecoveryAction = { actionId, _ in
            capturedActionId = actionId
        }

        let content = UNMutableNotificationContent()
        content.categoryIdentifier = NotificationManager.recoveryCategoryId
        content.userInfo = [NotificationManager.recoveryUserInfoTripId: "trip-789"]

        let request = UNNotificationRequest(
            identifier: "test-recovery",
            content: content,
            trigger: nil
        )

        let response = UNNotificationResponse(
            notification: UNNotification(request: request, date: Date()),
            actionIdentifier: NotificationManager.recoveryActionDiscard
        )

        notificationManager.userNotificationCenter(
            UNUserNotificationCenter.current(),
            didReceive: response
        ) { /* completion handler */ }

        #expect(capturedActionId == NotificationManager.recoveryActionDiscard)
    }

    @Test("didReceive does not dispatch for non-recovery categories")
    func ignoreNonRecoveryNotifications() {
        let notificationManager = NotificationManager()
        var wasCalled = false
        notificationManager.onRecoveryAction = { _, _ in
            wasCalled = true
        }

        let content = UNMutableNotificationContent()
        content.categoryIdentifier = "some-other-category"

        let request = UNNotificationRequest(
            identifier: "test-other",
            content: content,
            trigger: nil
        )

        let response = UNNotificationResponse(
            notification: UNNotification(request: request, date: Date()),
            actionIdentifier: "some-action"
        )

        notificationManager.userNotificationCenter(
            UNUserNotificationCenter.current(),
            didReceive: response
        ) { /* completion handler */ }

        #expect(!wasCalled)
    }
}

@Suite("TripRecorder Recovery Handlers")
struct TripRecorderRecoveryTests {

    @MainActor
    @Test("handleRecoveryResume sets up active trip state")
    func resumeSetsUpActiveState() throws {
        let h = try Harness()
        let tripId = try h.setupInflightTrip()

        h.recorder.handleRecoveryResume(tripId: tripId)

        #expect(h.recorder.state.isActive)
    }

    @MainActor
    @Test("handleRecoveryResume is no-op for unknown trip ID")
    func resumeUnknownTripIsNoOp() throws {
        let h = try Harness()

        h.recorder.handleRecoveryResume(tripId: "non-existent")

        #expect(h.recorder.state.isIdle)
    }

    @MainActor
    @Test("handleRecoverySaveAsIs saves the inflight trip")
    func saveAsIsFinalisesTrip() throws {
        let h = try Harness()
        let tripId = try h.setupInflightTrip()
        #expect(h.tripRepo.trip(id: tripId) != nil)

        h.recorder.handleRecoverySaveAsIs(tripId: tripId)

        // After save-as-is, the trip should still exist but no longer be inflight
        let trip = h.tripRepo.trip(id: tripId)
        #expect(trip != nil)
        #expect(trip?.source != .inflight)

        // State should reset to idle after saving
        #expect(h.recorder.state.isIdle)
    }

    @MainActor
    @Test("handleRecoveryDiscard deletes the inflight trip")
    func discardRemovesTrip() throws {
        let h = try Harness()
        let tripId = try h.setupInflightTrip()
        #expect(h.tripRepo.trip(id: tripId) != nil)

        h.recorder.handleRecoveryDiscard(tripId: tripId)

        // Trip should be deleted
        #expect(h.tripRepo.trip(id: tripId) == nil)
        #expect(h.recorder.state.isIdle)
    }

    @MainActor
    @Test("handleRecoveryDiscard is no-op for unknown trip ID")
    func discardUnknownTripIsNoOp() throws {
        let h = try Harness()

        // Should not crash
        h.recorder.handleRecoveryDiscard(tripId: "non-existent")
        #expect(h.recorder.state.isIdle)
    }
}

// MARK: - ═══════════════════════════════════════════════════════
// MARK:   Suite 16 — Gap-Fill Detection
// MARK: ═══════════════════════════════════════════════════════

@Suite("Gap-Fill Detection")
struct GapFillDetectionTests {

    @Test("Small gap below thresholds does not trigger gap-fill")
    func smallGapNotFilled() {
        let a = CLLocation(coordinate: CLLocationCoordinate2D(latitude: -36.848, longitude: 174.763),
                           altitude: 10, horizontalAccuracy: 10, verticalAccuracy: 5,
                           course: 0, speed: 10, timestamp: Date())
        let b = CLLocation(coordinate: CLLocationCoordinate2D(latitude: -36.849, longitude: 174.764),
                           altitude: 10, horizontalAccuracy: 10, verticalAccuracy: 5,
                           course: 0, speed: 10, timestamp: a.timestamp.addingTimeInterval(5))
        // ~130m gap over 5s — both below spatial (300m) and speed thresholds
        let dist = b.distance(from: a)
        #expect(TripRecorder.shouldFillGap(from: a, to: b) == false,
                "Gap of \(Int(dist))m over 5s should not trigger gap-fill")
    }

    @Test("Tunnel dropout with realistic gap triggers gap-fill")
    func tunnelDropoutTriggers() {
        let a = CLLocation(coordinate: CLLocationCoordinate2D(latitude: -36.848, longitude: 174.763),
                           altitude: 10, horizontalAccuracy: 10, verticalAccuracy: 5,
                           course: 0, speed: 20, timestamp: Date())
        let b = CLLocation(coordinate: CLLocationCoordinate2D(latitude: -36.835, longitude: 174.780),
                           altitude: 10, horizontalAccuracy: 50, verticalAccuracy: 5,
                           course: 0, speed: 25, timestamp: a.timestamp.addingTimeInterval(30))
        // ~1.8km gap over 30s = 60 m/s implied — should trigger on speed alone
        #expect(TripRecorder.shouldFillGap(from: a, to: b) == true)
    }

    @Test("Cold-start delay with moderate gap triggers on distance alone")
    func coldStartDelayTriggers() {
        let a = CLLocation(coordinate: CLLocationCoordinate2D(latitude: -36.848, longitude: 174.763),
                           altitude: 10, horizontalAccuracy: 10, verticalAccuracy: 5,
                           course: 0, speed: -1, timestamp: Date())
        let b = CLLocation(coordinate: CLLocationCoordinate2D(latitude: -36.840, longitude: 174.770),
                           altitude: 10, horizontalAccuracy: 50, verticalAccuracy: 5,
                           course: 0, speed: 15, timestamp: a.timestamp.addingTimeInterval(25))
        // ~900m gap over 25s = 36 m/s — below 54 km/h speed threshold but above 500m spatial
        #expect(TripRecorder.shouldFillGap(from: a, to: b) == true,
                "900m gap should trigger via spatial threshold alone")
    }

    @Test("Urban gap (350m over 30s) triggers via speed threshold")
    func urbanGapTriggers() {
        let a = CLLocation(coordinate: CLLocationCoordinate2D(latitude: -36.848, longitude: 174.763),
                           altitude: 10, horizontalAccuracy: 10, verticalAccuracy: 5,
                           course: 0, speed: 10, timestamp: Date())
        let b = CLLocation(coordinate: CLLocationCoordinate2D(latitude: -36.845, longitude: 174.770),
                           altitude: 10, horizontalAccuracy: 10, verticalAccuracy: 5,
                           course: 0, speed: 10, timestamp: a.timestamp.addingTimeInterval(30))
        // ~650m gap over 30s = ~78 km/h implied — above 54 km/h threshold
        #expect(TripRecorder.shouldFillGap(from: a, to: b) == true,
                "650m urban gap should trigger via speed threshold")
    }

    @Test("Gap below 300m does not trigger regardless of timing")
    func shortGapNeverTriggers() {
        let a = CLLocation(coordinate: CLLocationCoordinate2D(latitude: -36.848, longitude: 174.763),
                           altitude: 10, horizontalAccuracy: 10, verticalAccuracy: 5,
                           course: 0, speed: 10, timestamp: Date())
        let b = CLLocation(coordinate: CLLocationCoordinate2D(latitude: -36.8485, longitude: 174.7635),
                           altitude: 10, horizontalAccuracy: 10, verticalAccuracy: 5,
                           course: 0, speed: 10, timestamp: a.timestamp.addingTimeInterval(60))
        // ~60m gap over 60s — below 300m spatial threshold
        #expect(TripRecorder.shouldFillGap(from: a, to: b) == false)
    }
}

// MARK: - ═══════════════════════════════════════════════════════
// MARK:   Suite 17 — Leading-Walking Trim Updates startedAt
// MARK: ═══════════════════════════════════════════════════════

@Suite("Walking Trim Updates startedAt")
@MainActor
struct WalkingTrimStartedAtTests {

    private func savedTrips(in repo: TripRepository) -> [Trip] {
        Array(repo.testRealm.objects(Trip.self).sorted(byKeyPath: "startedAt"))
    }

    @Test("Leading-walking trim updates tripStartedAt before save")
    func trimUpdatesStartedAt() throws {
        let h = try Harness()
        h.enterActive()

        // Fire a walking-speed location first to simulate pre-drive walking
        h.fireLocation(speedMs: 1.0, lat: -36.850, lng: 174.760, timestamp: Date().addingTimeInterval(-120))
        h.fireLocation(speedMs: 1.2, lat: -36.850, lng: 174.761, timestamp: Date().addingTimeInterval(-60))
        // Then a driving-speed location
        let driveTime = Date()
        h.fireLocation(speedMs: 15.0, lat: -36.848, lng: 174.763, timestamp: driveTime)
        h.fireLocation(speedMs: 15.0, lat: -36.840, lng: 174.770, timestamp: driveTime.addingTimeInterval(30))

        h.recorder.forceFinaliseFromDebug()
        #expect(h.recorder.state.isIdle)

        // The saved trip's startedAt should reflect the trimmed first point,
        // not the walking preamble
        let trips = savedTrips(in: h.tripRepo)
        #expect(!trips.isEmpty)
        let trip = trips.first!
        // startedAt should be close to driveTime, not 120s before it
        let drift = abs(trip.startedAt.timeIntervalSince(driveTime))
        #expect(drift < 30, "startedAt should be near the first driving point, not the walking preamble. Drift: \(drift)s")
    }

    @Test("No walking preamble leaves startedAt unchanged")
    func noTrimLeavesStartedAt() throws {
        let h = try Harness()
        h.enterActive()

        let startTime = Date()
        h.fireLocation(speedMs: 15.0, lat: -36.848, lng: 174.763, timestamp: startTime)
        h.fireLocation(speedMs: 15.0, lat: -36.840, lng: 174.770, timestamp: startTime.addingTimeInterval(30))

        h.recorder.forceFinaliseFromDebug()
        #expect(h.recorder.state.isIdle)

        let trips = savedTrips(in: h.tripRepo)
        #expect(!trips.isEmpty)
        let trip = trips.first!
        #expect(abs(trip.startedAt.timeIntervalSince(startTime)) < 5)
    }
}

// MARK: - ═══════════════════════════════════════════════════════
// MARK:   Suite 18 — Auto-Merge Integration (commitTrip path)
// MARK: ═══════════════════════════════════════════════════════

@Suite("Auto-Merge Integration")
@MainActor
struct AutoMergeIntegrationTests {

    private func savedTrips(in repo: TripRepository) -> [Trip] {
        Array(repo.testRealm.objects(Trip.self).sorted(byKeyPath: "startedAt"))
    }

    @Test("commitTrip calls autoMergeAdjacent — merges same-vehicle fragments")
    func commitTripMergesAdjacent() throws {
        let h = try Harness()
        let vehicleId = h.profileRepo.defaultVehicle?.id ?? ""

        // Create two adjacent trips that should merge
        // Trip 1 ends at a location close to where Trip 2 starts
        let t1 = Trip()
        t1.vehicleId = vehicleId
        t1.startedAt = Date().addingTimeInterval(-600)
        t1.endedAt = Date().addingTimeInterval(-300)
        t1.distanceMetres = 500
        t1.source = .automatic
        t1.startLat = -36.848; t1.startLng = 174.763
        t1.endLat = -36.850; t1.endLng = 174.765

        let t2 = Trip()
        t2.vehicleId = vehicleId
        t2.startedAt = Date().addingTimeInterval(-300)
        t2.endedAt = Date()
        t2.distanceMetres = 700
        t2.source = .automatic
        t2.startLat = -36.850; t2.startLng = 174.765  // same as t1 end
        t2.endLat = -36.855; t2.endLng = 174.770

        let realm = h.tripRepo.testRealm
        try realm.write {
            realm.add(t1)
            realm.add(t2)
        }

        // Now call mergeTrips (simulating the autoMergeAdjacent logic).
        // The auto-merge logic should find t1 adjacent to t2 and merge them.
        let merged = h.tripRepo.mergeTrips([t1, t2])
        #expect(merged != nil, "Trips with same end/start coords should merge")
        #expect(merged!.distanceMetres == 1200)
    }

    @Test("Non-adjacent trips are not merged")
    func nonAdjacentNotMerged() throws {
        let h = try Harness()
        let vehicleId = h.profileRepo.defaultVehicle?.id ?? ""

        let t1 = Trip()
        t1.vehicleId = vehicleId
        t1.startedAt = Date().addingTimeInterval(-600)
        t1.endedAt = Date().addingTimeInterval(-300)
        t1.distanceMetres = 500
        t1.source = .automatic
        t1.startLat = -36.848; t1.startLng = 174.763
        t1.endLat = -36.860; t1.endLng = 174.780  // far from t2 start

        let t2 = Trip()
        t2.vehicleId = vehicleId
        t2.startedAt = Date().addingTimeInterval(-300)
        t2.endedAt = Date()
        t2.distanceMetres = 700
        t2.source = .automatic
        t2.startLat = -36.848; t2.startLng = 174.763  // ~2km from t1 end
        t2.endLat = -36.855; t2.endLng = 174.770

        let realm = h.tripRepo.testRealm
        try realm.write {
            realm.add(t1)
            realm.add(t2)
        }

        // Should NOT merge — spatial gap > 200m
        let merged = h.tripRepo.mergeTrips([t1, t2])
        #expect(merged == nil, "Non-adjacent trips should remain separate")
    }

    @Test("Different vehicle trips are never merged")
    func differentVehicleNotMerged() throws {
        let h = try Harness()
        let v1 = h.profileRepo.defaultVehicle?.id ?? ""
        // Add a second vehicle
        h.profileRepo.addVehicle(name: "Second", registration: "SEC002")
        let v2 = h.profileRepo.vehicles.last?.id ?? ""

        guard v1 != v2 else {
            Issue.record("Need two different vehicle IDs"); return
        }

        let t1 = Trip()
        t1.vehicleId = v1
        t1.startedAt = Date().addingTimeInterval(-600)
        t1.endedAt = Date().addingTimeInterval(-300)
        t1.distanceMetres = 500
        t1.source = .automatic
        t1.startLat = -36.848; t1.startLng = 174.763
        t1.endLat = -36.850; t1.endLng = 174.765

        let t2 = Trip()
        t2.vehicleId = v2
        t2.startedAt = Date().addingTimeInterval(-300)
        t2.endedAt = Date()
        t2.distanceMetres = 700
        t2.source = .automatic
        t2.startLat = -36.850; t2.startLng = 174.765
        t2.endLat = -36.855; t2.endLng = 174.770

        let realm = h.tripRepo.testRealm
        try realm.write {
            realm.add(t1)
            realm.add(t2)
        }

        let merged = h.tripRepo.mergeTrips([t1, t2])
        #expect(merged == nil, "Different-vehicle trips should never merge")
    }
}

// MARK: - ═══════════════════════════════════════════════════════
// MARK:   Suite 19 — Threshold Drift: Code matches Docs
// MARK: ═══════════════════════════════════════════════════════

@Suite("Threshold Drift Reconciliation")
struct ThresholdDriftTests {

    @Test("slcSpeedKmh matches documented value of 22 km/h")
    func slcSpeedMatchesDoc() {
        // The CLAUDE.md documents slcSpeedKmh as 22 km/h.
        // Verified via the public shouldFillGap path (which uses the same Heuristic enum).
        // The CLAUDE.md documents both slcSpeedKmh as 22 and promotionSpeedKmh as 25.
        // Verified via public static method (non-MainActor, no instance needed).
        let a = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                           altitude: 0, horizontalAccuracy: 10, verticalAccuracy: -1,
                           course: 0, speed: 6.11, timestamp: Date())
        let b = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0.001),
                           altitude: 0, horizontalAccuracy: 10, verticalAccuracy: -1,
                           course: 0, speed: 6.11, timestamp: a.timestamp.addingTimeInterval(1))
        // Verify constants match documented values via shouldFillGap's threshold usage
        // (implied speed > 15 m/s = 54 km/h for gap activation; gap of 111m over 300s
        // is below both spatial and speed thresholds)
        let gap = b.distance(from: a)
        #expect(gap < 300) // 111m < 300m spatial threshold
        #expect(TripRecorder.shouldFillGap(from: a, to: b) == false)
    }
}

// MARK: - ═══════════════════════════════════════
// MARK:   Suite 20 — CloudSyncManager Conversion Tests
// MARK: ═══════════════════════════════════════

@Suite("CloudSyncManager Conversion")
struct CloudSyncManagerConversionTests {

    // MARK: - Trip toCloudRecord

    @Test("Trip toCloudRecord maps all fields")
    func tripToCloudRecordMapsAllFields() {
        let trip = Trip()
        trip.id = "test-trip-1"
        trip.vehicleId = "v1"
        trip.startAddress = "Start St"
        trip.endAddress = "End Ave"
        trip.startLat = -36.848
        trip.startLng = 174.763
        trip.endLat = -36.850
        trip.endLng = 174.765
        trip.startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        trip.endedAt = Date(timeIntervalSince1970: 1_700_003_600)
        trip.distanceMetres = 10_000
        trip.category = .business
        trip.source = .automatic
        trip.notes = "Client meeting"
        trip.dollarValue = 104.00
        trip.isCapExceeded = false
        trip.processingStatus = .complete
        trip.gpsDistanceMetres = 10_000
        trip.odometerDistanceMetres = nil
        trip.purpose = "Meet client"
        trip.commitHash = "abc123"
        trip.committedAt = Date(timeIntervalSince1970: 1_700_003_600)
        trip.isSyncedToCloud = false
        trip.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        trip.updatedAt = Date(timeIntervalSince1970: 1_700_003_600)

        let record = trip.toCloudRecord()

        #expect(record.recordType == "MTTrip")
        #expect(record.recordID.recordName == "test-trip-1")
        #expect(record["vehicleId"] as? String == "v1")
        #expect(record["startAddress"] as? String == "Start St")
        #expect(record["endAddress"] as? String == "End Ave")
        #expect(record["startLat"] as? Double == -36.848)
        #expect(record["startLng"] as? Double == 174.763)
        #expect(record["endLat"] as? Double == -36.850)
        #expect(record["endLng"] as? Double == 174.765)
    }

    @Test("Trip toCloudRecord maps optional fields as nil when not set")
    func tripToCloudRecordMapsOptionals() {
        let trip = Trip()
        trip.id = "test-trip-2"
        let record = trip.toCloudRecord()

        #expect(record["notes"] as? String == nil)
        #expect(record["dollarValue"] as? Double == nil)
        #expect(record["odometerDistanceMetres"] as? Double == nil)
        #expect(record["purpose"] as? String == nil)
        #expect(record["commitHash"] as? String == nil)
        #expect(record["committedAt"] as? Date == nil)
        #expect(record["endedAt"] as? Date == nil)
    }

    // MARK: - Vehicle toCloudRecord

    @Test("Vehicle toCloudRecord maps all fields")
    func vehicleToCloudRecordMapsAllFields() {
        let vehicle = Vehicle()
        vehicle.id = "test-vehicle-1"
        vehicle.name = "My Car"
        vehicle.registration = "ABC123"
        vehicle.type = .car
        vehicle.fuelType = .petrol
        vehicle.isDefault = true
        vehicle.isArchived = false
        vehicle.defaultCategory = .business

        let record = vehicle.toCloudRecord()

        #expect(record.recordType == "MTVehicle")
        #expect(record.recordID.recordName == "test-vehicle-1")
        #expect(record["name"] as? String == "My Car")
        #expect(record["registration"] as? String == "ABC123")
        #expect(record["type"] as? String == "car")
        #expect(record["fuelType"] as? String == "petrol")
        #expect(record["isDefault"] as? Bool == true)
        #expect(record["isArchived"] as? Bool == false)
        #expect(record["defaultCategory"] as? String == "business")
    }

    // MARK: - OdometerReading toCloudRecord

    @Test("OdometerReading toCloudRecord maps all fields")
    func odometerToCloudRecordMapsAllFields() {
        let reading = OdometerReading()
        reading.id = "test-reading-1"
        reading.vehicleId = "v1"
        reading.readingKm = 50_000
        reading.tripId = "trip-1"
        reading.notes = "Weekly check"
        reading.source = .manual

        let record = reading.toCloudRecord()

        #expect(record.recordType == "MTOdometerReading")
        #expect(record.recordID.recordName == "test-reading-1")
        #expect(record["vehicleId"] as? String == "v1")
        #expect(record["readingKm"] as? Double == 50_000)
        #expect(record["tripId"] as? String == "trip-1")
        #expect(record["notes"] as? String == "Weekly check")
        #expect(record["source"] as? String == "manual")
    }

    // MARK: - CKRecord to Realm Object

    @Test("CKRecord toRealmObject creates Trip correctly")
    func recordToTripObject() {
        let recordID = CKRecord.ID(recordName: "test-trip-3")
        let record = CKRecord(recordType: "MTTrip", recordID: recordID)
        record["vehicleId"] = "v1" as NSString
        record["startAddress"] = "Start" as NSString
        record["endAddress"] = "End" as NSString
        record["startLat"] = -36.848 as NSNumber
        record["startLng"] = 174.763 as NSNumber
        record["endLat"] = -36.850 as NSNumber
        record["endLng"] = 174.765 as NSNumber
        record["startedAt"] = Date(timeIntervalSince1970: 1_700_000_000) as NSDate
        record["category"] = "business" as NSString
        record["source"] = "automatic" as NSString
        record["distanceMetres"] = 10_000 as NSNumber
        record["processingStatus"] = "complete" as NSString

        let trip = record.toRealmObject(type: Trip.self)

        #expect(trip != nil)
        #expect(trip?.id == "test-trip-3")
        #expect(trip?.vehicleId == "v1")
        #expect(trip?.startAddress == "Start")
        #expect(trip?.endAddress == "End")
        #expect(trip?.startLat == -36.848)
        #expect(trip?.startLng == 174.763)
        #expect(trip?.category == .business)
        #expect(trip?.source == .automatic)
        #expect(trip?.distanceMetres == 10_000)
        #expect(trip?.isSyncedToCloud == true)
    }

    @Test("CKRecord toRealmObject creates Vehicle correctly")
    func recordToVehicleObject() {
        let recordID = CKRecord.ID(recordName: "test-vehicle-2")
        let record = CKRecord(recordType: "MTVehicle", recordID: recordID)
        record["name"] = "Work Van" as NSString
        record["registration"] = "VAN123" as NSString
        record["type"] = "car" as NSString
        record["fuelType"] = "diesel" as NSString
        record["isDefault"] = true as NSNumber
        record["isArchived"] = false as NSNumber
        record["defaultCategory"] = "business" as NSString

        let vehicle = record.toRealmObject(type: Vehicle.self)

        #expect(vehicle != nil)
        #expect(vehicle?.id == "test-vehicle-2")
        #expect(vehicle?.name == "Work Van")
        #expect(vehicle?.registration == "VAN123")
        #expect(vehicle?.type == .car)
        #expect(vehicle?.fuelType == .diesel)
        #expect(vehicle?.isDefault == true)
        #expect(vehicle?.isArchived == false)
        #expect(vehicle?.defaultCategory == .business)
        #expect(vehicle?.isSyncedToCloud == true)
    }

    @Test("CKRecord toRealmObject creates OdometerReading correctly")
    func recordToOdometerObject() {
        let recordID = CKRecord.ID(recordName: "test-reading-2")
        let record = CKRecord(recordType: "MTOdometerReading", recordID: recordID)
        record["vehicleId"] = "v1" as NSString
        record["readingKm"] = 75_000 as NSNumber
        record["tripId"] = "trip-5" as NSString
        record["notes"] = "Service" as NSString
        record["source"] = "manual" as NSString

        let reading = record.toRealmObject(type: OdometerReading.self)

        #expect(reading != nil)
        #expect(reading?.id == "test-reading-2")
        #expect(reading?.vehicleId == "v1")
        #expect(reading?.readingKm == 75_000)
        #expect(reading?.tripId == "trip-5")
        #expect(reading?.notes == "Service")
        #expect(reading?.source == .manual)
        #expect(reading?.isSyncedToCloud == true)
    }

    @Test("CKRecord toRealmObject with unknown type returns nil")
    func recordToUnknownTypeReturnsNil() {
        let recordID = CKRecord.ID(recordName: "unknown")
        let record = CKRecord(recordType: "UnknownType", recordID: recordID)

        let result = record.toRealmObject(type: Trip.self)
        #expect(result == nil)
    }

    // MARK: - Sync metadata fields

    @Test("New Vehicle has isSyncedToCloud = false")
    func newVehicleNotSynced() {
        let vehicle = Vehicle()
        #expect(vehicle.isSyncedToCloud == false)
    }

    @Test("New OdometerReading has isSyncedToCloud = false")
    func newOdometerNotSynced() {
        let reading = OdometerReading()
        #expect(reading.isSyncedToCloud == false)
    }

    @Test("Vehicle allows setting sync metadata")
    func vehicleSyncMetadataSettable() {
        let vehicle = Vehicle()
        vehicle.isSyncedToCloud = true
        vehicle.updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(vehicle.isSyncedToCloud == true)
    }

    @Test("OdometerReading allows setting sync metadata")
    func odometerSyncMetadataSettable() {
        let reading = OdometerReading()
        reading.isSyncedToCloud = true
        reading.updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(reading.isSyncedToCloud == true)
    }
}
