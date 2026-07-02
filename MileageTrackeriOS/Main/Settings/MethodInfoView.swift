// MethodInfoView — Informative comparison of claim methods.
// Explains mechanics, record-keeping requirements, and links to tax agency guidance.
// Does NOT give tax advice — just factual descriptions.

import SwiftUI

struct MethodInfoView: View {
    @Environment(AppState.self) private var appState

    private var jurisdiction: Jurisdiction { appState.profileRepo.profile.jurisdiction }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MTSpacing.lg) {
                // Header
                VStack(alignment: .leading, spacing: MTSpacing.sm) {
                    Text("Which method should you choose?")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.mtTextPrimary)
                    Text("The right method depends on how you use your vehicle and what records you keep. This page explains each option — it's not tax advice.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.mtTextSub)
                }

                // Disclaimers
                HStack(alignment: .top, spacing: MTSpacing.sm) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(Color.blue)
                        .font(.system(size: 14))
                    Text("You should consult the official guidance from your tax authority or speak to an accountant before choosing a method.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.mtTextSub)
                }
                .padding(MTSpacing.md)
                .background(Color.blue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: MTRadius.sm))

                // Standard Rate
                methodCard(
                    icon: "chart.bar.fill",
                    color: .mtGreen,
                    title: "Standard Rate",
                    summary: "Claim a fixed cents-per-km rate for business trips. Simple, no odometer readings needed.",
                    details: [
                        "Record the date, reason, and distance of each business trip.",
                        "Your total business kilometres for the year are multiplied by the official rate.",
                        capText,
                        "No logbook period required — you can start immediately.",
                    ],
                    linkText: agencyName + " mileage rates",
                    linkURL: agencyURL
                )

                // Logbook
                methodCard(
                    icon: "book.closed.fill",
                    color: .blue,
                    title: "Logbook",
                    summary: "Keep a 90-day logbook recording every trip. Your business-use percentage is then applied to all driving.",
                    details: [
                        "Record every trip (business and personal) for a continuous 90-day period.",
                        "Record odometer readings at the start and end of the logbook period.",
                        "Your business-use percentage = business km ÷ total km during the logbook period.",
                        "This percentage is applied to all future trips for up to 3 years.",
                        "Best if you do a lot of driving and a high proportion is for business.",
                    ],
                    linkText: agencyName + " logbook requirements",
                    linkURL: agencyLogbookURL
                )

                // Custom Rate
                methodCard(
                    icon: "slider.horizontal.3",
                    color: .orange,
                    title: "Custom Rate",
                    summary: "Set your own cents-per-km rate to match your actual vehicle costs.",
                    details: [
                        "Calculate your per-km cost based on fuel, maintenance, insurance, and depreciation.",
                        "Set tiered rates that decrease as your annual distance increases.",
                        "You must keep records of all vehicle expenses to justify your rate.",
                        "Most appropriate if you have a fleet vehicle or unusual operating costs.",
                    ],
                    linkText: nil,
                    linkURL: nil
                )

                // Per-jurisdiction caveat
                if let caveat = jurisdiction.claimMethodCaveat {
                    jurisdictionCaveatView(caveat)
                }

                Spacer(minLength: MTSpacing.xxl)
            }
            .padding(MTSpacing.lg)
        }
        .navigationTitle("Claim Methods")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.mtBackground)
    }

    // MARK: - Method Card

    private func methodCard(
        icon: String,
        color: Color,
        title: String,
        summary: String,
        details: [String],
        linkText: String?,
        linkURL: URL?
    ) -> some View {
        VStack(alignment: .leading, spacing: MTSpacing.md) {
            HStack(spacing: MTSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(color)
                    .frame(width: 32)
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.mtTextPrimary)
            }

            Text(summary)
                .font(.system(size: 14))
                .foregroundStyle(Color.mtTextSub)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(details, id: \.self) { detail in
                    HStack(alignment: .top, spacing: MTSpacing.sm) {
                        Text("•")
                            .foregroundStyle(color)
                        Text(detail)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.mtTextPrimary)
                    }
                }
            }

            if let linkText, let linkURL {
                Link(destination: linkURL) {
                    HStack(spacing: 4) {
                        Text(linkText)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11))
                    }
                    .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(color)
            }
        }
        .padding(MTSpacing.lg)
        .background(Color.mtSurface)
        .clipShape(RoundedRectangle(cornerRadius: MTRadius.md))
    }

    // MARK: - Jurisdiction Caveat

    /// A highlighted banner showing a per-jurisdiction caveat about claim-method validity.
    /// Only shown for jurisdictions with notable restrictions (CA, ES, NL, ZA, US, GB).
    private func jurisdictionCaveatView(_ caveat: String) -> some View {
        VStack(alignment: .leading, spacing: MTSpacing.sm) {
            Label("Important: " + jurisdiction.displayName, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.orange)

            Text(caveat)
                .font(.system(size: 13))
                .foregroundStyle(Color.mtTextPrimary)
        }
        .padding(MTSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: MTRadius.sm))
    }

    // MARK: - Jurisdiction-specific

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

    private var agencyURL: URL {
        switch jurisdiction {
        case .newZealand:
            return URL(string: "https://www.ird.govt.nz/income-tax/income-tax-for-businesses-and-organisations/types-of-business-expenses/motor-vehicle-expenses/kilometre-rates")!
        case .australia:
            return URL(string: "https://www.ato.gov.au/individuals-and-families/income-deductions-and-concessions/deductions-you-can-claim/transport-and-travel-expenses/car-expenses/cents-per-kilometre-method")!
        case .unitedStates:
            return URL(string: "https://www.irs.gov/tax-professionals/standard-mileage-rates")!
        case .canada:
            return URL(string: "https://www.canada.ca/en/department-finance/news/2026/01/government-announces-the-2026-automobile-deduction-limits-and-expense-benefit-rates-for-businesses.html")!
        case .germany:
            return URL(string: "https://www.gesetze-im-internet.de/brkg_2005/__5.html")!
        case .belgium:
            return URL(string: "https://www.partena-professional.be/fr/nouveau-montant-pour-lindemnite-kilometrique-de-juillet-2026")!
        case .netherlands:
            return URL(string: "https://www.belastingdienst.nl/wps/wcm/connect/bldcontentnl/berichten/nieuws/verhoging-onbelaste-kilometervergoeding-hoe-verwerkt-u-dit-in-de-loonaangifte")!
        case .switzerland:
            return URL(string: "https://law.ch/lawnews/2026/01/autokilometeransatz-regeln-ab-01-01-2026/")!
        case .austria:
            return URL(string: "https://www.bmf.gv.at/themen/steuern/kraftfahrzeuge/kilometergeld.html")!
        case .sweden:
            return URL(string: "https://www.skatteverket.se/privat/skatter/beloppochprocent/2026.4.1522bf3f19aea8075ba21.html")!
        case .norway:
            return URL(string: "https://www.skatteetaten.no/en/rates/car-allowance-distance-based-allowance/")!
        case .denmark:
            return URL(string: "https://sktst.dk/nyheder-og-pressemeddelelser/hoejere-fradrag-til-pendlerne-i-2026")!
        case .finland:
            return URL(string: "https://www.vero.fi/en/About-us/newsroom/news/uutiset/2025/tax-exempt-allowances-in-2026-for-business-travel/")!
        case .spain:
            return URL(string: "https://sede.agenciatributaria.gob.es")!
        case .southAfrica:
            return URL(string: "https://www.sars.gov.za/wp-content/uploads/Docs/PAYE/Tables/tables2026/PAYE-GEN-01-G03-A01-Rate-per-Kilometre-Schedule-External-Annexure.pdf")!
        case .other:
            return URL(string: "https://www.gov.uk/expenses-and-benefits-business-travel-mileage/rules-for-tax")!
        }
    }

    /// Logbook-specific guidance pages weren't researched for the newer jurisdictions (out of scope
    /// for the rates research pass) — fall back to the same general agency page rather than guess a URL.
    private var agencyLogbookURL: URL {
        switch jurisdiction {
        case .newZealand:
            return URL(string: "https://www.ird.govt.nz/income-tax/income-tax-for-businesses-and-organisations/types-of-business-expenses/motor-vehicle-expenses/keeping-a-logbook")!
        case .australia:
            return URL(string: "https://www.ato.gov.au/individuals-and-families/income-deductions-and-concessions/deductions-you-can-claim/transport-and-travel-expenses/car-expenses/logbook-method")!
        case .other:
            return URL(string: "https://www.gov.uk/expenses-and-benefits-business-travel-mileage/rules-for-tax")!
        default:
            return agencyURL
        }
    }

    private var capText: String {
        switch jurisdiction {
        case .newZealand:
            return "NZ rates have a two-tier structure: a higher rate for the first 14,000 km, and a lower rate beyond that."
        case .australia:
            return "The ATO caps claims at 5,000 business kilometres per year."
        case .unitedStates:
            return "The IRS rate is flat — 72.5¢/mile for 2026, with no distance tiers or annual cap."
        case .canada:
            return "CRA rates are tiered: a higher rate for the first 5,000 km, then a lower rate beyond that."
        case .germany:
            return "The BRKG rate is flat — €0.30/km for cars, with no distance tiers or annual cap."
        case .belgium:
            return "Belgium's rate is flat but revised frequently — the figure shown is the most recently published one."
        case .netherlands:
            return "The Belastingdienst rate is flat — €0.25/km, with no distance tiers or annual cap."
        case .switzerland:
            return "The federal rate is flat — CHF 0.75/km, with no distance tiers or annual cap."
        case .austria:
            return "Austria's rate is flat but capped at 30,000 km per year."
        case .sweden:
            return "Skatteverket's rate is flat — 2.50 SEK/km for your own car, with no distance tiers or annual cap."
        case .norway:
            return "Skatteetaten's rate is flat — 3.50 NOK/km, with no distance tiers or annual cap."
        case .denmark:
            return "Danish rates are tiered: a higher rate for the first 20,000 km, then a lower rate beyond that."
        case .finland:
            return "Verohallinto's rate is flat — €0.55/km, with no distance tiers or annual cap."
        case .spain:
            return "The Spanish rate is flat — €0.26/km, with no distance tiers or annual cap."
        case .southAfrica:
            return "This uses SARS's simplified flat rate (495 c/km) — only valid if you receive no other travel allowance besides tolls/parking."
        case .other:
            return "UK rates are 55p/mi for the first 10,000 miles, then 25p/mi beyond that."
        }
    }
}
