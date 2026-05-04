import SwiftUI

// MARK: - TripsView

struct TripsView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedFilter: TripFilter = .all
    @State private var showManualTrip: Bool = false

    enum TripFilter: String, CaseIterable {
        case all           = "All"
        case uncategorised = "Needs Review"
        case business      = "Business"
        case personal      = "Personal"
    }

    private var displayedTrips: [Trip] {
        switch selectedFilter {
        case .all:           return appState.tripRepo.allTrips
        case .uncategorised: return appState.tripRepo.uncategorisedTrips
        case .business:      return appState.tripRepo.businessTrips
        case .personal:      return appState.tripRepo.allTrips.filter { $0.category == .personal }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: MTSpacing.sm) {
                        ForEach(TripFilter.allCases, id: \.self) { filter in
                            FilterPill(
                                label: filter.rawValue,
                                badge: badgeCount(filter),
                                isSelected: selectedFilter == filter
                            ) {
                                withAnimation { selectedFilter = filter }
                            }
                        }
                    }
                    .padding(.horizontal, MTSpacing.md)
                    .padding(.vertical, MTSpacing.sm)
                }
                .background(Color.mtSurface)

                Divider()

                if displayedTrips.isEmpty {
                    EmptyTripsPlaceholder(filter: selectedFilter)
                } else {
                    List {
                        ForEach(displayedTrips) { trip in
                            NavigationLink(destination: TripDetailView(trip: trip)) {
                                TripRow(trip: trip)
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button {
                                            appState.tripRepo.categorise(trip, as: .business)
                                        } label: {
                                            Label("Business", systemImage: "briefcase.fill")
                                        }
                                        .tint(Color.mtGreen)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button {
                                            appState.tripRepo.categorise(trip, as: .personal)
                                        } label: {
                                            Label("Personal", systemImage: "person.fill")
                                        }
                                        .tint(.blue)
                                    }
                                    .listRowBackground(Color.mtBackground)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 4, leading: MTSpacing.md, bottom: 4, trailing: MTSpacing.md))
                            }
                        }
                        .onDelete { indexSet in
                            indexSet.forEach { appState.tripRepo.deleteTrip(displayedTrips[$0]) }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(Color.mtBackground)
            .navigationTitle("Trips")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showManualTrip = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                }
            }
            .sheet(isPresented: $showManualTrip) {
                ManualTripSheet()
                    .environment(appState)
            }
        }
    }

    private func badgeCount(_ filter: TripFilter) -> Int? {
        switch filter {
        case .uncategorised: return appState.tripRepo.uncategorisedTrips.count > 0
                                    ? appState.tripRepo.uncategorisedTrips.count : nil
        default: return nil
        }
    }
}

// MARK: - TripRow

private struct TripRow: View {
    let trip: Trip

    var body: some View {
        HStack(spacing: MTSpacing.md) {
            // Category dot
            Circle()
                .fill(categoryColor)
                .frame(width: 10, height: 10)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                // Route
                HStack {
                    Text(trip.startAddress.isEmpty ? "Unknown start" : trip.startAddress)
                        .lineLimit(1)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.mtTextSub)
                    Text(trip.endAddress.isEmpty ? "Unknown end" : trip.endAddress)
                        .lineLimit(1)
                }
                .font(.system(size: 14, weight: .medium))

                // Meta row
                HStack(spacing: MTSpacing.sm) {
                    Text(trip.startedAt, style: .date)
                    Text("·")
                    Text(trip.distanceString)
                    if let dur = trip.durationString {
                        Text("·")
                        Text(dur)
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(Color.mtTextSub)
            }

            Spacer()

            // Dollar value if available
            if let val = trip.dollarValue {
                Text("$\(String(format: "%.2f", val))")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.mtGreen)
            }
        }
        .padding(MTSpacing.md)
        .background(Color.mtSurface)
        .clipShape(RoundedRectangle(cornerRadius: MTRadius.md))
    }

    private var categoryColor: Color {
        switch trip.category {
        case .business:      return .mtGreen
        case .personal:      return .blue
        case .uncategorised: return .mtWarning
        }
    }
}

// MARK: - Filter Pill

private struct FilterPill: View {
    let label: String
    let badge: Int?
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                if let b = badge {
                    Text("\(b)")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(isSelected ? Color.white.opacity(0.3) : Color.mtWarning)
                        .clipShape(Capsule())
                        .foregroundStyle(isSelected ? Color.white : Color.white)
                }
            }
            .foregroundStyle(isSelected ? .white : Color.mtTextPrimary)
            .padding(.horizontal, MTSpacing.md)
            .padding(.vertical, 6)
            .background(isSelected ? Color.mtGreen : Color.mtSurface)
            .clipShape(Capsule())
        }
    }
}

// MARK: - Empty State

private struct EmptyTripsPlaceholder: View {
    let filter: TripsView.TripFilter

    var body: some View {
        VStack(spacing: MTSpacing.lg) {
            Image(systemName: "car.2.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.mtBorder)
            VStack(spacing: MTSpacing.sm) {
                Text(filter == .all ? "No trips yet" : "No \(filter.rawValue.lowercased()) trips")
                    .font(.system(size: 18, weight: .semibold))
                Text(filter == .all
                     ? "Auto-tracking will record your first drive.\nOr add a trip manually."
                     : "Swipe trips left or right to categorise them.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.mtTextSub)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(MTSpacing.xl)
    }
}
