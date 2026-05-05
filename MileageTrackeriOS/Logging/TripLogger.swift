// TripLogger — Persistent, exportable debug logging
// Writes timestamped entries to Documents/TripLogs.txt
// Categories colour-code log output and let you grep easily in exports

import Foundation
import Combine
import OSLog

// MARK: - Log Category

enum LogCategory: String {
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

struct LogEntry: Identifiable {
    let id    = UUID()
    let date  : Date
    let category: LogCategory
    let message : String

    var formatted: String {
        let ts = TripLogger.timestampFormatter.string(from: date)
        return "\(ts) \(category.emoji)[\(category.rawValue)] \(message)"
    }
}

// MARK: - TripLogger

@MainActor
final class TripLogger: ObservableObject {
    static let shared = TripLogger()

    // In-memory ring buffer for the debug view (keep last 500)
    @Published private(set) var entries: [LogEntry] = []

    private let fileURL: URL
    private let maxFileBytes = 20 * 1024 * 1024  // 5 MB rolling cap
    private let logger = Logger(subsystem: "com.harryjust.MileageTrackeriOS", category: "TripLogger")

    static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("TripLogs.txt")
        // Write session separator on launch
        appendToFile("──────────────────────────────────────────\n")
        appendToFile("Session started: \(Date())\n")
        appendToFile("──────────────────────────────────────────\n")
    }

    // MARK: - Public API

    func log(_ message: String, category: LogCategory = .system, file: String = #file, line: Int = #line) {
        let entry = LogEntry(date: Date(), category: category, message: message)
        // Append to in-memory buffer (ring)
        entries.append(entry)
        if entries.count > 5000 { entries.removeFirst(entries.count - 5000) }
        // Write to file
        appendToFile(entry.formatted + "\n")
        // Also emit to unified logging (visible in Console.app)
        switch category {
        case .error:  logger.error("\(entry.formatted)")
        default:      logger.info("\(entry.formatted)")
        }
    }

    // Convenience typed helpers
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

    // MARK: - File operations

    /// Clear the log file and in-memory buffer
    func clearLogs() {
        entries.removeAll()
        try? "".write(to: fileURL, atomically: true, encoding: .utf8)
        log("Logs cleared by user", category: .system)
    }

    /// URL to the log file for sharing via ShareSheet
    var exportURL: URL { fileURL }

    /// Raw contents of the log file (for preview in debug view)
    func fileContents() -> String {
        (try? String(contentsOf: fileURL, encoding: .utf8)) ?? "No log file found."
    }

    // MARK: - Private

    private func appendToFile(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            // Roll file if too large
            if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
               let size = attrs[.size] as? Int, size > maxFileBytes {
                rotateLog()
            }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func rotateLog() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let archive = docs.appendingPathComponent("TripLogs_archive_\(Int(Date().timeIntervalSince1970)).txt")
        try? FileManager.default.moveItem(at: fileURL, to: archive)
        appendToFile("Log rotated. Previous log archived.\n")
    }
}
