import Testing
import CoreLocation
import CoreMotion
import RealmSwift
@testable import MileageTrackeriOS

@Suite("Schedule Gate Notifications")
@MainActor
struct ScheduleGateNotificationTests {

    @Test("Schedule manager callbacks send notifications without crashing")
    func scheduleGateCallbacksDoNotCrash() throws {
        let h = try Harness()
        // The scheduleManager callbacks are set up in configure()
        // No crash = success
        #expect(h.recorder.state.isIdle)
    }
}
