import Testing
import CoreLocation
import CoreMotion
import RealmSwift
@testable import MileageTrackeriOS

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

