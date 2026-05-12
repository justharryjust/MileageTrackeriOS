// NotificationManager — Handles permission requests and schedules local notifications
// for odometer reminders, weekly summaries, and trip-detected alerts.

import Foundation
import UserNotifications

@Observable
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private(set) var isAuthorized = false

    // UserDefaults keys for per-type toggles
    private static let keyOdometerReminder = "notify.odometerReminder"
    private static let keyWeeklySummary   = "notify.weeklySummary"
    private static let keyTripDetected    = "notify.tripDetected"

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

    /// Request notification permission. Call after the user has seen value (e.g. after first trip).
    func requestPermission() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                self.isAuthorized = granted
                if granted {
                    TripLogger.shared.log("Notification permission granted", category: .system)
                } else if let error {
                    TripLogger.shared.log("Notification permission error: \(error.localizedDescription)", category: .error)
                }
            }
        }
    }

    private func refreshAuthorizationStatus() {
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isAuthorized = settings.authorizationStatus == .authorized
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
        let kmStr = String(format: "%.0f km", weekKm)
        let valStr = valueDollars > 0 ? String(format: " · $%.0f", valueDollars) : ""
        content.body = "\(kmStr) across \(businessCount) business trips this week\(valStr)."
        content.sound = .default

        var date = DateComponents()
        date.weekday = 1  // Sunday
        date.hour = 20
        date.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        let request = UNNotificationRequest(identifier: "weekly-summary", content: content, trigger: trigger)
        center.add(request)
    }

    // MARK: - Trip Detected

    /// Fire when a trip enters Active state. Only meaningful if the app is in the background.
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

    // MARK: - §1.E Trip Recovery Prompt

    /// Notification action category for trip recovery decisions.
    static let recoveryCategoryId = "com.mileagetracker.tripRecovery"
    static let recoveryActionResume   = "TR_RESUME"
    static let recoveryActionSaveAsIs = "TR_SAVE"
    static let recoveryActionDiscard  = "TR_DISCARD"
    static let recoveryUserInfoTripId = "tripId"

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

    // MARK: - Reschedule All

    /// Called after profile changes (e.g. claim method switch, new vehicle).
    func reschedule(claimMethod: ClaimMethod, vehicleName: String) {
        if claimMethod == .logbook {
            scheduleOdometerReminder(vehicleName: vehicleName)
        } else {
            cancelOdometerReminder()
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                  willPresent notification: UNNotification,
                                  withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notifications even when app is in foreground
        handler([.banner, .sound])
    }
}
