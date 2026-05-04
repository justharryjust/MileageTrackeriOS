// RealmProvider — Opens and vends the shared Realm instance.
// All schema classes registered here. Migration block handles future schema changes.

import Foundation
import RealmSwift

final class RealmProvider {
    static let shared = RealmProvider()

    private(set) var realm: Realm

    /// Current schema version — bump this whenever the model changes and add a migration block.
    static let schemaVersion: UInt64 = 3

    private init() {
        let config = Realm.Configuration(
            schemaVersion: Self.schemaVersion,
            migrationBlock: { migration, oldVersion in
                // v0 -> v1: initial schema
                // v1 -> v2: added Trip.carKitName (optional String -- no action needed)
                // v2 -> v3: added UserProfile.trackingSchedule (List<DaySchedule>)
                //           Populated lazily in UserProfileRepository.init
//                migration
            },
            objectTypes: [
                UserProfile.self,
                DaySchedule.self,
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
            TripLogger.shared.log("FATAL: Could not open Realm -- \(error)", category: .error)
            fatalError("Could not open Realm: \(error)")
        }
    }
}
