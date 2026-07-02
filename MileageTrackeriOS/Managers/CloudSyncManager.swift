// CloudSyncManager — Bidirectional sync between Realm and CloudKit private database.
//
// Syncs Trip, Vehicle, and OdometerReading objects. Conflict resolution uses
// last-write-wins based on the `updatedAt` timestamp on each model.
// TripPoint objects are excluded (they are GPS breadcrumbs that are too
// numerous and not needed for cross-device usage).
//
// The manager debounces local changes: a sync is scheduled 5 seconds after
// the last local mutation so that rapid writes batch into a single operation.
// First-time initialisation also schedules an immediate sync.

import Foundation
import CloudKit
import Realm
import RealmSwift

// MARK: - SyncStatus

enum CloudSyncStatus: Equatable {
    case notStarted
    case idle
    case uploading(Int)   // record count
    case downloading
    case error(String)

    var isBusy: Bool {
        switch self {
        case .uploading, .downloading: return true
        default: return false
        }
    }
}

// MARK: - SyncableObject protocol

/// Protocol for Realm objects that can be synced to CloudKit.
/// Every syncable model must have these properties.
protocol SyncableObject: AnyObject {
    var id: String { get set }
    var isSyncedToCloud: Bool { get set }
    var updatedAt: Date { get set }
}

extension Trip: SyncableObject {}
extension Vehicle: SyncableObject {}
extension OdometerReading: SyncableObject {}

// MARK: - CloudKitRecordConvertible

/// Objects that can be converted to/from CKRecord.
protocol CloudKitRecordConvertible {
    associatedtype RealmObject: Object

    /// CloudKit record type string.
    static var recordType: String { get }

    /// Convert the Realm object to a CKRecord.
    func toRecord() -> CKRecord

    /// Update a Realm object from a CKRecord. Returns true if the record is newer
    /// than the local object (or the local object doesn't exist).
    static func shouldApply(record: CKRecord, to existing: RealmObject?) -> Bool

    /// Apply remote CKRecord data to a Realm object (already in a write transaction).
    static func apply(record: CKRecord, to object: RealmObject)
}

// MARK: - CloudSyncManager

@Observable
final class CloudSyncManager {
    private let container: CKContainer
    private let database: CKDatabase
    private let realm: Realm

    // Observers
    private var tripObserver: NotificationToken?
    private var vehicleObserver: NotificationToken?
    private var odometerObserver: NotificationToken?

    // Debounce
    private var pendingSyncWorkItem: DispatchWorkItem?
    private let syncQueue = DispatchQueue(label: "com.harryjust.cloudsync", qos: .utility)

    // State
    private(set) var syncStatus: CloudSyncStatus = .notStarted
    private(set) var lastSyncAt: Date?
    private var pendingSyncCount: Int = 0
    private var isSyncing = false

    /// Whether the user has an active iCloud account. Checked before every sync.
    private var accountStatus: CKAccountStatus = .couldNotDetermine

    // Deletion tracking — snapshots of IDs known to exist in Realm.
    // When a collection notification fires, we diff the current IDs against
    // the snapshot to detect deletions and propagate them to CloudKit.
    private var knownTripIDs: Set<String> = []
    private var knownVehicleIDs: Set<String> = []
    private var knownOdometerIDs: Set<String> = []
    /// IDs of locally-deleted objects whose CKRecords need to be removed.
    private var pendingDeleteRecordIDs: Set<String> = []
    /// Timestamp of last account status check -- used to avoid re-checking on every sync.
    private var lastAccountStatusCheck: Date = .distantPast

    init(realm: Realm, containerIdentifier: String = "iCloud.com.harryjust.MileageTrackeriOS") {
        self.realm = realm
        self.container = CKContainer(identifier: containerIdentifier)
        self.database = container.privateCloudDatabase
        checkAccountStatus()
        observeRealm()
        scheduleSync() // First-time sync on init
    }

    // MARK: - Account Status

    private func checkAccountStatus() {
        container.accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.syncStatus = .error("iCloud account check failed: \(error.localizedDescription)")
                    return
                }
                self.accountStatus = status
                if status == .available {
                    self.syncStatus = .idle
                } else {
                    self.syncStatus = .error("iCloud account not available (status: \(status.rawValue))")
                }
            }
        }
    }


    /// Re-checks account status if the cached value is stale (>60s old).
    /// Calls completion with true if the account is available, false otherwise.
    private func refreshAccountStatusIfNeeded(completion: @escaping (Bool) -> Void) {
        if accountStatus == .available, Date().timeIntervalSince(lastAccountStatusCheck) < 60 {
            completion(true)
            return
        }

        container.accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                guard let self else {
                    completion(false)
                    return
                }
                self.lastAccountStatusCheck = Date()
                if let error {
                    self.syncStatus = .error("iCloud account check failed: \(error.localizedDescription)")
                    completion(false)
                    return
                }
                self.accountStatus = status
                if status == .available {
                    self.syncStatus = .idle
                    completion(true)
                } else {
                    self.syncStatus = .error("iCloud account not available (status: \(status.rawValue))")
                    completion(false)
                }
            }
        }
    }

    // MARK: - Realm Observation

    private func observeRealm() {
        // Observe trips
        let trips = realm.objects(Trip.self)
        knownTripIDs = Set(trips.map { $0.id })
        tripObserver = trips.observe { [weak self] changes in
            guard let self else { return }
            guard case .update(let results, _, _, _) = changes else { return }
            let newIDs = Set(results.map { $0.id })

            // Detect and track deletions by diffing snapshot vs current state
            let deletedIDs = knownTripIDs.subtracting(newIDs)
            if !deletedIDs.isEmpty {
                TripLogger.shared.log("CloudSync: \(deletedIDs.count) trips deleted locally", category: .system)
                pendingDeleteRecordIDs.formUnion(deletedIDs)
            }

            knownTripIDs = newIDs

            // Count insertions/modifications from the change set; schedule sync if anything changed
            if case .update(_, _, let insertions, let modifications) = changes, insertions.count + modifications.count > 0 {
                scheduleSync()
            } else if !deletedIDs.isEmpty {
                scheduleSync()
            }
        }

        // Observe vehicles
        let vehicles = realm.objects(Vehicle.self)
        knownVehicleIDs = Set(vehicles.map { $0.id })
        vehicleObserver = vehicles.observe { [weak self] changes in
            guard let self else { return }
            guard case .update(let results, _, _, _) = changes else { return }
            let newIDs = Set(results.map { $0.id })

            let deletedIDs = knownVehicleIDs.subtracting(newIDs)
            if !deletedIDs.isEmpty {
                TripLogger.shared.log("CloudSync: \(deletedIDs.count) vehicles deleted locally", category: .system)
                pendingDeleteRecordIDs.formUnion(deletedIDs)
            }

            knownVehicleIDs = newIDs

            if case .update(_, _, let insertions, let modifications) = changes, insertions.count + modifications.count > 0 {
                scheduleSync()
            } else if !deletedIDs.isEmpty {
                scheduleSync()
            }
        }

        // Observe odometer readings
        let readings = realm.objects(OdometerReading.self)
        knownOdometerIDs = Set(readings.map { $0.id })
        odometerObserver = readings.observe { [weak self] changes in
            guard let self else { return }
            guard case .update(let results, _, _, _) = changes else { return }
            let newIDs = Set(results.map { $0.id })

            let deletedIDs = knownOdometerIDs.subtracting(newIDs)
            if !deletedIDs.isEmpty {
                TripLogger.shared.log("CloudSync: \(deletedIDs.count) odometer readings deleted locally", category: .system)
                pendingDeleteRecordIDs.formUnion(deletedIDs)
            }

            knownOdometerIDs = newIDs

            if case .update(_, _, let insertions, let modifications) = changes, insertions.count + modifications.count > 0 {
                scheduleSync()
            } else if !deletedIDs.isEmpty {
                scheduleSync()
            }
        }
    }

    func invalidate() {
        tripObserver = nil
        vehicleObserver = nil
        odometerObserver = nil
        pendingSyncWorkItem?.cancel()
        pendingSyncWorkItem = nil
    }

    // MARK: - Debounced Sync Scheduling

    /// Schedules a sync 5 seconds after the last local change.
    /// Cancels any previously scheduled sync so rapid writes coalesce.
    private func scheduleSync() {
        pendingSyncWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.executeSync()
        }
        pendingSyncWorkItem = workItem
        syncQueue.asyncAfter(deadline: .now() + 5, execute: workItem)
    }

    /// Forces an immediate sync, cancelling any pending debounce.
    /// Dispatches to the background sync queue so it never blocks the caller.
    func syncNow() {
        pendingSyncWorkItem?.cancel()
        syncQueue.async { [weak self] in
            self?.executeSync()
        }
    }

    // MARK: - Main Sync

    /// Executes a full sync cycle: upload local changes, then download remote changes.
    /// Uses async callback chaining instead of DispatchGroup.wait() to avoid
    /// blocking the sync queue (which would deadlock with notify-dispatch patterns).
    private func executeSync() {
        guard !isSyncing else { return }
        guard accountStatus == .available else { return }

        // Refresh account status if stale (user may have signed in/out since last check)
        self.lastAccountStatusCheck = Date()

        isSyncing = true

        // 1. Upload local changes (including deletions)
        uploadDirtyObjects { [weak self] uploadCount in
            guard let self else { return }

            if uploadCount > 0 {
                DispatchQueue.main.async {
                    self.syncStatus = .idle
                    self.lastSyncAt = Date()
                }
            }

            // 2. Download remote changes
            DispatchQueue.main.async {
                self.syncStatus = .downloading
            }

            self.downloadRemoteChanges {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.isSyncing = false
                    self.syncStatus = .idle
                    self.lastSyncAt = Date()
                }
            }
        }
    }

    // MARK: - Upload

    private func uploadDirtyObjects(completion: @escaping (Int) -> Void) {
        var records: [CKRecord] = []
        var recordIDsToDelete: [CKRecord.ID] = []

        // Collect dirty trips
        let dirtyTrips = realm.objects(Trip.self).where { $0.isSyncedToCloud == false }
        records.append(contentsOf: dirtyTrips.map { $0.toCloudRecord() })

        // Collect dirty vehicles
        let dirtyVehicles = realm.objects(Vehicle.self).where { $0.isSyncedToCloud == false }
        records.append(contentsOf: dirtyVehicles.map { $0.toCloudRecord() })

        // Collect dirty odometer readings
        let dirtyReadings = realm.objects(OdometerReading.self).where { $0.isSyncedToCloud == false }
        records.append(contentsOf: dirtyReadings.map { $0.toCloudRecord() })

        // Collect pending deletion IDs (locally-deleted objects to propagate to CloudKit)
        let deletionIDs = pendingDeleteRecordIDs
        pendingDeleteRecordIDs.removeAll()
        for objectID in deletionIDs {
            let recordID = CKRecord.ID(recordName: objectID)
            recordIDsToDelete.append(recordID)
        }

        guard !records.isEmpty || !recordIDsToDelete.isEmpty else {
            DispatchQueue.main.async {
                self.syncStatus = .idle
            }
            completion(0)
            return
        }

        let totalCount = records.count
        DispatchQueue.main.async {
            self.syncStatus = .uploading(totalCount)
        }

        // CloudKit limit is 400 per operation; we use 200 for safety.
        let chunks = stride(from: 0, to: records.count, by: 200).map {
            Array(records[$0..<min($0 + 200, records.count)])
        }

        let uploadGroup = DispatchGroup()
        var allSucceeded = true

        if chunks.isEmpty && !recordIDsToDelete.isEmpty {
            // Only deletions to send, no records to save
            uploadGroup.enter()
            let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIDsToDelete)
            operation.savePolicy = .allKeys
            operation.qualityOfService = .utility

            operation.modifyRecordsResultBlock = { result in
                if case .failure(let error) = result {
                    TripLogger.shared.log("[CloudSync] Deletion upload error: \(error.localizedDescription)", category: .error)
                    allSucceeded = false
                }
                uploadGroup.leave()
            }

            database.add(operation)
        } else {
            for chunk in chunks {
                uploadGroup.enter()
                let operation = CKModifyRecordsOperation(
                    recordsToSave: chunk,
                    recordIDsToDelete: nil
                )
                operation.savePolicy = .allKeys
                operation.qualityOfService = .utility

                operation.modifyRecordsResultBlock = { result in
                    if case .failure(let error) = result {
                        TripLogger.shared.log("[CloudSync] Upload error: \(error.localizedDescription)", category: .error)
                        allSucceeded = false
                    }
                    uploadGroup.leave()
                }

                database.add(operation)
            }

            // If there are also deletions, send them in the last chunk
            if !recordIDsToDelete.isEmpty {
                uploadGroup.enter()
                let deleteOp = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIDsToDelete)
                deleteOp.qualityOfService = .utility
                deleteOp.modifyRecordsResultBlock = { result in
                    if case .failure(let error) = result {
                        TripLogger.shared.log("[CloudSync] Deletion error: \(error.localizedDescription)", category: .error)
                        allSucceeded = false
                    }
                    uploadGroup.leave()
                }
                database.add(deleteOp)
            }
        }

        uploadGroup.notify(queue: self.syncQueue) { [weak self] in
            guard let self else { return }
            if allSucceeded {
                try? self.realm.write {
                    for trip in dirtyTrips {
                        trip.isSyncedToCloud = true
                    }
                    for vehicle in dirtyVehicles {
                        vehicle.isSyncedToCloud = true
                    }
                    for reading in dirtyReadings {
                        reading.isSyncedToCloud = true
                    }
                }
            }
            completion(totalCount)
        }
    }

    // MARK: - Download

    private func downloadRemoteChanges(completion: @escaping () -> Void) {
        let group = DispatchGroup()

        group.enter()
        fetchRecords(type: "MTTrip") { [weak self] records, error in
            guard let self, let records else {
                group.leave()
                return
            }
            self.applyRemoteRecords(records, type: Trip.self) { group.leave() }
        }

        group.enter()
        fetchRecords(type: "MTVehicle") { [weak self] records, error in
            guard let self, let records else {
                group.leave()
                return
            }
            self.applyRemoteRecords(records, type: Vehicle.self) { group.leave() }
        }

        group.enter()
        fetchRecords(type: "MTOdometerReading") { [weak self] records, error in
            guard let self, let records else {
                group.leave()
                return
            }
            self.applyRemoteRecords(records, type: OdometerReading.self) { group.leave() }
        }

        group.notify(queue: .main) {
            completion()
        }
    }

    /// Fetches all records of a given CloudKit type from the private database.
    private func fetchRecords(type recordType: String, completion: @escaping ([CKRecord]?, Error?) -> Void) {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "modificationDate", ascending: false)]

        var allRecords: [CKRecord] = []
        let operation = CKQueryOperation(query: query)
        operation.qualityOfService = .utility
        operation.resultsLimit = 200

        operation.recordMatchedBlock = { _, result in
            switch result {
            case .success(let record):
                allRecords.append(record)
            case .failure:
                break
            }
        }

        operation.queryResultBlock = { result in
            switch result {
            case .success(let cursor):
                if let cursor {
                    // There are more records — fetch next page using self.database
                    let nextOp = CKQueryOperation(cursor: cursor)
                    nextOp.qualityOfService = .utility
                    nextOp.resultsLimit = 200
                    nextOp.recordMatchedBlock = operation.recordMatchedBlock
                    nextOp.queryResultBlock = operation.queryResultBlock
                    self.database.add(nextOp)
                } else {
                    completion(allRecords, nil)
                }
            case .failure(let error):
                completion(allRecords, error)
            }
        }

        database.add(operation)
    }

    /// Applies remote CKRecords to local Realm, using last-write-wins.
    private func applyRemoteRecords<T: Object & SyncableObject>(
        _ records: [CKRecord],
        type: T.Type,
        completion: @escaping () -> Void
    ) {
        syncQueue.async { [weak self] in
            guard let self else { return }

            for record in records {
                guard let recordID = record.recordID.recordName as String? else { continue }

                // Get the remote modification date from CKRecord system field
                let remoteModifiedAt = record.modificationDate ?? Date.distantPast

                // Check local object
                if let local = self.realm.object(ofType: T.self, forPrimaryKey: recordID) {
                    // Last-write-wins: skip if local is newer
                    if local.updatedAt > remoteModifiedAt {
                        continue
                    }
                    // Local is older — update it
                    self.applyRecord(record, to: local)
                } else {
                    // Object doesn't exist locally — create it
                    self.createObject(from: record, type: T.self)
                }
            }
            completion()
        }
    }

    /// Creates a Realm object from a CKRecord and adds it to the local database.
    private func createObject<T: Object>(from record: CKRecord, type: T.Type) {
        guard let object = record.toRealmObject(type: T.self) else { return }

        // Ensure the object has the sync flag
        if let syncable = object as? SyncableObject {
            syncable.isSyncedToCloud = true
            syncable.updatedAt = record.modificationDate ?? Date()
        }

        try? realm.write {
            realm.add(object, update: .modified)
        }
    }

    /// Applies CKRecord field values to an existing Realm object (last-write-wins).
    private func applyRecord(_ record: CKRecord, to object: Object) {
        guard let syncable = object as? SyncableObject else { return }

        try? realm.write {
            syncable.isSyncedToCloud = true
            syncable.updatedAt = record.modificationDate ?? Date()

            // Apply type-specific fields
            if let trip = object as? Trip {
                trip.vehicleId = record["vehicleId"] as? String ?? trip.vehicleId
                trip.startAddress = record["startAddress"] as? String ?? trip.startAddress
                trip.endAddress = record["endAddress"] as? String ?? trip.endAddress
                trip.startLat = record["startLat"] as? Double ?? trip.startLat
                trip.startLng = record["startLng"] as? Double ?? trip.startLng
                trip.endLat = record["endLat"] as? Double ?? trip.endLat
                trip.endLng = record["endLng"] as? Double ?? trip.endLng
                trip.startedAt = record["startedAt"] as? Date ?? trip.startedAt
                trip.endedAt = record["endedAt"] as? Date
                trip.distanceMetres = record["distanceMetres"] as? Double ?? trip.distanceMetres
                if let categoryRaw = record["category"] as? String,
                   let category = TripCategory(rawValue: categoryRaw) {
                    trip.category = category
                }
                if let sourceRaw = record["source"] as? String,
                   let source = TripSource(rawValue: sourceRaw) {
                    trip.source = source
                }
                trip.notes = record["notes"] as? String
                trip.dollarValue = record["dollarValue"] as? Double
                trip.isCapExceeded = record["isCapExceeded"] as? Bool ?? false
                if let statusRaw = record["processingStatus"] as? String,
                   let status = TripProcessingStatus(rawValue: statusRaw) {
                    trip.processingStatus = status
                }
                trip.gpsDistanceMetres = record["gpsDistanceMetres"] as? Double ?? 0
                trip.odometerDistanceMetres = record["odometerDistanceMetres"] as? Double
                trip.purpose = record["purpose"] as? String
                trip.commitHash = record["commitHash"] as? String
                trip.committedAt = record["committedAt"] as? Date
                trip.createdAt = record["createdAt"] as? Date ?? trip.createdAt
            } else if let vehicle = object as? Vehicle {
                vehicle.name = record["name"] as? String ?? vehicle.name
                vehicle.registration = record["registration"] as? String ?? vehicle.registration
                if let typeRaw = record["type"] as? String,
                   let type = VehicleType(rawValue: typeRaw) {
                    vehicle.type = type
                }
                if let fuelRaw = record["fuelType"] as? String,
                   let fuel = FuelType(rawValue: fuelRaw) {
                    vehicle.fuelType = fuel
                }
                vehicle.isDefault = record["isDefault"] as? Bool ?? false
                vehicle.isArchived = record["isArchived"] as? Bool ?? false
                if let catRaw = record["defaultCategory"] as? String,
                   let cat = TripCategory(rawValue: catRaw) {
                    vehicle.defaultCategory = cat
                }
                vehicle.createdAt = record["createdAt"] as? Date ?? vehicle.createdAt
            } else if let reading = object as? OdometerReading {
                reading.vehicleId = record["vehicleId"] as? String ?? reading.vehicleId
                reading.readingKm = record["readingKm"] as? Double ?? reading.readingKm
                reading.recordedAt = record["recordedAt"] as? Date ?? reading.recordedAt
                reading.tripId = record["tripId"] as? String
                reading.notes = record["notes"] as? String
                if let sourceRaw = record["source"] as? String,
                   let source = OdometerSource(rawValue: sourceRaw) {
                    reading.source = source
                }
                reading.createdAt = record["createdAt"] as? Date ?? reading.createdAt
            }
        }
    }
}

// MARK: - CKRecord Conversion Extensions

extension Trip {
    func toCloudRecord() -> CKRecord {
        let recordID = CKRecord.ID(recordName: id)
        let record = CKRecord(recordType: "MTTrip", recordID: recordID)

        record["vehicleId"] = vehicleId
        record["startAddress"] = startAddress
        record["endAddress"] = endAddress
        record["startLat"] = startLat
        record["startLng"] = startLng
        record["endLat"] = endLat
        record["endLng"] = endLng
        record["startedAt"] = startedAt
        record["endedAt"] = endedAt
        record["distanceMetres"] = distanceMetres
        record["category"] = category.rawValue
        record["source"] = source.rawValue
        record["notes"] = notes
        record["dollarValue"] = dollarValue
        record["isCapExceeded"] = isCapExceeded
        record["processingStatus"] = processingStatus.rawValue
        record["purpose"] = purpose
        record["commitHash"] = commitHash
        record["committedAt"] = committedAt
        record["gpsDistanceMetres"] = gpsDistanceMetres
        record["odometerDistanceMetres"] = odometerDistanceMetres
        record["createdAt"] = createdAt
        record["updatedAt"] = updatedAt

        return record
    }
}

extension Vehicle {
    func toCloudRecord() -> CKRecord {
        let recordID = CKRecord.ID(recordName: id)
        let record = CKRecord(recordType: "MTVehicle", recordID: recordID)

        record["name"] = name
        record["registration"] = registration
        record["type"] = type.rawValue
        record["fuelType"] = fuelType.rawValue
        record["isDefault"] = isDefault
        record["isArchived"] = isArchived
        record["defaultCategory"] = defaultCategory.rawValue
        record["createdAt"] = createdAt
        record["updatedAt"] = updatedAt

        return record
    }
}

extension OdometerReading {
    func toCloudRecord() -> CKRecord {
        let recordID = CKRecord.ID(recordName: id)
        let record = CKRecord(recordType: "MTOdometerReading", recordID: recordID)

        record["vehicleId"] = vehicleId
        record["readingKm"] = readingKm
        record["recordedAt"] = recordedAt
        record["tripId"] = tripId
        record["notes"] = notes
        record["source"] = source.rawValue
        record["createdAt"] = createdAt
        record["updatedAt"] = updatedAt

        return record
    }
}

// MARK: - CKRecord to Realm Object (for incoming sync)

extension CKRecord {
    func toRealmObject<T: Object>(type: T.Type) -> T? {
        let recordName = recordID.recordName

        if type == Trip.self {
            let trip = Trip()
            trip.id = recordName
            trip.vehicleId = self["vehicleId"] as? String ?? ""
            trip.startAddress = self["startAddress"] as? String ?? ""
            trip.endAddress = self["endAddress"] as? String ?? ""
            trip.startLat = self["startLat"] as? Double ?? 0
            trip.startLng = self["startLng"] as? Double ?? 0
            trip.endLat = self["endLat"] as? Double ?? 0
            trip.endLng = self["endLng"] as? Double ?? 0
            trip.startedAt = self["startedAt"] as? Date ?? Date()
            trip.endedAt = self["endedAt"] as? Date
            trip.distanceMetres = self["distanceMetres"] as? Double ?? 0
            if let raw = self["category"] as? String, let cat = TripCategory(rawValue: raw) {
                trip.category = cat
            }
            if let raw = self["source"] as? String, let src = TripSource(rawValue: raw) {
                trip.source = src
            }
            trip.notes = self["notes"] as? String
            trip.dollarValue = self["dollarValue"] as? Double
            trip.isCapExceeded = self["isCapExceeded"] as? Bool ?? false
            if let raw = self["processingStatus"] as? String, let status = TripProcessingStatus(rawValue: raw) {
                trip.processingStatus = status
            }
            trip.gpsDistanceMetres = self["gpsDistanceMetres"] as? Double ?? 0
            trip.odometerDistanceMetres = self["odometerDistanceMetres"] as? Double
            trip.purpose = self["purpose"] as? String
            trip.commitHash = self["commitHash"] as? String
            trip.committedAt = self["committedAt"] as? Date
            trip.createdAt = self["createdAt"] as? Date ?? Date()
            trip.updatedAt = self["updatedAt"] as? Date ?? Date()
            trip.isSyncedToCloud = true
            return trip as? T
        } else if type == Vehicle.self {
            let vehicle = Vehicle()
            vehicle.id = recordName
            vehicle.name = self["name"] as? String ?? ""
            vehicle.registration = self["registration"] as? String ?? ""
            if let raw = self["type"] as? String, let t = VehicleType(rawValue: raw) {
                vehicle.type = t
            }
            if let raw = self["fuelType"] as? String, let f = FuelType(rawValue: raw) {
                vehicle.fuelType = f
            }
            vehicle.isDefault = self["isDefault"] as? Bool ?? false
            vehicle.isArchived = self["isArchived"] as? Bool ?? false
            if let raw = self["defaultCategory"] as? String, let cat = TripCategory(rawValue: raw) {
                vehicle.defaultCategory = cat
            }
            vehicle.createdAt = self["createdAt"] as? Date ?? Date()
            vehicle.updatedAt = self["updatedAt"] as? Date ?? Date()
            vehicle.isSyncedToCloud = true
            return vehicle as? T
        } else if type == OdometerReading.self {
            let reading = OdometerReading()
            reading.id = recordName
            reading.vehicleId = self["vehicleId"] as? String ?? ""
            reading.readingKm = self["readingKm"] as? Double ?? 0
            reading.recordedAt = self["recordedAt"] as? Date ?? Date()
            reading.tripId = self["tripId"] as? String
            reading.notes = self["notes"] as? String
            if let raw = self["source"] as? String, let s = OdometerSource(rawValue: raw) {
                reading.source = s
            }
            reading.createdAt = self["createdAt"] as? Date ?? Date()
            reading.updatedAt = self["updatedAt"] as? Date ?? Date()
            reading.isSyncedToCloud = true
            return reading as? T
        }
        return nil
    }
}
