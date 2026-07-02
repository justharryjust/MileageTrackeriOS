// WeeklyStatsWidget — Home-screen widget showing this week's business trip summary.
// Reads pre-computed stats from App Group UserDefaults (written by WidgetStatStore
// in the main app after every trip-data change).

import SwiftUI
import WidgetKit

// MARK: - WidgetStats (duplicated from the main app to avoid a shared framework)

struct WidgetStats: Codable, Equatable {
    var weeklyDistanceKm: Double = 0
    var weeklyDollarValue: Double = 0
    var weeklyTripCount: Int = 0

    var isEmpty: Bool { weeklyTripCount == 0 && weeklyDistanceKm == 0 }
}

// MARK: - Timeline Provider

struct WeeklyStatsProvider: TimelineProvider {
    typealias Entry = WeeklyStatsEntry

    func placeholder(in context: Context) -> WeeklyStatsEntry {
        WeeklyStatsEntry(date: Date(), stats: WidgetStats(weeklyDistanceKm: 0, weeklyDollarValue: 0, weeklyTripCount: 0))
    }

    func getSnapshot(in context: Context, completion: @escaping (WeeklyStatsEntry) -> Void) {
        let stats = WidgetStatStore.read()
        completion(WeeklyStatsEntry(date: Date(), stats: stats))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeeklyStatsEntry>) -> Void) {
        let stats = WidgetStatStore.read()
        let entry = WeeklyStatsEntry(date: Date(), stats: stats)
        // Refresh every 30 minutes so the widget stays reasonably current without
        // excessive recomputation. The main app also calls WidgetCenter.shared.reloadAllTimelines
        // after trip saves to push updates immediately.
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Entry

struct WeeklyStatsEntry: TimelineEntry {
    let date: Date
    let stats: WidgetStats
}

// MARK: - WidgetStatStore (widget-side reader)

/// Minimal copy of the main app's WidgetStatStore — reads-only, no Realm dependency.
/// Uses the same App Group suite name so both processes share the same UserDefaults.
private enum WidgetStatStore {
    private static let defaults = UserDefaults(suiteName: "group.com.harryjust.MileageTrackeriOS")
    private static let statsKey = "widget.weeklyStats"

    static func read() -> WidgetStats {
        guard let data = defaults?.data(forKey: statsKey) else { return WidgetStats() }
        return (try? JSONDecoder().decode(WidgetStats.self, from: data)) ?? WidgetStats()
    }
}

// MARK: - Entry View

struct WeeklyStatsWidgetEntryView: View {
    var entry: WeeklyStatsProvider.Entry

    var body: some View {
        VStack(spacing: 8) {
            Text("This Week")
                .font(.caption)
                .foregroundStyle(.secondary)

            if entry.stats.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "figure.walk")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No trips yet")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.0f", entry.stats.weeklyDistanceKm))
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                    Text("km")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Label {
                        Text(String(format: "$%.0f", entry.stats.weeklyDollarValue))
                            .font(.caption)
                    } icon: {
                        Image(systemName: "dollarsign.circle.fill")
                            .foregroundStyle(.green)
                    }

                    Label {
                        Text("\(entry.stats.weeklyTripCount)")
                            .font(.caption)
                    } icon: {
                        Image(systemName: "car.fill")
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
        .containerBackground(.background, for: .widget)
    }
}

// MARK: - Widget Configuration

struct WeeklyStatsWidget: Widget {
    let kind = "WeeklyStatsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeeklyStatsProvider()) { entry in
            WeeklyStatsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Weekly Stats")
        .description("Shows your business trip distance, value, and count for the current week.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
