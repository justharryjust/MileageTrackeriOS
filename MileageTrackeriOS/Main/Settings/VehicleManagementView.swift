// VehicleManagementView — Add, edit, archive vehicles and set the active default.
// Trips are already associated with a vehicleId; this screen makes vehicle management user-facing.

import SwiftUI

struct VehicleManagementView: View {
    @Environment(AppState.self) private var appState

    @State private var showingAddSheet = false
    @State private var editingVehicle: Vehicle?
    @State private var vehicleToDelete: Vehicle?
    @State private var showArchiveConfirmation: Vehicle?
    @State private var vehicleTripCounts: [String: Int] = [:]

    private var repo: UserProfileRepository { appState.profileRepo }
    private var activeVehicles: [Vehicle] { repo.vehicles }
    private var archivedVehicles: [Vehicle] { repo.allVehicles.filter { $0.isArchived } }

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
            VehicleFormView(mode: .add) { name, reg, type, fuel, _ in
                repo.addVehicle(name: name, registration: reg, type: type, fuelType: fuel)
                showingAddSheet = false
            }
        }
        .sheet(item: $editingVehicle) { vehicle in
            VehicleFormView(
                mode: .edit(vehicle: vehicle),
                onSave: { name, reg, type, fuel, category in
                    repo.updateVehicle(vehicle, name: name, registration: reg, type: type, fuelType: fuel)
                    if category != vehicle.defaultCategory {
                        repo.setVehicleDefaultCategory(vehicle, category)
                    }
                    editingVehicle = nil
                }
            )
        }
        .onAppear {
            loadTripCounts()
        }
        .confirmationDialog(
            "Delete Vehicle",
            isPresented: Binding(
                get: { vehicleToDelete != nil },
                set: { if !$0 { vehicleToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let vehicle = vehicleToDelete {
                let count = vehicleTripCounts[vehicle.id] ?? 0
                if count > 0 {
                    Text("This will also delete \(count) trip\(count == 1 ? "" : "s") associated with this vehicle.")
                }
                Button("Delete", role: .destructive) {
                    confirmDelete(vehicle)
                }
                Button("Cancel", role: .cancel) {
                    vehicleToDelete = nil
                }
            }
        } message: {
            if let vehicle = vehicleToDelete {
                let count = vehicleTripCounts[vehicle.id] ?? 0
                if count > 0 {
                    Text("This will also delete \(count) trip\(count == 1 ? "" : "s") associated with this vehicle. This action cannot be undone.")
                } else {
                    Text("This action cannot be undone.")
                }
            }
        }
        .confirmationDialog(
            "Archive Vehicle",
            isPresented: Binding(
                get: { showArchiveConfirmation != nil },
                set: { if !$0 { showArchiveConfirmation = nil } }
            ),
            titleVisibility: .visible
        ) {
            Text("Archive")
            Button("Archive", role: .destructive) {
                if let vehicle = showArchiveConfirmation {
                    repo.archiveVehicle(vehicle)
                }
                showArchiveConfirmation = nil
            }
            Button("Cancel", role: .cancel) {
                showArchiveConfirmation = nil
            }
        } message: {
            if let vehicle = showArchiveConfirmation {
                Text("Archive \(vehicle.name.isEmpty ? vehicle.registration : vehicle.name)? The vehicle will be hidden from the active list but its trips will be preserved.")
            }
        }
    }

    // MARK: - Helpers

    private func loadTripCounts() {
        var counts: [String: Int] = [:]
        for vehicle in repo.allVehicles {
            counts[vehicle.id] = appState.tripRepo.trips(for: vehicle.id).count
        }
        vehicleTripCounts = counts
    }

    private func confirmDelete(_ vehicle: Vehicle) {
        repo.deleteVehicle(vehicle, tripRepo: appState.tripRepo)
        vehicleToDelete = nil
        // Refresh trip counts after deletion
        loadTripCounts()
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

            // Name + plate + trip count
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
                HStack(spacing: MTSpacing.xs) {
                    Text("\(vehicle.registration) · \(vehicle.fuelType.displayName)")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.mtTextSub)
                    if let count = vehicleTripCounts[vehicle.id], count > 0 {
                        Text("· \(count) trip\(count == 1 ? "" : "s")")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.mtTextSub)
                    }
                }
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
                        showArchiveConfirmation = vehicle
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.mtTextSub)
                }
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
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                let count = vehicleTripCounts[vehicle.id] ?? 0
                if count > 0 {
                    vehicleToDelete = vehicle
                } else {
                    confirmDelete(vehicle)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
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

        var initialCategory: TripCategory {
            if case .edit(let v) = self { return v.defaultCategory }
            return .uncategorised
        }
    }

    let mode: Mode
    let onSave: (String, String, VehicleType, FuelType, TripCategory) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var registration: String
    @State private var vehicleType: VehicleType
    @State private var fuelType: FuelType
    @State private var defaultCategory: TripCategory

    init(mode: Mode, onSave: @escaping (String, String, VehicleType, FuelType, TripCategory) -> Void) {
        self.mode = mode
        self.onSave = onSave
        _name = State(initialValue: mode.initialName)
        _registration = State(initialValue: mode.initialReg)
        _vehicleType = State(initialValue: mode.initialType)
        _fuelType = State(initialValue: mode.initialFuel)
        _defaultCategory = State(initialValue: mode.initialCategory)
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

                Section("Default Trip Category") {
                    Picker("Default Category", selection: $defaultCategory) {
                        Text("Business").tag(TripCategory.business)
                        Text("Personal").tag(TripCategory.personal)
                        Text("Uncategorised").tag(TripCategory.uncategorised)
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    Button("Save") {
                        onSave(
                            name.trimmingCharacters(in: .whitespaces),
                            registration.trimmingCharacters(in: .whitespaces),
                            vehicleType,
                            fuelType,
                            defaultCategory
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
