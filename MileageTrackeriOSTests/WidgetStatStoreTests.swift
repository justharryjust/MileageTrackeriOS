import Testing
import Foundation
import RealmSwift
@testable import MileageTrackeriOS

@Suite("WidgetStatStore")
struct WidgetStatStoreTests {

    // MARK: - WidgetStats (value type)

    @Test("WidgetStats isEmpty is true when all values are zero")
    func isEmptyWhenZero() {
        let stats = WidgetStats()
        #expect(stats.isEmpty)
    }

    @Test("WidgetStats isEmpty is false when weeklyDistanceKm is non-zero")
    func notEmptyWhenDistanceNonZero() {
        var stats = WidgetStats()
        stats.weeklyDistanceKm = 10
        #expect(!stats.isEmpty)
    }

    @Test("WidgetStats isEmpty is false when weeklyTripCount is non-zero")
    func notEmptyWhenTripCountNonZero() {
        var stats = WidgetStats()
        stats.weeklyTripCount = 1
        #expect(!stats.isEmpty)
    }

    @Test("WidgetStats Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let original = WidgetStats(
            weeklyDistanceKm: 123.45,
            weeklyDollarValue: 67.89,
            weeklyTripCount: 5
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WidgetStats.self, from: data)

        #expect(decoded.weeklyDistanceKm == 123.45)
        #expect(decoded.weeklyDollarValue == 67.89)
        #expect(decoded.weeklyTripCount == 5)
    }

    @Test("WidgetStats Codable round-trip preserves empty state")
    func codableEmptyRoundTrip() throws {
        let original = WidgetStats()

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WidgetStats.self, from: data)

        #expect(decoded.isEmpty)
        #expect(decoded.weeklyDistanceKm == 0)
        #expect(decoded.weeklyDollarValue == 0)
        #expect(decoded.weeklyTripCount == 0)
    }

    // MARK: - WidgetStatStore

    @Test("WidgetStatStore read returns empty WidgetStats when nothing written")
    func readEmpty() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = WidgetStatStore(defaults: defaults)

        let stats = store.read()

        #expect(stats.isEmpty)
    }

    @Test("WidgetStatStore write/read cycle round-trips data")
    func writeReadCycle() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = WidgetStatStore(defaults: defaults)

        let stats = WidgetStats(
            weeklyDistanceKm: 50.0,
            weeklyDollarValue: 25.0,
            weeklyTripCount: 3
        )
        store.write(stats)

        let read = store.read()
        #expect(read.weeklyDistanceKm == 50.0)
        #expect(read.weeklyDollarValue == 25.0)
        #expect(read.weeklyTripCount == 3)
    }

    @Test("WidgetStatStore overwrite replaces previous data")
    func overwrite() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = WidgetStatStore(defaults: defaults)

        let first = WidgetStats(weeklyDistanceKm: 10, weeklyDollarValue: 5, weeklyTripCount: 1)
        store.write(first)

        let second = WidgetStats(weeklyDistanceKm: 99, weeklyDollarValue: 50, weeklyTripCount: 10)
        store.write(second)

        let read = store.read()
        #expect(read.weeklyDistanceKm == 99)
        #expect(read.weeklyDollarValue == 50)
        #expect(read.weeklyTripCount == 10)
    }

    @Test("WidgetStatStore empty-state read returns fresh WidgetStats")
    func emptyState() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = WidgetStatStore(defaults: defaults)

        // Read before any write
        let stats = store.read()
        #expect(stats.weeklyDistanceKm == 0)
        #expect(stats.weeklyDollarValue == 0)
        #expect(stats.weeklyTripCount == 0)
        #expect(stats.isEmpty)
    }
}
