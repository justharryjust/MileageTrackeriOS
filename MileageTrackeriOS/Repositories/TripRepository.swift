// TripRepository — CRUD for Trip and TripPoint objects.
// Provides live Realm-backed queries for the UI, and a save path for TripRecorder.

import Foundation
import Realm
import RealmSwift
import CoreLocation

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

    // MARK: - Save Trip (called by TripRecorder)

    /// Persists a completed trip and its GPS points.
    func saveTrip(
        vehicleId: String,
        startedAt: Date,
        endedAt: Date,
        distanceMetres: Double,
        locations: [CLLocation],
        source: TripSource = .automatic,
        visitDepartureAt: Date? = nil
    ) {
        let trip = Trip()
        trip.vehicleId        = vehicleId
        trip.startedAt        = startedAt
        trip.endedAt          = endedAt
        trip.distanceMetres   = distanceMetres
        trip.source           = source
        trip.visitDepartureAt = visitDepartureAt

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
                "Trip saved ✅ id:\(trip.id) dist:\(String(format:"%.0f",distanceMetres))m pts:\(points.count)",
                category: .trip
            )
        } catch {
            TripLogger.shared.log("Failed to save trip: \(error)", category: .error)
        }
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

    // MARK: - Trip Points

    func tripPoints(for trip: Trip) -> [TripPoint] {
        Array(realm.objects(TripPoint.self)
            .where { $0.tripId == trip.id }
            .sorted(byKeyPath: "recordedAt"))
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
