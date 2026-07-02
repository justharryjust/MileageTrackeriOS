// NotificationManager — Handles permission requests and schedules local notifications
// for odometer reminders, weekly summaries, and trip-detected alerts.

import Foundation
import UIKit
import UserNotifications

@Observable
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

    /// Full authorization status from the system.
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// True when the user has granted provisional or full authorization.
    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    // UserDefaults keys for per-type toggles
    private static let keyOdometerReminder = "notify.odometerReminder"
    private static let keyWeeklySummary   = "notify.weeklySummary"
    private static let keyTripDetected    = "notify.tripDetected"
    private static let keyTripCounter     = "notify.tripCounterForFullAuth"

    static var odometerReminderEnabled: Bool {
        get { UserDefaults.standard.object(forKey: keyOdometerReminder) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: keyOdometerReminder) }
    }
    static var weeklySummaryEnabled: Bool {
        get { UserDefaults.standard.object(forKey: keyWeeklySummary) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: keyWeeklySummary) }
    }
    static var tripDetectedEnabled: Bool {
        get { UserDefaults.standard.object(forKey: keyTripDetected) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: keyTripDetected) }
    }

    override init() {
        super.init()
        center.delegate = self
        refreshAuthorizationStatus()
    }

    // MARK: - Permission

    /// Request provisional notification permission (silent — no system prompt).
    /// Safe to call even when status is already determined (system ignores it).
    func requestPermission() {
        center.requestAuthorization(options: [.provisional, .alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    TripLogger.shared.log("Provisional notification authorization granted", category: .system)
                } else if let error {
                    TripLogger.shared.log("Notification permission error: \(error.localizedDescription)", category: .error)
                }
                self.refreshAuthorizationStatus()
            }
        }
    }

    /// Request full (non-provisional) notification authorization.
    /// Shows the system permission prompt. Call after the user has seen value
    /// (e.g. after their third trip) and tapped through a custom pre-permission dialog.
    func requestFullAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    TripLogger.shared.log("Full notification authorization granted", category: .system)
                } else if let error {
                    TripLogger.shared.log("Full notification permission error: \(error.localizedDescription)", category: .error)
                }
                self.refreshAuthorizationStatus()
            }
        }
    }

    /// Open system Settings for this app. Call when authorization is `.denied`.
    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        DispatchQueue.main.async {
            UIApplication.shared.open(url)
        }
    }

    /// Increment the trip counter and return true when it's time to prompt for full auth.
    /// Resets the counter after returning true.
    static func incrementAndCheckFullAuthPrompt() -> Bool {
        let counter = UserDefaults.standard.integer(forKey: keyTripCounter) + 1
        guard counter >= 3 else {
            UserDefaults.standard.set(counter, forKey: keyTripCounter)
            return false
        }
        UserDefaults.standard.set(0, forKey: keyTripCounter)
        return true
    }

    private func refreshAuthorizationStatus() {
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.authorizationStatus = settings.authorizationStatus
            }
        }
    }

    // MARK: - Odometer Reminder (logbook users)

    /// Schedule a weekly reminder to record odometer readings. Sunday at 6pm.
    func scheduleOdometerReminder(vehicleName: String) {
        guard Self.odometerReminderEnabled else { return }
        center.removePendingNotificationRequests(withIdentifiers: ["odometer-reminder"])

        let content = UNMutableNotificationContent()
        content.title = "Record Odometer"
        content.body = "Time for your weekly odometer reading for \(vehicleName.isEmpty ? "your vehicle" : vehicleName)."
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        var date = DateComponents()
        date.weekday = 1  // Sunday
        date.hour = 18
        date.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        let request = UNNotificationRequest(identifier: "odometer-reminder", content: content, trigger: trigger)
        center.add(request)
    }

    /// Cancel odometer reminders (e.g. when switching from logbook to another method).
    func cancelOdometerReminder() {
        center.removePendingNotificationRequests(withIdentifiers: ["odometer-reminder"])
    }

    // MARK: - Weekly Summary

    /// Schedule a weekly summary notification. Sunday at 8pm.
    func scheduleWeeklySummary(weekKm: Double, businessCount: Int, valueDollars: Double) {
        guard Self.weeklySummaryEnabled else { return }
        center.removePendingNotificationRequests(withIdentifiers: ["weekly-summary"])

        let content = UNMutableNotificationContent()
        content.title = "Weekly Summary"
        if businessCount == 0 {
            content.body = "No business trips this week."
        } else {
            let kmStr = String(format: "%.0f km", weekKm)
            let valStr = valueDollars > 0 ? String(format: " · $%.0f", valueDollars) : ""
            content.body = "\(kmStr) across \(businessCount) business trips this week\(valStr)."
        }
        content.sound = .default

        var date = DateComponents()
        date.weekday = 1  // Sunday
        date.hour = 20
        date.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        let request = UNNotificationRequest(identifier: "weekly-summary", content: content, trigger: trigger)
        center.add(request)
    }

    /// Cancel the pending weekly summary notification.
    func cancelWeeklySummary() {
        center.removePendingNotificationRequests(withIdentifiers: ["weekly-summary"])
    }

    /// Re-schedule the weekly summary with fresh data from repositories.
    /// Only updates the notification when within the 4-hour window before Sunday 20:00.
    func refreshWeeklySummary(tripRepo: TripRepository, mileageCalculator: MileageCalculator, profileRepo: UserProfileRepository) {
        guard Self.weeklySummaryEnabled else { return }
        guard isWithinWeeklySummaryWindow() else { return }

        let cal = Calendar.current
        let now = Date()
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!

        let weeklyBusinessTrips = tripRepo.businessTrips.filter { $0.startedAt >= weekStart }
        let weeklyKm = weeklyBusinessTrips.reduce(0.0) { $0 + $1.distanceKm }
        let weeklyDollars = weeklyBusinessTrips.compactMap(\.dollarValue).reduce(0, +)
        let weeklyCount = weeklyBusinessTrips.count

        scheduleWeeklySummary(weekKm: weeklyKm, businessCount: weeklyCount, valueDollars: weeklyDollars)
    }

    /// Returns true when the current time is within the 4-hour window before Sunday 20:00.
    private func isWithinWeeklySummaryWindow() -> Bool {
        let cal = Calendar.current
        let now = Date()
        let weekday = cal.component(.weekday, from: now)
        guard weekday == 1 else { return false }  // Sunday
        let hour = cal.component(.hour, from: now)
        return hour >= 16 && hour < 20
    }

    // MARK: - Trip Detected

    /// Fire when a trip enters Active state. Only meaningful if the app is in the background.
    /// Works with both provisional (quiet delivery) and full (banner) authorization.
    func sendTripStarted(vehicleName: String) {
        guard Self.tripDetectedEnabled, isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Trip Started"
        let vehicle = vehicleName.isEmpty ? "your vehicle" : vehicleName
        content.body = "Recording trip in \(vehicle)."
        content.sound = .default

        // Deliver immediately
        let request = UNNotificationRequest(identifier: "trip-started", content: content, trigger: nil)
        center.add(request)
    }

    // MARK: - Tracking Status Change

    /// Notify when the schedule gate blocks a new trip start.
    func sendScheduleGateBlockedNotification(dayName: String, timeRange: String) {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Tracking Paused"
        content.body = "Tracking is paused \u{2014} your tracking hours are set to \(dayName) \(timeRange)."
        content.sound = .default

        let request = UNNotificationRequest(identifier: "schedule-gate-blocked", content: content, trigger: nil)
        center.add(request)
    }

    /// Notify when tracking resumes at the start of tracking hours.
    func sendTrackingResumedNotification(dayName: String) {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Tracking Resumed"
        content.body = "Tracking is now active for \(dayName)."
        content.sound = .default

        let request = UNNotificationRequest(identifier: "tracking-resumed", content: content, trigger: nil)
        center.add(request)
    }

    // MARK: - §1.E Trip Recovery Prompt

    /// Notification action category for trip recovery decisions.
    static let recoveryCategoryId = "com.mileagetracker.tripRecovery"
    static let recoveryActionResume   = "TR_RESUME"
    static let recoveryActionSaveAsIs = "TR_SAVE"
    static let recoveryActionDiscard  = "TR_DISCARD"
    static let recoveryUserInfoTripId = "tripId"

    /// Closure invoked when the user taps a recovery notification action.
    /// Parameters are the action identifier and the in-flight trip id.
    /// Set by AppState to wire the action to TripRecorder.
    var onRecoveryAction: ((_ actionId: String, _ tripId: String) -> Void)?

    /// Register the recovery action category. Call once on launch.
    func registerRecoveryActions() {
        let resume = UNNotificationAction(identifier: Self.recoveryActionResume,
                                          title: "Resume", options: [.foreground])
        let saveAs = UNNotificationAction(identifier: Self.recoveryActionSaveAsIs,
                                          title: "Save as-is", options: [])
        let discard = UNNotificationAction(identifier: Self.recoveryActionDiscard,
                                           title: "Discard", options: [.destructive])
        let category = UNNotificationCategory(
            identifier: Self.recoveryCategoryId,
            actions: [resume, saveAs, discard],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    /// §1.E: prompt the user when a recovered in-flight trip is past the auto-resume
    /// window but still looks real. The user decides via notification actions whether
    /// to resume, save as-is, or discard — avoiding silent data loss on long trips.
    func sendTripRecoveryPrompt(distanceMetres: Double, durationSec: TimeInterval, inflightId: String) {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Resume trip?"
        let km = String(format: "%.1f km", distanceMetres / 1000)
        let mins = Int(durationSec / 60)
        content.body = "We saved \(km) over \(mins) min before the app stopped. Resume it, save what we have, or discard?"
        content.sound = .default
        content.categoryIdentifier = Self.recoveryCategoryId
        content.userInfo = [Self.recoveryUserInfoTripId: inflightId]
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(identifier: "trip-recovery-\(inflightId)",
                                            content: content, trigger: nil)
        center.add(request)
    }

    // MARK: - Reschedule

    /// Called after profile changes (e.g. claim method switch, new vehicle).
    func reschedule(claimMethod: ClaimMethod, vehicleName: String) {
        if claimMethod == .logbook {
            scheduleOdometerReminder(vehicleName: vehicleName)
        } else {
            cancelOdometerReminder()
        }
    }

    /// Called when the odometer reminder toggle changes.
    func odometerToggleChanged(isEnabled: Bool, vehicleName: String) {
        if isEnabled {
            scheduleOdometerReminder(vehicleName: vehicleName)
        } else {
            cancelOdometerReminder()
        }
    }

    /// Called when the weekly summary toggle changes.
    func weeklySummaryToggleChanged(isEnabled: Bool) {
        if !isEnabled {
            cancelWeeklySummary()
        }
    }

    // MARK: - Logbook Period Notifications

    /// Schedule notification 7 days before the logbook period ends.
    func scheduleLogbookEndSoonReminder(endDate: Date, daysRemaining: Int) {
        let fireDate = Calendar.current.date(byAdding: .day, value: -7, to: endDate)
        guard let fireDate, fireDate > Date() else {
            if endDate > Date() {
                sendImmediateLogbookEndSoon(daysRemaining: daysRemaining)
            }
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Logbook Period Ending Soon"
        content.body = "Your logbook period ends in \(daysRemaining) days. Make sure your odometer readings are up to date."
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: "logbook-end-soon", content: content, trigger: trigger)
        center.add(request)
    }

    /// Schedule notification when the logbook period ends.
    func scheduleLogbookEnded(endDate: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Logbook Period Ended"
        content.body = "Your logbook period has ended. Please record your final odometer reading and review your trip categorisations."
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: endDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: "logbook-ended", content: content, trigger: trigger)
        center.add(request)
    }

    /// Schedule notification 30 days before the logbook validity expires.
    func scheduleLogbookValidityExpiry(validUntil: Date) {
        let fireDate = Calendar.current.date(byAdding: .day, value: -30, to: validUntil)
        guard let fireDate, fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Logbook Period Expiring"
        content.body = "Your logbook period's validity is expiring soon. Consider starting a new logbook period."
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: "logbook-validity-expiring", content: content, trigger: trigger)
        center.add(request)
    }

    /// Cancel all logbook-related notifications.
    func cancelLogbookNotifications() {
        center.removePendingNotificationRequests(withIdentifiers: [
            "logbook-end-soon",
            "logbook-ended",
            "logbook-validity-expiring"
        ])
    }

    private func sendImmediateLogbookEndSoon(daysRemaining: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Logbook Period Ending Soon"
        content.body = "Your logbook period ends in \(daysRemaining) days. Make sure your odometer readings are up to date."
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(identifier: "logbook-end-soon-immediate", content: content, trigger: nil)
        center.add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                  willPresent notification: UNNotification,
                                  withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notifications even when app is in foreground
        handler([.banner, .sound])
    }

    /// Testable entry point for recovery notification actions.
    /// Extracted from the delegate callback so tests don't need to construct
    /// UNNotificationResponse objects (whose public init was removed in a recent SDK).
    func handleRecoveryAction(categoryIdentifier: String,
                              actionIdentifier: String,
                              userInfo: [AnyHashable: Any]) {
        if categoryIdentifier == Self.recoveryCategoryId,
           let tripId = userInfo[Self.recoveryUserInfoTripId] as? String {
            TripLogger.shared.log("Recovery action: \(actionIdentifier) for trip \(tripId)", category: .system)
            onRecoveryAction?(actionIdentifier, tripId)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                  didReceive response: UNNotificationResponse,
                                  withCompletionHandler handler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo

        handleRecoveryAction(
            categoryIdentifier: response.notification.request.content.categoryIdentifier,
            actionIdentifier: response.actionIdentifier,
            userInfo: userInfo
        )

        handler()
    }
}
