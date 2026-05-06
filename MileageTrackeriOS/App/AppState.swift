// AppState — Root observable state container.
// Instantiates Realm then builds repositories on top of it.
// All managers and repositories are owned here and injected via SwiftUI environment.

import Foundation
import RealmSwift

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
        locationManager  = LocationManager()
        motionManager    = MotionManager()
        bluetoothManager = BluetoothManager()
        tripRecorder     = TripRecorder.shared

        // 6. Wire TripRecorder
        tripRecorder.configure(
            location    : locationManager,
            motion      : motionManager,
            bluetooth   : bluetoothManager,
            tripRepo    : tripRepo,
            profileRepo : profileRepo
        )

        TripLogger.shared.log("AppState initialised — Realm ready", category: .system)

        // If onboarding is already complete, start tracking immediately
        if profileRepo.hasCompletedOnboarding {
            startTracking()
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
