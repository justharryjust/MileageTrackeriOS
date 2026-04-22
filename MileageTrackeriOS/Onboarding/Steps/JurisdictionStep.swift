import SwiftUI

struct JurisdictionStep: View {
    @Bindable var vm: OnboardingViewModel

    var body: some View {
        OnboardingStepShell(
            icon: "globe.asia.australia.fill",
            iconColor: .mtGreen,
            title: "Where are you based?",
            subtitle: "We've pre-selected based on your device region. This sets the applicable mileage rates for your expense claims."
        ) {
            VStack(spacing: MTSpacing.md) {
                ForEach(Jurisdiction.allCases, id: \.self) { j in
                    JurisdictionCard(
                        jurisdiction: j,
                        isSelected: vm.jurisdiction == j,
                        onTap: { vm.jurisdiction = j }
                    )
                }
            }

            Spacer(minLength: MTSpacing.xl)

            Button("Continue") { vm.advance() }
                .buttonStyle(MTPrimaryButtonStyle())
        }
    }
}

private struct JurisdictionCard: View {
    let jurisdiction: Jurisdiction
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: MTSpacing.md) {
                Text(jurisdiction.flag)
                    .font(.system(size: 36))

                Text(jurisdiction.displayName)
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
            .background(
                RoundedRectangle(cornerRadius: MTRadius.md)
                    .strokeBorder(isSelected ? Color.mtGreen : Color.mtBorder, lineWidth: isSelected ? 2 : 1)
                    .background(Color.mtSurface.clipShape(RoundedRectangle(cornerRadius: MTRadius.md)))
            )
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}
