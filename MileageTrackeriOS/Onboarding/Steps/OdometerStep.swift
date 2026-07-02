import SwiftUI

struct OdometerStep: View {
    @Bindable var vm: OnboardingViewModel

    var body: some View {
        OnboardingStepShell(
            icon: "speedometer",
            iconColor: .orange,
            title: "Initial Odometer Reading",
            subtitle: vm.claimMethod == .logbook
                ? "Enter your vehicle's current odometer reading. Required for logbook tracking."
                : "Optionally enter your starting odometer reading. You can add one later."
        ) {
            VStack(spacing: MTSpacing.md) {
                // Odometer input
                VStack(alignment: .leading, spacing: MTSpacing.xs) {
                    HStack {
                        Label("Odometer Reading (\(vm.distanceUnit.shortName))", systemImage: "speedometer")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.mtTextSub)
                        if vm.claimMethod == .logbook {
                            Text("Required")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.mtGreen)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.mtGreen.opacity(0.12))
                                .clipShape(Capsule())
                        } else {
                            Text("Optional")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.mtTextSub)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.mtBorder.opacity(0.4))
                                .clipShape(Capsule())
                        }
                    }

                    TextField("e.g. 45200", text: $vm.initialOdometerKm)
                        .keyboardType(.decimalPad)
                        .fieldStyle()

                    Text("Record your vehicle's current odometer reading. You can update this later in Settings.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.mtTextSub)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if vm.claimMethod == .logbook {
                    LogbookOdometerTip()
                }
            }

            Spacer(minLength: MTSpacing.xl)

            Button("Continue") { vm.advance() }
                .buttonStyle(MTPrimaryButtonStyle())
                .disabled(vm.claimMethod == .logbook && vm.initialOdometerKm.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(vm.claimMethod == .logbook && vm.initialOdometerKm.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
        }
    }
}

// MARK: - Logbook Tip

private struct LogbookOdometerTip: View {
    var body: some View {
        VStack(alignment: .leading, spacing: MTSpacing.sm) {
            Label("Why this matters", systemImage: "info.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.mtTextSub)

            Text("With the logbook method, the difference between odometer readings determines your total kilometres. The app uses this to calculate your business-use percentage — essential for a defensible claim.")
                .font(.system(size: 12))
                .foregroundStyle(Color.mtTextSub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(MTSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mtSurface)
        .clipShape(RoundedRectangle(cornerRadius: MTRadius.md))
        .overlay(RoundedRectangle(cornerRadius: MTRadius.md).strokeBorder(Color.orange.opacity(0.3), lineWidth: 1))
    }
}

// MARK: - Field Style

private extension View {
    func fieldStyle() -> some View {
        self
            .padding(MTSpacing.sm + 4)
            .background(Color.mtSurface)
            .clipShape(RoundedRectangle(cornerRadius: MTRadius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: MTRadius.sm)
                    .strokeBorder(Color.mtBorder, lineWidth: 1)
            )
    }
}
