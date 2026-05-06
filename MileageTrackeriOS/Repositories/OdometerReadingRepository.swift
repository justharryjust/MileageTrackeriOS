// OdometerReadingRepository — CRUD for OdometerReading Realm objects.
// Manages per-vehicle odometer logs for the logbook claim method.

import Foundation
import Realm
import RealmSwift

@Observable
final class OdometerReadingRepository {
    private let realm: Realm
    private(set) var readings: [OdometerReading] = []
    private var token: NotificationToken?

    init(realm: Realm) {
        self.realm = realm
        observe()
    }

    deinit { token?.invalidate() }

    private func observe() {
        let results = realm.objects(OdometerReading.self).sorted(byKeyPath: "recordedAt", ascending: false)
        token = results.observe { [weak self] _ in
            self?.readings = Array(results)
        }
    }

    // MARK: - Queries

    func readings(for vehicleId: String) -> [OdometerReading] {
        readings.filter { $0.vehicleId == vehicleId }
    }

    func latestReading(for vehicleId: String) -> OdometerReading? {
        readings.first { $0.vehicleId == vehicleId }
    }

    /// All readings for a vehicle within a date range, sorted oldest first.
    func readings(for vehicleId: String, from: Date, to: Date) -> [OdometerReading] {
        readings
            .filter { $0.vehicleId == vehicleId && $0.recordedAt >= from && $0.recordedAt <= to }
            .sorted { $0.recordedAt < $1.recordedAt }
    }

    // MARK: - Mutations

    func recordReading(
        vehicleId: String,
        readingKm: Double,
        tripId: String? = nil,
        notes: String? = nil,
        source: OdometerSource = .manual
    ) {
        let reading = OdometerReading()
        reading.vehicleId  = vehicleId
        reading.readingKm  = readingKm
        reading.recordedAt = Date()
        reading.tripId     = tripId
        reading.notes      = notes
        reading.source     = source

        write { realm.add(reading) }
        TripLogger.shared.log("Odometer reading recorded: \(String(format: "%.0f", readingKm)) km (\(source.rawValue))", category: .trip)
    }

    func deleteReading(_ reading: OdometerReading) {
        write { realm.delete(reading) }
        TripLogger.shared.log("Odometer reading deleted", category: .trip)
    }

    // MARK: - Private

    private func write(_ block: () -> Void) {
        do { try realm.write(block) } catch {
            TripLogger.shared.log("Odometer repo write error: \(error)", category: .error)
        }
    }
}
