import SwiftUI

struct AddVehicleStep: View {
    @Bindable var vm: OnboardingViewModel

    var body: some View {
        OnboardingStepShell(
            icon: "car.fill",
            iconColor: .mtGreen,
            title: "Add your vehicle",
            subtitle: "Your first vehicle. You can add more in Settings at any time."
        ) {
            VStack(spacing: MTSpacing.md) {
                // Number plate (required)
                VStack(alignment: .leading, spacing: MTSpacing.xs) {
                    HStack {
                        Label("Number Plate", systemImage: "number.square")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.mtTextSub)
                        Text("Required")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.mtGreen)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.mtGreen.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    TextField("e.g. ABC123", text: $vm.vehicleRegistration)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .fieldStyle()
                }

                // Name (optional)
                VStack(alignment: .leading, spacing: MTSpacing.xs) {
                    HStack {
                        Label("Vehicle Name", systemImage: "textformat")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.mtTextSub)
                        Text("Optional")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.mtTextSub)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.mtBorder.opacity(0.4))
                            .clipShape(Capsule())
                    }
                    TextField("e.g. My Ute", text: $vm.vehicleName)
                        .fieldStyle()
                }

                // Fuel Type
                VStack(alignment: .leading, spacing: MTSpacing.xs) {
                    Label("Fuel / Energy", systemImage: "fuelpump.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.mtTextSub)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: MTSpacing.sm) {
                        ForEach(FuelType.allCases, id: \.self) { f in
                            TypeChip(label: f.displayName, isSelected: vm.fuelType == f) {
                                vm.fuelType = f
                            }
                        }
                    }
                }
            }

            Spacer(minLength: MTSpacing.xl)

            Button("Continue") { vm.advance() }
                .buttonStyle(MTPrimaryButtonStyle())
                .disabled(!vm.isVehicleValid)
                .opacity(vm.isVehicleValid ? 1 : 0.5)
        }
    }
}

// MARK: - Chip

private struct TypeChip: View {
    let label: String
    var icon: String?
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 12))
                }
                Text(label).font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(isSelected ? .white : Color.mtTextPrimary)
            .padding(.horizontal, MTSpacing.sm)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.mtGreen : Color.mtSurface)
            .clipShape(RoundedRectangle(cornerRadius: MTRadius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: MTRadius.sm)
                    .strokeBorder(isSelected ? Color.clear : Color.mtBorder, lineWidth: 1)
            )
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
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
