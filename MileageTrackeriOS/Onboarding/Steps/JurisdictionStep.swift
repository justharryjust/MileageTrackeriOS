import SwiftUI

struct JurisdictionStep: View {
    @Bindable var vm: OnboardingViewModel

    private let options: [(code: String, name: String, flag: String)] = [
        ("NZ", "New Zealand", "🇳🇿"),
        ("AU", "Australia",   "🇦🇺"),
        ("--", "Other",       "🌍"),
    ]

    var body: some View {
        OnboardingStepShell(
            icon: "globe.asia.australia.fill",
            iconColor: .mtGreen,
            title: "Where are you based?",
            subtitle: "Sets the mileage rates used for your expense claims."
        ) {
            VStack(spacing: MTSpacing.sm) {
                ForEach(options, id: \.code) { option in
                    RegionCard(
                        flag: option.flag,
                        name: option.name,
                        isSelected: vm.regionCode == option.code
                            || (option.code == "--" && !["NZ", "AU"].contains(vm.regionCode)),
                        onTap: {
                            vm.regionCode = option.code
                            vm.hasTappedRegion = true
                        }
                    )
                }
            }

            Spacer(minLength: MTSpacing.xl)

            Button("Continue") { vm.advance() }
                .buttonStyle(MTPrimaryButtonStyle())
                .disabled(!vm.isJurisdictionValid)
                .opacity(vm.isJurisdictionValid ? 1 : 0.5)
        }
    }
}

private struct RegionCard: View {
    let flag: String
    let name: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: MTSpacing.md) {
                Text(flag)
                    .font(.system(size: 32))

                Text(name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.mtTextPrimary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.mtGreen)
                }
            }
            .padding(MTSpacing.md)
            .background(Color.mtSurface)
            .clipShape(RoundedRectangle(cornerRadius: MTRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: MTRadius.md)
                    .strokeBorder(isSelected ? Color.mtGreen : Color.mtBorder, lineWidth: isSelected ? 2 : 1)
            )
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}
