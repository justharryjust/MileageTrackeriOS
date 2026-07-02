import Testing
import CoreLocation
import CoreMotion
import RealmSwift
import UserNotifications
@testable import MileageTrackeriOS

@Suite("Notification Recovery Actions")
struct NotificationRecoveryTests {

    @Test("handleRecoveryAction dispatches Resume action")
    func dispatchResumeAction() {
        let notificationManager = NotificationManager()
        var capturedActionId: String?
        var capturedTripId: String?
        notificationManager.onRecoveryAction = { actionId, tripId in
            capturedActionId = actionId
            capturedTripId = tripId
        }

        notificationManager.handleRecoveryAction(
            categoryIdentifier: NotificationManager.recoveryCategoryId,
            actionIdentifier: NotificationManager.recoveryActionResume,
            userInfo: [NotificationManager.recoveryUserInfoTripId: "trip-123"]
        )

        #expect(capturedActionId == NotificationManager.recoveryActionResume)
        #expect(capturedTripId == "trip-123")
    }

    @Test("handleRecoveryAction dispatches Save action")
    func dispatchSaveAction() {
        let notificationManager = NotificationManager()
        var capturedActionId: String?
        notificationManager.onRecoveryAction = { actionId, _ in
            capturedActionId = actionId
        }

        notificationManager.handleRecoveryAction(
            categoryIdentifier: NotificationManager.recoveryCategoryId,
            actionIdentifier: NotificationManager.recoveryActionSaveAsIs,
            userInfo: [NotificationManager.recoveryUserInfoTripId: "trip-456"]
        )

        #expect(capturedActionId == NotificationManager.recoveryActionSaveAsIs)
    }

    @Test("handleRecoveryAction dispatches Discard action")
    func dispatchDiscardAction() {
        let notificationManager = NotificationManager()
        var capturedActionId: String?
        notificationManager.onRecoveryAction = { actionId, _ in
            capturedActionId = actionId
        }

        notificationManager.handleRecoveryAction(
            categoryIdentifier: NotificationManager.recoveryCategoryId,
            actionIdentifier: NotificationManager.recoveryActionDiscard,
            userInfo: [NotificationManager.recoveryUserInfoTripId: "trip-789"]
        )

        #expect(capturedActionId == NotificationManager.recoveryActionDiscard)
    }

    @Test("handleRecoveryAction ignores non-recovery categories")
    func ignoreNonRecoveryNotifications() {
        let notificationManager = NotificationManager()
        var wasCalled = false
        notificationManager.onRecoveryAction = { _, _ in
            wasCalled = true
        }

        notificationManager.handleRecoveryAction(
            categoryIdentifier: "some-other-category",
            actionIdentifier: "some-action",
            userInfo: [:]
        )

        #expect(!wasCalled)
    }
}
