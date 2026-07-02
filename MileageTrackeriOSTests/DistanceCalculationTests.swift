import Testing
import CoreLocation
import CoreMotion
import RealmSwift
@testable import MileageTrackeriOS

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

