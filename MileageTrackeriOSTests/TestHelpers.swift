//
//  MileageTrackeriOSTests.swift
//  MileageTrackeriOSTests
//
//  Created by Harry Just on 21/04/2026.
//

import Testing
import CoreLocation
import CoreMotion
import RealmSwift
@testable import MileageTrackeriOS

// MARK: - TripRecorderState helpers (pattern-match shorthands for assertions)

extension TripRecorderState {
    var isIdle: Bool { if case .idle = self { return true }; return false }
    var isSuspected: Bool { if case .suspected = self { return true }; return false }
    var isActive: Bool { if case .active = self { return true }; return false }
    var isPausing: Bool { if case .pausing = self { return true }; return false }
    var isEnding: Bool { if case .ending = self { return true }; return false }
}

// MARK: - Test Harness

/// Creates an isolated TripRecorder + in-memory Realm for each test.
@MainActor
struct Harness {
    let recorder: TripRecorder
    let locationManager: LocationManager
    let motionManager: MotionManager
    let tripRepo: TripRepository
    let profileRepo: UserProfileRepository
    let notificationManager: NotificationManager
    let scheduleManager: TrackingScheduleManager
    let realm: Realm

    init() throws {
        let config = Realm.Configuration(
            inMemoryIdentifier: UUID().uuidString,
            schemaVersion: RealmProvider.schemaVersion,
            objectTypes: [UserProfile.self, Vehicle.self, Trip.self, TripPoint.self, OdometerReading.self, SavedAddress.self, LogbookPeriod.self]
        )
        self.realm    = try Realm(configuration: config)
        tripRepo     = TripRepository(realm: realm)
        profileRepo  = UserProfileRepository(realm: realm)
        let odometerRepo = OdometerReadingRepository(realm: realm)
        profileRepo.addVehicle(name: "Test", registration: "TST001")

        locationManager = LocationManager()
        motionManager   = MotionManager()
        let bluetoothManager = BluetoothManager()
        notificationManager = NotificationManager()
        scheduleManager = TrackingScheduleManager()
        scheduleManager.configure(profileRepo: profileRepo)

        recorder = TripRecorder()
        // Zero out validation thresholds so trips save regardless of distance/duration
        recorder.heuristicMinTripDistance = 0
        recorder.heuristicMinTripDuration = 0

        let liveActivityManager = LiveActivityManager()
        let mileageCalculator = MileageCalculator()

        recorder.configure(
            location      : locationManager,
            motion        : motionManager,
            bluetooth     : bluetoothManager,
            liveActivity  : liveActivityManager,
            notifications : notificationManager,
            tripRepo      : tripRepo,
            profileRepo   : profileRepo,
            odometerRepo  : odometerRepo,
            scheduleManager: scheduleManager,
            mileageCalculator: mileageCalculator
        )
    }

    // MARK: Simulation helpers

    func fireActivity(_ type: DetectedActivity.ActivityType,
                      _ confidence: CMMotionActivityConfidence,
                      timestamp: Date = Date()) {
        motionManager.onActivityUpdate?(
            DetectedActivity(type: type, confidence: confidence, timestamp: timestamp)
        )
    }

    /// Fires spaced automotive samples going back `seconds` seconds to satisfy the rolling window check.
    func fireSustainedAutomotive(confidence: CMMotionActivityConfidence = .high, spanning seconds: TimeInterval = 20) {
        let now = Date()
        for i in stride(from: seconds, through: 0, by: -5) {
            fireActivity(.automotive, confidence, timestamp: now.addingTimeInterval(-i))
        }
    }

    func fireLocation(speedMs: Double = 15,
                      accuracy: Double = 10,
                      lat: Double = -36.85,
                      lng: Double = 174.76,
                      timestamp: Date = Date()) {
        let loc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
            altitude: 10,
            horizontalAccuracy: accuracy,
            verticalAccuracy: 5,
            course: 0,
            speed: speedMs,
            timestamp: timestamp
        )
        locationManager.onLocationUpdate?(loc)
    }

    func fireVisitDeparture(at date: Date = Date()) {
        locationManager.onVisitDeparture?(date)
    }

    func fireCarKitConnect(name: String = "Test Car", uid: String = "test.uid.1") {
        let event = CarKitEvent(type: .connected, deviceName: name, portUID: uid, timestamp: Date())
        BluetoothManager().onCarKitConnected?(event)
    }

    /// Drive the recorder through suspected → active in one step.
    func enterActive() {
        // Set a lastGoodFix so the anchor is available
        fireLocation()
        // Fire sustained automotive at high confidence — triggers suspected
        fireActivity(.automotive, .high)
        fireActivity(.automotive, .high)
        fireActivity(.automotive, .high)
        // Fire GPS speed > 25 km/h to promote
        fireLocation(speedMs: 30 / 3.6) // ~30 km/h
        fireLocation(speedMs: 30 / 3.6)
        fireLocation(speedMs: 30 / 3.6)
    }
