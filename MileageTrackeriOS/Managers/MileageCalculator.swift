// MileageCalculator — Rate lookup and dollar-value computation for trip expenses.
// Supports standard-rate, logbook, and custom-rate claim methods across all jurisdictions.

import Foundation

@Observable
final class MileageCalculator {

    // MARK: - Rate Lookup

    /// Returns the matching rate entry for the user's profile and vehicle fuel type.
    func rateEntry(for profile: UserProfile, fuelType: FuelType) -> MileageRates? {
        guard let country = officialRates.first(where: { $0.countryCode == profile.jurisdiction.rawValue })
                ?? officialRates.first(where: { $0.countryCode == profile.jurisdiction.countryCodeOverride })
        else { return nil }
        return country.rateFor(fuelType: fuelType)
    }

    /// Returns the cents-per-km rate at a given cumulative distance for the tax year.
    func centsPerKm(at cumulativeKm: Double, profile: UserProfile, fuelType: FuelType) -> Double? {
        let country = officialRates.first(where: { $0.countryCode == profile.jurisdiction.rawValue })
            ?? officialRates.first(where: { $0.countryCode == profile.jurisdiction.countryCodeOverride })
        return country?.centsPerKm(at: cumulativeKm, fuelType: fuelType)
    }

    // MARK: - Dollar Value

    /// The dollar value for a single trip, based on the user's claim method.
    func dollarValue(for trip: Trip, profile: UserProfile, fuelType: FuelType = .petrol, cumulativeKm: Double) -> Double {
        let distanceKm = trip.distanceMetres / 1000
        let isMiles = profile.distanceUnit == .miles
        let kmForCalc = isMiles ? distanceKm * 1.60934 : distanceKm

        switch profile.claimMethod {
        case .standardRate:
            guard let cRate = centsPerKm(at: cumulativeKm, profile: profile, fuelType: fuelType) else { return 0 }
            return (kmForCalc * cRate) / 100  // cents → dollars

        case .logbook:
            guard let cRate = centsPerKm(at: cumulativeKm, profile: profile, fuelType: fuelType) else { return 0 }
            let percent = trip.businessUsePercent ?? 0
            return (kmForCalc * cRate * percent) / 10000  // c/km × km × % / 10000

        case .customRate:
            let tierRate = customTierRate(km: kmForCalc, tiers: Array(profile.customRateThresholds))
            return (kmForCalc * tierRate) / 100
        }
    }

    // MARK: - Logbook Business Use %

    /// Calculates business-use percentage from a set of odometer readings.
    /// Returns a value between 0 and 1 (e.g. 0.35 = 35% business use).
    func businessUsePercent(readings: [OdometerReading], trips: [Trip]) -> Double {
        let businessKm = trips
            .filter { $0.category == .business }
            .reduce(0) { $0 + ($1.distanceMetres / 1000) }
        let totalKm = trips.reduce(0) { $0 + ($1.distanceMetres / 1000) }
        guard totalKm > 0 else { return 0 }
        return min(businessKm / totalKm, 1.0)
    }

    // MARK: - Custom Rate Tier Lookup

    private func customTierRate(km: Double, tiers: [RateThreshold]) -> Double {
        for tier in tiers {
            if km >= Double(tier.lowerBound) && km <= Double(tier.upperBound) {
                return tier.centsPerUnit
            }
        }
        return tiers.last?.centsPerUnit ?? 0
    }
}

// MARK: - Jurisdiction Helpers

private extension Jurisdiction {
    /// Override country code for rate lookup when Jurisdiction.other is used but a specific country applies.
    var countryCodeOverride: String? {
        switch self {
        case .other: return "GB"   // default "other" to UK rates
        default: return nil
        }
    }
}


