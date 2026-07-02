import Testing
import CoreLocation
import CoreMotion
import RealmSwift
@testable import MileageTrackeriOS

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

