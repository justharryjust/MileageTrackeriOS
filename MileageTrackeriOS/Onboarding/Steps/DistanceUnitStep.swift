import SwiftUI

struct DistanceUnitStep: View {
    @Bindable var vm: OnboardingViewModel

    var body: some View {
        OnboardingStepShell(
            icon: "ruler.fill",
            iconColor: .mtGreen,
            title: "Distance unit",
            subtitle: "How do you measure distance? This affects how trips and rates are displayed."
        ) {
            VStack(spacing: MTSpacing.md) {
                ForEach(DistanceUnit.allCases, id: \.self) { unit in
                    DistanceUnitCard(
                        unit: unit,
                        isSelected: vm.distanceUnit == unit,
                        onTap: { vm.distanceUnit = unit }
                    )
                }
            }

            Spacer(minLength: MTSpacing.xl)

            Button("Continue") { vm.advance() }
                .buttonStyle(MTPrimaryButtonStyle())
        }
    }
}

private struct DistanceUnitCard: View {
    let unit: DistanceUnit
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: MTSpacing.md) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.mtGreen : Color.mtBorder.opacity(0.3))
                        .frame(width: 52, height: 52)
                    Image(systemName: unit.icon)
                        .font(.system(size: 24))
                        .foregroundStyle(isSelected ? .white : Color.mtTextSub)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(unit.displayName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.mtTextPrimary)
                    Text(unit.shortName)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.mtTextSub)
                }

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
