import Foundation

// MARK: - DebugDataCollector

struct DebugDataCollector {

    /// Collects debug information and writes it to a JSON file in the temp directory.
    /// - Parameter appState: The app's root state container.
    /// - Returns: URL to the generated JSON file, ready for sharing.
    static func collectDebugData(appState: AppState) -> URL {
        let payload = DebugPayload(
            timestamp: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            logs: collectLogs(),
            trips: collectTrips(from: appState.tripRepo),
            tripRecorderState: collectRecorderState(from: appState.tripRecorder),
            profile: collectProfile(from: appState.profileRepo),
            vehicles: collectVehicles(from: appState.profileRepo)
        )

        let fm = DateFormatter()
        fm.dateFormat = "yyyy-MM-dd_HHmmss"
        let filename = "debug_export_\(fm.string(from: Date())).json"

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        if let data = try? encoder.encode(payload) {
            try? data.write(to: url, options: .atomic)
        }

        return url
    }

    // MARK: - Private collection helpers

    private static func collectLogs() -> [LogEntry] {
        Array(TripLogger.shared.entries.suffix(500))
    }

    private static func collectTrips(from repo: TripRepository) -> [DebugTrip] {
        repo.allTrips.map { trip in
            DebugTrip(
                id: trip.id,
                vehicleId: trip.vehicleId,
                startAddress: trip.startAddress,
                endAddress: trip.endAddress,
                startedAt: trip.startedAt,
                endedAt: trip.endedAt,
                distanceMetres: trip.distanceMetres,
                category: trip.category.rawValue,
                source: trip.source.rawValue,
                startLat: trip.startLat,
                startLng: trip.startLng,
                endLat: trip.endLat,
                endLng: trip.endLng,
                notes: trip.notes,
                isSyncedToCloud: trip.isSyncedToCloud,
                pointCount: repo.tripPoints(for: trip).count
            )
        }
    }

    private static func collectRecorderState(from recorder: TripRecorder) -> DebugRecorderState {
        let s = recorder.state
        return DebugRecorderState(
            stateLabel: label(s),
            isRecording: s.isRecording,
            collectedLocationCount: recorder.collectedLocations.count,
            tripStartedAt: s.startedAt,
            currentDistance: s.distanceString(),
            currentDuration: s.durationString()
        )
    }

    private static func collectProfile(from repo: UserProfileRepository) -> DebugProfile {
        DebugProfile(
            jurisdiction: repo.jurisdiction.rawValue,
            claimMethod: repo.claimMethod.rawValue,
            distanceUnit: repo.distanceUnit.rawValue,
            hasCompletedOnboarding: repo.hasCompletedOnboarding,
            vehicleCount: repo.vehicles.count
        )
    }

    private static func collectVehicles(from repo: UserProfileRepository) -> [DebugVehicle] {
        repo.vehicles.map { vehicle in
            DebugVehicle(
                id: vehicle.id,
                name: vehicle.name,
                registration: vehicle.registration,
                type: vehicle.type.rawValue,
                fuelType: vehicle.fuelType.rawValue,
                isDefault: vehicle.isDefault,
                isArchived: vehicle.isArchived
            )
        }
    }

    private static func label(_ s: TripRecorderState) -> String {
        switch s {
        case .idle:                                         return "idle"
        case .suspected(let d, let r):                       return "suspected(\(Int(abs(d.timeIntervalSinceNow)))s \(r))"
        case .active(_, let dist):                           return "active(\(Int(dist))m)"
        case .pausing(_, let dist, let ps):                  return "pausing(\(Int(dist))m paused \(Int(abs(ps.timeIntervalSinceNow)))s)"
        case .ending(_, let dist, let r):                    return "ending(\(Int(dist))m \(r))"
        }
    }
}

// MARK: - Codable Payload Types

private struct DebugPayload: Codable {
    let timestamp: Date
    let appVersion: String
    let buildNumber: String
    let logs: [LogEntry]
    let trips: [DebugTrip]
    let tripRecorderState: DebugRecorderState
    let profile: DebugProfile
    let vehicles: [DebugVehicle]
}

private struct DebugTrip: Codable {
    let id: String
    let vehicleId: String
    let startAddress: String
    let endAddress: String
    let startedAt: Date
    let endedAt: Date?
    let distanceMetres: Double
    let category: String
    let source: String
    let startLat: Double
    let startLng: Double
    let endLat: Double
    let endLng: Double
    let notes: String?
    let isSyncedToCloud: Bool
    let pointCount: Int
}

private struct DebugRecorderState: Codable {
    let stateLabel: String
    let isRecording: Bool
    let collectedLocationCount: Int
    let tripStartedAt: Date?
    let currentDistance: String?
    let currentDuration: String?
}

private struct DebugProfile: Codable {
    let jurisdiction: String
    let claimMethod: String
    let distanceUnit: String
    let hasCompletedOnboarding: Bool
    let vehicleCount: Int
}

private struct DebugVehicle: Codable {
    let id: String
    let name: String
    let registration: String
    let type: String
    let fuelType: String
    let isDefault: Bool
    let isArchived: Bool
}
