// RealmProvider — Opens and vends the shared Realm instance.
// All schema classes registered here. Migration block handles future schema changes.
// The Realm file is stored in the App Group shared container so both the main app
// and the widget extension can read it.
// On open failure, attempts graceful recovery by backing up corrupt files.

import Foundation
import RealmSwift

final class RealmProvider {
    static let shared = RealmProvider()

    private(set) var realm: Realm

    /// App Group identifier shared between the main app and widget extension.
    static let appGroupID = "group.com.harryjust.MileageTrackeriOS"

    /// Current schema version — bump this whenever the model changes and add a migration block.
    static let schemaVersion: UInt64 = 11

    private init() {
        // Fall back to default path when running without App Group (e.g. unit tests on CI).
        let sharedURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID)?
            .appendingPathComponent("default.realm")

        // Migration: copy existing Realm from the old default location to the App Group
        // container so existing users don't lose their data when the App Group URL is
        // first used. Only copies when the source exists and the destination does not.
        if let sharedURL {
            let defaultConfig = Realm.Configuration()
            if let oldURL = defaultConfig.fileURL,
               oldURL != sharedURL,
               FileManager.default.fileExists(atPath: oldURL.path),
               !FileManager.default.fileExists(atPath: sharedURL.path)
            {
                do {
                    try FileManager.default.copyItem(at: oldURL, to: sharedURL)
                    TripLogger.shared.log("Migrated existing Realm to App Group container", category: .system)
                } catch {
                    TripLogger.shared.log("Could not copy Realm to App Group: \(error)", category: .error)
                }
            }
        }

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
                // v9 -> v10: added Vehicle.isSyncedToCloud (Bool, default false),
                //            Vehicle.updatedAt (Date, default Date()),
                //            OdometerReading.isSyncedToCloud (Bool, default false),
                //            OdometerReading.updatedAt (Date, default Date())
                //            All new fields with defaults — no migration action needed.
                // v10 -> v11: added OdometerReading.createdAt (Date, default Date())
                //            New field with default — no migration action needed.
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
            realm = Self.recoverFromFailure(originalError: error, config: config)
        }
    }

    // MARK: - Recovery

    /// Attempts to recover from a Realm open failure by backing up corrupt files
    /// and creating a fresh database. Last resort uses `deleteRealmIfMigrationNeeded`.
    private static func recoverFromFailure(originalError: Error, config: Realm.Configuration) -> Realm {
        guard let fileURL = config.fileURL else {
            fatalError("Could not open Realm: \(originalError) (no fileURL to recover)")
        }

        // Step 1: Back up corrupt Realm files so data is preserved for debugging.
        do {
            try backupCorruptRealmFiles(fileURL: fileURL)
        } catch {
            TripLogger.shared.log("Recovery: file backup failed (non-fatal) -- \(error)", category: .error)
        }

        // Step 2: Try opening fresh Realm (old files are now in the backup directory).
        do {
            let realm = try Realm(configuration: config)
            TripLogger.shared.log("Realm recovered: corrupt file backed up, fresh database created", category: .system)
            return realm
        } catch let retryError {
            TripLogger.shared.log("CRITICAL: Recovery open failed -- \(retryError)", category: .error)

            // Step 3: Last resort — deleteRealmIfMigrationNeeded handles migration mismatches.
            var fallbackConfig = config
            fallbackConfig.deleteRealmIfMigrationNeeded = true
            do {
                let realm = try Realm(configuration: fallbackConfig)
                TripLogger.shared.log("Realm recovered via deleteRealmIfMigrationNeeded", category: .system)
                return realm
            } catch let finalError {
                TripLogger.shared.log("CRITICAL: All recovery paths exhausted -- \(finalError)", category: .error)
                fatalError("""
                    Could not open Realm after recovery attempts. \
                    Original: \(originalError). Recovery: \(finalError)
                    """)
            }
        }
    }

    /// Moves corrupt Realm files (main file + companion files) to a timestamped backup directory
    /// under `RealmBackups/` so they can be inspected if needed.
    static func backupCorruptRealmFiles(fileURL: URL) throws {
        let fm = FileManager.default
        let baseDir = fileURL.deletingLastPathComponent()
        let backupDir = baseDir.appendingPathComponent("RealmBackups", isDirectory: true)
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)

        let realmName = fileURL.deletingPathExtension().lastPathComponent
        let timestamp = Int(Date().timeIntervalSince1970)
        let backupPrefix = "\(realmName)_\(timestamp).realm"

        // Main realm file
        let backupMain = backupDir.appendingPathComponent(backupPrefix)
        try fm.moveItem(at: fileURL, to: backupMain)
        TripLogger.shared.log("Recovery: backed up \(fileURL.lastPathComponent) to \(backupMain.lastPathComponent)", category: .system)

        // Companion files (lock, note) — optional; skip if they don't exist.
        for ext in ["lock", "note"] {
            let companionURL = fileURL.appendingPathExtension(ext)
            if fm.fileExists(atPath: companionURL.path) {
                let dest = backupDir.appendingPathComponent("\(backupPrefix).\(ext)")
                try fm.moveItem(at: companionURL, to: dest)
            }
        }

        // Management directory — optional.
        let mgmtDir = baseDir.appendingPathComponent("\(realmName).realm.management", isDirectory: true)
        if fm.fileExists(atPath: mgmtDir.path) {
            let dest = backupDir.appendingPathComponent("\(backupPrefix).management", isDirectory: true)
            try fm.moveItem(at: mgmtDir, to: dest)
        }
    }
}
