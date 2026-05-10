// VehicleManagementView — Add, edit, archive vehicles and set the active default.
// Trips are already associated with a vehicleId; this screen makes vehicle management user-facing.

import SwiftUI

struct VehicleManagementView: View {
    @Environment(AppState.self) private var appState

    @State private var showingAddSheet = false
    @State private var editingVehicle: Vehicle?

    private var repo: UserProfileRepository { appState.profileRepo }
    private var activeVehicles: [Vehicle] { repo.vehicles.filter { !$0.isArchived } }
    private var archivedVehicles: [Vehicle] { repo.vehicles.filter { $0.isArchived } }

    var body: some View {
        List {
            // Active vehicles
            Section("Active Vehicles") {
                if activeVehicles.isEmpty {
                    Text("No vehicles added").foregroundStyle(Color.mtTextSub)
                } else {
                    ForEach(activeVehicles) { vehicle in
                        vehicleRow(vehicle)
                    }
                }
            }

            // Archived vehicles
            if !archivedVehicles.isEmpty {
                Section("Archived") {
                    ForEach(archivedVehicles) { vehicle in
                        vehicleRow(vehicle, isArchived: true)
                    }
                }
            }
        }
        .navigationTitle("Vehicles")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAddSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            VehicleFormView(mode: .add) { name, reg, type, fuel in
                repo.addVehicle(name: name, registration: reg, type: type, fuelType: fuel)
                showingAddSheet = false
            }
        }
        .sheet(item: $editingVehicle) { vehicle in
            VehicleFormView(
                mode: .edit(vehicle: vehicle),
                onSave: { name, reg, type, fuel in
                    repo.updateVehicle(vehicle, name: name, registration: reg, type: type, fuelType: fuel)
                    editingVehicle = nil
                }
            )
        }
    }

    // MARK: - Vehicle Row

    private func vehicleRow(_ vehicle: Vehicle, isArchived: Bool = false) -> some View {
        HStack(spacing: MTSpacing.md) {
            // Type icon
            ZStack {
                Circle()
                    .fill(vehicle.isDefault ? Color.mtGreen.opacity(0.15) : Color.mtBorder.opacity(0.3))
                    .frame(width: 40, height: 40)
                Image(systemName: vehicle.type.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(vehicle.isDefault ? Color.mtGreen : Color.mtTextSub)
            }

            // Name + plate
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: MTSpacing.xs) {
                    Text(vehicle.name.isEmpty ? vehicle.registration : vehicle.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isArchived ? Color.mtTextSub : Color.mtTextPrimary)
                    if vehicle.isDefault && !isArchived {
                        Text("Default")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.mtGreen)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.mtGreen.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                Text("\(vehicle.registration) · \(vehicle.fuelType.displayName)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.mtTextSub)
            }

            Spacer()

            // Context menu
            if !isArchived {
                Menu {
                    Button {
                        editingVehicle = vehicle
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }

                    if !vehicle.isDefault {
                        Button {
                            repo.setDefaultVehicle(vehicle)
                        } label: {
                            Label("Set as Default", systemImage: "checkmark.circle")
                        }
                    }

                    Divider()

                    Button(role: .destructive) {
                        repo.archiveVehicle(vehicle)
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.mtTextSub)
                }
                .disabled(isArchived)
            } else {
                Button {
                    repo.unarchiveVehicle(vehicle)
                } label: {
                    Text("Restore")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(Color.mtGreen)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Vehicle Form (Add / Edit)

private struct VehicleFormView: View {
    enum Mode {
        case add
        case edit(vehicle: Vehicle)

        var title: String {
            switch self {
            case .add: return "Add Vehicle"
            case .edit: return "Edit Vehicle"
            }
        }

        var initialName: String {
            if case .edit(let v) = self { return v.name }
            return ""
        }

        var initialReg: String {
            if case .edit(let v) = self { return v.registration }
            return ""
        }

        var initialType: VehicleType {
            if case .edit(let v) = self { return v.type }
            return .car
        }

        var initialFuel: FuelType {
            if case .edit(let v) = self { return v.fuelType }
            return .petrol
        }
    }

    let mode: Mode
    let onSave: (String, String, VehicleType, FuelType) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var registration: String
    @State private var vehicleType: VehicleType
    @State private var fuelType: FuelType

    init(mode: Mode, onSave: @escaping (String, String, VehicleType, FuelType) -> Void) {
        self.mode = mode
        self.onSave = onSave
        _name = State(initialValue: mode.initialName)
        _registration = State(initialValue: mode.initialReg)
        _vehicleType = State(initialValue: mode.initialType)
        _fuelType = State(initialValue: mode.initialFuel)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name (optional)", text: $name)
                    TextField("Number Plate", text: $registration)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }

                Section("Type") {
                    Picker("Vehicle Type", selection: $vehicleType) {
                        ForEach(VehicleType.allCases, id: \.self) { t in
                            Label(t.displayName, systemImage: t.icon).tag(t)
                        }
                    }

                    Picker("Fuel / Energy", selection: $fuelType) {
                        ForEach(FuelType.allCases, id: \.self) { f in
                            Text(f.displayName).tag(f)
                        }
                    }
                }

                Section {
                    Button("Save") {
                        onSave(
                            name.trimmingCharacters(in: .whitespaces),
                            registration.trimmingCharacters(in: .whitespaces),
                            vehicleType,
                            fuelType
                        )
                    }
                    .buttonStyle(MTPrimaryButtonStyle())
                    .disabled(registration.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
