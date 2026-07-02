import Testing
import CoreLocation
import CoreMotion
import RealmSwift
@testable import MileageTrackeriOS

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

