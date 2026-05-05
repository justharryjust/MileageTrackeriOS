// ingLocationManager — CLLocationManager wrapper
// Handles permission requests, background location, and streaming location updates.
// Uses the significant-location-change API as a low-power wake trigger,
// then upgrades to full GPS accuracy once automotive motion is confirmed.
// Also uses CLVisit monitoring as a zero-battery departure signal to pre-arm trip detection.

import Foundation
import CoreLocation

// MARK: - Location Authorization Status (Observable)

@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    // MARK: Published State
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var currentLocation: CLLocation?
    var lastKnownSpeed: CLLocationSpeed = -1   // m/s, -1 = unknown

    // MARK: Private
    private let manager = CLLocationManager()
    private let logger  = TripLogger.shared

    /// True when full high-accuracy updates are running (during recording)
    private(set) var isHighAccuracyActive = false

    // Callback fires on every new location — TripRecorder subscribes to this
    var onLocationUpdate: ((CLLocation) -> Void)?

    /// Fires when the OS detects the user has departed a known visit location.
    /// Delivers the departure time — TripRecorder uses this to pre-arm detection.
    var onVisitDeparture: ((Date) -> Void)?

    /// Fires on any background wake (significant-location or visit departure).
    /// Caller should use this to query missed motion activities since the given date.
    var onBackgroundWake: ((Date) -> Void)?

    /// Tracks the last time a background wake was received, used as the `since` date
    /// for motion catch-up queries.
    private(set) var lastBackgroundWakeAt: Date?

    override init() {
        super.init()
        authorizationStatus = manager.authorizationStatus
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter  = 10   // metres between updates during recording
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
    }

    // MARK: - Permission

    /// Tracks whether we should escalate to Always once WhenInUse is granted.
    private var pendingAlwaysRequest = false

    /// Two-step iOS permission flow:
    /// 1. Request WhenInUse (shows the system prompt).
    /// 2. Once granted, immediately request Always (shows a second system prompt).
    func requestLocationPermission() {
        switch authorizationStatus {
        case .notDetermined:
            // Step 1 — ask for WhenInUse; delegate will escalate to Always when granted.
            pendingAlwaysRequest = true
            logger.log("Requesting WhenInUse location authorization (step 1)", category: .location)
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            // Already have WhenInUse — jump straight to step 2.
            logger.log("Requesting Always location authorization (step 2)", category: .location)
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    func requestAlwaysAuthorization() {
        logger.log("Requesting always-on location authorization", category: .location)
        manager.requestAlwaysAuthorization()
    }

    var hasAlwaysAuthorization: Bool {
        authorizationStatus == .authorizedAlways
    }

    var hasAnyAuthorization: Bool {
        authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
    }

    // MARK: - Significant Location Changes (low-power background wake)

    func startSignificantLocationMonitoring() {
        guard hasAnyAuthorization else {
            logger.log("Cannot start significant location — no permission", category: .location)
            return
        }
        manager.startMonitoringSignificantLocationChanges()
        logger.log("Started significant location change monitoring", category: .location)
    }

    func stopSignificantLocationMonitoring() {
        manager.stopMonitoringSignificantLocationChanges()
        logger.log("Stopped significant location change monitoring", category: .location)
    }

    // MARK: - Visit Monitoring (zero-battery departure signal)

    /// Start CLVisit monitoring. Requires Always authorization.
    /// iOS fires arrivals/departures for places the user regularly spends time.
    func startVisitMonitoring() {
        guard hasAlwaysAuthorization else {
            logger.log("Cannot start visit monitoring — Always authorization required", category: .location)
            return
        }
        manager.startMonitoringVisits()
        logger.log("Started CLVisit monitoring", category: .location)
    }

    func stopVisitMonitoring() {
        manager.stopMonitoringVisits()
        logger.log("Stopped CLVisit monitoring", category: .location)
    }

    // MARK: - High-Accuracy Updates (during active recording)

    func startHighAccuracyUpdates() {
        guard !isHighAccuracyActive else { return }
        isHighAccuracyActive = true
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter  = 5
        manager.startUpdatingLocation()
        logger.log("Started high-accuracy GPS updates", category: .location)
    }

    func stopHighAccuracyUpdates() {
        guard isHighAccuracyActive else { return }
        isHighAccuracyActive = false
        manager.stopUpdatingLocation()
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter  = 10
        logger.log("Stopped high-accuracy GPS updates", category: .location)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let prev = authorizationStatus
        authorizationStatus = manager.authorizationStatus
        logger.log("Location auth changed: \(prev) → \(authorizationStatus.debugDescription)", category: .location)

        // Step 2: escalate to Always immediately after WhenInUse is granted
        if authorizationStatus == .authorizedWhenInUse && pendingAlwaysRequest {
            pendingAlwaysRequest = false
            logger.log("WhenInUse granted — escalating to Always authorization (step 2)", category: .location)
            manager.requestAlwaysAuthorization()
        }

        if hasAlwaysAuthorization {
            pendingAlwaysRequest = false
            startSignificantLocationMonitoring()
            startVisitMonitoring()
        }
    }

    // MARK: - Visit Delegate

    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        // A departure is signalled when departureDate is not distantFuture
        guard visit.departureDate != .distantFuture else {
            logger.log("CLVisit arrival recorded at (\(String(format:"%.4f",visit.coordinate.latitude)), \(String(format:"%.4f",visit.coordinate.longitude)))", category: .location)
            return
        }
        logger.log("CLVisit departure at \(visit.departureDate) — notifying TripRecorder", category: .location)
        // Trigger motion catch-up from the departure time
        let since = lastBackgroundWakeAt ?? visit.departureDate
        lastBackgroundWakeAt = Date()
        onBackgroundWake?(since)
        onVisitDeparture?(visit.departureDate)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }

        // If we're not in high-accuracy mode, this is a significant-location wake — trigger catch-up
        if !isHighAccuracyActive {
            let since = lastBackgroundWakeAt ?? Date().addingTimeInterval(-300)
            lastBackgroundWakeAt = Date()
            logger.log("Significant-location wake — triggering motion catch-up since \(since)", category: .location)
            onBackgroundWake?(since)
        }

        // Filter out stale or low-accuracy fixes
        let age = abs(loc.timestamp.timeIntervalSinceNow)
        guard age < 10, loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 100 else {
            logger.log("Discarding stale/inaccurate fix — age: \(String(format: "%.1f", age))s acc: \(String(format: "%.0f", loc.horizontalAccuracy))m", category: .location)
            return
        }

        currentLocation = loc
        lastKnownSpeed  = loc.speed

        let speedKmh = loc.speed >= 0 ? String(format: "%.1f km/h", loc.speed * 3.6) : "unknown speed"
        let acc      = String(format: "±%.0fm", loc.horizontalAccuracy)
        logger.log("Location: \(String(format: "%.5f", loc.coordinate.latitude)), \(String(format: "%.5f", loc.coordinate.longitude)) | \(speedKmh) | \(acc)", category: .location)

        onLocationUpdate?(loc)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        logger.log("CLLocationManager error: \(error.localizedDescription)", category: .error)
    }
}

// MARK: - CLAuthorizationStatus Debug Description

private extension CLAuthorizationStatus {
    var debugDescription: String {
        switch self {
        case .notDetermined:         return "notDetermined"
        case .restricted:            return "restricted"
        case .denied:                return "denied"
        case .authorizedAlways:      return "authorizedAlways"
        case .authorizedWhenInUse:   return "authorizedWhenInUse"
        @unknown default:            return "unknown(\(rawValue))"
        }
    }
}

