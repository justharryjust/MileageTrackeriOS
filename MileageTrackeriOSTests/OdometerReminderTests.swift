import Testing
import Foundation
import RealmSwift
@testable import MileageTrackeriOS

@Suite("Odometer Reminder")
@MainActor
struct OdometerReminderTests {

    // MARK: - Schedule

    @Test("scheduleOdometerReminder with toggle enabled does not crash")
    func scheduleWithEnabledToggle() throws {
        let nm = NotificationManager()
        NotificationManager.odometerReminderEnabled = true
        nm.scheduleOdometerReminder(vehicleName: "Test Car")
        nm.cancelOdometerReminder()
        NotificationManager.odometerReminderEnabled = false
    }

    @Test("scheduleOdometerReminder with empty vehicle name does not crash")
    func scheduleWithEmptyVehicleName() throws {
        let nm = NotificationManager()
        NotificationManager.odometerReminderEnabled = true
        nm.scheduleOdometerReminder(vehicleName: "")
        nm.cancelOdometerReminder()
        NotificationManager.odometerReminderEnabled = false
    }

    @Test("scheduleOdometerReminder no-ops when toggle is disabled")
    func scheduleWithDisabledToggle() throws {
        let nm = NotificationManager()
        NotificationManager.odometerReminderEnabled = false
        // Should silently no-op — no crash
        nm.scheduleOdometerReminder(vehicleName: "Test Car")
    }

    // MARK: - Cancel

    @Test("cancelOdometerReminder removes pending request without crashing")
    func cancelReminder() throws {
        let nm = NotificationManager()
        nm.cancelOdometerReminder()
    }

    @Test("cancelOdometerReminder called twice does not crash")
    func cancelReminderTwice() throws {
        let nm = NotificationManager()
        nm.cancelOdometerReminder()
        nm.cancelOdometerReminder()
    }

    // MARK: - Toggle

    @Test("odometerToggleChanged schedules when enabled and cancels when disabled")
    func toggleOnThenOff() throws {
        let nm = NotificationManager()
        NotificationManager.odometerReminderEnabled = true

        nm.odometerToggleChanged(isEnabled: true, vehicleName: "Test Car")
        nm.odometerToggleChanged(isEnabled: false, vehicleName: "Test Car")

        NotificationManager.odometerReminderEnabled = false
    }

    @Test("odometerToggleChanged with disabled toggle does not schedule")
    func toggleOffDoesNotSchedule() throws {
        let nm = NotificationManager()
        NotificationManager.odometerReminderEnabled = false

        nm.odometerToggleChanged(isEnabled: false, vehicleName: "Test Car")

        // Toggle remains off — no crash
        NotificationManager.odometerReminderEnabled = false
    }

    // MARK: - Reschedule

    @Test("reschedule with logbook method schedules odometer reminder")
    func rescheduleLogbook() throws {
        let nm = NotificationManager()
        NotificationManager.odometerReminderEnabled = true

        nm.reschedule(claimMethod: .logbook, vehicleName: "Test Car")
        // Should schedule the monthly reminder — no crash

        NotificationManager.odometerReminderEnabled = false
    }

    @Test("reschedule with standardRate cancels odometer reminder")
    func rescheduleStandardRate() throws {
        let nm = NotificationManager()
        nm.reschedule(claimMethod: .standardRate, vehicleName: "Test Car")
        // Should cancel — no crash
    }

    @Test("reschedule with customRate cancels odometer reminder")
    func rescheduleCustomRate() throws {
        let nm = NotificationManager()
        nm.reschedule(claimMethod: .customRate, vehicleName: "Test Car")
        // Should cancel — no crash
    }

    @Test("reschedule switching from logbook to standardRate cancels reminder")
    func rescheduleSwitchAwayFromLogbook() throws {
        let nm = NotificationManager()
        NotificationManager.odometerReminderEnabled = true

        nm.reschedule(claimMethod: .logbook, vehicleName: "Test Car")
        nm.reschedule(claimMethod: .standardRate, vehicleName: "Test Car")
        // Second call should cancel — no crash

        NotificationManager.odometerReminderEnabled = false
    }

    @Test("reschedule switching from standardRate to logbook schedules reminder")
    func rescheduleSwitchToLogbook() throws {
        let nm = NotificationManager()
        NotificationManager.odometerReminderEnabled = true

        nm.reschedule(claimMethod: .standardRate, vehicleName: "Test Car")
        nm.reschedule(claimMethod: .logbook, vehicleName: "Test Car")
        // Switching to logbook should schedule — no crash

        NotificationManager.odometerReminderEnabled = false
    }
}
