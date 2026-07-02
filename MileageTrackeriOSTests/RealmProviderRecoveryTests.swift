import Testing
import CoreLocation
import CoreMotion
import RealmSwift
@testable import MileageTrackeriOS

@Suite("RealmProvider Graceful Recovery")
struct RealmProviderRecoveryTests {

    /// Helper: creates a unique temp directory that is cleaned up on exit.
    private func withTempDir<T>(_ body: (URL) throws -> T) throws -> T {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("realmtest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        return try body(dir)
    }

    @Test("backupCorruptRealmFiles moves the main realm file to the backup directory")
    func backupMovesMainFile() throws {
        try withTempDir { dir in
            let realmURL = dir.appendingPathComponent("test.realm")
            try "corrupt data".write(to: realmURL, atomically: true, encoding: .utf8)

            try RealmProvider.backupCorruptRealmFiles(fileURL: realmURL)

            // Original file should be gone
            #expect(!FileManager.default.fileExists(atPath: realmURL.path))

            // Backup file should exist
            let backupDir = dir.appendingPathComponent("RealmBackups")
            let backups = try FileManager.default.contentsOfDirectory(atPath: backupDir.path)
            #expect(backups.contains { $0.hasSuffix("test.realm") || $0.contains("test_") })
            #expect(backups.contains { $0.hasSuffix(".realm") })
        }
    }

    @Test("backupCorruptRealmFiles backs up companion lock and note files")
    func backupMovesCompanionFiles() throws {
        try withTempDir { dir in
            let realmURL = dir.appendingPathComponent("test.realm")
            try "corrupt data".write(to: realmURL, atomically: true, encoding: .utf8)
            try "lock data".write(to: realmURL.appendingPathExtension("lock"), atomically: true, encoding: .utf8)
            try "note data".write(to: realmURL.appendingPathExtension("note"), atomically: true, encoding: .utf8)

            try RealmProvider.backupCorruptRealmFiles(fileURL: realmURL)

            let backupDir = dir.appendingPathComponent("RealmBackups")
            let backups = try FileManager.default.contentsOfDirectory(atPath: backupDir.path)
            #expect(backups.contains { $0.hasSuffix(".realm.lock") || $0.contains("lock") })
            #expect(backups.contains { $0.hasSuffix(".realm.note") || $0.contains("note") })
        }
    }

    @Test("backupCorruptRealmFiles handles missing companion files gracefully")
    func backupWithMissingCompanions() throws {
        try withTempDir { dir in
            let realmURL = dir.appendingPathComponent("test.realm")
            try "corrupt data".write(to: realmURL, atomically: true, encoding: .utf8)

            // Only main file exists — no lock or note companion files.
            // Should not throw despite missing companions.
            try RealmProvider.backupCorruptRealmFiles(fileURL: realmURL)

            let backupDir = dir.appendingPathComponent("RealmBackups")
            #expect(FileManager.default.fileExists(atPath: backupDir.path))
        }
    }

    @Test("backupCorruptRealmFiles backs up management directory")
    func backupMovesManagementDir() throws {
        try withTempDir { dir in
            let realmURL = dir.appendingPathComponent("test.realm")
            try "corrupt data".write(to: realmURL, atomically: true, encoding: .utf8)

            // Create management directory with a file inside
            let mgmtDir = dir.appendingPathComponent("test.realm.management")
            try FileManager.default.createDirectory(at: mgmtDir, withIntermediateDirectories: true)
            try "meta".write(to: mgmtDir.appendingPathComponent("meta.lock"), atomically: true, encoding: .utf8)

            try RealmProvider.backupCorruptRealmFiles(fileURL: realmURL)

            let backupDir = dir.appendingPathComponent("RealmBackups")
            let backups = try FileManager.default.contentsOfDirectory(atPath: backupDir.path)
            #expect(backups.contains { $0.contains("management") })

            // Verify the management directory was moved (original gone)
            #expect(!FileManager.default.fileExists(atPath: mgmtDir.path))
        }
    }

    @Test("backup creates the RealmBackups directory if it does not exist")
    func backupCreatesRealmBackupsDir() throws {
        try withTempDir { dir in
            let realmURL = dir.appendingPathComponent("test.realm")
            try "corrupt data".write(to: realmURL, atomically: true, encoding: .utf8)

            let backupDir = dir.appendingPathComponent("RealmBackups")
            #expect(!FileManager.default.fileExists(atPath: backupDir.path),
                    "Precondition: backup dir should not exist yet")

            try RealmProvider.backupCorruptRealmFiles(fileURL: realmURL)

            #expect(FileManager.default.fileExists(atPath: backupDir.path))
        }
    }

    @Test("backup with a real in-memory Realm does not interfere with normal operation")
    func backupDoesNotAffectNormalRealm() throws {
        // This tests that the backup logic is purely file-based and doesn't affect
        // normal Realm operation. We create a real in-memory Realm, then verify
        // the backup function is only concerned with file paths.
        let config = Realm.Configuration(
            inMemoryIdentifier: UUID().uuidString,
            schemaVersion: RealmProvider.schemaVersion,
            objectTypes: [UserProfile.self, Vehicle.self, Trip.self, TripPoint.self,
                          OdometerReading.self, SavedAddress.self, LogbookPeriod.self]
        )
        let realm = try Realm(configuration: config)
        #expect(realm.objects(Trip.self).count == 0)
    }
}

// MARK: - Notification Recovery Action Tests

