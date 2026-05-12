// LearnedStore — Disk-backed persistence for TripRecorder's learning sets.
//
// §1.D fix: knownCarBTUIDs, btCorrelations, and parkingHintsLRU were previously
// in-memory only, so they were wiped on every cold start. A user's "known car"
// was re-learned from scratch every app kill. This file persists them to
// UserDefaults as JSON so they survive across launches.
//
// We use UserDefaults (rather than a Realm row) because:
//   1. These are not user-visible domain objects — they're tracker internals.
//   2. The data is small (<5 KB even with 50 parking hints).
//   3. We need atomic save/load with no migration overhead.

import Foundation
import CoreLocation

/// Immutable snapshot of all persisted learning state.
struct LearnedStateSnapshot: Codable {
    var knownCarBTUIDs: Set<String>
    var btCorrelations: [String: Int]
    var parkingHints: [CLLocationCoordinate2D]

    init(knownCarBTUIDs: Set<String> = [],
         btCorrelations: [String: Int] = [:],
         parkingHints: [CLLocationCoordinate2D] = []) {
        self.knownCarBTUIDs = knownCarBTUIDs
        self.btCorrelations = btCorrelations
        self.parkingHints = parkingHints
    }

    // Codable shim — CLLocationCoordinate2D isn't Codable out of the box
    private enum CodingKeys: String, CodingKey {
        case knownCarBTUIDs
        case btCorrelations
        case parkingHintsRaw
    }

    private struct Coord: Codable {
        let lat: Double
        let lng: Double
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.knownCarBTUIDs = try c.decode(Set<String>.self, forKey: .knownCarBTUIDs)
        self.btCorrelations = try c.decode([String: Int].self, forKey: .btCorrelations)
        let raw = try c.decode([Coord].self, forKey: .parkingHintsRaw)
        self.parkingHints = raw.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(knownCarBTUIDs, forKey: .knownCarBTUIDs)
        try c.encode(btCorrelations, forKey: .btCorrelations)
        let raw = parkingHints.map { Coord(lat: $0.latitude, lng: $0.longitude) }
        try c.encode(raw, forKey: .parkingHintsRaw)
    }
}

final class LearnedStore {
    static let shared = LearnedStore()

    private let defaults: UserDefaults
    private let key = "com.mileagetracker.learnedState.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> LearnedStateSnapshot {
        guard let data = defaults.data(forKey: key) else {
            return LearnedStateSnapshot()
        }
        do {
            return try JSONDecoder().decode(LearnedStateSnapshot.self, from: data)
        } catch {
            TripLogger.shared.log("LearnedStore decode failed: \(error.localizedDescription)", category: .error)
            return LearnedStateSnapshot()
        }
    }

    func save(_ snapshot: LearnedStateSnapshot) {
        do {
            let data = try JSONEncoder().encode(snapshot)
            defaults.set(data, forKey: key)
        } catch {
            TripLogger.shared.log("LearnedStore encode failed: \(error.localizedDescription)", category: .error)
        }
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
