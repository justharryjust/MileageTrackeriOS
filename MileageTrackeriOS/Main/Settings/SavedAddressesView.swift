// SavedAddressesView — Settings list of user-saved places.
//
// The lever for NZ commute auto-classification: when a user marks one address
// "Home" and another "Work", every home↔work trip gets auto-categorised
// .personal (commute, not claimable under IRD rules). Other saved places with
// a defaultCategory of .business auto-flag trips ending at them.
//
// List shows: icon · label · subtitle (Home/Work badge · default category · address).
// Tap to edit. Trailing swipe → delete. Toolbar "+" → add via address search.

import SwiftUI

struct SavedAddressesView: View {
    @Environment(AppState.self) private var appState
    @State private var isPresentingAdd = false
    @State private var editing: SavedAddress?

    var body: some View {
        List {
            // Educational header — explains the commute auto-classification win for NZ users
            Section {
                VStack(alignment: .leading, spacing: MTSpacing.xs) {
                    Label("Auto-categorise commutes", systemImage: "info.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.mtGreen)
                    Text("Mark one address as **Home** and another as **Work**. Trips between them will be flagged Personal automatically — IRD doesn't allow commute mileage to be claimed.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.mtTextSub)
                }
                .listRowBackground(Color.mtGreenLight.opacity(0.2))
            }

            if appState.savedAddressRepo.addresses.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No saved places", systemImage: "mappin.slash")
                    } description: {
                        Text("Add your home, office, or frequent client addresses to auto-categorise trips.")
                    } actions: {
                        Button("Add address") { isPresentingAdd = true }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.mtGreen)
                    }
                    .listRowBackground(Color.clear)
                }
            } else {
                Section("Saved places") {
                    ForEach(appState.savedAddressRepo.addresses, id: \.id) { addr in
                        SavedAddressRow(address: addr)
                            .contentShape(Rectangle())
                            .onTapGesture { editing = addr }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    appState.savedAddressRepo.delete(addr)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle("Saved Places")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isPresentingAdd = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isPresentingAdd) {
            SavedAddressEditSheet(mode: .add)
                .environment(appState)
        }
        .sheet(item: $editing) { addr in
            SavedAddressEditSheet(mode: .edit(addr))
                .environment(appState)
        }
    }
}

// MARK: - Row

private struct SavedAddressRow: View {
    let address: SavedAddress

    var body: some View {
        HStack(spacing: MTSpacing.md) {
            Image(systemName: address.icon)
                .font(.system(size: 22))
                .foregroundStyle(iconTint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(address.label)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.mtTextPrimary)
                    if address.isHome {
                        Pill(text: "Home", colour: Color.mtGreen)
                    }
                    if address.isWork {
                        Pill(text: "Work", colour: Color.blue)
                    }
                    if address.defaultCategory == .business && !address.isHome && !address.isWork {
                        Pill(text: "Business", colour: Color.mtGreen)
                    }
                }
                Text(address.address)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.mtTextSub)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.mtBorder)
        }
        .padding(.vertical, 4)
    }

    private var iconTint: Color {
        if address.isHome { return Color.mtGreen }
        if address.isWork { return Color.blue }
        if address.defaultCategory == .business { return Color.mtGreen }
        return Color.mtTextSub
    }
}

// MARK: - Pill

private struct Pill: View {
    let text: String
    let colour: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(colour.opacity(0.15))
            .foregroundStyle(colour)
            .clipShape(Capsule())
    }
}
