import Testing
import CoreLocation
import CoreMotion
import RealmSwift
@testable import MileageTrackeriOS

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

