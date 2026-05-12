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

    private init() {
        // 1. Open Realm first — everything else reads from it
        realmProvider = RealmProvider.shared
        let realm     = realmProvider.realm

        // 2. Build repositories
        profileRepo  = UserProfileRepository(realm: realm)
        tripRepo     = TripRepository(realm: realm)
        odometerRepo = OdometerReadingRepository(realm: realm)

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

        // 6. Wire TripRecorder
        tripRecorder.configure(
            location    : locationManager,
            motion      : motionManager,
            bluetooth   : bluetoothManager,
            liveActivity: liveActivityManager,
            notifications: notificationManager,
            tripRepo    : tripRepo,
            profileRepo : profileRepo,
            odometerRepo: odometerRepo
        )

        // §1.E: register recovery notification actions so the user can resolve
        // in-flight trips via lock-screen / banner actions.
        notificationManager.registerRecoveryActions()

        TripLogger.shared.log("AppState initialised — Realm ready", category: .system)

        // If onboarding is already complete, start tracking immediately
        if profileRepo.hasCompletedOnboarding {
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
        TripLogger.shared.log("Tracking started — motion, pedometer, battery, bluetooth, significant-location, and visit monitoring active", category: .system)
    }
}
