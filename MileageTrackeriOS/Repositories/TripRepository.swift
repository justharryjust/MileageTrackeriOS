// TripRepository — CRUD for Trip and TripPoint objects.
// Provides live Realm-backed queries for the UI, and a save path for TripRecorder.

import Foundation
import Realm
import RealmSwift
import CoreLocation
import CommonCrypto

@Observable
final class TripRepository {
    // MARK: - Live-updating trip collections
    private(set) var allTrips: [Trip]           = []
    private(set) var uncategorisedTrips: [Trip] = []
    private(set) var businessTrips: [Trip]      = []

    // MARK: - Stats (recomputed on collection change)
    private(set) var weeklyDistanceKm: Double   = 0
    private(set) var monthlyDistanceKm: Double  = 0
    private(set) var totalDollarValue: Double   = 0

    private let realm: Realm
    /// Exposed as internal so tests can query Realm directly to bypass notification timing.
    var testRealm: Realm { realm }
    private var allTripsToken: NotificationToken?

    init(realm: Realm) {
        self.realm = realm
        observeTrips()
    }

    deinit { allTripsToken?.invalidate() }

    // MARK: - Observe

    private func observeTrips() {
        let results = realm.objects(Trip.self).sorted(byKeyPath: "startedAt", ascending: false)
        allTripsToken = results.observe { [weak self] _ in
            self?.refreshCollections()
        }
        refreshCollections()
    }

    private func refreshCollections() {
        let all = Array(realm.objects(Trip.self).sorted(byKeyPath: "startedAt", ascending: false))
        allTrips           = all
        uncategorisedTrips = all.filter { $0.category == .uncategorised }
        businessTrips      = all.filter { $0.category == .business }
        recalculateStats()
    }

    private func recalculateStats() {
        let cal   = Calendar.current
        let now   = Date()
        let weekStart  = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now))!

        let business = businessTrips
        weeklyDistanceKm  = business.filter { $0.startedAt >= weekStart }.reduce(0) { $0 + $1.distanceKm }
        monthlyDistanceKm = business.filter { $0.startedAt >= monthStart }.reduce(0) { $0 + $1.distanceKm }
        totalDollarValue  = business.compactMap(\.dollarValue).reduce(0, +)
    }

    // MARK: - In-flight Trip Management (called by TripRecorder during active recording)

    /// Creates an in-flight Trip in Realm so it survives crashes. No TripPoints yet —
    /// those are appended via `appendPoints` as GPS fixes arrive.
    @discardableResult
    func beginTrip(vehicleId: String, startedAt: Date,
                   startLat: Double, startLng: Double,
                   source: TripSource = .inflight) -> Trip {
        let trip = Trip()
        trip.vehicleId  = vehicleId
        trip.startedAt  = startedAt
        trip.startLat   = startLat
        trip.startLng   = startLng
        trip.source     = source
        trip.processingStatus = .complete
        write { realm.add(trip) }
        return trip
    }

    /// Appends a batch of locations as TripPoints to the in-flight trip.
    func appendPoints(to tripId: String, locations: [CLLocation]) {
        guard !locations.isEmpty else { return }
        let points: [TripPoint] = locations.map { loc in
            TripPoint(tripId: tripId,
                      latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude,
                      altitude: loc.altitude, speedMs: loc.speed, accuracy: loc.horizontalAccuracy,
                      recordedAt: loc.timestamp)
        }
        write { realm.add(points) }
    }

    /// Commits an in-flight trip on completion — sets end time, distance, address,
    /// writes any remaining location points, and flips source from .inflight to .automatic.
    func commitTrip(_ trip: Trip, endedAt: Date, distanceMetres: Double,
                    locations: [CLLocation], startAddress: String, endAddress: String,
                    visitDepartureAt: Date?, carKitName: String?,
                    processingStatus: TripProcessingStatus) {
        let sampled = downsample(locations, maxPoints: 500)
        // Replace inflight TripPoints with the full downsampled set
        write {
            let oldPts = realm.objects(TripPoint.self).where { $0.tripId == trip.id }
            realm.delete(oldPts)
            let pts: [TripPoint] = sampled.map { loc in
                TripPoint(tripId: trip.id,
                          latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude,
                          altitude: loc.altitude, speedMs: loc.speed, accuracy: loc.horizontalAccuracy,
                          recordedAt: loc.timestamp)
            }
            realm.add(pts)
            trip.endedAt    = endedAt
            trip.distanceMetres = distanceMetres
            trip.startAddress   = startAddress
            trip.endAddress     = endAddress
            trip.visitDepartureAt = visitDepartureAt
            trip.carKitName     = carKitName
            trip.processingStatus = processingStatus
            trip.source         = .automatic
            if let last = locations.last {
                trip.endLat = last.coordinate.latitude
                trip.endLng = last.coordinate.longitude
            }
            trip.updatedAt = Date()
        }
    }

    /// Deletes an in-flight trip that didn't meet minimum thresholds.
    func discardInflightTrip(_ trip: Trip) {
        write {
            let pts = realm.objects(TripPoint.self).where { $0.tripId == trip.id }
            realm.delete(pts)
            realm.delete(trip)
        }
    }

    /// Returns any trip still in flight from a previous run (crash recovery).
    var inflightTrip: Trip? {
        realm.objects(Trip.self).where { $0.source == .inflight }.first
    }

    // MARK: - Save Trip (called by TripRecorder)

    /// Persists a completed trip and its GPS points.
    func saveTrip(
        vehicleId: String,
        startedAt: Date,
        endedAt: Date,
        distanceMetres: Double,
        locations: [CLLocation],
        startAddress: String,
        endAddress: String,
        source: TripSource = .automatic,
        visitDepartureAt: Date? = nil,
        carKitName: String? = nil,
        processingStatus: TripProcessingStatus = .complete
    ) {
        let trip = Trip()
        trip.startAddress     = startAddress
        trip.endAddress       = endAddress
        trip.vehicleId        = vehicleId
        trip.startedAt        = startedAt
        trip.endedAt          = endedAt
        trip.distanceMetres   = distanceMetres
        trip.source           = source
        trip.visitDepartureAt = visitDepartureAt
        trip.carKitName       = carKitName
        trip.processingStatus = processingStatus

        // Capture start/end coordinates from first/last reliable fix
        if let first = locations.first {
            trip.startLat = first.coordinate.latitude
            trip.startLng = first.coordinate.longitude
        }
        if let last = locations.last {
            trip.endLat = last.coordinate.latitude
            trip.endLng = last.coordinate.longitude
        }

        // Build TripPoints (downsample if many points to save storage)
        let sampledLocations = downsample(locations, maxPoints: 500)
        let points: [TripPoint] = sampledLocations.map { loc in
            TripPoint(
                tripId: trip.id,
                latitude: loc.coordinate.latitude,
                longitude: loc.coordinate.longitude,
                altitude: loc.altitude,
                speedMs: loc.speed,
                accuracy: loc.horizontalAccuracy,
                recordedAt: loc.timestamp
            )
        }

        do {
            try realm.write {
                realm.add(trip)
                realm.add(points)
            }
            TripLogger.shared.log(
                "Trip saved ✅ id:\(trip.id.prefix(8))… dist:\(String(format:"%.0f",distanceMetres))m pts:\(points.count)",
                category: .trip
            )
            // Check for adjacent trip fragments to auto-merge
            autoMergeAdjacent(to: trip)
        } catch {
            TripLogger.shared.log("Failed to save trip: \(error)", category: .error)
        }
    }

    // MARK: - Save Manual Trip

    /// Persists a trip created by the user without GPS tracking.
    /// Creates TripPoints for start, optional stops, and end so the map renders a polyline.
    /// Returns the saved Trip for further processing (e.g. dollar value computation).
    @discardableResult
    func saveManualTrip(
        vehicleId     : String,
        startedAt     : Date,
        endedAt       : Date,
        distanceMetres: Double,
        startAddress  : String,
        endAddress    : String,
        startLat      : Double,
        startLng      : Double,
        endLat        : Double,
        endLng        : Double,
        stops         : [(lat: Double, lng: Double)] = [],
        category      : TripCategory = .business,
        notes         : String? = nil
    ) -> Trip {
        let trip = Trip()
        trip.vehicleId      = vehicleId
        trip.startedAt      = startedAt
        trip.endedAt        = endedAt
        trip.distanceMetres = distanceMetres
        trip.startAddress   = startAddress
        trip.endAddress     = endAddress
        trip.startLat       = startLat
        trip.startLng       = startLng
        trip.endLat         = endLat
        trip.endLng         = endLng
        trip.category       = category
        trip.source         = .manual
        trip.notes          = notes

        var points: [TripPoint] = [
            TripPoint(tripId: trip.id, latitude: startLat, longitude: startLng,
                      altitude: 0, speedMs: -1, accuracy: -1, recordedAt: startedAt)
        ]
        // Intermediate stops
        let stopInterval = endedAt.timeIntervalSince(startedAt) / Double(stops.count + 1)
        for (i, stop) in stops.enumerated() {
            points.append(TripPoint(
                tripId: trip.id, latitude: stop.lat, longitude: stop.lng,
                altitude: 0, speedMs: -1, accuracy: -1,
                recordedAt: startedAt.addingTimeInterval(stopInterval * Double(i + 1))
            ))
        }
        points.append(
            TripPoint(tripId: trip.id, latitude: endLat, longitude: endLng,
                      altitude: 0, speedMs: -1, accuracy: -1, recordedAt: endedAt)
        )

        write {
            realm.add(trip)
            realm.add(points)
        }
        TripLogger.shared.log(
            "Manual trip saved ✅ id:\(trip.id.prefix(8)) \(startAddress) → \(endAddress) \(String(format:"%.0f",distanceMetres))m pts:\(points.count)",
            category: .trip
        )
        return trip
    }

    // MARK: - Dollar Value

    /// Stores a computed dollar value on a trip (snapshot at time of finalisation).
    func storeDollarValue(_ value: Double, for trip: Trip) {
        write { trip.dollarValue = value; trip.updatedAt = Date() }
    }

    /// Sum of distance (in km) for all business-category trips that started before `trip`.
    /// Used to determine the correct rate tier for dollar value computation.
    func cumulativeBusinessKm(before trip: Trip) -> Double {
        allTrips
            .filter { $0.category == .business && $0.startedAt < trip.startedAt && $0.id != trip.id }
            .reduce(0) { $0 + ($1.distanceMetres / 1000) }
    }

    // MARK: - Categorise

    func categorise(_ trip: Trip, as category: TripCategory) {
        write {
            trip.category  = category
            trip.updatedAt = Date()
        }
        TripLogger.shared.log("Trip \(trip.id.prefix(8)) categorised as \(category.rawValue)", category: .trip)

        // Personal trips are kept 7 days then deleted (scheduled in AppState via BGTask)
    }

    func deleteTrip(_ trip: Trip) {
        // Delete associated TripPoints first
        let points = realm.objects(TripPoint.self).where { $0.tripId == trip.id }
        write {
            self.realm.delete(points)
            self.realm.delete(trip)
        }
    }

    /// Purge personal trips older than 7 days
    func purgeOldPersonalTrips() {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        let old = realm.objects(Trip.self)
            .where { $0.category == .personal && $0.endedAt < cutoff }
        let count = old.count
        let ids = old.map { $0.id }

        write {
            ids.forEach { id in
                if let trip = self.realm.object(ofType: Trip.self, forPrimaryKey: id) {
                    let pts = self.realm.objects(TripPoint.self).where { $0.tripId == id }
                    self.realm.delete(pts)
                    self.realm.delete(trip)
                }
            }
        }
        if count > 0 {
            TripLogger.shared.log("Purged \(count) personal trips older than 7 days", category: .trip)
        }
    }

    // MARK: - Date-filtered Queries (for export/reporting)

    /// Returns all trips within a date range, sorted oldest first (for CSV export ordering).
    func trips(from: Date, to: Date) -> [Trip] {
        allTrips
            .filter { $0.startedAt >= from && $0.startedAt <= to }
            .sorted { $0.startedAt < $1.startedAt }
    }

    // MARK: - Trip Points

    func tripPoints(for trip: Trip) -> [TripPoint] {
        Array(realm.objects(TripPoint.self)
            .where { $0.tripId == trip.id }
            .sorted(byKeyPath: "recordedAt"))
    }

    // MARK: - Pending Trip Reprocessing

    /// Trips saved while offline that still need address resolution / route snapping.
    var pendingTrips: [Trip] {
        Array(realm.objects(Trip.self)
            .where { $0.processingStatus == .pending && $0.processingRetries < 3 }
            .sorted(byKeyPath: "startedAt"))
    }

    /// Marks a pending trip as complete after successful re-processing.
    func markTripComplete(_ trip: Trip) {
        write {
            trip.processingStatus = .complete
            trip.updatedAt = Date()
        }
    }

    /// Increments the retry counter without changing status (trip stays pending).
    func bumpTripRetry(_ trip: Trip) {
        write {
            trip.processingRetries += 1
            trip.updatedAt = Date()
        }
    }

    /// Updates addresses and polyline for an already-saved trip (re-processing path).
    func updateTrip(_ trip: Trip, startAddress: String, endAddress: String, locations: [CLLocation]) {
        // Delete old TripPoints and insert updated ones
        let sampled = downsample(locations, maxPoints: 500)
        let points: [TripPoint] = sampled.map { loc in
            TripPoint(tripId: trip.id,
                      latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude,
                      altitude: loc.altitude, speedMs: loc.speed, accuracy: loc.horizontalAccuracy,
                      recordedAt: loc.timestamp)
        }
        write {
            let oldPts = realm.objects(TripPoint.self).where { $0.tripId == trip.id }
            realm.delete(oldPts)
            realm.add(points)
            trip.startAddress = startAddress
            trip.endAddress   = endAddress
            trip.processingStatus = .complete
            trip.updatedAt = Date()
            if let first = locations.first {
                trip.startLat = first.coordinate.latitude
                trip.startLng = first.coordinate.longitude
            }
            if let last = locations.last {
                trip.endLat = last.coordinate.latitude
                trip.endLng = last.coordinate.longitude
            }
        }
    }

    // MARK: - Trip Merging

    /// Returns all trips for a given vehicleId.
    func trips(for vehicleId: String) -> [Trip] {
        Array(realm.objects(Trip.self).where { $0.vehicleId == vehicleId })
    }

    /// Fetches a single trip by primary key.
    func trip(id: String) -> Trip? {
        realm.object(ofType: Trip.self, forPrimaryKey: id)
    }

    /// Fetches multiple trips by primary key.
    func trips(ids: [String]) -> [Trip] {
        Array(realm.objects(Trip.self).filter { ids.contains($0.id) })
    }

    /// Merges an array of trips into a single combined trip.
    /// All source trips must share the same vehicleId.
    @discardableResult
    func mergeTrips(_ trips: [Trip]) -> Trip? {
        guard trips.count >= 2 else {
            TripLogger.shared.log("Merge aborted — need at least 2 trips", category: .error)
            return nil
        }
        let sorted = trips.sorted { $0.startedAt < $1.startedAt }

        let vehicleIds = Set(sorted.map { $0.vehicleId })
        guard vehicleIds.count == 1, let vehicleId = vehicleIds.first else {
            TripLogger.shared.log("Merge aborted — trips must share the same vehicleId", category: .error)
            return nil
        }

        let merged = Trip()
        merged.vehicleId      = vehicleId
        merged.startedAt      = sorted.first!.startedAt
        merged.endedAt        = sorted.last!.endedAt
        merged.distanceMetres = sorted.reduce(0) { $0 + $1.distanceMetres }
        merged.startAddress   = sorted.first!.startAddress
        merged.endAddress     = sorted.last!.endAddress
        merged.startLat       = sorted.first!.startLat
        merged.startLng       = sorted.first!.startLng
        merged.endLat         = sorted.last!.endLat
        merged.endLng         = sorted.last!.endLng
        merged.category       = .uncategorised
        merged.source         = .merged

        // Collect TripPoints from all source trips, sorted by recordedAt
        let allPoints: [TripPoint] = sorted.flatMap { trip in
            Array(realm.objects(TripPoint.self)
                .where { $0.tripId == trip.id }
                .sorted(byKeyPath: "recordedAt"))
        }
        .sorted { $0.recordedAt < $1.recordedAt }

        // Derive start/end from the actual earliest/latest TripPoint — more accurate
        // than source trips' stored coordinates, which may be walking-trimmed or
        // anchor-based. Without this the merged polyline can start mid-route.
        if let firstPoint = allPoints.first {
            merged.startedAt  = firstPoint.recordedAt
            merged.startLat   = firstPoint.latitude
            merged.startLng   = firstPoint.longitude
        }
        if let lastPoint = allPoints.last {
            merged.endedAt    = lastPoint.recordedAt
            merged.endLat     = lastPoint.latitude
            merged.endLng     = lastPoint.longitude
        }

        // Downsample to 500 points
        let sampledLocations = downsample(allPoints.map {
            CLLocation(coordinate: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude),
                       altitude: $0.altitude,
                       horizontalAccuracy: $0.horizontalAccuracy,
                       verticalAccuracy: -1,
                       course: -1,
                       speed: $0.speedMs,
                       timestamp: $0.recordedAt)
        }, maxPoints: 500)

        let mergedPoints: [TripPoint] = sampledLocations.map { loc in
            let pt = TripPoint()
            pt.tripId              = merged.id
            pt.latitude            = loc.coordinate.latitude
            pt.longitude           = loc.coordinate.longitude
            pt.altitude            = loc.altitude
            pt.speedMs             = loc.speed
            pt.horizontalAccuracy  = loc.horizontalAccuracy
            pt.recordedAt          = loc.timestamp
            return pt
        }

        do {
            try realm.write {
                realm.add(merged)
                realm.add(mergedPoints)
                for trip in sorted {
                    let pts = realm.objects(TripPoint.self).where { $0.tripId == trip.id }
                    realm.delete(pts)
                    realm.delete(trip)
                }
            }
            TripLogger.shared.log(
                "Trips merged ✅ id:\(merged.id.prefix(8))… sources:\(sorted.count) dist:\(Int(merged.distanceMetres))m pts:\(mergedPoints.count)",
                category: .trip
            )
            return merged
        } catch {
            TripLogger.shared.log("Merge failed: \(error)", category: .error)
            return nil
        }
    }

    // MARK: - Auto-Merge

    /// After a trip is saved, checks for an adjacent trip fragment that should be
    /// automatically merged. Two trips are considered adjacent when:
    /// - Same vehicleId
    /// - End of one is within the spatial threshold of the start of the other
    /// - They are within 10 minutes of each other
    ///
    /// Micro-fragments (duration < 120s or distance < 500m) use a wider 500m spatial
    /// window because their end coordinates are often unreliable — walking trim may
    /// have removed the points closest to the actual parking location.
    ///
    /// Chains are followed: if A merges with B producing AB, we re-check AB against
    /// C (up to 5 merges deep) so rapid-fire fragments all collapse into one trip.
    private func autoMergeAdjacent(to trip: Trip, depth: Int = 0) {
        guard depth < 5 else { return }

        // Wider window for micro-fragments whose coordinates are less reliable
        let isMicroFragment: Bool = {
            let duration = (trip.endedAt ?? trip.startedAt).timeIntervalSince(trip.startedAt)
            return duration < 120 || trip.distanceMetres < 500
        }()
        let spatialThreshold: Double = isMicroFragment ? 500 : 200
        let temporalWindow: TimeInterval = 10 * 60 // 10 minutes

        // Look for trips near this one's start (predecessor fragment)
        let beforeStart = trip.startedAt.addingTimeInterval(-temporalWindow)
        let afterStart  = trip.startedAt.addingTimeInterval(temporalWindow)

        let candidates = realm.objects(Trip.self)
            .filter { $0.vehicleId == trip.vehicleId && $0.id != trip.id }
            .filter { ($0.startedAt >= beforeStart && $0.startedAt <= afterStart)
                   || ($0.endedAt != nil && $0.endedAt! >= beforeStart && $0.endedAt! <= afterStart) }

        // Check for a trip whose end is near our start (predecessor)
        if let predecessor = candidates.first(where: { candidate in
            guard let candidateEnd = candidate.endedAt, candidateEnd <= trip.startedAt else { return false }
            let endLoc   = CLLocation(latitude: candidate.endLat, longitude: candidate.endLng)
            let startLoc = CLLocation(latitude: trip.startLat, longitude: trip.startLng)
            return endLoc.distance(from: startLoc) < spatialThreshold
        }) {
            TripLogger.shared.log(
                "Auto-merge: found predecessor \(predecessor.id.prefix(8))… → \(trip.id.prefix(8))… (\(Int(CLLocation(latitude: predecessor.endLat, longitude: predecessor.endLng).distance(from: CLLocation(latitude: trip.startLat, longitude: trip.startLng))))m gap)",
                category: .trip
            )
            if let merged = mergeTrips([predecessor, trip]) {
                autoMergeAdjacent(to: merged, depth: depth + 1)
            }
            return
        }

        // Check for a trip whose start is near our end (successor)
        if let successor = candidates.first(where: { candidate in
            guard candidate.startedAt >= trip.endedAt ?? trip.startedAt else { return false }
            let endLoc   = CLLocation(latitude: trip.endLat, longitude: trip.endLng)
            let startLoc = CLLocation(latitude: candidate.startLat, longitude: candidate.startLng)
            return endLoc.distance(from: startLoc) < spatialThreshold
        }) {
            TripLogger.shared.log(
                "Auto-merge: found successor \(trip.id.prefix(8))… → \(successor.id.prefix(8))… (\(Int(CLLocation(latitude: trip.endLat, longitude: trip.endLng).distance(from: CLLocation(latitude: successor.startLat, longitude: successor.startLng))))m gap)",
                category: .trip
            )
            if let merged = mergeTrips([trip, successor]) {
                autoMergeAdjacent(to: merged, depth: depth + 1)
            }
        }
    }

    // MARK: - §3.4 Odometer Cross-Check

    /// Compares GPS-derived distance against odometer-bookend deltas for the same period.
    /// When odometer readings are available and bracket the trip, uses
    /// `max(gpsDistance, odometerDelta)` as the claim distance (the conservative-but-true
    /// figure). Both raw values are preserved on the Trip for audit trail.
    func crossCheckOdometer(trip: Trip, gpsDistanceMetres: Double, odometerRepo: OdometerReadingRepository) {
        let bookends = odometerRepo.periodBookends(for: trip.vehicleId, from: trip.startedAt.addingTimeInterval(-3600), to: (trip.endedAt ?? trip.startedAt).addingTimeInterval(3600))
        guard let start = bookends.start, let end = bookends.end, end.id != start.id else {
            // No bookends — just persist the GPS figure
            write {
                trip.gpsDistanceMetres = gpsDistanceMetres
                trip.odometerDistanceMetres = nil
            }
            return
        }
        // Odometer is in km — convert to metres
        let odometerDeltaMetres = max(0, (end.readingKm - start.readingKm) * 1000)
        // Sanity guard: an odometer delta >50% off GPS is more likely a different trip than tighter accuracy
        let agreesRoughly = abs(odometerDeltaMetres - gpsDistanceMetres) <= max(gpsDistanceMetres * 0.5, 200)
        let claimDistance = agreesRoughly ? max(gpsDistanceMetres, odometerDeltaMetres) : gpsDistanceMetres
        write {
            trip.gpsDistanceMetres = gpsDistanceMetres
            trip.odometerDistanceMetres = agreesRoughly ? odometerDeltaMetres : nil
            trip.distanceMetres = claimDistance
            trip.updatedAt = Date()
        }
        if agreesRoughly && odometerDeltaMetres > gpsDistanceMetres {
            TripLogger.shared.log("Odometer cross-check: claim distance upgraded to \(Int(claimDistance))m (GPS \(Int(gpsDistanceMetres))m, odo \(Int(odometerDeltaMetres))m)", category: .trip)
        }
    }

    // MARK: - §5.2 Tamper-Evident Commit Hash

    /// Computes and stores SHA-256 of (id || startedAt || endedAt || distance || polylineHash)
    /// plus the wall-clock commit time. If the trip is later edited, the hash recomputed at
    /// audit time won't match — proving it was modified after commit.
    func writeCommitHash(for trip: Trip, locations: [CLLocation]) {
        let polylineHash = Self.polylineFingerprint(locations: locations)
        let payload = [
            trip.id,
            ISO8601DateFormatter().string(from: trip.startedAt),
            ISO8601DateFormatter().string(from: trip.endedAt ?? trip.startedAt),
            String(Int(trip.distanceMetres)),
            polylineHash
        ].joined(separator: "|")
        let hash = Self.sha256(payload)
        write {
            trip.commitHash = hash
            trip.committedAt = Date()
        }
    }

    /// Verify a trip's commit hash matches its current state. Returns false when the trip
    /// has been edited since commit (or never had a hash). Surface from a "verify" UI.
    func verifyCommitHash(_ trip: Trip) -> Bool {
        guard let stored = trip.commitHash else { return false }
        let locations = tripPoints(for: trip).map { pt in
            CLLocation(coordinate: CLLocationCoordinate2D(latitude: pt.latitude, longitude: pt.longitude),
                       altitude: pt.altitude, horizontalAccuracy: pt.horizontalAccuracy,
                       verticalAccuracy: -1, course: -1, speed: pt.speedMs, timestamp: pt.recordedAt)
        }
        let polylineHash = Self.polylineFingerprint(locations: locations)
        let payload = [
            trip.id,
            ISO8601DateFormatter().string(from: trip.startedAt),
            ISO8601DateFormatter().string(from: trip.endedAt ?? trip.startedAt),
            String(Int(trip.distanceMetres)),
            polylineHash
        ].joined(separator: "|")
        return Self.sha256(payload) == stored
    }

    private static func sha256(_ s: String) -> String {
        let data = Data(s.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { ptr in
            _ = CC_SHA256(ptr.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private static func polylineFingerprint(locations: [CLLocation]) -> String {
        // Sparse fingerprint: round each coord to 4dp, join, hash. Small jitter doesn't
        // bust the hash but any meaningful re-routing does.
        let s = locations.map { String(format: "%.4f,%.4f", $0.coordinate.latitude, $0.coordinate.longitude) }
                          .joined(separator: ";")
        return sha256(s)
    }

    // MARK: - §2.5 Same-Day Fragment Stitching

    /// Looks for previously-saved trips that share start/end addresses or coordinates
    /// with this trip's neighbours, ending within ±30 min — characteristic of a
    /// fragmented multi-stop business trip. Delegates the actual merge to `mergeTrips`.
    /// Distinct from `autoMergeAdjacent` (called from saveTrip): that one uses tighter
    /// spatial/temporal windows for true continuation. This one is for "I went A → B → C"
    /// with longer stops in between.
    func stitchSameDayFragments(around trip: Trip) {
        guard trip.category == .uncategorised || trip.category == .business else { return }
        // 30-min window — wider than autoMerge's 10 min — for multi-stop trips
        let windowSec: TimeInterval = 30 * 60
        let calendar = Calendar.current

        let candidateRange = realm.objects(Trip.self)
            .where { $0.vehicleId == trip.vehicleId && $0.id != trip.id }
            .filter { other in
                guard let otherEnd = other.endedAt else { return false }
                let gap = abs(otherEnd.timeIntervalSince(trip.startedAt))
                let gap2 = abs((trip.endedAt ?? trip.startedAt).timeIntervalSince(other.startedAt))
                guard min(gap, gap2) <= windowSec else { return false }
                return calendar.isDate(trip.startedAt, inSameDayAs: other.startedAt)
            }

        let matches = candidateRange.filter { other in
            // Address fuzzy match — either the trip's end equals other's start (or v.v.)
            let endA = trip.endAddress.lowercased()
            let startB = other.startAddress.lowercased()
            return !endA.isEmpty && !startB.isEmpty
                && (endA.contains(startB) || startB.contains(endA))
        }

        guard !matches.isEmpty else { return }
        TripLogger.shared.log("Stitch candidates: \(matches.count) same-day fragment(s) for trip \(trip.id.prefix(8))", category: .trip)
        // Stitching is suggested, not auto-applied — surface in UI for user confirmation
        // (auto-merging multi-stop trips silently is too risky for tax purposes).
    }

    // MARK: - Recent / Lookups

    /// Most-recently-saved trip for a vehicle. Used by TripRecorder after `saveTrip()` to
    /// apply categorisation + hash to a freshly-written row when no in-flight ID was held.
    func mostRecentTrip(vehicleId: String) -> Trip? {
        realm.objects(Trip.self)
            .where { $0.vehicleId == vehicleId }
            .sorted(byKeyPath: "startedAt", ascending: false)
            .first
    }

    // MARK: - Categorisation Helper

    /// Apply a category to a trip in a write transaction. Public so `TripCategoriser` can call it.
    /// `purpose` is written only when the trip has no existing purpose — never overwrites user text.
    func applyCategory(_ category: TripCategory, to trip: Trip, purpose: String? = nil) {
        write {
            trip.category = category
            if let p = purpose, !p.isEmpty, (trip.purpose ?? "").isEmpty {
                trip.purpose = p
            }
            trip.updatedAt = Date()
        }
        TripLogger.shared.log("Trip \(trip.id.prefix(8)) auto-categorised as \(category.rawValue)", category: .trip)
    }

    // MARK: - Private helpers

    private func write(_ block: () -> Void) {
        do { try realm.write(block) } catch {
            TripLogger.shared.log("Realm write error: \(error)", category: .error)
        }
    }

    /// Keep every Nth point to avoid storing thousands of GPS fixes for long trips.
    private func downsample(_ locations: [CLLocation], maxPoints: Int) -> [CLLocation] {
        guard locations.count > maxPoints else { return locations }
        let step = locations.count / maxPoints
        var result: [CLLocation] = []
        for i in stride(from: 0, to: locations.count, by: step) {
            result.append(locations[i])
        }
        // Always include last point
        if result.last !== locations.last { result.append(locations[locations.last.map { _ in locations.count - 1 } ?? 0]) }
        return result
    }
}
