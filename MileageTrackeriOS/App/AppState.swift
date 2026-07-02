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
    let logbookPeriodRepo   : LogbookPeriodRepository

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
        logbookPeriodRepo = LogbookPeriodRepository(realm: realm)

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

        // 2a. Wire notification manager to logbook period repo
        logbookPeriodRepo.notificationManager = notificationManager

        // 2b. Wire logbook period lifecycle to claim method changes
        profileRepo.onClaimMethodChange = { [weak self] newMethod, jurisdiction, vehicleId in
            guard let self, let vehicleId else { return }
            if newMethod == .logbook {
                if self.logbookPeriodRepo.activePeriod(for: vehicleId) == nil {
                    let period = self.logbookPeriodRepo.createPeriod(vehicleId: vehicleId, jurisdiction: jurisdiction)
                    if let endDate = period.endedAt {
                        self.notificationManager.scheduleLogbookEndSoonReminder(endDate: endDate, daysRemaining: 7)
                        self.notificationManager.scheduleLogbookEnded(endDate: endDate)
                    }
                }
            } else {
                self.logbookPeriodRepo.abandonPeriods(for: vehicleId)
                self.notificationManager.cancelLogbookNotifications()
            }
        }

        // AC14: jurisdiction change mid-logbook-period
        profileRepo.onJurisdictionChange = { [weak self] newJurisdiction, vehicleId in
            guard let self, let vehicleId else { return }
            self.logbookPeriodRepo.abandonPeriods(for: vehicleId)
            self.logbookPeriodRepo.createPeriod(vehicleId: vehicleId, jurisdiction: newJurisdiction)
        }

        // AC6: auto-complete expired periods on launch
        logbookPeriodRepo.autoCompleteExpiredPeriods(jurisdiction: profileRepo.jurisdiction, calculator: mileageCalculator)

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

        // Wire recovery notification actions to TripRecorder
        notificationManager.onRecoveryAction = { [weak self] actionId, tripId in
            guard let self else { return }
            switch actionId {
            case NotificationManager.recoveryActionResume:
                self.tripRecorder.handleRecoveryResume(tripId: tripId)
            case NotificationManager.recoveryActionSaveAsIs:
                self.tripRecorder.handleRecoverySaveAsIs(tripId: tripId)
            case NotificationManager.recoveryActionDiscard:
                self.tripRecorder.handleRecoveryDiscard(tripId: tripId)
            default:
                TripLogger.shared.log("Unknown recovery action: \(actionId)", category: .error)
            }
        }

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
            guard let self else { return }
            self.tripRecorder.reprocessPendingTrips()
            self.logbookPeriodRepo.autoCompleteExpiredPeriods(
                jurisdiction: self.profileRepo.jurisdiction,
                calculator: self.mileageCalculator
            )
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
