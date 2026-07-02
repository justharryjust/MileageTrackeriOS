// RateInfoView — Displays official mileage rates for the selected jurisdiction.
// Used inline in ProfileEditView and as a standalone view from SettingsView.

import SwiftUI

struct RateInfoView: View {
    let jurisdiction: Jurisdiction

    private var rate: OfficalMileageRate? {
        officialRates.first { $0.countryCode == jurisdiction.rateCountryCode }
    }

    private var unitLabel: String {
        rate?.defaultDistanceUnit == .miles ? "p/\(rate!.defaultDistanceUnit.shortName)" : "\u{00A2}/\(rate?.defaultDistanceUnit.shortName ?? "km")"
    }

    var body: some View {
        Group {
            if let rate {
                rateContent(rate)
            } else {
                Text("No official rates available for \(jurisdiction.displayName).")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.mtTextSub)
            }
        }
    }

    // MARK: - Rate Content

    @ViewBuilder
    private func rateContent(_ rate: OfficalMileageRate) -> some View {
        VStack(alignment: .leading, spacing: MTSpacing.sm) {
            // Header
            Text(agencyName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.mtTextPrimary)

            // Each rate category
            VStack(alignment: .leading, spacing: MTSpacing.sm) {
                ForEach(rate.mileageRates, id: \.name) { entry in
                    rateEntryView(entry, defaultDistanceUnit: rate.defaultDistanceUnit)
                }
            }

            // Annual cap
            if jurisdiction.annualKilometreCap > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 11))
                    Text("Capped at \(formatCap(jurisdiction.annualKilometreCap)) \(rate.defaultDistanceUnit.shortName)/year")
                        .font(.system(size: 12))
                }
                .foregroundStyle(Color.mtWarning)
            }

            // Tax authority link
            if let url = agencyURL {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Text("View official \(agencyName) rates")
                            .font(.system(size: 12))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10))
                    }
                }
                .foregroundStyle(Color.mtGreen)
            }
        }
    }

    // MARK: - Rate Entry

    private func rateEntryView(_ entry: MileageRates, defaultDistanceUnit: DistanceUnit) -> some View {
        let label = entry.name ?? "Standard rate"
        let unit = defaultDistanceUnit == .miles ? "mi" : "km"
        let symbol = defaultDistanceUnit == .miles ? "p" : "\u{00A2}"

        return VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.mtTextPrimary)

            ForEach(Array(entry.thresholds.enumerated()), id: \.offset) { _, tier in
                let tierLabel: String = {
                    if tier.upperBound == Int.max {
                        if tier.lowerBound == 0 {
                            return "\(symbol)/\(unit)"
                        }
                        return "above \(tier.lowerBound) \(unit)"
                    }
                    if tier.lowerBound == 0 {
                        return "up to \(tier.upperBound) \(unit)"
                    }
                    return "\(tier.lowerBound)\u{2013}\(tier.upperBound) \(unit)"
                }()

                Text("\(formatRate(tier.centsPerKm))\(symbol)/\(unit) \(tierLabel)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.mtTextSub)
            }
        }
    }

    // MARK: - Helpers

    private var agencyName: String {
        switch jurisdiction {
        case .newZealand:   return "IRD"
        case .australia:    return "ATO"
        case .unitedStates: return "IRS"
        case .canada:       return "CRA"
        case .germany:      return "BMF"
        case .belgium:      return "SPF/BOSA"
        case .netherlands:  return "Belastingdienst"
        case .switzerland:  return "EFD/ESTV"
        case .austria:      return "BMF"
        case .sweden:       return "Skatteverket"
        case .norway:       return "Skatteetaten"
        case .denmark:      return "Skattestyrelsen"
        case .finland:      return "Verohallinto"
        case .spain:        return "Agencia Tributaria"
        case .southAfrica:  return "SARS"
        case .other:        return "HMRC"
        }
    }

    private var agencyURL: URL? {
        switch jurisdiction {
        case .newZealand:
            return URL(string: "https://www.ird.govt.nz/income-tax/income-tax-for-businesses-and-organisations/types-of-business-expenses/motor-vehicle-expenses/kilometre-rates")
        case .australia:
            return URL(string: "https://www.ato.gov.au/individuals-and-families/income-deductions-and-concessions/deductions-you-can-claim/transport-and-travel-expenses/car-expenses/cents-per-kilometre-method")
        case .unitedStates:
            return URL(string: "https://www.irs.gov/tax-professionals/standard-mileage-rates")
        case .canada:
            return URL(string: "https://www.canada.ca/en/department-finance/news/2026/01/government-announces-the-2026-automobile-deduction-limits-and-expense-benefit-rates-for-businesses.html")
        case .germany:
            return URL(string: "https://www.gesetze-im-internet.de/brkg_2005/__5.html")
        case .belgium:
            return URL(string: "https://www.partena-professional.be/fr/nouveau-montant-pour-lindemnite-kilometrique-de-juillet-2026")
        case .netherlands:
            return URL(string: "https://www.belastingdienst.nl/wps/wcm/connect/bldcontentnl/berichten/nieuws/verhoging-onbelaste-kilometervergoeding-hoe-verwerkt-u-dit-in-de-loonaangifte")
        case .switzerland:
            return URL(string: "https://law.ch/lawnews/2026/01/autokilometeransatz-regeln-ab-01-01-2026/")
        case .austria:
            return URL(string: "https://www.bmf.gv.at/themen/steuern/kraftfahrzeuge/kilometergeld.html")
        case .sweden:
            return URL(string: "https://www.skatteverket.se/privat/skatter/beloppochprocent/2026.4.1522bf3f19aea8075ba21.html")
        case .norway:
            return URL(string: "https://www.skatteetaten.no/en/rates/car-allowance-distance-based-allowance/")
        case .denmark:
            return URL(string: "https://sktst.dk/nyheder-og-pressemeddelelser/hoejere-fradrag-til-pendlerne-i-2026")
        case .finland:
            return URL(string: "https://www.vero.fi/en/About-us/newsroom/news/uutiset/2025/tax-exempt-allowances-in-2026-for-business-travel/")
        case .spain:
            return URL(string: "https://sede.agenciatributaria.gob.es")
        case .southAfrica:
            return URL(string: "https://www.sars.gov.za/wp-content/uploads/Docs/PAYE/Tables/tables2026/PAYE-GEN-01-G03-A01-Rate-per-Kilometre-Schedule-External-Annexure.pdf")
        case .other:
            return URL(string: "https://www.gov.uk/expenses-and-benefits-business-travel-mileage/rules-for-tax")
        }
    }

    private func formatRate(_ value: Double) -> String {
        value == floor(value) ? String(format: "%.0f", value) : String(format: "%.2f", value)
    }

    private func formatCap(_ km: Double) -> String {
        km == floor(km) ? String(format: "%.0f", km) : String(format: "%.1f", km)
    }
}

// MARK: - Standalone Wrapper (for AC5: access from settings without edit mode)

struct RatesListView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            Section {
                RateInfoView(jurisdiction: appState.profileRepo.jurisdiction)
                    .listRowInsets(EdgeInsets(top: MTSpacing.md, leading: MTSpacing.lg, bottom: MTSpacing.md, trailing: MTSpacing.lg))
            }
        }
        .navigationTitle("Mileage Rates")
        .navigationBarTitleDisplayMode(.inline)
    }
}
