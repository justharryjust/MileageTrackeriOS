// SavedAddressEditSheet — Add or edit a SavedAddress entry.
//
// Fields:
//   • Label (free text, required)            "Home" / "Office" / "Client X"
//   • Address (via AddressSearchScreen)       coordinates auto-resolved
//   • Icon picker (SF Symbol grid)            visual differentiation
//   • Role toggles (Home / Work, mutually exclusive)
//   • Default category (only shown when neither role flag is on)
//
// Home and Work are toggles, not pickers: only one of each can exist at a time,
// enforced in SavedAddressRepository.

import SwiftUI
import MapKit
import CoreLocation

enum SavedAddressEditMode {
    case add
    case edit(SavedAddress)
}

struct SavedAddressEditSheet: View {
    let mode: SavedAddressEditMode

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var label: String                  = ""
    @State private var addressResult: AddressResult?  = nil
    @State private var fullAddress: String            = ""
    @State private var isShowingAddressSearch         = false
    @State private var isHome: Bool                   = false
    @State private var isWork: Bool                   = false
    @State private var defaultCategory: TripCategory  = .uncategorised
    @State private var icon: String                   = "mappin.circle.fill"

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var canSave: Bool {
        !label.trimmingCharacters(in: .whitespaces).isEmpty && !fullAddress.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Label") {
                    TextField("e.g. Home, Office, Client X", text: $label)
                        .autocorrectionDisabled()
                }

                Section("Address") {
                    Button {
                        isShowingAddressSearch = true
                    } label: {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(Color.mtGreen)
                            VStack(alignment: .leading, spacing: 2) {
                                if fullAddress.isEmpty {
                                    Text("Search for an address")
                                        .foregroundStyle(Color.mtTextSub)
                                } else {
                                    Text(fullAddress)
                                        .foregroundStyle(Color.mtTextPrimary)
                                        .lineLimit(3)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.mtBorder)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    Toggle(isOn: $isHome) {
                        Label("Mark as Home", systemImage: "house.fill")
                    }
                    .tint(Color.mtGreen)
                    .onChange(of: isHome) { _, newValue in
                        if newValue {
                            isWork = false
                            icon = "house.fill"
                        } else if icon == "house.fill" {
                            icon = "mappin.circle.fill"
                        }
                    }

                    Toggle(isOn: $isWork) {
                        Label("Mark as Work", systemImage: "briefcase.fill")
                    }
                    .tint(Color.blue)
                    .onChange(of: isWork) { _, newValue in
                        if newValue {
                            isHome = false
                            icon = "briefcase.fill"
                        } else if icon == "briefcase.fill" {
                            icon = "mappin.circle.fill"
                        }
                    }
                } header: {
                    Text("Role")
                } footer: {
                    if isHome || isWork {
                        Text("Trips between Home and Work will be auto-categorised as Personal (commute is not claimable under IRD/ATO rules).")
                            .font(.system(size: 12))
                    }
                }

                // Hide explicit category picker when a role flag is set —
                // Home/Work imply personal commute when paired.
                if !isHome && !isWork {
                    Section {
                        Picker("Default category", selection: $defaultCategory) {
                            Text("None").tag(TripCategory.uncategorised)
                            Text("Business").tag(TripCategory.business)
                            Text("Personal").tag(TripCategory.personal)
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text("Auto-categorise")
                    } footer: {
                        Text("Trips ending here will be auto-categorised. Set to None to skip auto-categorisation for this place.")
                            .font(.system(size: 12))
                    }
                }

                Section("Icon") {
                    IconPicker(selected: $icon)
                }

                if case .edit(let addr) = mode {
                    Section {
                        Button(role: .destructive) {
                            appState.savedAddressRepo.delete(addr)
                            dismiss()
                        } label: {
                            Label("Delete saved place", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Place" : "Add Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $isShowingAddressSearch) {
                AddressSearchScreen(placeholder: "Search address") { completion in
                    Task { await resolveCompletion(completion) }
                }
            }
            .onAppear { hydrate() }
        }
    }

    // MARK: - Hydrate from existing record

    private func hydrate() {
        guard case .edit(let addr) = mode else { return }
        label           = addr.label
        fullAddress     = addr.address
        addressResult   = AddressResult(title: addr.address, subtitle: "",
                                        coordinate: CLLocationCoordinate2D(latitude: addr.latitude, longitude: addr.longitude))
        isHome          = addr.isHome
        isWork          = addr.isWork
        defaultCategory = addr.defaultCategory
        icon            = addr.icon
    }

    // MARK: - Resolve search completion to coordinates

    private func resolveCompletion(_ completion: MKLocalSearchCompletion) async {
        let searcher = AddressSearcher()
        do {
            let result = try await searcher.resolve(completion)
            await MainActor.run {
                addressResult = result
                fullAddress = result.fullAddress
            }
        } catch {
            TripLogger.shared.log("Address resolve failed: \(error.localizedDescription)", category: .error)
        }
    }

    // MARK: - Save

    private func save() {
        guard let result = addressResult else { return }
        let trimmedLabel = label.trimmingCharacters(in: .whitespaces)

        switch mode {
        case .add:
            appState.savedAddressRepo.add(
                label: trimmedLabel,
                address: fullAddress,
                latitude: result.coordinate.latitude,
                longitude: result.coordinate.longitude,
                isHome: isHome, isWork: isWork,
                defaultCategory: defaultCategory,
                icon: icon
            )
        case .edit(let addr):
            appState.savedAddressRepo.update(
                addr,
                label: trimmedLabel,
                isHome: isHome,
                isWork: isWork,
                defaultCategory: defaultCategory,
                icon: icon
            )
        }
        dismiss()
    }
}

// MARK: - Icon Picker

private struct IconPicker: View {
    @Binding var selected: String

    /// SF Symbols suitable for places. Keep this list short — too much choice is friction.
    private let options: [String] = [
        "house.fill", "briefcase.fill", "building.2.fill", "building.columns.fill",
        "cart.fill", "stethoscope", "fork.knife", "graduationcap.fill",
        "person.fill", "figure.run", "tram.fill", "airplane",
        "mappin.circle.fill", "star.fill", "heart.fill", "tag.fill",
    ]

    var body: some View {
        let cols = [GridItem(.adaptive(minimum: 44), spacing: MTSpacing.sm)]
        LazyVGrid(columns: cols, spacing: MTSpacing.sm) {
            ForEach(options, id: \.self) { name in
                Button { selected = name } label: {
                    Image(systemName: name)
                        .font(.system(size: 20))
                        .foregroundStyle(selected == name ? Color.white : Color.mtGreen)
                        .frame(width: 36, height: 36)
                        .background(selected == name ? Color.mtGreen : Color.mtSurface)
                        .clipShape(RoundedRectangle(cornerRadius: MTRadius.sm))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}
