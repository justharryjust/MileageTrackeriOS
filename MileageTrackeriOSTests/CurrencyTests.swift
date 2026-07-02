import Testing
@testable import MileageTrackeriOS

// MARK: - Per-Country Currency

@Suite("Per-Country Currency")
struct CurrencyTests {

    @Test("Jurisdiction.currencyCode returns correct ISO 4217 codes")
    func jurisdictionCurrencyCodes() {
        #expect(Jurisdiction.newZealand.currencyCode == "NZD")
        #expect(Jurisdiction.australia.currencyCode == "AUD")
        #expect(Jurisdiction.unitedStates.currencyCode == "USD")
        #expect(Jurisdiction.canada.currencyCode == "CAD")
        #expect(Jurisdiction.germany.currencyCode == "EUR")
        #expect(Jurisdiction.belgium.currencyCode == "EUR")
        #expect(Jurisdiction.netherlands.currencyCode == "EUR")
        #expect(Jurisdiction.switzerland.currencyCode == "CHF")
        #expect(Jurisdiction.austria.currencyCode == "EUR")
        #expect(Jurisdiction.sweden.currencyCode == "SEK")
        #expect(Jurisdiction.norway.currencyCode == "NOK")
        #expect(Jurisdiction.denmark.currencyCode == "DKK")
        #expect(Jurisdiction.finland.currencyCode == "EUR")
        #expect(Jurisdiction.spain.currencyCode == "EUR")
        #expect(Jurisdiction.southAfrica.currencyCode == "ZAR")
        #expect(Jurisdiction.other.currencyCode == "GBP")
    }

    @Test("OfficalMileageRate for each jurisdiction carries correct currencyCode")
    func rateCurrencyCodes() throws {
        let codes: [(String, String)] = officialRates.map { ($0.countryCode, $0.currencyCode) }
        #expect(codes.contains { $0 == ("NZ", "NZD") })
        #expect(codes.contains { $0 == ("AU", "AUD") })
        #expect(codes.contains { $0 == ("GB", "GBP") })
        #expect(codes.contains { $0 == ("US", "USD") })
        #expect(codes.contains { $0 == ("CA", "CAD") })
        #expect(codes.contains { $0 == ("DE", "EUR") })
        #expect(codes.contains { $0 == ("CH", "CHF") })
        #expect(codes.contains { $0 == ("SE", "SEK") })
        #expect(codes.contains { $0 == ("NO", "NOK") })
        #expect(codes.contains { $0 == ("DK", "DKK") })
        #expect(codes.contains { $0 == ("ZA", "ZAR") })
        #expect(codes.count == 16)
    }

    @Test("MileageCalculator.currencyCode matches jurisdiction for known profiles")
    func calculatorCurrencyCode() throws {
        let calc = MileageCalculator()

        // Build a minimal profile for testing
        let profile = UserProfile()
        profile.jurisdiction = .other
        #expect(calc.currencyCode(for: profile) == "GBP")

        profile.jurisdiction = .newZealand
        #expect(calc.currencyCode(for: profile) == "NZD")

        profile.jurisdiction = .sweden
        #expect(calc.currencyCode(for: profile) == "SEK")

        profile.jurisdiction = .switzerland
        #expect(calc.currencyCode(for: profile) == "CHF")
    }

    @Test("MileageCalculator.currencyCode maps Jurisdiction.other to GBP")
    func calculatorCurrencyCodeOther() throws {
        let calc = MileageCalculator()
        let profile = UserProfile()
        profile.jurisdiction = .other
        #expect(calc.currencyCode(for: profile) == "GBP")
    }

    @Test("MileageCalculator.formatCurrency produces locale-aware strings")
    func calculatorFormatCurrency() throws {
        let calc = MileageCalculator()
        let profile = UserProfile()
        profile.jurisdiction = .other

        let result = calc.formatCurrency(1234.56, for: profile)
        // Should contain "1,234.56" and "£" — exact format depends on user locale
        #expect(result.contains("1,234.56") || result.contains("1234,56"))
        #expect(result.contains("£") || result.contains("GBP"))
    }

    @Test("MileageCalculator.currencySymbol returns expected symbols")
    func calculatorCurrencySymbol() throws {
        let calc = MileageCalculator()
        let profile = UserProfile()
        profile.jurisdiction = .other
        #expect(calc.currencySymbol(for: profile) == "£")
    }
}
