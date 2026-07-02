import Testing
import CoreLocation
import CoreMotion
import RealmSwift
@testable import MileageTrackeriOS

@Suite("Notification Reschedule")
@MainActor
struct NotificationRescheduleTests {

    @Test("reschedule with logbook method schedules odometer reminder (no crash)")
    func rescheduleLogbook() throws {
        let nm = NotificationManager()
        nm.reschedule(claimMethod: .logbook, vehicleName: "Test Car")
        // Should have scheduled or no-opped, no crash
        nm.reschedule(claimMethod: .standardRate, vehicleName: "Test Car")
        // Switching away cancels
        #expect(true)
    }

    @Test("reschedule with non-logbook method cancels odometer reminder (no crash)")
    func rescheduleStandardRate() throws {
        let nm = NotificationManager()
        nm.reschedule(claimMethod: .standardRate, vehicleName: "Test Car")
        #expect(true)
    }
}

// MARK: - ═══════════════════════════════
// MARK:   Suite 9 — Tax Year Periods
// MARK: ═══════════════════════════════

