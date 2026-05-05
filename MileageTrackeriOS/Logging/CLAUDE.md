# Logging/

Single file: `TripLogger.swift`.

## TripLogger

`@MainActor final class TripLogger: ObservableObject` — singleton via `TripLogger.shared`.

---

## Log categories (`enum LogCategory`)

| Case | Emoji | Used by |
|------|-------|---------|
| `.system` | ⚙️ | `AppState`, `RealmProvider`, general lifecycle |
| `.location` | 📍 | `LocationManager` |
| `.motion` | 🏃 | `MotionManager` |
| `.trip` | 🚗 | `TripRecorder`, `TripRepository` |
| `.ui` | 📱 | Views (rarely) |
| `.error` | 🔴 | Any error path |

---

## API

| Method | Notes |
|--------|-------|
| `log(_:category:)` | Appends to in-memory buffer + writes to file + emits to unified logging (`os.Logger`) |
| `logLocation(_:)` | `nonisolated` — dispatches to `@MainActor`; convenience for managers off MainActor |
| `logMotion(_:)` | Same pattern |
| `logTrip(_:)` | Same pattern |
| `logError(_:)` | Same pattern |
| `clearLogs()` | Empties buffer array and truncates file |
| `exportURL` | Returns `Documents/TripLogs.txt` URL for `ShareSheet` |
| `fileContents()` | Raw string of current log file (debug preview) |

---

## Storage

- **In-memory buffer**: `@Published var entries: [LogEntry]` — capped at **5 000** entries (oldest removed when exceeded).
- **File**: `Documents/TripLogs.txt` — appended on every `log()` call.
- **Rolling**: file is moved to `TripLogs_archive_<timestamp>.txt` when it exceeds **20 MB**.

---

## Convention

Every significant event in every manager **must** be logged. Use the appropriate category so `DebugLogView` filtering is useful. Log at the point of action, not after. Error paths always use `.error` category.
