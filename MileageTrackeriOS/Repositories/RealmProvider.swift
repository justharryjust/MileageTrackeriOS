// RealmProvider — Opens and vends the shared Realm instance.
// All schema classes registered here. Migration block handles future schema changes.

import Foundation
import RealmSwift

final class RealmProvider {
    static let shared = RealmProvider()

    private(set) var realm: Realm

    /// Current schema version — bump this whenever the model changes and add a migration block.
    static let schemaVersion: UInt64 = 2

    private init() {
        let config = Realm.Configuration(
            schemaVersion: Self.schemaVersion,
            migrationBlock: { migration, oldVersion in
                // v0 → v1: initial schema, no migration needed
                // v1 → v2: added Trip.carKitName (optional String — defaults to nil, no action needed)
            },
            objectTypes: [
                UserProfile.self,
                Vehicle.self,
                Trip.self,
                TripPoint.self,
                OdometerReading.self,
            ]
        )
        Realm.Configuration.defaultConfiguration = config

        do {
            realm = try Realm()
            TripLogger.shared.log("Realm opened at: \(realm.configuration.fileURL?.path ?? "unknown")", category: .system)
        } catch {
            TripLogger.shared.log("FATAL: Could not open Realm — \(error)", category: .error)
            fatalError("Could not open Realm: \(error)")
        }
    }
}
