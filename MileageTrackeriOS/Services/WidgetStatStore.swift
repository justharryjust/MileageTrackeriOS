// WidgetStatStore — Writes weekly-trip snapshots to App Group UserDefaults for the widget to read.
// The widget reads these pre-computed values rather than opening Realm directly,
// keeping the widget lightweight and avoiding Realm dependency in the extension.

import Foundation

struct WidgetStats: Codable, Equatable {
    var weeklyDistanceKm: Double = 0
    var weeklyDollarValue: Double = 0
    var weeklyTripCount: Int = 0

    /// True when no trips have been recorded at all (fresh install).
    var isEmpty: Bool { weeklyTripCount == 0 && weeklyDistanceKm == 0 }
}

final class WidgetStatStore {
    static let shared = WidgetStatStore()

    private let defaults: UserDefaults?
    private let statsKey = "widget.weeklyStats"

    /// Internal init allows tests to inject a custom UserDefaults suite.
    /// Production callers should always use `WidgetStatStore.shared`.
    init(defaults: UserDefaults? = UserDefaults(suiteName: "group.com.harryjust.MileageTrackeriOS")) {
        self.defaults = defaults
    }

    /// Reads the latest widget stats from the shared container.
    func read() -> WidgetStats {
        guard let data = defaults?.data(forKey: statsKey) else { return WidgetStats() }
        return (try? JSONDecoder().decode(WidgetStats.self, from: data)) ?? WidgetStats()
    }

    /// Writes updated widget stats to the shared container.
    func write(_ stats: WidgetStats) {
        guard let data = try? JSONEncoder().encode(stats) else { return }
        defaults?.set(data, forKey: statsKey)
    }
}
