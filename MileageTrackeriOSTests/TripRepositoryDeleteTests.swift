import Testing
import CoreLocation
import CoreMotion
import RealmSwift
@testable import MileageTrackeriOS

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

// MARK: - ═══════════════════════════════════════════

// MARK:   Suite 9 — Onboarding Navigation
// MARK: ═══════════════════════════════════════════

