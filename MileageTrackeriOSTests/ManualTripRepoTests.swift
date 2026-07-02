import Testing
import CoreLocation
import CoreMotion
import RealmSwift
@testable import MileageTrackeriOS

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
}

// MARK:   Suite 11 — Onboarding Region Validation
// MARK: ═══════════════════════════════════════════════

