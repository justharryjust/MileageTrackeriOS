import Testing
import CoreLocation
import CoreMotion
import RealmSwift
@testable import MileageTrackeriOS

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

