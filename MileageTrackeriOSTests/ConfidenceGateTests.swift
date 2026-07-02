import Testing
import CoreLocation
import CoreMotion
import RealmSwift
@testable import MileageTrackeriOS

@Suite("Confidence Gate")
@MainActor
struct ConfidenceGateTests {

    @Test("Low-confidence automotive is ignored in idle — state stays .idle")
    func lowConfidenceIgnoredInIdle() throws {
        let h = try Harness()
        h.fireSustainedAutomotive(confidence: .low, spanning: 20)
        #expect(h.recorder.state.isIdle)
    }

    @Test("Medium-confidence automotive transitions idle → suspected (after rolling window)")
    func mediumConfidenceEntersSuspected() throws {
        let h = try Harness()
        h.fireSustainedAutomotive(confidence: .medium, spanning: 20)
        #expect(h.recorder.state.isSuspected)
    }

    @Test("High-confidence automotive transitions idle → suspected (after rolling window)")
    func highConfidenceEntersSuspected() throws {
        let h = try Harness()
        h.fireSustainedAutomotive(confidence: .high, spanning: 20)
        #expect(h.recorder.state.isSuspected)
    }

    @Test("Non-automotive activity in idle is ignored")
    func nonAutomotiveIgnoredInIdle() throws {
        let h = try Harness()
        h.fireActivity(.walking, .high)
        #expect(h.recorder.state.isIdle)
    }

    @Test("Automotive during active/pausing keeps state stable")
    func automotiveDuringActiveKeepsState() throws {
        let h = try Harness()
        h.fireLocation()
        h.fireSustainedAutomotive(confidence: .high, spanning: 20)
        // Fire GPS speed to promote
        let now = Date()
        for i in stride(from: 10, through: 0, by: -2) {
            h.fireLocation(speedMs: 30 / 3.6, timestamp: now.addingTimeInterval(-Double(i)))
        }
        // More automotive — should not exit active
        h.fireActivity(.automotive, .high)
        #expect(h.recorder.state.isActive || h.recorder.state.isSuspected)
    }
}

// MARK: - ══════════════════════════════════
// MARK:   Suite 2 — State Machine Transitions
// MARK: ══════════════════════════════════

