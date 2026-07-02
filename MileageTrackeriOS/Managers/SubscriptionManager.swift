// SubscriptionManager — Wraps StoreKit 2 for subscription purchasing, trial/grace logic,
// period-gating queries, and Realm-persisted subscription period records.
//
// DESIGN DECISION: StoreKit 2 vs RevenueCat
// This implementation uses raw StoreKit 2 instead of RevenueCat for the following reasons:
// 1. The app has zero RevenueCat dependencies today — adding one would increase binary size and
//    introduce a third-party network service for a relatively simple purchase flow.
// 2. StoreKit 2's async/await Transaction.updates API (iOS 15+) provides reliable transaction
//    observation without polling. The SDK's built-in receipt verification is sufficient for
//    the subscription models this app uses (monthly/annual auto-renewing).
// 3. RevenueCat's main advantage — cross-platform entitlements — isn't relevant for a single-platform
//    iOS app. The server-side receipt validation required by IRD/ATO audit trails is handled locally
//    via SHA-256 trip commit hashes (§5.2 in the codebase).
// 4. If multi-platform support or server-side receipt management becomes necessary, the MTSubscription*
//    model layer is designed to be RevenueCat-compatible: replace the StoreKit calls with
//    Purchases.shared.customerInfo() and keep everything below MTSubscriptionState untouched.

import Foundation
import RealmSwift
import StoreKit

// MARK: - SubscriptionState

struct MTSubscriptionState {
    let status: MTSubscriptionStatus
    let trialEndsAt: Date?
    let graceEndsAt: Date?
    let activePeriods: [MTSubscriptionPeriod]

    var daysRemainingInTrial: Int? {
        guard let end = trialEndsAt else { return nil }
        return max(0, Calendar.current.dateComponents([.day], from: Date(), to: end).day ?? 0)
    }

    var daysRemainingInGrace: Int? {
        guard let end = graceEndsAt else { return nil }
        return max(0, Calendar.current.dateComponents([.day], from: Date(), to: end).day ?? 0)
    }
}

// MARK: - SubscriptionManager

@Observable
final class SubscriptionManager {
    private(set) var subscriptionState: MTSubscriptionState
    private(set) var products: [Product] = []
    private(set) var isPurchasing = false
    private(set) var purchaseError: String?
    private(set) var shouldShowPaywall = false

    private weak var profileRepo: UserProfileRepository?
    private var realm: Realm?
    private let logger = TripLogger.shared

    static let trialDurationDays = 30
    static let graceDurationDays = 14
    static let monthlyProductID = "com.mileagetracker.monthly"
    static let annualProductID = "com.mileagetracker.annual"

    init() {
        self.subscriptionState = MTSubscriptionState(
            status: .trial,
            trialEndsAt: nil,
            graceEndsAt: nil,
            activePeriods: []
        )
    }

    func configure(profileRepo: UserProfileRepository, realm: Realm) {
        self.profileRepo = profileRepo
        self.realm = realm
        refreshState()
        Task { [weak self] in
            await self?.observeTransactionUpdates()
        }
    }

    func refreshState() {
#if DEBUG
        if let override = debugOverrideStatus {
            let activePeriods = fetchActivePeriods()
            let state = MTSubscriptionState(
                status: override,
                trialEndsAt: nil,
                graceEndsAt: nil,
                activePeriods: activePeriods
            )
            updateProfileStatus(override)
            subscriptionState = state
            logger.log("SubscriptionManager: state refreshed with override -- \(override.rawValue)", category: .system)
            return
        }
#endif

        guard let profile = profileRepo?.profile else { return }
        let activePeriods = fetchActivePeriods()

        let status = computeStatus(
            trialStartedAt: profile.trialStartedAt,
            activePeriods: activePeriods
        )
        updateProfileStatus(status)
        subscriptionState = MTSubscriptionState(
            status: status,
            trialEndsAt: trialEndDate(trialStartedAt: profile.trialStartedAt),
            graceEndsAt: graceEndDate(trialStartedAt: profile.trialStartedAt),
            activePeriods: activePeriods
        )
        logger.log("SubscriptionManager: state refreshed -- \(status.rawValue)", category: .system)
    }

    func fetchProducts() async {
        do {
            let all = try await Product.products(
                for: [Self.monthlyProductID, Self.annualProductID]
            ).sorted { $0.price < $1.price }
            await MainActor.run { self.products = all }
        } catch {
            await MainActor.run {
                logger.log("SubscriptionManager: failed to fetch products", category: .error)
            }
        }
    }

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        await MainActor.run { isPurchasing = true; purchaseError = nil }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await handlePurchase(transaction: transaction, plan: plan(for: product.id))
                await transaction.finish()
                await MainActor.run { isPurchasing = false }
                refreshState()
                return true
            case .pending:
                await MainActor.run { isPurchasing = false }
                return false
            case .userCancelled:
                await MainActor.run { isPurchasing = false }
                return false
            @unknown default:
                await MainActor.run { isPurchasing = false }
                return false
            }
        } catch {
            await MainActor.run {
                purchaseError = error.localizedDescription
                isPurchasing = false
            }
            return false
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            logger.log("SubscriptionManager: restore complete", category: .system)
            refreshState()
        } catch {
            logger.log("SubscriptionManager: restore failed", category: .error)
        }
    }

    /// Returns true if the trip can be viewed/categorised/exported.
    /// A trip is accessible when:
    ///   - The user has an active subscription overall (trial/active/grace), OR
    ///   - The trip was recorded during a past subscription period (period-gating)
    func isTripAccessible(_ trip: Trip) -> Bool {
        subscriptionState.status.allowsAccess || tripIsInActivePeriod(trip)
    }

    /// Returns true if ALL of the given trips are accessible.
    func areAllTripsAccessible(_ trips: [Trip]) -> Bool {
        trips.allSatisfy { isTripAccessible($0) }
    }

    /// Returns the subset of trips that are accessible (for display purposes).
    func accessibleTrips(_ trips: [Trip]) -> [Trip] {
        trips.filter { isTripAccessible($0) }
    }

    // MARK: - Debug Override (compiled out of release builds)

#if DEBUG
    /// UserDefaults key for persisting the debug override across launches.
    private static let debugOverrideKey = "DEBUG_subscriptionOverride"

    /// Reads/writes the persisted override status. `nil` means "use real state".
    private var debugOverrideStatus: MTSubscriptionStatus? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Self.debugOverrideKey) else { return nil }
            return MTSubscriptionStatus(rawValue: raw)
        }
        set {
            if let value = newValue {
                UserDefaults.standard.set(value.rawValue, forKey: Self.debugOverrideKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.debugOverrideKey)
            }
        }
    }

    /// Whether a debug override is currently active.
    var isOverrideActive: Bool { debugOverrideStatus != nil }

    /// Override the subscription state to the given status. Persists across launches.
    func setOverride(_ status: MTSubscriptionStatus) {
        debugOverrideStatus = status
        refreshState()
        logger.log("SubscriptionManager: override set to \(status.rawValue)", category: .system)
    }

    /// Clear the override and revert to computing state from real StoreKit and Realm data.
    func clearOverride() {
        debugOverrideStatus = nil
        refreshState()
        logger.log("SubscriptionManager: override cleared", category: .system)
    }
#else
    var isOverrideActive: Bool { false }
    func setOverride(_ status: MTSubscriptionStatus) {}
    func clearOverride() {}
#endif

    // MARK: - Private

    private func computeStatus(
        trialStartedAt: Date?,
        activePeriods: [MTSubscriptionPeriod]
    ) -> MTSubscriptionStatus {
        let now = Date()

        // If there's an active subscription period, user is .active
        if activePeriods.contains(where: { $0.isActive && ($0.endedAt == nil || $0.endedAt! >= now) }) {
            return .active
        }

        // Check trial / grace window
        if let trialStart = trialStartedAt {
            let trialEnd = trialStart.addingTimeInterval(Double(Self.trialDurationDays * 24 * 3600))
            if now <= trialEnd { return .trial }

            let graceEnd = trialEnd.addingTimeInterval(Double(Self.graceDurationDays * 24 * 3600))
            if now <= graceEnd { return .gracePeriod }
        } else {
            // No trial start date — treat as trial (fresh install)
            return .trial
        }

        return .expired
    }

    private func trialEndDate(trialStartedAt: Date?) -> Date? {
        guard let start = trialStartedAt else { return nil }
        return start.addingTimeInterval(Double(Self.trialDurationDays * 24 * 3600))
    }

    private func graceEndDate(trialStartedAt: Date?) -> Date? {
        guard let start = trialStartedAt else { return nil }
        return start.addingTimeInterval(Double((Self.trialDurationDays + Self.graceDurationDays) * 24 * 3600))
    }

    private func handlePurchase(transaction: Transaction, plan: MTSubscriptionPlan) {
        let period = MTSubscriptionPeriod()
        period.startedAt = transaction.purchaseDate
        period.endedAt = transaction.expirationDate
        period.plan = plan
        period.isActive = transaction.revocationDate == nil
        write { self.realm?.add(period) }
    }

    private func plan(for productID: String) -> MTSubscriptionPlan {
        productID == Self.monthlyProductID ? .monthly : .annual
    }

    private func observeTransactionUpdates() async {
        for await verification in Transaction.updates {
            guard let t = try? checkVerified(verification),
                  t.productType == .autoRenewable else { continue }
            let pid = t.productID
            if pid == Self.monthlyProductID || pid == Self.annualProductID {
                await handlePurchase(transaction: t,
                                     plan: pid == Self.monthlyProductID ? .monthly : .annual)
                await t.finish()
            }
            await MainActor.run { self.refreshState() }
        }
    }

    private func fetchActivePeriods() -> [MTSubscriptionPeriod] {
        guard let realm else { return [] }
        return Array(realm.objects(MTSubscriptionPeriod.self)
            .sorted(byKeyPath: "startedAt", ascending: false))
    }

    private func tripIsInActivePeriod(_ trip: Trip) -> Bool {
        subscriptionState.activePeriods.contains { $0.contains(trip.startedAt) }
    }

    private func updateProfileStatus(_ status: MTSubscriptionStatus) {
        profileRepo?.setSubscriptionStatus(status.rawValue)
    }

    private func checkVerified<T>(_ verification: VerificationResult<T>) throws -> T {
        switch verification {
        case .unverified(_, let e): throw e
        case .verified(let s): return s
        }
    }

    private func write(_ block: () -> Void) {
        guard let realm else { return }
        do {
            try realm.write(block)
        } catch {
            logger.log("SubscriptionManager: Realm write error", category: .error)
        }
    }
}
