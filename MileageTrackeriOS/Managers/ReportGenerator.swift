// ReportGenerator — Builds tax-agent-ready CSV mileage expense reports.
// Supports standard-rate and logbook methods. Output is shareable via the system share sheet.

import Foundation

final class ReportGenerator {

    // MARK: - CSV Export

    /// Generates a CSV report for the given trips within a date range.
    /// Only business-category trips are included in the claim totals.
    /// Returns a temporary file URL ready for sharing.
    func exportCSV(
        trips: [Trip],
        calculator: MileageCalculator,
        profile: UserProfile,
        dateRange: (start: Date, end: Date),
        baseCumulativeKm: Double = 0
    ) -> URL {
        let sorted = trips
            .filter { $0.category == .business }
            .filter { $0.startedAt >= dateRange.start && $0.startedAt <= dateRange.end }
            .sorted { $0.startedAt < $1.startedAt }

        let unit = profile.distanceUnit.shortName

        var csv = "Mileage Expense Report\n"
        csv += "Jurisdiction: \(profile.jurisdiction.displayName)\n"
        csv += "Method: \(profile.claimMethod.displayName)\n"
        csv += "Period: \(format(dateRange.start)) – \(format(dateRange.end))\n"
        csv += "Generated: \(format(Date()))\n\n"

        // Column headers
        csv += "Date,Start Address,End Address,Distance (\(unit)),Rate (c/\(unit)),Value ($),Category,Business Use %,Notes\n"

        var cumulativeKm = baseCumulativeKm
        var totalValue = 0.0
        var totalDistance = 0.0

        for trip in sorted {
            let distanceKm = trip.distanceMetres / 1000
            let distance = profile.distanceUnit == .miles ? distanceKm * 0.621371 : distanceKm
            cumulativeKm += distanceKm
            let value = calculator.dollarValue(for: trip, profile: profile, cumulativeKm: cumulativeKm)
            totalValue += value
            totalDistance += distance

            let cRate = calculator.centsPerKm(at: cumulativeKm, profile: profile, fuelType: .petrol) ?? 0
            let bizPct = trip.businessUsePercent.map { String(format: "%.1f", $0 * 100) } ?? "—"
            let start = csvEscape(trip.startAddress)
            let end   = csvEscape(trip.endAddress)
            let notes = csvEscape(trip.notes ?? "")

            csv += "\(format(trip.startedAt)),\(start),\(end),\(String(format: "%.1f", distance)),\(String(format: "%.0f", cRate)),\(String(format: "%.2f", value)),\(trip.category.rawValue),\(bizPct),\(notes)\n"
        }

        // Summary rows
        csv += "\n"
        csv += "Summary\n"
        csv += "Total Trips,\(sorted.count)\n"
        csv += "Total Distance (\(unit)),\(String(format: "%.1f", totalDistance))\n"
        csv += "Total Value,$\(String(format: "%.2f", totalValue))\n"

        // Write to temp file
        let dir = FileManager.default.temporaryDirectory
        let filename = "MileageReport_\(sanitize(profile.jurisdiction.displayName))_\(format(dateRange.start, short: true)).csv"
        let url = dir.appendingPathComponent(filename)
        try? csv.write(to: url, atomically: true, encoding: .utf8)

        TripLogger.shared.log("CSV report generated: \(filename) — \(sorted.count) trips, $\(String(format: "%.2f", totalValue))", category: .trip)
        return url
    }

    // MARK: - Helpers

    private func format(_ date: Date, short: Bool = false) -> String {
        let f = DateFormatter()
        f.dateFormat = short ? "yyyyMMdd" : "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func csvEscape(_ str: String) -> String {
        if str.contains(",") || str.contains("\"") || str.contains("\n") {
            return "\"\(str.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return str
    }

    private func sanitize(_ str: String) -> String {
        str.replacingOccurrences(of: " ", with: "_")
    }
}
