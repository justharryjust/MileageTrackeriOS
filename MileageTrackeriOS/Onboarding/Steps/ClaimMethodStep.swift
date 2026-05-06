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

                // Logbook — capture initial odometer reading
                if vm.claimMethod == .logbook {
                    VStack(alignment: .leading, spacing: MTSpacing.sm) {
                        Label("Initial Odometer Reading", systemImage: "speedometer")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.mtTextSub)
                        TextField("e.g. 45200", text: $vm.initialOdometerKm)
                            .keyboardType(.decimalPad)
                            .padding(MTSpacing.sm + 4)
                            .background(Color.mtSurface)
                            .clipShape(RoundedRectangle(cornerRadius: MTRadius.sm))
                            .overlay(
                                RoundedRectangle(cornerRadius: MTRadius.sm)
                                    .strokeBorder(Color.mtBorder, lineWidth: 1)
                            )
                        Text("Record your vehicle's current odometer reading. You'll update this periodically — the difference between readings gives your total kilometres for the logbook period.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.mtTextSub)
                    }
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

    let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: MTSpacing.md) {
            Text("Custom Rate Details")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.mtTextSub)

            Picker("Unit", selection: $vm.distanceUnit) {
                ForEach(DistanceUnit.allCases, id: \.self) { unit in
                    Text(unit.displayName).tag(unit)
                }
            }
            .pickerStyle(.segmented)

            ForEach(Array(vm.customRateTiers.enumerated()), id: \.element.id) { idx, _ in
                TierRow(
                    tier: $vm.customRateTiers[idx],
                    index: idx,
                    unit: unit,
                    formatter: formatter,
                    canDelete: vm.customRateTiers.count > 1,
                    onDelete: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            vm.customRateTiers.remove(at: idx)
                            for i in idx..<vm.customRateTiers.count {
                                vm.customRateTiers[i].lowerBound = i == 0 ? 0 : vm.customRateTiers[i - 1].upperBound
                            }
                        }
                    }
                )
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    let last = vm.customRateTiers[vm.customRateTiers.count - 1]
                    vm.customRateTiers.append(CustomRateTier(
                        lowerBound: last.upperBound,
                        upperBound: last.upperBound + 5000,
                        centsPerUnit: last.centsPerUnit
                    ))
                }
            } label: {
                Label("Add another tier", systemImage: "plus.circle.fill")
            }
            .buttonStyle(MTSecondaryButtonStyle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Tier Rate Summary")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.mtTextSub)
                ForEach(vm.customRateTiers) { tier in
                    Text("• \(tier.lowerBound)–\(tier.upperBound) \(unit) @ \(String(format: "%.0f", tier.centsPerUnit))¢/\(unit)")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.mtTextSub)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(MTSpacing.md)
        .background(Color.mtSurface)
        .clipShape(RoundedRectangle(cornerRadius: MTRadius.md))
        .overlay(RoundedRectangle(cornerRadius: MTRadius.md).strokeBorder(Color.mtGreen.opacity(0.3), lineWidth: 1))
    }
}

// MARK: - Tier Row

private struct TierRow: View {
    @Binding var tier: CustomRateTier
    let index: Int
    let unit: String
    let formatter: NumberFormatter
    let canDelete: Bool
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MTSpacing.sm) {
            HStack {
                Text("Tier \(index + 1)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.mtTextSub)
                Spacer()
                if canDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundStyle(.red.opacity(0.8))
                    }
                }
            }

            HStack(spacing: MTSpacing.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("From (\(unit))").font(.system(size: 12)).foregroundStyle(Color.mtTextSub)
                    InputHStack {
                        HStack {
                            if index == 0 {
                                Text("\(tier.lowerBound)")
                                    .font(.system(size: 16, weight: .semibold))
                                    .frame(minWidth: 44)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(Color.mtTextSub)
                            } else {
                                TextField("", value: $tier.lowerBound, formatter: formatter)
                                    .font(.system(size: 16, weight: .semibold))
                                    .frame(minWidth: 44)
                                    .multilineTextAlignment(.center)
                                    .keyboardType(.numberPad)
                            }
                        }
                    }
                }

                Image(systemName: "arrow.right")
                    .foregroundStyle(Color.mtTextSub)
                    .padding(.top, 20)

                VStack(alignment: .leading, spacing: 4) {
                    Text("To (\(unit.capitalized))").font(.system(size: 12)).foregroundStyle(Color.mtTextSub)
                    InputHStack {
                        TextField("", value: $tier.upperBound, formatter: formatter)
                            .font(.system(size: 16, weight: .semibold))
                            .frame(minWidth: 44)
                            .multilineTextAlignment(.center)
                            .keyboardType(.numberPad)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Rate (cents per \(unit))").font(.system(size: 12)).foregroundStyle(Color.mtTextSub)
                HStack {
                    Button { if tier.centsPerUnit > 1 { tier.centsPerUnit -= 1 } } label: {
                        Image(systemName: "minus").frame(width: 36, height: 36)
                    }
                    Spacer()
                    Text(String(format: "%.0f¢ / \(unit)", tier.centsPerUnit))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.mtGreen)
                    Spacer()
                    Button { tier.centsPerUnit += 1 } label: {
                        Image(systemName: "plus").frame(width: 36, height: 36)
                    }
                }
                .foregroundStyle(Color.mtTextPrimary)
                .padding(.horizontal, MTSpacing.sm)
                .padding(.vertical, 8)
                .background(Color.mtSurface)
                .clipShape(RoundedRectangle(cornerRadius: MTRadius.sm))
                .overlay(RoundedRectangle(cornerRadius: MTRadius.sm).strokeBorder(Color.mtGreen.opacity(0.4), lineWidth: 1))

                Slider(value: $tier.centsPerUnit, in: 1...200, step: 1)
                    .tint(Color.mtGreen)
            }
        }
        .padding(MTSpacing.sm)
        .background(Color.mtBackground)
        .clipShape(RoundedRectangle(cornerRadius: MTRadius.sm))
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
                        .multilineTextAlignment(.leading)
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

struct InputHStack<Content: View>: View {
    var content: () -> Content
    
    var body: some View {
        HStack {
            content()
        }
        .foregroundStyle(Color.mtTextPrimary)
        .padding(.horizontal, MTSpacing.sm)
        .padding(.vertical, 6)
        .background(Color.mtSurface)
        .clipShape(RoundedRectangle(cornerRadius: MTRadius.sm))
        .overlay(RoundedRectangle(cornerRadius: MTRadius.sm).strokeBorder(Color.mtBorder, lineWidth: 1))
    }
}

#Preview {
    CustomRateEditor(vm: OnboardingViewModel())
}
