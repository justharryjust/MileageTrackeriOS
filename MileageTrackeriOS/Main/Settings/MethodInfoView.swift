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

    // MARK: - Jurisdiction-specific

    private var agencyName: String {
        switch jurisdiction {
        case .newZealand: return "IRD"
        case .australia:  return "ATO"
        case .other:      return "HMRC"
        }
    }

    private var agencyURL: URL {
        switch jurisdiction {
        case .newZealand:
            return URL(string: "https://www.ird.govt.nz/income-tax/income-tax-for-businesses-and-organisations/types-of-business-expenses/motor-vehicle-expenses/kilometre-rates")!
        case .australia:
            return URL(string: "https://www.ato.gov.au/individuals-and-families/income-deductions-and-concessions/deductions-you-can-claim/transport-and-travel-expenses/car-expenses/cents-per-kilometre-method")!
        case .other:
            return URL(string: "https://www.gov.uk/expenses-and-benefits-business-travel-mileage/rules-for-tax")!
        }
    }

    private var agencyLogbookURL: URL {
        switch jurisdiction {
        case .newZealand:
            return URL(string: "https://www.ird.govt.nz/income-tax/income-tax-for-businesses-and-organisations/types-of-business-expenses/motor-vehicle-expenses/keeping-a-logbook")!
        case .australia:
            return URL(string: "https://www.ato.gov.au/individuals-and-families/income-deductions-and-concessions/deductions-you-can-claim/transport-and-travel-expenses/car-expenses/logbook-method")!
        case .other:
            return URL(string: "https://www.gov.uk/expenses-and-benefits-business-travel-mileage/rules-for-tax")!
        }
    }

    private var capText: String {
        switch jurisdiction {
        case .newZealand:
            return "NZ rates have a two-tier structure: a higher rate for the first 14,000 km, and a lower rate beyond that."
        case .australia:
            return "The ATO caps claims at 5,000 business kilometres per year."
        case .other:
            return "UK rates are 45p/mi for the first 10,000 miles, then 25p/mi beyond that."
        }
    }
}
