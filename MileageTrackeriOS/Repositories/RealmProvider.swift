// RealmProvider — Opens and vends the shared Realm instance.
// All schema classes registered here. Migration block handles future schema changes.

import Foundation
import RealmSwift

final class RealmProvider {
    static let shared = RealmProvider()

    private(set) var realm: Realm

    /// Current schema version — bump this whenever the model changes and add a migration block.
    static let schemaVersion: UInt64 = 6

    private init() {
        let config = Realm.Configuration(
            schemaVersion: Self.schemaVersion,
            migrationBlock: { migration, oldVersion in
                // v0 -> v1: initial schema
                // v1 -> v2: added Trip.carKitName (optional String -- no action needed)
                // v2 -> v3: added UserProfile.trackingSchedule (List<DaySchedule>)
                //           Populated lazily in UserProfileRepository.init
                // v3 -> v4: added UserProfile.customRateThresholds (List<RateThreshold>)
                //           Empty list default requires no migration action
                // v4 -> v5: added Trip.businessUsePercent (optional Double),
                //           OdometerReading.source (OdometerSource, default .manual)
                //           Both are new optional/enum fields — no migration action needed
                // v5 -> v6: added Trip.processingStatus (TripProcessingStatus, default .complete),
                //           Trip.processingRetries (Int, default 0)
                if oldVersion < 6 {
                    migration.enumerateObjects(ofType: "Trip") { _, newObject in
                        newObject?["processingStatus"] = TripProcessingStatus.complete.rawValue
                        newObject?["processingRetries"] = 0
                    }
                }
            },
            objectTypes: [
                UserProfile.self,
                DaySchedule.self,
                RateThreshold.self,
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
