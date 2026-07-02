import Testing
import CoreLocation
import CoreMotion
import RealmSwift
@testable import MileageTrackeriOS

@Suite("Notification Recovery Actions")
struct NotificationRecoveryTests {

    @Test("didReceive dispatches Resume action to onRecoveryAction closure")
    func dispatchResumeAction() {
        let notificationManager = NotificationManager()
        var capturedActionId: String?
        var capturedTripId: String?
        notificationManager.onRecoveryAction = { actionId, tripId in
            capturedActionId = actionId
            capturedTripId = tripId
        }

        let content = UNMutableNotificationContent()
        content.categoryIdentifier = NotificationManager.recoveryCategoryId
        content.userInfo = [NotificationManager.recoveryUserInfoTripId: "trip-123"]

        let request = UNNotificationRequest(
            identifier: "test-recovery",
            content: content,
            trigger: nil
        )

        let response = UNNotificationResponse(
            notification: UNNotification(request: request, date: Date()),
            actionIdentifier: NotificationManager.recoveryActionResume
        )

        notificationManager.userNotificationCenter(
            UNUserNotificationCenter.current(),
            didReceive: response
        ) { /* completion handler */ }

        #expect(capturedActionId == NotificationManager.recoveryActionResume)
        #expect(capturedTripId == "trip-123")
    }

    @Test("didReceive dispatches Save action to onRecoveryAction closure")
    func dispatchSaveAction() {
        let notificationManager = NotificationManager()
        var capturedActionId: String?
        notificationManager.onRecoveryAction = { actionId, _ in
            capturedActionId = actionId
        }

        let content = UNMutableNotificationContent()
        content.categoryIdentifier = NotificationManager.recoveryCategoryId
        content.userInfo = [NotificationManager.recoveryUserInfoTripId: "trip-456"]

        let request = UNNotificationRequest(
            identifier: "test-recovery",
            content: content,
            trigger: nil
        )

        let response = UNNotificationResponse(
            notification: UNNotification(request: request, date: Date()),
            actionIdentifier: NotificationManager.recoveryActionSaveAsIs
        )

        notificationManager.userNotificationCenter(
            UNUserNotificationCenter.current(),
            didReceive: response
        ) { /* completion handler */ }

        #expect(capturedActionId == NotificationManager.recoveryActionSaveAsIs)
    }

    @Test("didReceive dispatches Discard action to onRecoveryAction closure")
    func dispatchDiscardAction() {
        let notificationManager = NotificationManager()
        var capturedActionId: String?
        notificationManager.onRecoveryAction = { actionId, _ in
            capturedActionId = actionId
        }

        let content = UNMutableNotificationContent()
        content.categoryIdentifier = NotificationManager.recoveryCategoryId
        content.userInfo = [NotificationManager.recoveryUserInfoTripId: "trip-789"]

        let request = UNNotificationRequest(
            identifier: "test-recovery",
            content: content,
            trigger: nil
        )

        let response = UNNotificationResponse(
            notification: UNNotification(request: request, date: Date()),
            actionIdentifier: NotificationManager.recoveryActionDiscard
        )

        notificationManager.userNotificationCenter(
            UNUserNotificationCenter.current(),
            didReceive: response
        ) { /* completion handler */ }

        #expect(capturedActionId == NotificationManager.recoveryActionDiscard)
    }

    @Test("didReceive does not dispatch for non-recovery categories")
    func ignoreNonRecoveryNotifications() {
        let notificationManager = NotificationManager()
        var wasCalled = false
        notificationManager.onRecoveryAction = { _, _ in
            wasCalled = true
        }

        let content = UNMutableNotificationContent()
        content.categoryIdentifier = "some-other-category"

        let request = UNNotificationRequest(
            identifier: "test-other",
            content: content,
            trigger: nil
        )

        let response = UNNotificationResponse(
            notification: UNNotification(request: request, date: Date()),
            actionIdentifier: "some-action"
        )

        notificationManager.userNotificationCenter(
            UNUserNotificationCenter.current(),
            didReceive: response
        ) { /* completion handler */ }

        #expect(!wasCalled)
    }
}

