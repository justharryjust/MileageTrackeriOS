// LocationManager — CLLocationManager wrapper
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

    /// Fires when the OS detects the user has arrived at a known visit location.
    var onVisitArrival: (() -> Void)?

    /// Fires on a region exit with a CLLocation anchored to the region center.
    /// TripRecorder uses this as the authoritative geographic trip start point.
    var onRegionDeparture: ((CLLocation) -> Void)?

    /// Fires on any background wake (significant-location or visit departure).
    /// Caller should use this to query missed motion activities since the given date.
    var onBackgroundWake: ((Date) -> Void)?

    /// Tracks the last time a background wake was received, used as the `since` date
    /// for motion catch-up queries.
    private(set) var lastBackgroundWakeAt: Date?

    /// Cached from the most recent SLC/visit/region fix. Used as the cold-start
    /// polyline anchor when GPS hasn't acquired yet (e.g. underground garage).
    private(set) var lastGoodFix: CLLocation?

    override init() {
        super.init()
        authorizationStatus = manager.authorizationStatus
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter  = 10   // metres between updates during recording
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.activityType = .automotiveNavigation
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

    // MARK: - Region Monitoring (geofence departure trigger)

    /// Rolling "where I was last seen" region — re-centred after every fix during idle.
    private let regionIdentifier = "com.mileagetracker.departureRegion"
    /// §1.C / §2.1: prefix for parking-hint geofences. Each hint gets its own region with
    /// identifier "com.mileagetracker.parkingHint.<index>", monitored alongside the rolling one.
    /// iOS allows 20 regions per app — we use up to 15 parking hints + 1 rolling = 16 max.
    private let parkingHintPrefix = "com.mileagetracker.parkingHint."

    func startRegionMonitoring(around coordinate: CLLocationCoordinate2D, radius: CLLocationDistance = 150) {
        guard hasAlwaysAuthorization else {
            logger.log("Cannot start region monitoring — Always authorization required", category: .location)
            return
        }
        // Only stop the rolling region — preserve parking-hint regions
        stopRollingRegionOnly()
        let region = CLCircularRegion(center: coordinate, radius: radius, identifier: regionIdentifier)
        region.notifyOnExit  = true
        region.notifyOnEntry = false
        manager.startMonitoring(for: region)
        logger.log("Started rolling region at (\(String(format: "%.5f", coordinate.latitude)), \(String(format: "%.5f", coordinate.longitude))) radius: \(Int(radius))m", category: .location)
    }

    /// §1.C / §2.1: monitor an arbitrary set of parking-hint coordinates as parallel
    /// geofences. Replaces the previous set in one shot — call with [] to clear all hints
    /// (the rolling departure region is preserved).
    func startParkingHintRegions(_ coordinates: [CLLocationCoordinate2D], radius: CLLocationDistance = 150) {
        guard hasAlwaysAuthorization else {
            logger.log("Cannot start parking-hint regions — Always authorization required", category: .location)
            return
        }
        // Stop existing parking-hint regions only
        stopParkingHintRegions()
        for (idx, coord) in coordinates.enumerated() {
            guard CLLocationCoordinate2DIsValid(coord) else { continue }
            let id = parkingHintPrefix + "\(idx)"
            let region = CLCircularRegion(center: coord, radius: radius, identifier: id)
            region.notifyOnExit  = true
            region.notifyOnEntry = false
            manager.startMonitoring(for: region)
        }
        logger.log("Started \(coordinates.count) parking-hint regions", category: .location)
    }

    private func stopRollingRegionOnly() {
        for region in manager.monitoredRegions where region.identifier == regionIdentifier {
            manager.stopMonitoring(for: region)
        }
    }

    private func stopParkingHintRegions() {
        for region in manager.monitoredRegions where region.identifier.hasPrefix(parkingHintPrefix) {
            manager.stopMonitoring(for: region)
        }
    }

    /// Stop ALL geofence monitoring (rolling + parking hints). Called when GPS active recording starts.
    func stopRegionMonitoring() {
        for region in manager.monitoredRegions
            where region.identifier == regionIdentifier
               || region.identifier.hasPrefix(parkingHintPrefix) {
            manager.stopMonitoring(for: region)
        }
        logger.log("Stopped all region monitoring", category: .location)
    }

    /// Re-centers the departure region when not actively recording, so the next
    /// departure is always caught. Called from didUpdateLocations on background wakes.
    func updateRegionIfIdle(to coordinate: CLLocationCoordinate2D) {
        guard !isHighAccuracyActive else { return }
        startRegionMonitoring(around: coordinate)
    }

    // MARK: - High-Accuracy Updates (during active recording)

    func startHighAccuracyUpdates() {
        guard !isHighAccuracyActive else { return }
        isHighAccuracyActive = true
        stopRegionMonitoring()
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
        if let coord = currentLocation?.coordinate {
            startRegionMonitoring(around: coord)
        }
        // §1.C: also re-arm parking-hint regions after recording ends.
        // TripRecorder will call startParkingHintRegions() with the up-to-date LRU
        // after each trip ends — this is a fallback for callers that don't.
        onIdleRecentred?()
    }

    /// Optional callback when entering idle (after a trip ends, etc.) — TripRecorder
    /// uses this to re-arm parking-hint regions with the latest LRU.
    var onIdleRecentred: (() -> Void)?

    // MARK: - One-Shot Location (cold-start fallback)

    /// Requests a single high-accuracy fix. Used as a fallback when `lastGoodFix` is nil
    /// and TripRecorder needs a start coordinate immediately.
    func requestOneShotLocation() {
        manager.requestLocation()
        logger.log("Requested one-shot location", category: .location)
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
            if let coord = currentLocation?.coordinate {
                startRegionMonitoring(around: coord)
            }
        }
    }

    // MARK: - Visit Delegate

    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        // A departure is signalled when departureDate is not distantFuture
        guard visit.departureDate != .distantFuture else {
            logger.log("CLVisit arrival recorded at (\(String(format:"%.4f",visit.coordinate.latitude)), \(String(format:"%.4f",visit.coordinate.longitude)))", category: .location)
            onVisitArrival?()
            return
        }
        logger.log("CLVisit departure at \(visit.departureDate) — notifying TripRecorder", category: .location)
        // Trigger motion catch-up from the departure time
        let since = lastBackgroundWakeAt ?? visit.departureDate
        lastBackgroundWakeAt = Date()
        onBackgroundWake?(since)
        onVisitDeparture?(visit.departureDate)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        let isRolling = region.identifier == regionIdentifier
        let isParkingHint = region.identifier.hasPrefix(parkingHintPrefix)
        guard isRolling || isParkingHint else { return }

        let departureDate = Date().addingTimeInterval(-60)
        logger.log("Region exit (\(isParkingHint ? "parking hint" : "rolling")) — signalling departure at \(departureDate)", category: .location)
        lastBackgroundWakeAt = Date()
        onBackgroundWake?(departureDate)
        onVisitDeparture?(departureDate)
        if let circular = region as? CLCircularRegion {
            let anchor = CLLocation(
                coordinate        : circular.center,
                altitude          : 0,
                horizontalAccuracy: circular.radius,
                verticalAccuracy  : -1,
                timestamp         : departureDate
            )
            onRegionDeparture?(anchor)
        }
        // Re-centre rolling region on current location so the next trip is caught.
        // Parking-hint regions are not re-centred — they're absolute "this is where my car gets parked" anchors.
        let recentre = currentLocation?.coordinate ?? (region as? CLCircularRegion)?.center
        if isRolling, let coord = recentre {
            startRegionMonitoring(around: coord)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithMonitoringRegion region: CLRegion, error: Error) {
        logger.log("Region monitoring failed for \(region.identifier): \(error.localizedDescription)", category: .error)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }

        // If we're not in high-accuracy mode, this is a significant-location or warm-idle wake — trigger catch-up
        if !isHighAccuracyActive {
            let since = lastBackgroundWakeAt ?? Date().addingTimeInterval(-300)
            lastBackgroundWakeAt = Date()
            logger.log("Significant-location wake — triggering motion catch-up since \(since)", category: .location)
            onBackgroundWake?(since)
            // Keep departure region centered on current position during idle
            updateRegionIfIdle(to: loc.coordinate)
        }

        // Filter out stale or low-accuracy fixes
        let age = abs(loc.timestamp.timeIntervalSinceNow)
        guard age < 10, loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 100 else {
            logger.log("Discarding stale/inaccurate fix — age: \(String(format: "%.1f", age))s acc: \(String(format: "%.0f", loc.horizontalAccuracy))m", category: .location)
            return
        }

        currentLocation = loc
        lastKnownSpeed  = loc.speed
        lastGoodFix     = loc

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

