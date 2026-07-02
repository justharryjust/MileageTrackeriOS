import Testing
import Foundation
import RealmSwift
@testable import MileageTrackeriOS

@Suite("Logbook Regime Model")
struct LogbookRegimeTests {

    // MARK: - logbookRegime property

    @Test("New Zealand is sample-period")
    func newZealandSamplePeriod() {
        #expect(Jurisdiction.newZealand.logbookRegime == .samplePeriod)
    }

    @Test("Australia is sample-period")
    func australiaSamplePeriod() {
        #expect(Jurisdiction.australia.logbookRegime == .samplePeriod)
    }

    @Test("Canada is sample-period")
    func canadaSamplePeriod() {
        #expect(Jurisdiction.canada.logbookRegime == .samplePeriod)
    }

    @Test("United States is continuous")
    func unitedStatesContinuous() {
        #expect(Jurisdiction.unitedStates.logbookRegime == .continuous)
    }

    @Test("Germany is continuous")
    func germanyContinuous() {
        #expect(Jurisdiction.germany.logbookRegime == .continuous)
    }

    @Test("All non-sample jurisdictions are continuous")
    func allOtherJurisdictionsContinuous() {
        let samplePeriods: Set<Jurisdiction> = [.newZealand, .australia, .canada]
        for j in Jurisdiction.allCases where !samplePeriods.contains(j) {
            #expect(j.logbookRegime == .continuous, "\(j) should be continuous")
        }
    }

    @Test("Sample-period regimes retain correct logbookPeriodDays")
    func samplePeriodDays() {
        #expect(Jurisdiction.newZealand.logbookPeriodDays == 90)
        #expect(Jurisdiction.australia.logbookPeriodDays == 84)
        #expect(Jurisdiction.canada.logbookPeriodDays == 90)
    }

    @Test("Sample-period regimes retain correct logbookValidityYears")
    func samplePeriodValidity() {
        #expect(Jurisdiction.newZealand.logbookValidityYears == 3)
        #expect(Jurisdiction.australia.logbookValidityYears == 5)
        #expect(Jurisdiction.canada.logbookValidityYears == 3)
    }

    // MARK: - createPeriod with continuous regime

    @Test("createPeriod for continuous jurisdiction omits endedAt")
    func createPeriodContinuousOmitsEndDate() throws {
        // Given
        let realm = try inMemoryRealm()
        let repo = LogbookPeriodRepository(realm: realm)
        let jurisdiction = Jurisdiction.unitedStates

        // When
        let period = repo.createPeriod(vehicleId: "v1", jurisdiction: jurisdiction)

        // Then
        #expect(period.vehicleId == "v1")
        #expect(period.status == .active)
        #expect(period.endedAt == nil, "Continuous regime periods should not have an end date")
    }

    @Test("createPeriod for sample-period jurisdiction sets endedAt")
    func createPeriodSampleSetsEndDate() throws {
        // Given
        let realm = try inMemoryRealm()
        let repo = LogbookPeriodRepository(realm: realm)
        let jurisdiction = Jurisdiction.newZealand

        // When
        let period = repo.createPeriod(vehicleId: "v1", jurisdiction: jurisdiction)

        // Then
        #expect(period.vehicleId == "v1")
        #expect(period.status == .active)
        #expect(period.endedAt != nil, "Sample-period regime periods should have an end date")
        let expectedDays = jurisdiction.logbookPeriodDays
        let actualDays = Calendar.current.dateComponents([.day], from: period.startedAt, to: period.endedAt!).day
        #expect(actualDays == expectedDays)
    }

    // MARK: - completePeriod with continuous regime

    @Test("completePeriod for continuous jurisdiction omits validUntil")
    func completePeriodContinuousOmitsValidUntil() throws {
        // Given
        let realm = try inMemoryRealm()
        let repo = LogbookPeriodRepository(realm: realm)
        let calculator = MileageCalculator()
        let jurisdiction = Jurisdiction.germany
        let period = repo.createPeriod(vehicleId: "v1", jurisdiction: jurisdiction)

        // When
        repo.completePeriod(period, jurisdiction: jurisdiction, businessTrips: [], calculator: calculator)

        // Then
        #expect(period.status == .complete)
        #expect(period.completedAt != nil)
        #expect(period.validUntil == nil, "Continuous regime completed periods should not have validUntil")
    }

    @Test("completePeriod for sample-period jurisdiction sets validUntil")
    func completePeriodSampleSetsValidUntil() throws {
        // Given
        let realm = try inMemoryRealm()
        let repo = LogbookPeriodRepository(realm: realm)
        let calculator = MileageCalculator()
        let jurisdiction = Jurisdiction.newZealand
        let period = repo.createPeriod(vehicleId: "v1", jurisdiction: jurisdiction)

        // When
        repo.completePeriod(period, jurisdiction: jurisdiction, businessTrips: [], calculator: calculator)

        // Then
        #expect(period.status == .complete)
        #expect(period.completedAt != nil)
        #expect(period.validUntil != nil, "Sample-period regime completed periods should have validUntil")
        let expectedYears = jurisdiction.logbookValidityYears
        let actualYears = Calendar.current.dateComponents([.year], from: period.completedAt!, to: period.validUntil!).year
        #expect(actualYears == expectedYears)
    }

    // MARK: - autoCompleteExpiredPeriods

    @Test("autoCompleteExpiredPeriods is no-op for continuous jurisdiction")
    func autoCompleteContinuousNoOp() throws {
        // Given
        let realm = try inMemoryRealm()
        let repo = LogbookPeriodRepository(realm: realm)
        let calculator = MileageCalculator()
        let jurisdiction = Jurisdiction.unitedStates
        // Create an active period with an endedAt in the past (simulating a legacy period
        // that somehow has an end date, or one created before the regime switch)
        let period = LogbookPeriod()
        period.vehicleId = "v1"
        period.startedAt = Calendar.current.date(byAdding: .day, value: -200, to: Date())!
        period.endedAt = Calendar.current.date(byAdding: .day, value: -100, to: Date())!
        period.status = .active
        try realm.write { realm.add(period) }

        // When
        repo.autoCompleteExpiredPeriods(jurisdiction: jurisdiction, calculator: calculator)

        // Then
        let refreshed = repo.periods(for: "v1")
        #expect(refreshed.count == 1)
        #expect(refreshed[0].status == .active, "Continuous regime should not auto-complete expired periods")
    }

    @Test("autoCompleteExpiredPeriods works for sample-period jurisdiction")
    func autoCompleteSampleCompletes() throws {
        // Given
        let realm = try inMemoryRealm()
        let repo = LogbookPeriodRepository(realm: realm)
        let calculator = MileageCalculator()
        let jurisdiction = Jurisdiction.newZealand
        // Create an active period whose endedAt is in the past
        let period = LogbookPeriod()
        period.vehicleId = "v1"
        period.startedAt = Calendar.current.date(byAdding: .day, value: -200, to: Date())!
        period.endedAt = Calendar.current.date(byAdding: .day, value: -100, to: Date())!
        period.status = .active
        try realm.write { realm.add(period) }

        // When
        repo.autoCompleteExpiredPeriods(jurisdiction: jurisdiction, calculator: calculator)

        // Then
        let refreshed = repo.periods(for: "v1")
        #expect(refreshed.count == 1)
        #expect(refreshed[0].status == .complete, "Sample-period regime should auto-complete expired periods")
    }

    // MARK: - Helpers

    private func inMemoryRealm() throws -> Realm {
        let config = Realm.Configuration(
            inMemoryIdentifier: UUID().uuidString,
            schemaVersion: RealmProvider.schemaVersion,
            objectTypes: [UserProfile.self, Vehicle.self, Trip.self, TripPoint.self, OdometerReading.self, SavedAddress.self, LogbookPeriod.self]
        )
        return try Realm(configuration: config)
    }
}
