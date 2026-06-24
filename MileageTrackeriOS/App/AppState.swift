// AppState — Root observable state container.
// Instantiates Realm then builds repositories on top of it.
// All managers and repositories are owned here and injected via SwiftUI environment.

import Foundation
import RealmSwift
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

    /// Alert flag: when true, the UI should show a pre-permission dialog
    /// offering to upgrade from provisional to full notification authorization.
    var showFullAuthAlert = false

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

        // 2a. Wire logbook period lifecycle to claim method changes
        profileRepo.onClaimMethodChange = { [weak self] newMethod, jurisdiction, vehicleId in
            guard let self, let vehicleId else { return }
            if newMethod == .logbook {
                if self.logbookPeriodRepo.activePeriod(for: vehicleId) == nil {
                    self.logbookPeriodRepo.createPeriod(vehicleId: vehicleId, jurisdiction: jurisdiction)
                }
            } else {
                self.logbookPeriodRepo.abandonPeriods(for: vehicleId)
            }
        }

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
            startTracking()
        }

        // Retry offline-saved trips when the app comes to the foreground
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.tripRecorder.reprocessPendingTrips()
            // Refresh weekly summary with fresh data when app foregrounds
            self.notificationManager.refreshWeeklySummary(
                tripRepo: self.tripRepo,
                mileageCalculator: self.mileageCalculator,
                profileRepo: self.profileRepo
            )
        }

        // Wire trip completion callback for full auth prompt and weekly summary refresh
        tripRecorder.onTripCompleted = { [weak self] in
            guard let self else { return }
            // Check if we should prompt for full notification authorization
            if NotificationManager.incrementAndCheckFullAuthPrompt() {
                self.showFullAuthAlert = true
            }
            // Refresh weekly summary after each trip save
            self.notificationManager.refreshWeeklySummary(
                tripRepo: self.tripRepo,
                mileageCalculator: self.mileageCalculator,
                profileRepo: self.profileRepo
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
        // Request provisional notification permission (silent -- no system prompt).
        // Safe to call even if already determined; the system ignores repeat requests.
        notificationManager.requestPermission()
        TripLogger.shared.log("Tracking started -- motion, pedometer, battery, bluetooth, significant-location, visit monitoring, and schedule gate active", category: .system)
    }
}
