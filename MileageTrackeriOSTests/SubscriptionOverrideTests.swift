import Testing
import Foundation
import RealmSwift
@testable import MileageTrackeriOS

@Suite("Subscription Override")
struct SubscriptionOverrideTests {

    @Test("override sets subscription status immediately")
    func overrideSetsStatus() {
        // Given
        let manager = SubscriptionManager()

        // When: override to expired
        manager.setOverride(.expired)

        // Then
        #expect(manager.subscriptionState.status == .expired)
        #expect(manager.isOverrideActive)
    }

    @Test("clearOverride reverts to real state")
    func clearOverrideReverts() {
        // Given: manager with no profile — defaults to trial via computeStatus
        let manager = SubscriptionManager()
        manager.setOverride(.expired)
        #expect(manager.subscriptionState.status == .expired)

        // When
        manager.clearOverride()

        // Then: should revert to the fallback trial state (no profile = no trial date)
        #expect(manager.subscriptionState.status == .trial)
        #expect(!manager.isOverrideActive)
    }

    @Test("isOverrideActive reflects override state")
    func isOverrideActiveReflectsState() {
        // Given
        let manager = SubscriptionManager()
        #expect(!manager.isOverrideActive)

        // When
        manager.setOverride(.active)

        // Then
        #expect(manager.isOverrideActive)

        // When
        manager.clearOverride()

        // Then
        #expect(!manager.isOverrideActive)
    }

    @Test("override persists in UserDefaults")
    func overridePersists() {
        // Given
        let manager1 = SubscriptionManager()
        manager1.setOverride(.gracePeriod)
        #expect(manager1.subscriptionState.status == .gracePeriod)

        // When: create a new manager (simulates relaunch) — reads same UserDefaults
        let manager2 = SubscriptionManager()

        // Then: override is restored from UserDefaults
        #expect(manager2.isOverrideActive)
        #expect(manager2.subscriptionState.status == .gracePeriod)

        // Cleanup
        manager2.clearOverride()
    }

    @Test("all MTSubscriptionStatus values can be overridden")
    func allStatusesOverridable() {
        let manager = SubscriptionManager()

        for status in MTSubscriptionStatus.allCases {
            // When
            manager.setOverride(status)

            // Then
            #expect(manager.subscriptionState.status == status,
                     "Expected status \(status) but got \(manager.subscriptionState.status)")
        }

        manager.clearOverride()
    }

    @Test("clearOverride after multiple overrides works")
    func clearAfterMultipleOverrides() {
        // Given
        let manager = SubscriptionManager()

        // When: cycle through all states
        for status in MTSubscriptionStatus.allCases {
            manager.setOverride(status)
        }

        // Then: last override sticks
        #expect(manager.subscriptionState.status == .expired)

        // When: clear
        manager.clearOverride()

        // Then: reverted
        #expect(manager.subscriptionState.status == .trial)
    }
}
