import SwiftUI

struct JurisdictionStep: View {
    @Bindable var vm: OnboardingViewModel

    var body: some View {
        OnboardingStepShell(
            icon: "globe.asia.australia.fill",
            iconColor: .mtGreen,
            title: "Where are you based?",
            subtitle: "Sets the mileage rates used for your expense claims.",
            contentScrolls: true
        ) {
            VStack(spacing: MTSpacing.sm) {
                ForEach(Jurisdiction.allCases, id: \.rawValue) { j in
                    RegionCard(
                        flag: j.flag,
                        name: j.displayName,
                        isSelected: j == .other
                            ? Jurisdiction(rawValue: vm.regionCode) == nil
                            : vm.regionCode == j.rawValue,
                        onTap: { vm.regionCode = j.rawValue }
                    )
                }
            }

            Spacer(minLength: MTSpacing.xl)

            Button("Continue") { vm.advance() }
                .buttonStyle(MTPrimaryButtonStyle())
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
