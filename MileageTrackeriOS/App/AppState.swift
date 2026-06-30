// AppState — Root observable state container.
// Instantiates Realm then builds repositories on top of it.
// All managers and repositories are owned here and injected via SwiftUI environment.

import Foundation
import RealmSwift
import StoreKit
import UIKit

@Observable
final class AppState {
    static let shared = AppState()

    // MARK: - Persistence
    let realmProvider       : RealmProvider
    let profileRepo         : UserProfileRepository
    let tripRepo            : TripRepository
    let odometerRepo        : OdometerReadingRepository
    let savedAddressRepo    : SavedAddressRepository

    // MARK: - Business Logic
    let mileageCalculator   : MileageCalculator
    let reportGenerator     : ReportGenerator

    // MARK: - Live Activity
    let liveActivityManager : LiveActivityManager

    // MARK: - Notifications
    let notificationManager : NotificationManager

    // MARK: - Hardware Managers
    let locationManager     : LocationManager
    let motionManager       : MotionManager
    let bluetoothManager    : BluetoothManager
    let tripRecorder        : TripRecorder

    // MARK: - Schedule Gate
    let scheduleManager     : TrackingScheduleManager

    // MARK: - Subscription
    let subscriptionManager : SubscriptionManager

    private init() {
        // 1. Open Realm first — everything else reads from it
        realmProvider = RealmProvider.shared
        let realm     = realmProvider.realm

        // 2. Build repositories
        profileRepo      = UserProfileRepository(realm: realm)
        tripRepo         = TripRepository(realm: realm)
        odometerRepo     = OdometerReadingRepository(realm: realm)
        savedAddressRepo = SavedAddressRepository(realm: realm)

        // 3. Business logic
        mileageCalculator = MileageCalculator()
        reportGenerator   = ReportGenerator()

        // 4. Hardware managers
        locationManager     = LocationManager()
        motionManager       = MotionManager()
        bluetoothManager    = BluetoothManager()
        liveActivityManager = LiveActivityManager()
        notificationManager = NotificationManager()
        tripRecorder        = TripRecorder.shared
        scheduleManager     = TrackingScheduleManager()
        scheduleManager.configure(profileRepo: profileRepo)

        // 5. Subscription manager
        subscriptionManager = SubscriptionManager()
        subscriptionManager.configure(profileRepo: profileRepo, realm: realm)

        // 6. Wire TripRecorder
        tripRecorder.configure(
            location    : locationManager,
            motion      : motionManager,
            bluetooth   : bluetoothManager,
            liveActivity: liveActivityManager,
            notifications: notificationManager,
            tripRepo    : tripRepo,
            profileRepo : profileRepo,
            odometerRepo: odometerRepo,
            savedAddressRepo: savedAddressRepo,
            scheduleManager: scheduleManager,
            mileageCalculator: mileageCalculator
        )

        // §1.E: register recovery notification actions so the user can resolve
        // in-flight trips via lock-screen / banner actions.
        notificationManager.registerRecoveryActions()

        TripLogger.shared.log("AppState initialised -- Realm ready", category: .system)

        // If onboarding is already complete, start tracking immediately
        if profileRepo.hasCompletedOnboarding {
            if profileRepo.trialStartedAt == nil {
                profileRepo.trialStartedAt = Date()
                TripLogger.shared.log("Trial start date set for existing user", category: .system)
            }
            startTracking()
        }

        // Retry offline-saved trips when the app comes to the foreground
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.tripRecorder.reprocessPendingTrips()
        }
    }

    /// Call once onboarding is complete (or on app launch when already onboarded).
    func startTracking() {
        motionManager.startActivityUpdates()
        motionManager.startBatteryMonitoring()
        bluetoothManager.startMonitoring()
        locationManager.startSignificantLocationMonitoring()
        locationManager.startVisitMonitoring()
        scheduleManager.startMonitoring()
        TripLogger.shared.log("Tracking started -- motion, pedometer, battery, bluetooth, significant-location, visit monitoring, and schedule gate active", category: .system)
    }
}


@Observable
final class SubscriptionManager {
    private(set) var subscriptionState: MTSubscriptionState
    private(set) var products: [Product] = []; private(set) var isPurchasing = false
    private(set) var purchaseError: String?
    private weak var profileRepo: UserProfileRepository?; private var realm: Realm?
    private let logger = TripLogger.shared
    static let trialDurationDays = 30; static let graceDurationDays = 14
    static let monthlyProductID = "com.mileagetracker.monthly"; static let annualProductID = "com.mileagetracker.annual"
    init() {
        self.subscriptionState = MTSubscriptionState(status: .trial, trialEndsAt: nil, graceEndsAt: nil, activePeriods: [])
    }
    func configure(profileRepo: UserProfileRepository, realm: Realm) {
        self.profileRepo = profileRepo; self.realm = realm; refreshState()
        Task { [weak self] in await self?.observeTransactionUpdates() }
    }
    func refreshState() {
        guard let profile = profileRepo?.profile else { return }
        let activePeriods = fetchActivePeriods()
        let status = computeStatus(trialStartedAt: profile.trialStartedAt, activePeriods: activePeriods)
        updateProfileStatus(status)
        subscriptionState = MTSubscriptionState(status: status, trialEndsAt: trialEndDate(trialStartedAt: profile.trialStartedAt), graceEndsAt: graceEndDate(trialStartedAt: profile.trialStartedAt), activePeriods: activePeriods)
        logger.log("SubscriptionManager: state refreshed -- \(status.rawValue)", category: .system)
    }
    func fetchProducts() async {
        do { let all = try await Product.products(for: [Self.monthlyProductID, Self.annualProductID]).sorted { $0.price < $1.price }
            await MainActor.run { self.products = all } }
        catch { await MainActor.run { logger.log("SubscriptionManager: failed to fetch products", category: .error) } }
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
                await MainActor.run { isPurchasing = false }; refreshState(); return true
            case .pending: await MainActor.run { isPurchasing = false }; return false
            case .userCancelled: await MainActor.run { isPurchasing = false }; return false
            @unknown default: await MainActor.run { isPurchasing = false }; return false
            }
        } catch {
            await MainActor.run { purchaseError = error.localizedDescription; isPurchasing = false }; return false
        }
    }
    func restorePurchases() async {
        do { try await AppStore.sync(); logger.log("SubscriptionManager: restore complete", category: .system); refreshState() }
        catch { logger.log("SubscriptionManager: restore failed", category: .error) }
    }
    func isTripAccessible(_ trip: Trip) -> Bool { subscriptionState.status.allowsAccess || tripIsInActivePeriod(trip) }
    private func computeStatus(trialStartedAt: Date?, activePeriods: [MTSubscriptionPeriod]) -> MTSubscriptionStatus {
        let now = Date()
        if activePeriods.contains(where: { $0.isActive && ($0.endedAt == nil || $0.endedAt! >= now) }) { return .active }
        if let trialStart = trialStartedAt {
            let trialEnd = trialStart.addingTimeInterval(Double(Self.trialDurationDays * 24 * 3600))
            if now <= trialEnd { return .trial }
            let graceEnd = trialEnd.addingTimeInterval(Double(Self.graceDurationDays * 24 * 3600))
            if now <= graceEnd { return .gracePeriod }
        } else { return .trial }
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
        period.startedAt = transaction.purchaseDate; period.endedAt = transaction.expirationDate
        period.plan = plan; period.isActive = transaction.revocationDate == nil
        write { self.realm?.add(period) }
    }
    private func plan(for productID: String) -> MTSubscriptionPlan { productID == Self.monthlyProductID ? .monthly : .annual }
    private func observeTransactionUpdates() async {
        for await verification in Transaction.updates {
            guard let t = try? checkVerified(verification), t.productType == .autoRenewable else { continue }
            let pid = t.productID
            if pid == Self.monthlyProductID || pid == Self.annualProductID {
                await handlePurchase(transaction: t, plan: pid == Self.monthlyProductID ? .monthly : .annual)
                await t.finish()
            }
            await MainActor.run { self.refreshState() }
        }
    }
    private func fetchActivePeriods() -> [MTSubscriptionPeriod] {
        guard let realm else { return [] }
        return Array(realm.objects(MTSubscriptionPeriod.self).sorted(byKeyPath: "startedAt", ascending: false))
    }
    private func tripIsInActivePeriod(_ trip: Trip) -> Bool { subscriptionState.activePeriods.contains { $0.contains(trip.startedAt) } }
    private func updateProfileStatus(_ status: MTSubscriptionStatus) { profileRepo?.setSubscriptionStatus(status.rawValue) }
    private func checkVerified<T>(_ verification: VerificationResult<T>) throws -> T {
        switch verification { case .unverified(_, let e): throw e; case .verified(let s): return s }
    }
    private func write(_ block: () -> Void) {
        guard let realm else { return }
        do { try realm.write(block) } catch { logger.log("SubscriptionManager: Realm write error", category: .error) }
    }
}
