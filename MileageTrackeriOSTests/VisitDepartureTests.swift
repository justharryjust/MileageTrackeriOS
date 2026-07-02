import Testing
import CoreLocation
import CoreMotion
import RealmSwift
@testable import MileageTrackeriOS

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

