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
        case .newZealand: return TaxYear(startMonth: 4, startDay: 1, endMonth: 3, endDay: 31)   // 1 Apr – 31 Mar
        case .australia:  return TaxYear(startMonth: 7, startDay: 1, endMonth: 6, endDay: 30)   // 1 Jul – 30 Jun
        case .other:      return TaxYear(startMonth: 4, startDay: 6, endMonth: 4, endDay: 5)    // UK: 6 Apr – 5 Apr
        }
    }

    /// Annual cap on business kilometres for the standard-rate method. 0 = no cap.
    var annualKilometreCap: Double {
        switch self {
        case .newZealand: return 0        // NZ has no cap — rate reduces via tiers
        case .australia:  return 5_000    // ATO caps at 5,000 km per year
        case .other:      return 0        // UK has no cap — rate reduces via tiers
        }
    }
}

// MARK: - Official Rates

let officialRates: [OfficalMileageRate] = [
    // ── New Zealand (IRD) — 2025–2026 ────────────────────────────
    .init(
        countryCode: "NZ",
        defaultDistanceUnit: .kilometres,
        mileageRates: [
            .init(
                name: "Petrol / Hybrid / EV",
                fuelType: [.petrol, .hybrid, .pluginHybrid, .electric],
                thresholds: [
                    .init(centsPerKm: 104, lowerBound: 0, upperBound: 14_000),
                    .init(centsPerKm: 34,  lowerBound: 14_001, upperBound: Int.max),
                ]
            ),
            .init(
                name: "Diesel",
                fuelType: [.diesel],
                thresholds: [
                    .init(centsPerKm: 83, lowerBound: 0, upperBound: 14_000),
                    .init(centsPerKm: 28, lowerBound: 14_001, upperBound: Int.max),
                ]
            ),
        ]
    ),

    // ── Australia (ATO) — 2025–2026 ──────────────────────────────
    .init(
        countryCode: "AU",
        defaultDistanceUnit: .kilometres,
        mileageRates: [
            .init(
                name: "All vehicles",
                fuelType: [.petrol, .diesel, .hybrid, .pluginHybrid, .electric],
                thresholds: [
                    .init(centsPerKm: 88, lowerBound: 0, upperBound: Int.max),
                ]
            ),
        ]
    ),

    // ── United Kingdom (HMRC) — 2025–2026 ─────────────────────────
    .init(
        countryCode: "GB",
        defaultDistanceUnit: .miles,
        mileageRates: [
            .init(
                name: "Car / Van",
                fuelType: [.petrol, .diesel, .hybrid, .pluginHybrid, .electric],
                thresholds: [
                    .init(centsPerKm: 45, lowerBound: 0, upperBound: 10_000),   // 45p/mi first 10,000 mi
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
        ]
    ),
]

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
