import Testing
import Foundation
@testable import MileageTrackeriOS

@Suite("Rate Info Display")
struct RateInfoViewTests {

    // MARK: - Jurisdiction rate lookup

    @Test("Jurisdiction.rateCountryCode returns correct country code for each case")
    func rateCountryCodeMapping() {
        #expect(Jurisdiction.newZealand.rateCountryCode == "NZ")
        #expect(Jurisdiction.australia.rateCountryCode == "AU")
        #expect(Jurisdiction.unitedStates.rateCountryCode == "US")
        #expect(Jurisdiction.canada.rateCountryCode == "CA")
        #expect(Jurisdiction.germany.rateCountryCode == "DE")
        #expect(Jurisdiction.belgium.rateCountryCode == "BE")
        #expect(Jurisdiction.netherlands.rateCountryCode == "NL")
        #expect(Jurisdiction.switzerland.rateCountryCode == "CH")
        #expect(Jurisdiction.austria.rateCountryCode == "AT")
        #expect(Jurisdiction.sweden.rateCountryCode == "SE")
        #expect(Jurisdiction.norway.rateCountryCode == "NO")
        #expect(Jurisdiction.denmark.rateCountryCode == "DK")
        #expect(Jurisdiction.finland.rateCountryCode == "FI")
        #expect(Jurisdiction.spain.rateCountryCode == "ES")
        #expect(Jurisdiction.southAfrica.rateCountryCode == "ZA")
        #expect(Jurisdiction.other.rateCountryCode == "GB")
    }

    @Test("Each jurisdiction finds a matching rate in officialRates")
    func allJurisdictionsHaveRates() {
        for j in Jurisdiction.allCases {
            let found = officialRates.first { $0.countryCode == j.rateCountryCode }
            #expect(found != nil, "Missing official rate for \(j.displayName) (\(j.rateCountryCode))")
        }
    }

    @Test("New Zealand rate has 4 fuel-type entries with two-tier thresholds")
    func newZealandRateStructure() {
        guard let rate = officialRates.first(where: { $0.countryCode == "NZ" }) else {
            Issue.record("NZ rate not found"); return
        }

        #expect(rate.defaultDistanceUnit == .kilometres)
        #expect(rate.mileageRates.count == 4)

        // Petrol: two tiers, 120 and 37
        let petrol = rate.mileageRates.first { $0.name == "Petrol" }
        #expect(petrol != nil)
        #expect(petrol?.thresholds.count == 2)
        #expect(petrol?.thresholds[0].centsPerKm == 120)
        #expect(petrol?.thresholds[0].upperBound == 14_000)
        #expect(petrol?.thresholds[1].centsPerKm == 37)
        #expect(petrol?.thresholds[1].lowerBound == 14_001)

        // Electric: two tiers
        let electric = rate.mileageRates.first { $0.name == "Electric" }
        #expect(electric != nil)
        #expect(electric?.thresholds[1].lowerBound == 14_001)
    }

    @Test("Australia rate is flat 88c/km with 5,000km cap")
    func australiaRateStructure() {
        guard let rate = officialRates.first(where: { $0.countryCode == "AU" }) else {
            Issue.record("AU rate not found"); return
        }

        #expect(rate.defaultDistanceUnit == .kilometres)
        #expect(rate.mileageRates.count == 1)
        #expect(rate.mileageRates[0].thresholds.count == 1)
        #expect(rate.mileageRates[0].thresholds[0].centsPerKm == 88)
        #expect(rate.mileageRates[0].thresholds[0].upperBound == Int.max)
        #expect(Jurisdiction.australia.annualKilometreCap == 5_000)
    }

    @Test("United Kingdom rate uses miles and has three vehicle-type entries")
    func unitedKingdomRateStructure() {
        guard let rate = officialRates.first(where: { $0.countryCode == "GB" }) else {
            Issue.record("GB rate not found"); return
        }

        #expect(rate.defaultDistanceUnit == .miles)
        #expect(rate.mileageRates.count == 3)

        // Car / Van: 55p/mi first 10,000 mi, 25p/mi above
        let carVan = rate.mileageRates.first { $0.name == "Car / Van" }
        #expect(carVan != nil)
        #expect(carVan?.thresholds[0].centsPerKm == 55)
        #expect(carVan?.thresholds[0].upperBound == 10_000)
        #expect(carVan?.thresholds[1].centsPerKm == 25)
        #expect(carVan?.thresholds[1].lowerBound == 10_001)

        // Motorcycle: flat 24p/mi
        let motorcycle = rate.mileageRates.first { $0.name == "Motorcycle" }
        #expect(motorcycle != nil)
        #expect(motorcycle?.thresholds[0].centsPerKm == 24)

        // Bicycle: flat 20p/mi
        let bicycle = rate.mileageRates.first { $0.name == "Bicycle" }
        #expect(bicycle != nil)
        #expect(bicycle?.thresholds[0].centsPerKm == 20)
    }

    @Test("United States rate uses miles and is flat 72.5c/mi")
    func unitedStatesRateStructure() {
        guard let rate = officialRates.first(where: { $0.countryCode == "US" }) else {
            Issue.record("US rate not found"); return
        }

        #expect(rate.defaultDistanceUnit == .miles)
        #expect(rate.mileageRates.count == 1)
        #expect(rate.mileageRates[0].thresholds[0].centsPerKm == 72.5)
    }

    @Test("Jurisdictions with annual caps return correct values")
    func annualCapValues() {
        #expect(Jurisdiction.australia.annualKilometreCap == 5_000)
        #expect(Jurisdiction.austria.annualKilometreCap == 30_000)
        #expect(Jurisdiction.newZealand.annualKilometreCap == 0)
        #expect(Jurisdiction.other.annualKilometreCap == 0)
        #expect(Jurisdiction.germany.annualKilometreCap == 0)
    }

    @Test("Canada rate has two tiers")
    func canadaRateStructure() {
        guard let rate = officialRates.first(where: { $0.countryCode == "CA" }) else {
            Issue.record("CA rate not found"); return
        }

        #expect(rate.defaultDistanceUnit == .kilometres)
        #expect(rate.mileageRates[0].thresholds.count == 2)
        #expect(rate.mileageRates[0].thresholds[0].centsPerKm == 73)
        #expect(rate.mileageRates[0].thresholds[0].upperBound == 5_000)
        #expect(rate.mileageRates[0].thresholds[1].centsPerKm == 67)
    }

    @Test("Denmark rate has two tiers")
    func denmarkRateStructure() {
        guard let rate = officialRates.first(where: { $0.countryCode == "DK" }) else {
            Issue.record("DK rate not found"); return
        }

        #expect(rate.defaultDistanceUnit == .kilometres)
        #expect(rate.mileageRates[0].thresholds.count == 2)
        #expect(rate.mileageRates[0].thresholds[0].centsPerKm == 394)
        #expect(rate.mileageRates[0].thresholds[0].upperBound == 20_000)
        #expect(rate.mileageRates[0].thresholds[1].centsPerKm == 228)
        #expect(rate.mileageRates[0].thresholds[1].lowerBound == 20_001)
    }

    @Test("South Africa rate has SARS simplified method name")
    func southAfricaRateStructure() {
        guard let rate = officialRates.first(where: { $0.countryCode == "ZA" }) else {
            Issue.record("ZA rate not found"); return
        }

        #expect(rate.defaultDistanceUnit == .kilometres)
        #expect(rate.mileageRates[0].name == "Simplified method (opt-in, no other allowance)")
        #expect(rate.mileageRates[0].thresholds[0].centsPerKm == 495)
        #expect(rate.mileageRates[0].thresholds[0].upperBound == Int.max)
    }

    @Test("Rate lookup by fuel type returns correct entry for NZ")
    func nzRateForFuelType() {
        guard let rate = officialRates.first(where: { $0.countryCode == "NZ" }) else {
            Issue.record("NZ rate not found"); return
        }

        let petrol = rate.rateFor(fuelType: .petrol)
        #expect(petrol?.name == "Petrol")

        let diesel = rate.rateFor(fuelType: .diesel)
        #expect(diesel?.name == "Diesel")

        let hybrid = rate.rateFor(fuelType: .hybrid)
        #expect(hybrid?.name == "Petrol Hybrid")

        let phev = rate.rateFor(fuelType: .pluginHybrid)
        #expect(phev?.name == "Petrol Hybrid")

        let electric = rate.rateFor(fuelType: .electric)
        #expect(electric?.name == "Electric")
    }

    @Test("centsPerKm at various annual distances returns correct tier")
    func centsPerKmTierSelection() {
        guard let rate = officialRates.first(where: { $0.countryCode == "NZ" }) else {
            Issue.record("NZ rate not found"); return
        }

        // Below threshold: should match first tier
        let low = rate.centsPerKm(at: 5_000, fuelType: .petrol)
        #expect(low == 120)

        // At threshold boundary: should match first tier (lowerBound is inclusive)
        let atBoundary = rate.centsPerKm(at: 14_000, fuelType: .petrol)
        #expect(atBoundary == 120)

        // Above threshold: should match second tier
        let high = rate.centsPerKm(at: 20_000, fuelType: .petrol)
        #expect(high == 37)
    }

    @Test("Rate for GB is accessible via Jurisdiction.other")
    func otherJurisdictionMapsToGB() {
        let gbRate = officialRates.first { $0.countryCode == "GB" }
        #expect(gbRate != nil)

        let otherRate = officialRates.first { $0.countryCode == Jurisdiction.other.rateCountryCode }
        #expect(otherRate != nil)
        #expect(otherRate?.countryCode == "GB")
    }
}
