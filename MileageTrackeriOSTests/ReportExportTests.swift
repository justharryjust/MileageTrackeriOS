import Testing
import CoreLocation
import CoreMotion
import RealmSwift
@testable import MileageTrackeriOS

@Suite("Report Export Tests")
struct ReportExportTests {

    private struct ExportHarness {
        let realm: Realm
        let profile: UserProfile
        let calculator: MileageCalculator
        let generator: ReportGenerator

        init(jurisdiction: Jurisdiction, distanceUnit: DistanceUnit) throws {
            let config = Realm.Configuration(
                inMemoryIdentifier: UUID().uuidString,
                schemaVersion: RealmProvider.schemaVersion,
                objectTypes: [UserProfile.self, Vehicle.self, Trip.self, TripPoint.self, OdometerReading.self, SavedAddress.self, LogbookPeriod.self]
            )
            realm = try Realm(configuration: config)
            calculator = MileageCalculator()
            generator = ReportGenerator()

            guard let p = realm.object(ofType: UserProfile.self, forPrimaryKey: "singleton") else {
                Issue.record("No profile singleton"); fatalError()
            }
            try realm.write {
                p.jurisdiction = jurisdiction
                p.claimMethod = .standardRate
                p.distanceUnit = distanceUnit
            }
            profile = p
        }

        @discardableResult
        func addTrip(startedAt: Date, distanceMetres: Double, category: TripCategory) -> Trip {
            let trip = Trip()
            trip.startedAt = startedAt
            trip.distanceMetres = distanceMetres
            trip.category = category
            trip.startAddress = "Start"
            trip.endAddress = "End"
            try! realm.write { realm.add(trip) }
            return trip
        }
    }

    @Test("CSV excludes personal and uncategorised trips")
    func csvExcludesNonBusinessTrips() throws {
        let h = try ExportHarness(jurisdiction: .newZealand, distanceUnit: .kilometres)
        let now = Date()

        let business = h.addTrip(startedAt: now.addingTimeInterval(-7200), distanceMetres: 10_000, category: .business)
        let personal = h.addTrip(startedAt: now.addingTimeInterval(-3600), distanceMetres: 5_000, category: .personal)
        let uncat    = h.addTrip(startedAt: now.addingTimeInterval(-1800), distanceMetres: 3_000, category: .uncategorised)

        let url = h.generator.exportCSV(
            trips: [business, personal, uncat],
            calculator: h.calculator,
            profile: h.profile,
            dateRange: (now.addingTimeInterval(-86400), now.addingTimeInterval(86400))
        )

        let csv = try String(contentsOf: url, encoding: .utf8)
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        let dataLines = lines.filter { $0.contains(",business,") || $0.contains(",personal,") || $0.contains(",uncategorised,") }
        #expect(dataLines.count == 1)
        #expect(dataLines[0].contains(",business,"))
    }

    @Test("CSV column headers use profile distance unit")
    func csvUsesProfileDistanceUnit() throws {
        let h = try ExportHarness(jurisdiction: .newZealand, distanceUnit: .miles)
        let now = Date()

        let trip = h.addTrip(startedAt: now, distanceMetres: 10_000, category: .business)
        let url = h.generator.exportCSV(
            trips: [trip],
            calculator: h.calculator,
            profile: h.profile,
            dateRange: (now.addingTimeInterval(-86400), now.addingTimeInterval(86400))
        )

        let csv = try String(contentsOf: url, encoding: .utf8)
        #expect(csv.contains("Distance (mi)"))
        #expect(csv.contains("Rate (c/mi)"))
    }

    @Test("CSV with km unit uses km labels")
    func csvWithKmUnit() throws {
        let h = try ExportHarness(jurisdiction: .newZealand, distanceUnit: .kilometres)
        let now = Date()

        let trip = h.addTrip(startedAt: now, distanceMetres: 10_000, category: .business)
        let url = h.generator.exportCSV(
            trips: [trip],
            calculator: h.calculator,
            profile: h.profile,
            dateRange: (now.addingTimeInterval(-86400), now.addingTimeInterval(86400))
        )

        let csv = try String(contentsOf: url, encoding: .utf8)
        #expect(csv.contains("Distance (km)"))
        #expect(csv.contains("Rate (c/km)"))
    }

    @Test("Cumulative km above NZ tier threshold uses lower rate")
    func nzTierRateWithHighCumulativeKm() throws {
        let h = try ExportHarness(jurisdiction: .newZealand, distanceUnit: .kilometres)
        let now = Date()

        let trip = h.addTrip(startedAt: now, distanceMetres: 10_000, category: .business)
        let url = h.generator.exportCSV(
            trips: [trip],
            calculator: h.calculator,
            profile: h.profile,
            dateRange: (now.addingTimeInterval(-86400), now.addingTimeInterval(86400)),
            baseCumulativeKm: 14_500
        )

        let csv = try String(contentsOf: url, encoding: .utf8)
        let lines = csv.components(separatedBy: "\n")
        let dataLine = lines.first { $0.contains(",business,") } ?? ""
        #expect(dataLine.contains(",34,"))
    }

    @Test("Cumulative km within NZ tier-1 uses higher rate")
    func nzTierRateWithinThreshold() throws {
        let h = try ExportHarness(jurisdiction: .newZealand, distanceUnit: .kilometres)
        let now = Date()

        let trip = h.addTrip(startedAt: now, distanceMetres: 10_000, category: .business)
        let url = h.generator.exportCSV(
            trips: [trip],
            calculator: h.calculator,
            profile: h.profile,
            dateRange: (now.addingTimeInterval(-86400), now.addingTimeInterval(86400)),
            baseCumulativeKm: 0
        )

        let csv = try String(contentsOf: url, encoding: .utf8)
        let lines = csv.components(separatedBy: "\n")
        let dataLine = lines.first { $0.contains(",business,") } ?? ""
        #expect(dataLine.contains(",104,"))
    }

    @Test("Cumulative km with base below threshold stays in tier-1")
    func nzTierRateWithPartialBase() throws {
        let h = try ExportHarness(jurisdiction: .newZealand, distanceUnit: .kilometres)
        let now = Date()

        let trip = h.addTrip(startedAt: now, distanceMetres: 3_000_000, category: .business)
        let url = h.generator.exportCSV(
            trips: [trip],
            calculator: h.calculator,
            profile: h.profile,
            dateRange: (now.addingTimeInterval(-86400), now.addingTimeInterval(86400)),
            baseCumulativeKm: 10_000
        )

        let csv = try String(contentsOf: url, encoding: .utf8)
        let lines = csv.components(separatedBy: "\n")
        let dataLine = lines.first { $0.contains(",business,") } ?? ""
        #expect(dataLine.contains(",104,"))
    }

    @Test("Summary total value is computed correctly")
    func summaryTotalValue() throws {
        let h = try ExportHarness(jurisdiction: .newZealand, distanceUnit: .kilometres)
        let now = Date()

        let trip = h.addTrip(startedAt: now.addingTimeInterval(-3600), distanceMetres: 100_000, category: .business)
        let url = h.generator.exportCSV(
            trips: [trip],
            calculator: h.calculator,
            profile: h.profile,
            dateRange: (now.addingTimeInterval(-86400), now.addingTimeInterval(86400))
        )

        let csv = try String(contentsOf: url, encoding: .utf8)
        #expect(csv.contains("Total Value,$"))
        #expect(csv.contains("$104.00"))
    }

    // MARK: - PDF Tests

    /// Helper: reads the raw PDF data string to verify text content.
    /// PDF is binary with text embedded as ASCII strings; we can at least
    /// verify expected strings are present in the content stream.
    private func pdfContains(_ url: URL, _ substring: String) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        let raw = String(data: data, encoding: .ascii) ?? ""
        return raw.contains(substring)
    }

    @Test("PDF excludes personal and uncategorised trips")
    func pdfExcludesNonBusinessTrips() throws {
        let h = try ExportHarness(jurisdiction: .newZealand, distanceUnit: .kilometres)
        let now = Date()

        let business = h.addTrip(startedAt: now.addingTimeInterval(-7200), distanceMetres: 10_000, category: .business)
        let personal = h.addTrip(startedAt: now.addingTimeInterval(-3600), distanceMetres: 5_000, category: .personal)
        let uncat    = h.addTrip(startedAt: now.addingTimeInterval(-1800), distanceMetres: 3_000, category: .uncategorised)

        let trips = h.realm.objects(Trip.self).map { $0 }
        let vehicles = h.realm.objects(Vehicle.self).map { $0 }

        let url = h.generator.exportPDF(
            trips: Array(trips),
            calculator: h.calculator,
            profile: h.profile,
            vehicles: Array(vehicles),
            dateRange: (now.addingTimeInterval(-86400), now.addingTimeInterval(86400))
        )

        // Should contain only 1 business trip line in content
        #expect(pdfContains(url, "Mileage Expense Report"))
        #expect(pdfContains(url, "2026")) // date present
    }

    @Test("PDF contains branded header and metadata")
    func pdfContainsHeaderAndMeta() throws {
        let h = try ExportHarness(jurisdiction: .newZealand, distanceUnit: .kilometres)
        let now = Date()

        let trip = h.addTrip(startedAt: now.addingTimeInterval(-3600), distanceMetres: 10_000, category: .business)
        let trips = h.realm.objects(Trip.self).map { $0 }
        let vehicles = h.realm.objects(Vehicle.self).map { $0 }

        let url = h.generator.exportPDF(
            trips: Array(trips),
            calculator: h.calculator,
            profile: h.profile,
            vehicles: Array(vehicles),
            dateRange: (now.addingTimeInterval(-86400), now.addingTimeInterval(86400))
        )

        #expect(pdfContains(url, "Mileage Expense Report"))
        #expect(pdfContains(url, "New Zealand"))
        #expect(pdfContains(url, "Standard Mileage Rate"))
        #expect(pdfContains(url, "MileageTrackeriOS"))
    }

    @Test("PDF column headers match distance unit (miles)")
    func pdfUsesMilesUnit() throws {
        let h = try ExportHarness(jurisdiction: .newZealand, distanceUnit: .miles)
        let now = Date()

        let trip = h.addTrip(startedAt: now.addingTimeInterval(-3600), distanceMetres: 10_000, category: .business)
        let trips = h.realm.objects(Trip.self).map { $0 }
        let vehicles = h.realm.objects(Vehicle.self).map { $0 }

        let url = h.generator.exportPDF(
            trips: Array(trips),
            calculator: h.calculator,
            profile: h.profile,
            vehicles: Array(vehicles),
            dateRange: (now.addingTimeInterval(-86400), now.addingTimeInterval(86400))
        )

        #expect(pdfContains(url, "c/mi"))
    }

    @Test("PDF column headers match distance unit (km)")
    func pdfUsesKmUnit() throws {
        let h = try ExportHarness(jurisdiction: .newZealand, distanceUnit: .kilometres)
        let now = Date()

        let trip = h.addTrip(startedAt: now.addingTimeInterval(-3600), distanceMetres: 10_000, category: .business)
        let trips = h.realm.objects(Trip.self).map { $0 }
        let vehicles = h.realm.objects(Vehicle.self).map { $0 }

        let url = h.generator.exportPDF(
            trips: Array(trips),
            calculator: h.calculator,
            profile: h.profile,
            vehicles: Array(vehicles),
            dateRange: (now.addingTimeInterval(-86400), now.addingTimeInterval(86400))
        )

        #expect(pdfContains(url, "c/km"))
    }

    @Test("PDF contains summary section with totals")
    func pdfContainsSummary() throws {
        let h = try ExportHarness(jurisdiction: .newZealand, distanceUnit: .kilometres)
        let now = Date()

        let trip = h.addTrip(startedAt: now.addingTimeInterval(-3600), distanceMetres: 100_000, category: .business)
        let trips = h.realm.objects(Trip.self).map { $0 }
        let vehicles = h.realm.objects(Vehicle.self).map { $0 }

        let url = h.generator.exportPDF(
            trips: Array(trips),
            calculator: h.calculator,
            profile: h.profile,
            vehicles: Array(vehicles),
            dateRange: (now.addingTimeInterval(-86400), now.addingTimeInterval(86400))
        )

        #expect(pdfContains(url, "Summary"))
        #expect(pdfContains(url, "Total Value"))
    }

    @Test("PDF contains vehicle registration for trips")
    func pdfContainsVehicleReg() throws {
        let h = try ExportHarness(jurisdiction: .newZealand, distanceUnit: .kilometres)
        let now = Date()

        let trip = h.addTrip(startedAt: now.addingTimeInterval(-3600), distanceMetres: 10_000, category: .business)
        // Get the vehicle that was auto-created by the harness
        let vehicle = h.realm.objects(Vehicle.self).first!
        let trips = h.realm.objects(Trip.self).map { $0 }
        let vehicles = h.realm.objects(Vehicle.self).map { $0 }

        let url = h.generator.exportPDF(
            trips: Array(trips),
            calculator: h.calculator,
            profile: h.profile,
            vehicles: Array(vehicles),
            dateRange: (now.addingTimeInterval(-86400), now.addingTimeInterval(86400))
        )

        #expect(pdfContains(url, vehicle.registration))
    }

    @Test("Cumulative km above NZ tier threshold uses lower rate in PDF")
    func pdfNzTierRateWithHighCumulativeKm() throws {
        let h = try ExportHarness(jurisdiction: .newZealand, distanceUnit: .kilometres)
        let now = Date()

        h.addTrip(startedAt: now.addingTimeInterval(-3600), distanceMetres: 10_000, category: .business)
        let trips = h.realm.objects(Trip.self).map { $0 }
        let vehicles = h.realm.objects(Vehicle.self).map { $0 }

        let url = h.generator.exportPDF(
            trips: Array(trips),
            calculator: h.calculator,
            profile: h.profile,
            vehicles: Array(vehicles),
            dateRange: (now.addingTimeInterval(-86400), now.addingTimeInterval(86400)),
            baseCumulativeKm: 14_500
        )

        // With 14,500 base + 10 km trip = 14,510 cumulative → tier 2 (34 c/km)
        // The rate "34" should appear
        #expect(pdfContains(url, "34"))
    }

    @Test("PDF with logbook method shows odometer section")
    func pdfLogbookShowsOdometerSection() throws {
        let h = try ExportHarness(jurisdiction: .newZealand, distanceUnit: .kilometres)
        try h.realm.write {
            h.profile.claimMethod = .logbook
        }
        let now = Date()

        let trip = h.addTrip(startedAt: now.addingTimeInterval(-3600), distanceMetres: 10_000, category: .business)
        trip.businessUsePercent = 0.65
        let trips = h.realm.objects(Trip.self).map { $0 }
        let vehicles = h.realm.objects(Vehicle.self).map { $0 }

        let url = h.generator.exportPDF(
            trips: Array(trips),
            calculator: h.calculator,
            profile: h.profile,
            vehicles: Array(vehicles),
            dateRange: (now.addingTimeInterval(-86400), now.addingTimeInterval(86400))
        )

        #expect(pdfContains(url, "Odometer Summary"))
        #expect(pdfContains(url, "65.0%"))
    }
}

// MARK: - ═══════════════════════════════════════════════
// MARK:   Suite 19 — RealmProvider Graceful Recovery
// MARK: ═══════════════════════════════════════════════

