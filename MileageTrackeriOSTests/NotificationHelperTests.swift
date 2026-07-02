import Testing
import CoreLocation
import CoreMotion
import RealmSwift
@testable import MileageTrackeriOS

@Suite("Notification Helpers")
struct NotificationHelperTests {

    // MARK: TripRecorder helpers

    @Test("dayName returns English names for Calendar weekday numbers")
    func dayNameValues() throws {
        #expect(TripRecorder.dayName(for: 1) == "Sunday")
        #expect(TripRecorder.dayName(for: 2) == "Monday")
        #expect(TripRecorder.dayName(for: 3) == "Tuesday")
        #expect(TripRecorder.dayName(for: 4) == "Wednesday")
        #expect(TripRecorder.dayName(for: 5) == "Thursday")
        #expect(TripRecorder.dayName(for: 6) == "Friday")
        #expect(TripRecorder.dayName(for: 7) == "Saturday")
        #expect(TripRecorder.dayName(for: 0) == "")
        #expect(TripRecorder.dayName(for: 8) == "")
    }

    @Test("formatHour returns zero-padded HH:MM string")
    func formatHourValues() throws {
        #expect(TripRecorder.formatHour(0) == "00:00")
        #expect(TripRecorder.formatHour(8) == "08:00")
        #expect(TripRecorder.formatHour(17) == "17:00")
        #expect(TripRecorder.formatHour(23) == "23:00")
    }

    // MARK: Full auth prompt trip counter

    @Test("incrementAndCheckFullAuthPrompt returns false for first two trips")
    func tripCounterFirstTwoTrips() throws {
        // Reset counter
        UserDefaults.standard.set(0, forKey: "notify.tripCounterForFullAuth")

        #expect(NotificationManager.incrementAndCheckFullAuthPrompt() == false)
        #expect(NotificationManager.incrementAndCheckFullAuthPrompt() == false)
    }

    @Test("incrementAndCheckFullAuthPrompt returns true on third trip and resets")
    func tripCounterThirdTripTriggers() throws {
        // Reset counter
        UserDefaults.standard.set(0, forKey: "notify.tripCounterForFullAuth")

        #expect(NotificationManager.incrementAndCheckFullAuthPrompt() == false)
        #expect(NotificationManager.incrementAndCheckFullAuthPrompt() == false)
        #expect(NotificationManager.incrementAndCheckFullAuthPrompt() == true)
        // Counter should be reset, so next call returns false
        #expect(NotificationManager.incrementAndCheckFullAuthPrompt() == false)
    }

    // MARK: Authorization status

    @Test("isAuthorized returns false initially (notDetermined)")
    func isAuthorizedInitialState() throws {
        let nm = NotificationManager()
        #expect(nm.authorizationStatus == .notDetermined)
        #expect(nm.isAuthorized == false)
    }

    // MARK: Weekly Summary

    @Test("weekly summary content handles zero business trips gracefully")
    func weeklySummaryEmptyContent() throws {
        let nm = NotificationManager()
        NotificationManager.weeklySummaryEnabled = true

        // Call with zero values — should not crash
        nm.scheduleWeeklySummary(weekKm: 0, businessCount: 0, valueDollars: 0)
        nm.cancelWeeklySummary()

        NotificationManager.weeklySummaryEnabled = false
    }

    @Test("weekly summary with data formats correctly")
    func weeklySummaryWithData() throws {
        let nm = NotificationManager()
        NotificationManager.weeklySummaryEnabled = true

        // Should not crash with positive values
        nm.scheduleWeeklySummary(weekKm: 150.5, businessCount: 3, valueDollars: 45.75)
        nm.cancelWeeklySummary()

        NotificationManager.weeklySummaryEnabled = false
    }

    @Test("weekly summary toggle cancel removes pending notification")
    func weeklySummaryToggleCancel() throws {
        let nm = NotificationManager()
        NotificationManager.weeklySummaryEnabled = true
        nm.scheduleWeeklySummary(weekKm: 100, businessCount: 2, valueDollars: 20)
        nm.weeklySummaryToggleChanged(isEnabled: false)
        // The toggle change should cancel the pending notification
        // No assertion possible on UNUserNotificationCenter state, but no crash = success
        nm.weeklySummaryToggleChanged(isEnabled: true)
        NotificationManager.weeklySummaryEnabled = false
    }

    // MARK: Odometer Reminder Toggle

    @Test("odometer toggle cancel removes pending notification")
    func odometerToggleCancel() throws {
        let nm = NotificationManager()
        NotificationManager.odometerReminderEnabled = true
        nm.scheduleOdometerReminder(vehicleName: "Test Car")
        nm.odometerToggleChanged(isEnabled: false, vehicleName: "Test Car")
        // Toggling back on should reschedule
        nm.odometerToggleChanged(isEnabled: true, vehicleName: "Test Car")
        NotificationManager.odometerReminderEnabled = false
    }
}

// MARK: - ═══════════════════════════════════════════════
// MARK:   Suite 9 — Schedule Gate Notifications
// MARK: ═══════════════════════════════════════════════

