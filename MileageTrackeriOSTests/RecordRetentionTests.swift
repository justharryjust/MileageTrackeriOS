import Testing
import Foundation
@testable import MileageTrackeriOS

@Suite("Record Retention Periods")
struct RecordRetentionTests {

    /// Helper to build a date from components.
    private func date(year: Int, month: Int, day: Int) -> Date {
        let cal = Calendar.current
        return cal.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    // MARK: - Retention Years (AC: US 3; ES 4; AU/GB/NO/DK/ZA 5; CA/FI 6; NZ/AT/SE/BE/NL 7; DE/CH 10)

    @Test("US returns 3 years")
    func usRetentionYears() {
        #expect(Jurisdiction.unitedStates.recordRetentionYears == 3)
    }

    @Test("ES returns 4 years")
    func esRetentionYears() {
        #expect(Jurisdiction.spain.recordRetentionYears == 4)
    }

    @Test("AU returns 5 years")
    func auRetentionYears() {
        #expect(Jurisdiction.australia.recordRetentionYears == 5)
    }

    @Test("GB (other) returns 5 years")
    func gbRetentionYears() {
        #expect(Jurisdiction.other.recordRetentionYears == 5)
    }

    @Test("NO returns 5 years")
    func noRetentionYears() {
        #expect(Jurisdiction.norway.recordRetentionYears == 5)
    }

    @Test("DK returns 5 years")
    func dkRetentionYears() {
        #expect(Jurisdiction.denmark.recordRetentionYears == 5)
    }

    @Test("ZA returns 5 years")
    func zaRetentionYears() {
        #expect(Jurisdiction.southAfrica.recordRetentionYears == 5)
    }

    @Test("CA returns 6 years")
    func caRetentionYears() {
        #expect(Jurisdiction.canada.recordRetentionYears == 6)
    }

    @Test("FI returns 6 years")
    func fiRetentionYears() {
        #expect(Jurisdiction.finland.recordRetentionYears == 6)
    }

    @Test("NZ returns 7 years")
    func nzRetentionYears() {
        #expect(Jurisdiction.newZealand.recordRetentionYears == 7)
    }

    @Test("AT returns 7 years")
    func atRetentionYears() {
        #expect(Jurisdiction.austria.recordRetentionYears == 7)
    }

    @Test("SE returns 7 years")
    func seRetentionYears() {
        #expect(Jurisdiction.sweden.recordRetentionYears == 7)
    }

    @Test("BE returns 7 years")
    func beRetentionYears() {
        #expect(Jurisdiction.belgium.recordRetentionYears == 7)
    }

    @Test("NL returns 7 years")
    func nlRetentionYears() {
        #expect(Jurisdiction.netherlands.recordRetentionYears == 7)
    }

    @Test("DE returns 10 years")
    func deRetentionYears() {
        #expect(Jurisdiction.germany.recordRetentionYears == 10)
    }

    @Test("CH returns 10 years")
    func chRetentionYears() {
        #expect(Jurisdiction.switzerland.recordRetentionYears == 10)
    }

    // MARK: - Retention End Date

    @Test("US retention date is ~3 years from tax year end")
    func usRetentionDate() {
        let (_, taxYearEnd) = Jurisdiction.unitedStates.taxYear.containing(Date())
        let expected = Calendar.current.date(byAdding: .year, value: 3, to: taxYearEnd)!
        // Allow 1 day tolerance for time-of-day differences
        let diff = abs(Jurisdiction.unitedStates.retentionEndDate.timeIntervalSince(expected))
        #expect(diff < 86400)
    }
}
