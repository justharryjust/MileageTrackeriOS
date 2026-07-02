//
//  MileageRates.swift
//  MileageTrackeriOS
//
//  Official mileage reimbursement rates per jurisdiction.
//  Rates are updated annually — verify against published tax agency figures each financial year.
//

import Foundation

// MARK: - Rate Data Structures (shared with Models.swift types)

struct OfficalMileageRate {
    let countryCode: String
    let defaultDistanceUnit: DistanceUnit
    let currencyCode: String
    let mileageRates: [MileageRates]
}

// MARK: - Tax Year

struct TaxYear {
    let startMonth: Int     // 1 = Jan
    let startDay: Int
    let endMonth: Int
    let endDay: Int

    /// Returns the tax year containing `date`.
    func containing(_ date: Date) -> (start: Date, end: Date) {
        let cal = Calendar.current
        let year = cal.component(.year, from: date)

        // Build candidate start: if date is before start, it belongs to previous tax year
        var start = DateComponents(year: year, month: startMonth, day: startDay)
        if let startDate = cal.date(from: start), date < startDate {
            start.year = year - 1
        } else if let startDate = cal.date(from: start), date >= startDate {
            start.year = year
        }
        guard let finalStart = cal.date(from: start) else { return (date, date) }

        var end = DateComponents(year: (start.year ?? year) + 1, month: endMonth, day: endDay)
        // Adjust end to be one second before midnight of endDay
        guard var finalEnd = cal.date(from: end) else { return (date, date) }
        finalEnd = cal.date(byAdding: .day, value: 1, to: finalEnd)!.addingTimeInterval(-1)
        return (finalStart, finalEnd)
    }
}

extension Jurisdiction {
    var taxYear: TaxYear {
        switch self {
        case .newZealand:  return TaxYear(startMonth: 4, startDay: 1, endMonth: 3, endDay: 31)   // 1 Apr – 31 Mar
        case .australia:   return TaxYear(startMonth: 7, startDay: 1, endMonth: 6, endDay: 30)   // 1 Jul – 30 Jun
        case .belgium:     return TaxYear(startMonth: 7, startDay: 1, endMonth: 6, endDay: 30)   // 1 Jul – 30 Jun
        case .southAfrica: return TaxYear(startMonth: 3, startDay: 1, endMonth: 2, endDay: 28)   // 1 Mar – 28/29 Feb
        case .other:       return TaxYear(startMonth: 4, startDay: 6, endMonth: 4, endDay: 5)    // UK: 6 Apr – 5 Apr
        default:           return TaxYear(startMonth: 1, startDay: 1, endMonth: 12, endDay: 31)  // calendar year
        }
    }

    /// Annual cap on business kilometres for the standard-rate method. 0 = no cap.
    var annualKilometreCap: Double {
        switch self {
        case .newZealand: return 0        // NZ has no cap — rate reduces via tiers
        case .australia:  return 5_000    // ATO caps at 5,000 km per year
        case .austria:    return 30_000   // BMF caps the flat Kilometergeld rate at 30,000 km per year
        case .other:      return 0        // UK has no cap — rate reduces via tiers
        default:          return 0
        }
    }
}

// MARK: - Official Rates
//
// Each jurisdiction is its own top-level constant rather than one entry in a single
// giant array literal — with 16 countries the combined nested-`.init` expression made
// the type checker time out ("unable to type-check this expression in reasonable
// time"). Keep new entries as separate `private let`s and just list them below.

private let newZealandRate: OfficalMileageRate = .init(
    countryCode: "NZ",
    defaultDistanceUnit: .kilometres,
    currencyCode: "NZD",
    mileageRates: [
        .init(
            name: "Petrol",
            fuelType: [.petrol],
            thresholds: [
                .init(centsPerKm: 120, lowerBound: 0, upperBound: 14_000),
                .init(centsPerKm: 37,  lowerBound: 14_001, upperBound: Int.max),
            ]
        ),
        .init(
            name: "Diesel",
            fuelType: [.diesel],
            thresholds: [
                .init(centsPerKm: 130, lowerBound: 0, upperBound: 14_000),
                .init(centsPerKm: 38,  lowerBound: 14_001, upperBound: Int.max),
            ]
        ),
        .init(
            name: "Petrol Hybrid",
            fuelType: [.hybrid, .pluginHybrid], // IRD doesn't publish PHEV separately; grouped with hybrid as this dataset's inference, not IRD-confirmed
            thresholds: [
                .init(centsPerKm: 90, lowerBound: 0, upperBound: 14_000),
                .init(centsPerKm: 24, lowerBound: 14_001, upperBound: Int.max),
            ]
        ),
        .init(
            name: "Electric",
            fuelType: [.electric],
            thresholds: [
                .init(centsPerKm: 122, lowerBound: 0, upperBound: 14_000),
                .init(centsPerKm: 23,  lowerBound: 14_001, upperBound: Int.max),
            ]
        ),
    ]
)

// ── Australia (ATO) — 2025–2026 ──────────────────────────────
private let australiaRate: OfficalMileageRate = .init(
    countryCode: "AU",
    defaultDistanceUnit: .kilometres,
    currencyCode: "AUD",
    mileageRates: [
        .init(
            name: "All vehicles",
            fuelType: [.petrol, .diesel, .hybrid, .pluginHybrid, .electric],
            thresholds: [
                .init(centsPerKm: 88, lowerBound: 0, upperBound: Int.max),
            ]
        ),
    ]
)

// ── United Kingdom (HMRC) — 2026–2027 ─────────────────────────
private let unitedKingdomRate: OfficalMileageRate = .init(
    countryCode: "GB",
    defaultDistanceUnit: .miles,
    currencyCode: "GBP",
    mileageRates: [
        .init(
            name: "Car / Van",
            fuelType: [.petrol, .diesel, .hybrid, .pluginHybrid, .electric],
            thresholds: [
                .init(centsPerKm: 55, lowerBound: 0, upperBound: 10_000),   // 55p/mi first 10,000 mi (raised from 45p, 6 Apr 2026)
                .init(centsPerKm: 25, lowerBound: 10_001, upperBound: Int.max), // 25p/mi above
            ]
        ),
        .init(
            name: "Motorcycle",
            fuelType: [],   // matches any fuel type not covered above
            thresholds: [
                .init(centsPerKm: 24, lowerBound: 0, upperBound: Int.max),   // 24p/mi flat
            ]
        ),
        .init(
            name: "Bicycle",
            fuelType: [],
            thresholds: [
                .init(centsPerKm: 20, lowerBound: 0, upperBound: Int.max),   // 20p/mi flat (HMRC AMAP)
            ]
        ),
    ]
)

// ── United States (IRS) — 2026 ────────────────────────────
private let unitedStatesRate: OfficalMileageRate = .init(
    countryCode: "US",
    defaultDistanceUnit: .miles,
    currencyCode: "USD",
    mileageRates: [
        .init(
            name: "Business",
            fuelType: [.petrol, .diesel, .hybrid, .pluginHybrid, .electric],
            thresholds: [
                .init(centsPerKm: 72.5, lowerBound: 0, upperBound: Int.max),
            ]
        ),
    ]
)

// ── Canada (CRA) — 2026 ───────────────────────────────────
// Note: territories (Yukon/NWT/Nunavut) get +4¢/km on both tiers (77¢/71¢) — not modeled, no region dimension.
private let canadaRate: OfficalMileageRate = .init(
    countryCode: "CA",
    defaultDistanceUnit: .kilometres,
    currencyCode: "CAD",
    mileageRates: [
        .init(
            name: "Provinces",
            fuelType: [.petrol, .diesel, .hybrid, .pluginHybrid, .electric],
            thresholds: [
                .init(centsPerKm: 73, lowerBound: 0, upperBound: 5_000),
                .init(centsPerKm: 67, lowerBound: 5_001, upperBound: Int.max),
            ]
        ),
    ]
)

// ── Germany (BMF / BRKG §5) — 2026 ────────────────────────
// Note: Motorcycle row is currently unreachable by MileageCalculator.rateFor(fuelType:) — see known limitation.
private let germanyRate: OfficalMileageRate = .init(
    countryCode: "DE",
    defaultDistanceUnit: .kilometres,
    currencyCode: "EUR",
    mileageRates: [
        .init(
            name: "Car",
            fuelType: [.petrol, .diesel, .hybrid, .pluginHybrid, .electric],
            thresholds: [.init(centsPerKm: 30, lowerBound: 0, upperBound: Int.max)]
        ),
        .init(
            name: "Motorcycle",
            fuelType: [],
            thresholds: [.init(centsPerKm: 20, lowerBound: 0, upperBound: Int.max)]
        ),
    ]
)

// ── Belgium (SPF / BOSA) — Jul 2026 ───────────────────────
// Note: revised quarterly/frequently — recheck more often than other entries.
private let belgiumRate: OfficalMileageRate = .init(
    countryCode: "BE",
    defaultDistanceUnit: .kilometres,
    currencyCode: "EUR",
    mileageRates: [
        .init(
            name: "All vehicles",
            fuelType: [.petrol, .diesel, .hybrid, .pluginHybrid, .electric],
            thresholds: [.init(centsPerKm: 47.61, lowerBound: 0, upperBound: Int.max)]
        ),
    ]
)

// ── Netherlands (Belastingdienst) — 2026 ──────────────────
private let netherlandsRate: OfficalMileageRate = .init(
    countryCode: "NL",
    defaultDistanceUnit: .kilometres,
    currencyCode: "EUR",
    mileageRates: [
        .init(
            name: "All vehicles",
            fuelType: [.petrol, .diesel, .hybrid, .pluginHybrid, .electric],
            thresholds: [.init(centsPerKm: 25, lowerBound: 0, upperBound: Int.max)]
        ),
    ]
)

// ── Switzerland (EFD / ESTV) — 2026 ───────────────────────
private let switzerlandRate: OfficalMileageRate = .init(
    countryCode: "CH",
    defaultDistanceUnit: .kilometres,
    currencyCode: "CHF",
    mileageRates: [
        .init(
            name: "Car",
            fuelType: [.petrol, .diesel, .hybrid, .pluginHybrid, .electric],
            thresholds: [.init(centsPerKm: 75, lowerBound: 0, upperBound: Int.max)]
        ),
    ]
)

// ── Austria (BMF Kilometergeldverordnung) — 2026 ──────────
// Note: 30,000km/yr cap handled via Jurisdiction.annualKilometreCap. Motorcycle row currently
// unreachable (same known limitation). +€0.15/km passenger surcharge not modeled.
private let austriaRate: OfficalMileageRate = .init(
    countryCode: "AT",
    defaultDistanceUnit: .kilometres,
    currencyCode: "EUR",
    mileageRates: [
        .init(
            name: "Car",
            fuelType: [.petrol, .diesel, .hybrid, .pluginHybrid, .electric],
            thresholds: [.init(centsPerKm: 50, lowerBound: 0, upperBound: Int.max)]
        ),
        .init(
            name: "Motorcycle",
            fuelType: [],
            thresholds: [.init(centsPerKm: 25, lowerBound: 0, upperBound: Int.max)]
        ),
    ]
)

// ── Sweden (Skatteverket) — 2026 ──────────────────────────
// 2.50 SEK/km = 250 öre/km. "Benefit car" rows (1.20/0.95 SEK/km) omitted — would need a
// non-fuel dimension (ownership status), currently unreachable, same known limitation.
private let swedenRate: OfficalMileageRate = .init(
    countryCode: "SE",
    defaultDistanceUnit: .kilometres,
    currencyCode: "SEK",
    mileageRates: [
        .init(
            name: "Own car",
            fuelType: [.petrol, .diesel, .hybrid, .pluginHybrid, .electric],
            thresholds: [.init(centsPerKm: 250, lowerBound: 0, upperBound: Int.max)]
        ),
    ]
)

// ── Norway (Skatteetaten) — 2026 ──────────────────────────
// 3.50 NOK/km = 350 øre/km.
private let norwayRate: OfficalMileageRate = .init(
    countryCode: "NO",
    defaultDistanceUnit: .kilometres,
    currencyCode: "NOK",
    mileageRates: [
        .init(
            name: "All vehicles",
            fuelType: [.petrol, .diesel, .hybrid, .pluginHybrid, .electric],
            thresholds: [.init(centsPerKm: 350, lowerBound: 0, upperBound: Int.max)]
        ),
    ]
)

// ── Denmark (Skattestyrelsen) — 2026 ──────────────────────
// 3.94/2.28 DKK/km = 394/228 øre/km.
private let denmarkRate: OfficalMileageRate = .init(
    countryCode: "DK",
    defaultDistanceUnit: .kilometres,
    currencyCode: "DKK",
    mileageRates: [
        .init(
            name: "All vehicles",
            fuelType: [.petrol, .diesel, .hybrid, .pluginHybrid, .electric],
            thresholds: [
                .init(centsPerKm: 394, lowerBound: 0, upperBound: 20_000),
                .init(centsPerKm: 228, lowerBound: 20_001, upperBound: Int.max),
            ]
        ),
    ]
)

// ── Finland (Verohallinto) — 2026 ─────────────────────────
private let finlandRate: OfficalMileageRate = .init(
    countryCode: "FI",
    defaultDistanceUnit: .kilometres,
    currencyCode: "EUR",
    mileageRates: [
        .init(
            name: "All vehicles",
            fuelType: [.petrol, .diesel, .hybrid, .pluginHybrid, .electric],
            thresholds: [.init(centsPerKm: 55, lowerBound: 0, upperBound: Int.max)]
        ),
    ]
)

// ── Spain (Agencia Tributaria) — 2026 ─────────────────────
private let spainRate: OfficalMileageRate = .init(
    countryCode: "ES",
    defaultDistanceUnit: .kilometres,
    currencyCode: "EUR",
    mileageRates: [
        .init(
            name: "All vehicles",
            fuelType: [.petrol, .diesel, .hybrid, .pluginHybrid, .electric],
            thresholds: [.init(centsPerKm: 26, lowerBound: 0, upperBound: Int.max)]
        ),
    ]
)

// ── South Africa (SARS) — simplified method only — 2027 year of assessment ──
// SARS's PRIMARY method is vehicle-value-banded (fixed+fuel+maintenance per band) —
// needs a data-model extension, not represented here. This is only the SARS-sanctioned
// simplified flat-rate alternative, valid only if the employee elects it and receives
// no other travel allowance besides tolls/parking.
private let southAfricaRate: OfficalMileageRate = .init(
    countryCode: "ZA",
    defaultDistanceUnit: .kilometres,
    currencyCode: "ZAR",
    mileageRates: [
        .init(
            name: "Simplified method (opt-in, no other allowance)",
            fuelType: [.petrol, .diesel, .hybrid, .pluginHybrid, .electric],
            thresholds: [.init(centsPerKm: 495, lowerBound: 0, upperBound: Int.max)]
        ),
    ]
)

let officialRates: [OfficalMileageRate] = [
    newZealandRate,
    australiaRate,
    unitedKingdomRate,
    unitedStatesRate,
    canadaRate,
    germanyRate,
    belgiumRate,
    netherlandsRate,
    switzerlandRate,
    austriaRate,
    swedenRate,
    norwayRate,
    denmarkRate,
    finlandRate,
    spainRate,
    southAfricaRate,
]

// MARK: - Jurisdiction Rate Lookup

extension Jurisdiction {
    /// The country code used to look up this jurisdiction's entry in `officialRates`.
    /// Maps `.other` → "GB" (United Kingdom / HMRC) so the rates table is reachable.
    var rateCountryCode: String {
        self == .other ? "GB" : rawValue
    }
}

// MARK: - Rate Lookup Helpers

extension OfficalMileageRate {
    /// Find the rate entry matching the user's fuel type (or the first entry if no specific match).
    func rateFor(fuelType: FuelType) -> MileageRates? {
        mileageRates.first { $0.fuelType?.contains(fuelType) == true }
            ?? mileageRates.first { $0.fuelType?.isEmpty == true }  // catch-all entry
            ?? mileageRates.first
    }

    /// Rate in cents per km at a given cumulative annual distance.
    func centsPerKm(at cumulativeKm: Double, fuelType: FuelType) -> Double? {
        guard let entry = rateFor(fuelType: fuelType) else { return nil }
        for tier in entry.thresholds {
            if cumulativeKm >= Double(tier.lowerBound) && cumulativeKm <= Double(tier.upperBound) {
                return tier.centsPerKm
            }
        }
        return entry.thresholds.last?.centsPerKm
    }
}
