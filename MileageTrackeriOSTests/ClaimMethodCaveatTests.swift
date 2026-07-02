import Testing
import Foundation
@testable import MileageTrackeriOS

@Suite("Claim Method Caveats")
struct ClaimMethodCaveatTests {

    @Test("Canada returns employer reimbursement caveat")
    func canadaCaveat() {
        #expect(Jurisdiction.canada.claimMethodCaveat == "The per-km amount is an employer reimbursement, not a self-employed deduction.")
    }

    @Test("Spain returns autónomo caveat")
    func spainCaveat() {
        #expect(Jurisdiction.spain.claimMethodCaveat == "No per-km option for autónomos; requires ~100% exclusive business use.")
    }

    @Test("Netherlands returns actual-cost caveat")
    func netherlandsCaveat() {
        #expect(Jurisdiction.netherlands.claimMethodCaveat == "Actual-cost is not permitted for a privately-owned car; only the flat rate applies.")
    }

    @Test("South Africa returns mandatory logbook caveat")
    func southAfricaCaveat() {
        #expect(Jurisdiction.southAfrica.claimMethodCaveat == "A logbook is effectively mandatory to claim, and resets annually.")
    }

    @Test("United States returns first-year election caveat")
    func unitedStatesCaveat() {
        #expect(Jurisdiction.unitedStates.claimMethodCaveat == "Standard rate must be elected in year 1; disallowed if operating 5+ cars.")
    }

    @Test("United Kingdom (other) returns locked-method caveat")
    func unitedKingdomCaveat() {
        #expect(Jurisdiction.other.claimMethodCaveat == "Method is locked per-vehicle once chosen.")
    }

    @Test("New Zealand has no caveat")
    func newZealandCaveatIsNil() {
        #expect(Jurisdiction.newZealand.claimMethodCaveat == nil)
    }

    @Test("Australia has no caveat")
    func australiaCaveatIsNil() {
        #expect(Jurisdiction.australia.claimMethodCaveat == nil)
    }

    @Test("Germany has no caveat")
    func germanyCaveatIsNil() {
        #expect(Jurisdiction.germany.claimMethodCaveat == nil)
    }

    @Test("Belgium has no caveat")
    func belgiumCaveatIsNil() {
        #expect(Jurisdiction.belgium.claimMethodCaveat == nil)
    }

    @Test("Switzerland has no caveat")
    func switzerlandCaveatIsNil() {
        #expect(Jurisdiction.switzerland.claimMethodCaveat == nil)
    }

    @Test("Austria has no caveat")
    func austriaCaveatIsNil() {
        #expect(Jurisdiction.austria.claimMethodCaveat == nil)
    }

    @Test("Sweden has no caveat")
    func swedenCaveatIsNil() {
        #expect(Jurisdiction.sweden.claimMethodCaveat == nil)
    }

    @Test("Norway has no caveat")
    func norwayCaveatIsNil() {
        #expect(Jurisdiction.norway.claimMethodCaveat == nil)
    }

    @Test("Denmark has no caveat")
    func denmarkCaveatIsNil() {
        #expect(Jurisdiction.denmark.claimMethodCaveat == nil)
    }

    @Test("Finland has no caveat")
    func finlandCaveatIsNil() {
        #expect(Jurisdiction.finland.claimMethodCaveat == nil)
    }

    @Test("All 16 jurisdictions produce a consistent result")
    func allJurisdictionsCovered() {
        var caveatCount = 0
        var nilCount = 0
        for j in Jurisdiction.allCases {
            if j.claimMethodCaveat != nil {
                caveatCount += 1
            } else {
                nilCount += 1
            }
        }
        // 6 jurisdictions with caveats: US, CA, ES, NL, ZA, other(GB)
        #expect(caveatCount == 6)
        // 10 without: NZ, AU, DE, BE, CH, AT, SE, NO, DK, FI
        #expect(nilCount == 10)
    }
}
