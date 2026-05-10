// TripLogger — Persistent, exportable debug logging
// Logs survive app restarts but are excluded from iCloud backup.
// Buffer persists to disk so DebugLogView shows history across launches.
// Writes human-readable lines to a text file + serialised entries for the in-app viewer.

import Foundation
import Combine
import OSLog

// MARK: - Log Category

enum LogCategory: String, Codable {
    case system   = "SYSTEM"
    case location = "LOCATION"
    case motion   = "MOTION"
    case trip     = "TRIP"
    case ui       = "UI"
    case error    = "ERROR"

    var emoji: String {
        switch self {
        case .system:   return "⚙️"
        case .location: return "📍"
        case .motion:   return "🏃"
        case .trip:     return "🚗"
        case .ui:       return "📱"
        case .error:    return "🔴"
        }
    }
}

// MARK: - Log Entry

struct LogEntry: Identifiable, Codable {
    let id       : UUID
    let date     : Date
    let category : LogCategory
    let message  : String

    var formatted: String {
        let ts = TripLogger.timestampFormatter.string(from: date)
        return "\(ts) \(category.emoji)[\(category.rawValue)] \(message)"
    }
}

// MARK: - TripLogger

@MainActor
final class TripLogger: ObservableObject {
    static let shared = TripLogger()

    /// In-memory ring buffer (last 5000 entries) — persisted to disk so history survives restarts.
    @Published private(set) var entries: [LogEntry] = []

    private let textLogURL: URL       // human-readable, exportable
    private let entriesCacheURL: URL   // serialised entries for the debug viewer
    private let maxEntries      = 5000
    private let maxFileBytes    = 5 * 1024 * 1024   // 5 MB rolling cap for text log
    private let logger = Logger(subsystem: "com.harryjust.MileageTrackeriOS", category: "TripLogger")

    static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    private init() {
        // Use Application Support — not backed up to iCloud, not visible to the user
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let logDir = base.appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

        textLogURL       = logDir.appendingPathComponent("TripLogs.txt")
        entriesCacheURL  = logDir.appendingPathComponent("TripLogs_entries.json")

        // Restore persisted entries from disk
        loadPersistedEntries()

        // Write session separator
        appendToFile("──────────────────────────────────────────\n")
        appendToFile("Session started: \(Date())\n")
        appendToFile("──────────────────────────────────────────\n")
    }

    // MARK: - Public API

    func log(_ message: String, category: LogCategory = .system, file: String = #file, line: Int = #line) {
        let entry = LogEntry(id: UUID(), date: Date(), category: category, message: message)

        // In-memory buffer (ring)
        entries.append(entry)
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }

        // Persist to text file
        appendToFile(entry.formatted + "\n")

        // Persist entries cache (throttle this? It's small JSON — fine for debug logging volume)
        persistEntries()

        // Unified logging (Console.app)
        switch category {
        case .error:  logger.error("\(entry.formatted)")
        default:      logger.info("\(entry.formatted)")
        }
    }

    nonisolated func logLocation(_ msg: String) {
        Task { @MainActor in self.log(msg, category: .location) }
    }
    nonisolated func logMotion(_ msg: String) {
        Task { @MainActor in self.log(msg, category: .motion) }
    }
    nonisolated func logTrip(_ msg: String) {
        Task { @MainActor in self.log(msg, category: .trip) }
    }
    nonisolated func logError(_ msg: String) {
        Task { @MainActor in self.log(msg, category: .error) }
    }

    /// Clear the log file, entries cache, and in-memory buffer
    func clearLogs() {
        entries.removeAll()
        try? FileManager.default.removeItem(at: textLogURL)
        try? FileManager.default.removeItem(at: entriesCacheURL)
        log("Logs cleared by user", category: .system)
    }

    /// URL to the human-readable log file for sharing via ShareSheet
    var exportURL: URL { textLogURL }

    /// Raw contents of the log file (for preview in debug view)
    func fileContents() -> String {
        (try? String(contentsOf: textLogURL, encoding: .utf8)) ?? "No log file found."
    }

    // MARK: - Persistence

    private func loadPersistedEntries() {
        guard let data = try? Data(contentsOf: entriesCacheURL),
              let saved = try? JSONDecoder().decode([LogEntry].self, from: data)
        else { return }
        // Restore last N entries
        entries = Array(saved.suffix(maxEntries))
    }

    private func persistEntries() {
        let slice = entries.suffix(maxEntries)
        guard let data = try? JSONEncoder().encode(Array(slice)) else { return }
        try? data.write(to: entriesCacheURL, options: .atomic)
    }

    // MARK: - File operations

    private func appendToFile(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: textLogURL.path) {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: textLogURL.path),
               let size = attrs[.size] as? Int, size > maxFileBytes {
                rotateLog()
            }
            if let handle = try? FileHandle(forWritingTo: textLogURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: textLogURL, options: .atomic)
        }
    }

    private func rotateLog() {
        let dir = textLogURL.deletingLastPathComponent()
        let archive = dir.appendingPathComponent("TripLogs_\(Int(Date().timeIntervalSince1970)).txt")
        try? FileManager.default.moveItem(at: textLogURL, to: archive)
    }
}
