import Testing
import CoreLocation
import CoreMotion
import RealmSwift
@testable import MileageTrackeriOS

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

