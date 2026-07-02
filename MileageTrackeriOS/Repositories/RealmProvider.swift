// RealmProvider — Opens and vends the shared Realm instance.
// All schema classes registered here. Migration block handles future schema changes.
// The Realm file is stored in the App Group shared container so both the main app
// and the widget extension can read it.

import Foundation
import RealmSwift

final class RealmProvider {
    static let shared = RealmProvider()

    private(set) var realm: Realm

    /// App Group identifier shared between the main app and widget extension.
    static let appGroupID = "group.com.harryjust.MileageTrackeriOS"

    /// Current schema version — bump this whenever the model changes and add a migration block.
    static let schemaVersion: UInt64 = 9

    private init() {
        // Fall back to default path when running without App Group (e.g. unit tests on CI).
        let sharedURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID)?
            .appendingPathComponent("default.realm")

        var config = Realm.Configuration(
            fileURL: sharedURL,
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
                // v6 -> v7: §4.3 — Vehicle.defaultCategory (TripCategory, default .uncategorised)
                //           §5.1 — Trip.purpose (optional String)
                //           §5.2 — Trip.commitHash (optional String), Trip.committedAt (optional Date)
                //           §3.4 — Trip.gpsDistanceMetres (Double, default = current distanceMetres),
                //                  Trip.odometerDistanceMetres (optional Double)
                if oldVersion < 6 {
                    migration.enumerateObjects(ofType: "Trip") { _, newObject in
                        newObject?["processingStatus"] = TripProcessingStatus.complete.rawValue
                        newObject?["processingRetries"] = 0
                    }
                }
                if oldVersion < 7 {
                    migration.enumerateObjects(ofType: "Vehicle") { _, newObject in
                        newObject?["defaultCategory"] = TripCategory.uncategorised.rawValue
                    }
                    migration.enumerateObjects(ofType: "Trip") { oldObject, newObject in
                        // Seed gpsDistanceMetres from existing distanceMetres so historic trips
                        // preserve their as-recorded GPS figure (vs future odometer-corrected one).
                        let existing = (oldObject?["distanceMetres"] as? Double) ?? 0
                        newObject?["gpsDistanceMetres"] = existing
                    }
                }
                // v7 -> v8: new SavedAddress collection — no enumerate needed (empty default).
                // Drives the commute (home↔work) auto-categorisation rule.
                // v8 -> v9: new LogbookPeriod model + MTSubscriptionPeriod table — no enumerate needed (empty defaults).
            },
            objectTypes: [
                UserProfile.self,
                DaySchedule.self,
                RateThreshold.self,
                Vehicle.self,
                Trip.self,
                TripPoint.self,
                OdometerReading.self,
                SavedAddress.self,
                LogbookPeriod.self,
                MTSubscriptionPeriod.self,
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
