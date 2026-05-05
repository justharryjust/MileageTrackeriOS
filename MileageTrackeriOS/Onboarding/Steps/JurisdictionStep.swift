import SwiftUI

struct JurisdictionStep: View {
    @Bindable var vm: OnboardingViewModel
    @State private var searchText = ""

    private var allCountries: [(code: String, name: String)] {
        Locale.Region.isoRegions
            .filter { $0.identifier.count == 2 }
            .compactMap { region in
                guard let name = Locale.current.localizedString(forRegionCode: region.identifier) else { return nil }
                return (code: region.identifier, name: name)
            }
            .sorted { $0.name < $1.name }
    }

    private var filteredCountries: [(code: String, name: String)] {
        guard !searchText.isEmpty else { return allCountries }
        let q = searchText.lowercased()
        return allCountries.filter { $0.name.lowercased().contains(q) || $0.code.lowercased() == q }
    }

    var body: some View {
        OnboardingStepShell(
            icon: "globe.asia.australia.fill",
            iconColor: .mtGreen,
            title: "Where are you based?",
            subtitle: "Sets the applicable mileage rates for your expense claims."
        ) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.mtTextSub)
                TextField("Search country", text: $searchText)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Color.mtTextSub)
                    }
                }
            }
            .padding(MTSpacing.sm + 2)
            .background(Color.mtSurface)
            .clipShape(RoundedRectangle(cornerRadius: MTRadius.sm))
            .overlay(RoundedRectangle(cornerRadius: MTRadius.sm).strokeBorder(Color.mtBorder, lineWidth: 1))

            LazyVStack(spacing: 0) {
                ForEach(filteredCountries, id: \.code) { country in
                    CountryRow(
                        code: country.code,
                        name: country.name,
                        isSelected: vm.regionCode == country.code,
                        onTap: { vm.regionCode = country.code }
                    )
                    if country.code != filteredCountries.last?.code {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .background(Color.mtSurface)
            .clipShape(RoundedRectangle(cornerRadius: MTRadius.md))
            .overlay(RoundedRectangle(cornerRadius: MTRadius.md).strokeBorder(Color.mtBorder, lineWidth: 1))

            Spacer(minLength: MTSpacing.xl)

            Button("Continue") { vm.advance() }
                .buttonStyle(MTPrimaryButtonStyle())
        }
    }
}

private struct CountryRow: View {
    let code: String
    let name: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: MTSpacing.md) {
                Text(flagEmoji(for: code))
                    .font(.system(size: 24))
                    .frame(width: 36)
                Text(name)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.mtTextPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.mtGreen)
                }
            }
            .padding(.horizontal, MTSpacing.md)
            .padding(.vertical, MTSpacing.sm + 2)
        }
        .animation(.easeInOut(duration: 0.1), value: isSelected)
    }

    private func flagEmoji(for code: String) -> String {
        code.unicodeScalars
            .compactMap { Unicode.Scalar($0.value + 127397) }
            .map(String.init)
            .joined()
    }
}
