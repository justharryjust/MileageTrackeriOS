import Testing
import Foundation
import RealmSwift
@testable import MileageTrackeriOS

@Suite("Currency Code & Formatter")
struct CurrencyTests {

    // MARK: - Jurisdiction currency codes

    @Test("New Zealand uses NZD")
    func nzCurrency() { #expect(Jurisdiction.newZealand.currencyCode == "NZD") }

    @Test("Australia uses AUD")
    func auCurrency() { #expect(Jurisdiction.australia.currencyCode == "AUD") }

    @Test("United Kingdom uses GBP")
    func gbCurrency() { #expect(Jurisdiction.other.currencyCode == "GBP") }

    @Test("United States uses USD")
    func usCurrency() { #expect(Jurisdiction.unitedStates.currencyCode == "USD") }

    @Test("Canada uses CAD")
    func caCurrency() { #expect(Jurisdiction.canada.currencyCode == "CAD") }

    @Test("Germany uses EUR")
    func deCurrency() { #expect(Jurisdiction.germany.currencyCode == "EUR") }

    @Test("Belgium uses EUR")
    func beCurrency() { #expect(Jurisdiction.belgium.currencyCode == "EUR") }

    @Test("Netherlands uses EUR")
    func nlCurrency() { #expect(Jurisdiction.netherlands.currencyCode == "EUR") }

    @Test("Switzerland uses CHF")
    func chCurrency() { #expect(Jurisdiction.switzerland.currencyCode == "CHF") }

    @Test("Austria uses EUR")
    func atCurrency() { #expect(Jurisdiction.austria.currencyCode == "EUR") }

    @Test("Sweden uses SEK")
    func seCurrency() { #expect(Jurisdiction.sweden.currencyCode == "SEK") }

    @Test("Norway uses NOK")
    func noCurrency() { #expect(Jurisdiction.norway.currencyCode == "NOK") }

    @Test("Denmark uses DKK")
    func dkCurrency() { #expect(Jurisdiction.denmark.currencyCode == "DKK") }

    @Test("Finland uses EUR")
    func fiCurrency() { #expect(Jurisdiction.finland.currencyCode == "EUR") }

    @Test("Spain uses EUR")
    func esCurrency() { #expect(Jurisdiction.spain.currencyCode == "EUR") }

    @Test("South Africa uses ZAR")
    func zaCurrency() { #expect(Jurisdiction.southAfrica.currencyCode == "ZAR") }

    // MARK: - OfficalMileageRate currency codes

    @Test("Each official rate has a non-empty currencyCode")
    func allRatesHaveCurrency() {
        for rate in officialRates {
            #expect(!rate.currencyCode.isEmpty, "Rate for \(rate.countryCode) has empty currencyCode")
        }
    }

    @Test("OfficalMileageRate currency matches Jurisdiction currency")
    func rateCurrencyMatchesJurisdiction() {
        let jurisdictionMap: [String: Jurisdiction] = [
            "NZ": .newZealand, "AU": .australia, "US": .unitedStates, "CA": .canada,
            "DE": .germany, "BE": .belgium, "NL": .netherlands, "CH": .switzerland,
            "AT": .austria, "SE": .sweden, "NO": .norway, "DK": .denmark,
            "FI": .finland, "ES": .spain, "ZA": .southAfrica,
        ]
        for rate in officialRates {
            if let jurisdiction = jurisdictionMap[rate.countryCode] {
                #expect(rate.currencyCode == jurisdiction.currencyCode,
                        "Rate \(rate.countryCode) has \(rate.currencyCode) but \(jurisdiction) has \(jurisdiction.currencyCode)")
            }
        }
    }

    @Test("UK (.other) rate maps correctly")
    func ukRateCurrency() {
        guard let ukRate = officialRates.first(where: { $0.countryCode == "GB" }) else {
            Issue.record("GB rate not found"); return
        }
        #expect(ukRate.currencyCode == "GBP")
        #expect(ukRate.currencyCode == Jurisdiction.other.currencyCode)
    }

    // MARK: - Currency Formatter

    @Test("Formatter produces USD output")
    func formatterUSD() {
        let fmt = MileageCalculator.currencyFormatter(for: "USD")
        let result = fmt.string(from: NSNumber(value: 1234.56))
        // Should contain "1,234.56" (or "1234.56" depending on locale) and "$" or "USD"
        #expect(result != nil)
        #expect(result?.isEmpty == false)
        // The formatter respects the user's locale, so we check it contains the digits
        #expect(result?.contains("1234") == true || result?.contains("1,234") == true)
    }

    @Test("Formatter produces GBP output")
    func formatterGBP() {
        let fmt = MileageCalculator.currencyFormatter(for: "GBP")
        let result = fmt.string(from: NSNumber(value: 99.99))
        #expect(result != nil)
        #expect(result?.isEmpty == false)
    }

    @Test("Formatter produces EUR output")
    func formatterEUR() {
        let fmt = MileageCalculator.currencyFormatter(for: "EUR")
        let result = fmt.string(from: NSNumber(value: 50))
        #expect(result != nil)
        #expect(result?.isEmpty == false)
    }

    @Test("Formatter handles zero")
    func formatterZero() {
        let fmt = MileageCalculator.currencyFormatter(for: "USD")
        let result = fmt.string(from: NSNumber(value: 0))
        #expect(result != nil)
        #expect(result?.isEmpty == false)
    }

    @Test("Formatter handles large values")
    func formatterLarge() {
        let fmt = MileageCalculator.currencyFormatter(for: "JPY")
        let result = fmt.string(from: NSNumber(value: 1_000_000))
        #expect(result != nil)
        #expect(result?.isEmpty == false)
    }

    @Test("Multiple formatters are independent")
    func formatterIndependence() {
        let usd = MileageCalculator.currencyFormatter(for: "USD")
        let eur = MileageCalculator.currencyFormatter(for: "EUR")
        let usdResult = usd.string(from: NSNumber(value: 100))
        let eurResult = eur.string(from: NSNumber(value: 100))
        #expect(usdResult != nil)
        #expect(eurResult != nil)
        // The two outputs should differ because they have different currency codes
        #expect(usdResult != eurResult)
    }
}
