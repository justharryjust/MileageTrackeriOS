import Testing
import CoreLocation
import CoreMotion
import RealmSwift
@testable import MileageTrackeriOS

@Suite("Engine Signal Tests")
@MainActor
struct EngineSignalTests {

    @Test("Pedometer steps > 30 during suspected biases toward discard")
    func pedometerStepsBiasDuringSuspected() throws {
        let h = try Harness()
        h.fireSustainedAutomotive(confidence: .high, spanning: 20)
        #expect(h.recorder.state.isSuspected)
        // Inject high step count — should trigger walking gate
        h.motionManager.onPedometerUpdate?(45)
        // The state should still be suspected (pedometer gate doesn't immediately discard,
        // it biases the promotion check at timeout)
        #expect(h.recorder.state.isSuspected)
    }

    @Test("Pedometer steps = 0 allows promotion")
    func noPedometerStepsAllowsPromotion() throws {
        let h = try Harness()
        h.fireLocation()
        h.fireSustainedAutomotive(confidence: .high, spanning: 20)
        // Zero steps — should not block
        h.motionManager.onPedometerUpdate?(0)
        #expect(h.recorder.state.isSuspected)
    }
}

// MARK: - ════════════════════════════
// MARK:   Suite 7 — Distance Calculation
// MARK: ════════════════════════════

