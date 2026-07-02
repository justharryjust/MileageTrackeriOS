import Testing
import CoreLocation
import CoreMotion
import RealmSwift
@testable import MileageTrackeriOS

@Suite("Tax Year Periods")
struct TaxYearTests {

    /// Helper to build a date from components.
    private func date(year: Int, month: Int, day: Int) -> Date {
        let cal = Calendar.current
        return cal.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    // MARK: New Zealand (1 Apr – 31 Mar)

    @Test("NZ: date in Apr–Dec returns current-year tax year starting 1 Apr")
    func nzDateInAprToDec() throws {
        let d = date(year: 2026, month: 6, day: 15)
        let period = Jurisdiction.newZealand.taxYear.containing(d)
        let expectedStart = date(year: 2026, month: 4, day: 1)
        let expectedEnd = date(year: 2027, month: 4, day: 1).addingTimeInterval(-1)
        #expect(period.start == expectedStart)
        #expect(period.end == expectedEnd)
    }

    @Test("NZ: date in Jan–Mar returns previous-year tax year starting 1 Apr")
    func nzDateInJanToMar() throws {
        let d = date(year: 2027, month: 2, day: 10)
        let period = Jurisdiction.newZealand.taxYear.containing(d)
        let expectedStart = date(year: 2026, month: 4, day: 1)
        let expectedEnd = date(year: 2027, month: 4, day: 1).addingTimeInterval(-1)
        #expect(period.start == expectedStart)
        #expect(period.end == expectedEnd)
    }

    // MARK: Australia (1 Jul – 30 Jun)

    @Test("AU: date in Jul–Dec returns current-year tax year starting 1 Jul")
    func auDateInJulToDec() throws {
        let d = date(year: 2026, month: 10, day: 1)
        let period = Jurisdiction.australia.taxYear.containing(d)
        let expectedStart = date(year: 2026, month: 7, day: 1)
        let expectedEnd = date(year: 2027, month: 7, day: 1).addingTimeInterval(-1)
        #expect(period.start == expectedStart)
        #expect(period.end == expectedEnd)
    }

    @Test("AU: date in Jan–Jun returns previous-year tax year starting 1 Jul")
    func auDateInJanToJun() throws {
        let d = date(year: 2027, month: 3, day: 15)
        let period = Jurisdiction.australia.taxYear.containing(d)
        let expectedStart = date(year: 2026, month: 7, day: 1)
        let expectedEnd = date(year: 2027, month: 7, day: 1).addingTimeInterval(-1)
        #expect(period.start == expectedStart)
        #expect(period.end == expectedEnd)
    }

    // MARK: UK (6 Apr – 5 Apr) via .other

    @Test("UK: date in Apr–Dec returns current-year tax year starting 6 Apr")
    func ukDateInAprToDec() throws {
        let d = date(year: 2026, month: 8, day: 20)
        let period = Jurisdiction.other.taxYear.containing(d)
        let expectedStart = date(year: 2026, month: 4, day: 6)
        let expectedEnd = date(year: 2027, month: 4, day: 6).addingTimeInterval(-1)
        #expect(period.start == expectedStart)
        #expect(period.end == expectedEnd)
    }

    @Test("UK: date 1 Jan–5 Apr returns previous-year tax year starting 6 Apr")
    func ukDateInJanToApr5() throws {
        let d = date(year: 2027, month: 1, day: 1)
        let period = Jurisdiction.other.taxYear.containing(d)
        let expectedStart = date(year: 2026, month: 4, day: 6)
        let expectedEnd = date(year: 2027, month: 4, day: 6).addingTimeInterval(-1)
        #expect(period.start == expectedStart)
        #expect(period.end == expectedEnd)
    }

    // MARK: Edge cases — boundary dates

    @Test("NZ: 1 Apr exactly is start of tax year")
    func nzBoundaryStart() throws {
        let d = date(year: 2026, month: 4, day: 1)
        let period = Jurisdiction.newZealand.taxYear.containing(d)
        #expect(period.start == d)
    }

    @Test("NZ: 31 Mar is end of tax year (not start of next)")
    func nzBoundaryEnd() throws {
        let d = date(year: 2027, month: 3, day: 31)
        let period = Jurisdiction.newZealand.taxYear.containing(d)
        let expectedStart = date(year: 2026, month: 4, day: 1)
        let expectedEnd = date(year: 2027, month: 4, day: 1).addingTimeInterval(-1)
        #expect(period.start == expectedStart)
        #expect(period.end == expectedEnd)
    }

    @Test("AU: 1 Jul exactly is start of tax year")
    func auBoundaryStart() throws {
        let d = date(year: 2026, month: 7, day: 1)
        let period = Jurisdiction.australia.taxYear.containing(d)
        #expect(period.start == d)
    }

    @Test("UK: 6 Apr exactly is start of tax year")
    func ukBoundaryStart() throws {
        let d = date(year: 2026, month: 4, day: 6)
        let period = Jurisdiction.other.taxYear.containing(d)
        #expect(period.start == d)
    }
}


// MARK:   Suite 12 — DrivingDistanceResult + Haversine
// MARK: ═══════════════════════════════════════════════════

