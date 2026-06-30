// ReportGenerator — Builds tax-agent-ready CSV and PDF mileage expense reports.
// Supports standard-rate and logbook methods. Output is shareable via the system share sheet.

import Foundation
import UIKit

final class ReportGenerator {

    // MARK: - Shared Helpers

    private func sortedBusinessTrips(
        _ trips: [Trip],
        dateRange: (start: Date, end: Date)
    ) -> [Trip] {
        trips
            .filter { $0.category == .business }
            .filter { $0.startedAt >= dateRange.start && $0.startedAt <= dateRange.end }
            .sorted { $0.startedAt < $1.startedAt }
    }

    private func computeRunningTotals(
        trips: [Trip],
        calculator: MileageCalculator,
        profile: UserProfile,
        baseCumulativeKm: Double
    ) -> (cumulativeKm: Double, totalValue: Double, totalDistance: Double) {
        var cumulativeKm = baseCumulativeKm
        var totalValue = 0.0
        var totalDistance = 0.0
        for trip in trips {
            let distanceKm = trip.distanceMetres / 1000
            cumulativeKm += distanceKm
            let value = calculator.dollarValue(for: trip, profile: profile, cumulativeKm: cumulativeKm)
            totalValue += value
            let displayedDistance = profile.distanceUnit == .miles ? distanceKm * 0.621371 : distanceKm
            totalDistance += displayedDistance
        }
        return (cumulativeKm, totalValue, totalDistance)
    }

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
        let sorted = sortedBusinessTrips(trips, dateRange: dateRange)
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
        let totals = computeRunningTotals(trips: sorted, calculator: calculator, profile: profile, baseCumulativeKm: baseCumulativeKm)
        csv += "\n"
        csv += "Summary\n"
        csv += "Total Trips,\(sorted.count)\n"
        csv += "Total Distance (\(unit)),\(String(format: "%.1f", totals.totalDistance))\n"
        csv += "Total Value,$\(String(format: "%.2f", totals.totalValue))\n"

        // Write to temp file
        let dir = FileManager.default.temporaryDirectory
        let filename = "MileageReport_\(sanitize(profile.jurisdiction.displayName))_\(format(dateRange.start, short: true)).csv"
        let url = dir.appendingPathComponent(filename)
        try? csv.write(to: url, atomically: true, encoding: .utf8)

        TripLogger.shared.log("CSV report generated: \(filename) — \(sorted.count) trips, $\(String(format: "%.2f", totals.totalValue))", category: .trip)
        return url
    }

    // MARK: - PDF Export

    /// Generates a PDF logbook report for the given trips within a date range.
    /// Uses UIGraphicsPDFRenderer with a branded header, per-trip table, totals,
    /// and odometer summary for logbook method. Returns a temporary file URL ready for sharing.
    func exportPDF(
        trips: [Trip],
        calculator: MileageCalculator,
        profile: UserProfile,
        vehicles: [Vehicle],
        dateRange: (start: Date, end: Date),
        baseCumulativeKm: Double = 0
    ) -> URL {
        let sorted = sortedBusinessTrips(trips, dateRange: dateRange)
        let vehicleMap = Dictionary(uniqueKeysWithValues: vehicles.map { ($0.id, $0) })
        let unit = profile.distanceUnit.shortName
        let totals = computeRunningTotals(trips: sorted, calculator: calculator, profile: profile, baseCumulativeKm: baseCumulativeKm)

        // Page layout
        let pageWidth: CGFloat = 595.2   // A4
        let pageHeight: CGFloat = 841.8
        let margin: CGFloat = 40
        let headerBgHeight: CGFloat = 64

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight),
            format: {
                let fmt = UIGraphicsPDFRendererFormat()
                let info: [String: Any] = [
                    kCGPDFContextCreator as String: "MileageTrackeriOS",
                    kCGPDFContextTitle as String: "Mileage Expense Report",
                    kCGPDFContextSubject as String: "\(profile.jurisdiction.displayName) — \(formatter.string(from: dateRange.start)) to \(formatter.string(from: dateRange.end))"
                ]
                fmt.documentInfo = info
                return fmt
            }()
        )

        let filename = "MileageLogbook_\(sanitize(profile.jurisdiction.displayName))_\(format(dateRange.start, short: true)).pdf"
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent(filename)

        // Column definitions
        struct ColumnSpec {
            let label: String
            let width: CGFloat
            let alignment: NSTextAlignment
        }
        let colSpecs: [ColumnSpec] = [
            ColumnSpec(label: "Date", width: 60, alignment: .left),
            ColumnSpec(label: "Route", width: 145, alignment: .left),
            ColumnSpec(label: "Reg", width: 28, alignment: .center),
            ColumnSpec(label: unit, width: 35, alignment: .right),
            ColumnSpec(label: "c/\(unit)", width: 38, alignment: .right),
            ColumnSpec(label: "Value", width: 42, alignment: .right),
            ColumnSpec(label: "Biz%", width: 32, alignment: .right)
        ]
        let totalTableWidth = colSpecs.reduce(0) { $0 + $1.width }
        let leftEdge = margin

        let mtGreen = UIColor(red: 0.05, green: 0.37, blue: 0.21, alpha: 1.0)
        let lightGray = UIColor(white: 0.95, alpha: 1.0)
        let darkGray = UIColor.darkGray

        try? renderer.writePDF(to: url) { ctx in
            let pageRect = ctx.pdfContextBounds
            var y = margin

            // Helper: draw page background and branded header, returns Y after header
            func drawPageHeader(startY: CGFloat) -> CGFloat {
                UIColor.white.setFill()
                ctx.fill(pageRect)

                // Branded header bar
                mtGreen.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: pageWidth, height: headerBgHeight))

                let titleAttr: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 18),
                    .foregroundColor: UIColor.white
                ]
                ("Mileage Expense Report" as NSString).draw(at: CGPoint(x: margin, y: 18), withAttributes: titleAttr)

                return max(startY, headerBgHeight + 16)
            }

            // Helper: draw metadata section (jurisdiction, method, period, generated)
            func drawMeta(at y: CGFloat) -> CGFloat {
                let metaLines = [
                    "Jurisdiction: \(profile.jurisdiction.displayName)  |  Method: \(profile.claimMethod.displayName)",
                    "Period: \(formatter.string(from: dateRange.start)) – \(formatter.string(from: dateRange.end))",
                    "Generated: \(formatter.string(from: Date()))"
                ]
                var currentY = y
                for line in metaLines {
                    (line as NSString).draw(at: CGPoint(x: margin, y: currentY), withAttributes: [
                        .font: UIFont.systemFont(ofSize: 12),
                        .foregroundColor: darkGray
                    ])
                    currentY += 16
                }
                return currentY + 8
            }

            // Helper: draw table header row
            func drawTableHeader(at y: CGFloat) {
                mtGreen.setFill()
                ctx.fill(CGRect(x: leftEdge, y: y, width: totalTableWidth, height: 20))

                var xOff = leftEdge + 4
                for col in colSpecs {
                    let textRect = CGRect(x: xOff, y: y + 3, width: col.width - 4, height: 14)
                    (col.label as NSString).draw(in: textRect, withAttributes: [
                        .font: UIFont.boldSystemFont(ofSize: 9),
                        .foregroundColor: UIColor.white
                    ])
                    xOff += col.width
                }
            }

            // Helper: draw a single trip data row
            func drawTripRow(_ trip: Trip, index: Int, at y: CGFloat) -> CGFloat {
                let rowHeight: CGFloat = 14

                // Alternating row background
                if index % 2 == 1 {
                    lightGray.setFill()
                    ctx.fill(CGRect(x: leftEdge, y: y, width: totalTableWidth, height: rowHeight))
                }

                let distanceKm = trip.distanceMetres / 1000
                let displayDistance = profile.distanceUnit == .miles ? distanceKm * 0.621371 : distanceKm
                let cRate = calculator.centsPerKm(at: baseCumulativeKm + distanceKm, profile: profile, fuelType: .petrol) ?? 0
                let bizPct = trip.businessUsePercent.map { String(format: "%.1f%%", $0 * 100) } ?? "—"
                let value = calculator.dollarValue(for: trip, profile: profile, cumulativeKm: baseCumulativeKm + distanceKm)
                let vehicle = vehicleMap[trip.vehicleId]
                let reg = vehicle?.registration ?? "—"
                let route = "\(trip.startAddress) → \(trip.endAddress)"
                let dateStr = formatter.string(from: trip.startedAt)
                let valueStr = String(format: "$%.2f", value)
                let distStr = String(format: "%.1f", displayDistance)
                let rateStr = String(format: "%.0f", cRate)

                let cells: [(String, CGFloat, UIFont)] = [
                    (dateStr, 60, UIFont.systemFont(ofSize: 8)),
                    (route, 145, UIFont.systemFont(ofSize: 7.5)),
                    (reg, 28, UIFont.systemFont(ofSize: 8)),
                    (distStr, 35, UIFont.systemFont(ofSize: 8)),
                    (rateStr, 38, UIFont.systemFont(ofSize: 8)),
                    (valueStr, 42, UIFont.systemFont(ofSize: 8)),
                    (bizPct, 32, UIFont.systemFont(ofSize: 8))
                ]

                var xOff = leftEdge + 4
                for cell in cells {
                    let textRect = CGRect(x: xOff, y: y + 1, width: cell.1 - 4, height: rowHeight)
                    (cell.0 as NSString).draw(in: textRect, withAttributes: [
                        .font: cell.2,
                        .foregroundColor: darkGray
                    ])
                    xOff += cell.1
                }

                return y + rowHeight
            }

            // Helper: draw summary + odometer sections
            func drawSummary(at y: CGFloat) -> CGFloat {
                var currentY = y + 12
                let boldAttr: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 13),
                    .foregroundColor: UIColor.black
                ]
                ("Summary" as NSString).draw(at: CGPoint(x: margin, y: currentY), withAttributes: boldAttr)
                currentY += 20

                let summaryLines = [
                    "Total Trips:         \(sorted.count)",
                    "Total Distance (\(unit)):  \(String(format: "%.1f", totals.totalDistance))",
                    "Total Value:         $\(String(format: "%.2f", totals.totalValue))"
                ]
                for line in summaryLines {
                    (line as NSString).draw(at: CGPoint(x: margin, y: currentY), withAttributes: [
                        .font: UIFont.systemFont(ofSize: 11),
                        .foregroundColor: darkGray
                    ])
                    currentY += 16
                }

                // Odometer summary for logbook method
                if profile.claimMethod == .logbook {
                    currentY += 8
                    let logbookAttr: [NSAttributedString.Key: Any] = [
                        .font: UIFont.boldSystemFont(ofSize: 12),
                        .foregroundColor: UIColor.black
                    ]
                    ("Odometer Summary" as NSString).draw(at: CGPoint(x: margin, y: currentY), withAttributes: logbookAttr)
                    currentY += 18

                    let odometerLines = [
                        "Business use percentage is calculated from odometer readings.",
                        "See Odometer Log for complete reading history."
                    ]
                    for line in odometerLines {
                        (line as NSString).draw(at: CGPoint(x: margin, y: currentY), withAttributes: [
                            .font: UIFont.systemFont(ofSize: 9),
                            .foregroundColor: darkGray
                        ])
                        currentY += 13
                    }
                }

                // Footer
                currentY += 16
                let footerAttr: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 8),
                    .foregroundColor: UIColor.lightGray
                ]
                ("Generated by MileageTrackeriOS" as NSString).draw(at: CGPoint(x: margin, y: pageRect.maxY - 20), withAttributes: footerAttr)

                return currentY
            }

            // --- Page 1 ---
            ctx.beginPage()
            y = drawPageHeader(startY: margin)
            y = drawMeta(at: y)
            drawTableHeader(at: y)
            y += 20

            let rowHeight: CGFloat = 14
            let minFooterSpace: CGFloat = 80 // reserve space for summary + footer

            for (index, trip) in sorted.enumerated() {
                // Check if we need a new page for this row
                if y + rowHeight + minFooterSpace > pageRect.maxY {
                    // New page
                    ctx.beginPage()
                    y = drawPageHeader(startY: margin)
                    y = drawMeta(at: y)
                    drawTableHeader(at: y)
                    y += 20
                }
                y = drawTripRow(trip, index: index, at: y)
            }

            // Draw summary on the last page
            y = drawSummary(at: y)
        }

        TripLogger.shared.log("PDF report generated: \(filename) — \(sorted.count) trips, $\(String(format: "%.2f", totals.totalValue))", category: .trip)
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
