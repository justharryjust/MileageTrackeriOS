import SwiftUI

struct ClaimMethodStep: View {
    @Bindable var vm: OnboardingViewModel

    var body: some View {
        OnboardingStepShell(
            icon: "chart.bar.doc.horizontal.fill",
            iconColor: .blue,
            title: "How do you claim?",
            subtitle: "Choose your claim method. You can change this later in Settings."
        ) {
            VStack(spacing: MTSpacing.md) {
                ForEach(ClaimMethod.allCases, id: \.self) { method in
                    ClaimMethodCard(
                        method: method,
                        isSelected: vm.claimMethod == method,
                        onTap: { vm.claimMethod = method }
                    )
                }

                // Expanded custom rate editor
                if vm.claimMethod == .customRate {
                    CustomRateEditor(vm: vm)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: vm.claimMethod)

            Spacer(minLength: MTSpacing.xl)

            Button("Continue") { vm.advance() }
                .buttonStyle(MTPrimaryButtonStyle())
        }
    }
}

// MARK: - Custom Rate Editor

private struct CustomRateEditor: View {
    @Bindable var vm: OnboardingViewModel

    private var unit: String { vm.distanceUnit.shortName }

    var body: some View {
        VStack(alignment: .leading, spacing: MTSpacing.md) {
            Text("Custom Rate Details")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.mtTextSub)

            // Distance range row
            HStack(spacing: MTSpacing.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("From (\(unit))").font(.system(size: 12)).foregroundStyle(Color.mtTextSub)
                    HStack {
                        Button { if vm.customRateLowerBound > 0 { vm.customRateLowerBound -= 100 } } label: {
                            Image(systemName: "minus").frame(width: 28, height: 28)
                        }
                        Text("\(vm.customRateLowerBound)")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(minWidth: 44)
                            .multilineTextAlignment(.center)
                        Button { if vm.customRateLowerBound < vm.customRateUpperBound - 100 { vm.customRateLowerBound += 100 } } label: {
                            Image(systemName: "plus").frame(width: 28, height: 28)
                        }
                    }
                    .foregroundStyle(Color.mtTextPrimary)
                    .padding(.horizontal, MTSpacing.sm)
                    .padding(.vertical, 6)
                    .background(Color.mtSurface)
                    .clipShape(RoundedRectangle(cornerRadius: MTRadius.sm))
                    .overlay(RoundedRectangle(cornerRadius: MTRadius.sm).strokeBorder(Color.mtBorder, lineWidth: 1))
                }

                Image(systemName: "arrow.right")
                    .foregroundStyle(Color.mtTextSub)
                    .padding(.top, 20)

                VStack(alignment: .leading, spacing: 4) {
                    Text("To (\(unit))").font(.system(size: 12)).foregroundStyle(Color.mtTextSub)
                    HStack {
                        Button { if vm.customRateUpperBound > vm.customRateLowerBound + 100 { vm.customRateUpperBound -= 100 } } label: {
                            Image(systemName: "minus").frame(width: 28, height: 28)
                        }
                        Text("\(vm.customRateUpperBound)")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(minWidth: 44)
                            .multilineTextAlignment(.center)
                        Button { vm.customRateUpperBound += 100 } label: {
                            Image(systemName: "plus").frame(width: 28, height: 28)
                        }
                    }
                    .foregroundStyle(Color.mtTextPrimary)
                    .padding(.horizontal, MTSpacing.sm)
                    .padding(.vertical, 6)
                    .background(Color.mtSurface)
                    .clipShape(RoundedRectangle(cornerRadius: MTRadius.sm))
                    .overlay(RoundedRectangle(cornerRadius: MTRadius.sm).strokeBorder(Color.mtBorder, lineWidth: 1))
                }
            }

            // Cents per unit row
            VStack(alignment: .leading, spacing: 4) {
                Text("Rate (cents per \(unit))").font(.system(size: 12)).foregroundStyle(Color.mtTextSub)
                HStack {
                    Button { if vm.customRateCents > 1 { vm.customRateCents -= 1 } } label: {
                        Image(systemName: "minus").frame(width: 36, height: 36)
                    }
                    Spacer()
                    Text(String(format: "%.0f¢ / \(unit)", vm.customRateCents))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.mtGreen)
                    Spacer()
                    Button { vm.customRateCents += 1 } label: {
                        Image(systemName: "plus").frame(width: 36, height: 36)
                    }
                }
                .foregroundStyle(Color.mtTextPrimary)
                .padding(.horizontal, MTSpacing.sm)
                .padding(.vertical, 8)
                .background(Color.mtSurface)
                .clipShape(RoundedRectangle(cornerRadius: MTRadius.sm))
                .overlay(RoundedRectangle(cornerRadius: MTRadius.sm).strokeBorder(Color.mtGreen.opacity(0.4), lineWidth: 1))

                Slider(value: $vm.customRateCents, in: 1...200, step: 1)
                    .tint(Color.mtGreen)
            }

            Text("\(vm.customRateLowerBound)–\(vm.customRateUpperBound) \(unit) at \(String(format: "%.0f", vm.customRateCents))¢ per \(unit)")
                .font(.system(size: 13))
                .foregroundStyle(Color.mtTextSub)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(MTSpacing.md)
        .background(Color.mtSurface)
        .clipShape(RoundedRectangle(cornerRadius: MTRadius.md))
        .overlay(RoundedRectangle(cornerRadius: MTRadius.md).strokeBorder(Color.mtGreen.opacity(0.3), lineWidth: 1))
    }
}

// MARK: - Claim Method Card

private struct ClaimMethodCard: View {
    let method: ClaimMethod
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: MTSpacing.md) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.mtGreen : Color.mtBorder.opacity(0.3))
                        .frame(width: 44, height: 44)
                    Image(systemName: method.icon)
                        .font(.system(size: 20))
                        .foregroundStyle(isSelected ? .white : Color.mtTextSub)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(method.displayName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.mtTextPrimary)
                    Text(method.claimDescription)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.mtTextSub)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.mtGreen)
                        .padding(.top, 2)
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
