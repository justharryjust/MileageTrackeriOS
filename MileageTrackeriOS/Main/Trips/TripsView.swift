import SwiftUI

// MARK: - TripsView

struct TripsView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedFilter: TripFilter = .all
    @State private var showManualTrip: Bool = false

    enum TripFilter: String, CaseIterable {
        case all           = "All"
        case uncategorised = "Review"
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
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    // Segmented filter — always visible
                    Picker("Filter", selection: $selectedFilter) {
                        ForEach(TripFilter.allCases, id: \.self) { filter in
                            Text(filterLabel(filter)).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, MTSpacing.md)
                    .padding(.vertical, MTSpacing.sm)

                    if displayedTrips.isEmpty {
                        EmptyTripsPlaceholder(filter: selectedFilter) {
                            showManualTrip = true
                        }
                        .transition(.opacity)
                    } else {
                        List {
                            ForEach(displayedTrips) { trip in
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
                                    .listRowInsets(EdgeInsets(top: 6, leading: MTSpacing.md, bottom: 6, trailing: MTSpacing.md))
                            }
                            .onDelete { indexSet in
                                indexSet.forEach { appState.tripRepo.deleteTrip(displayedTrips[$0]) }
                            }
                        }
                        .listStyle(.plain)
                    }
                }

                // Floating add button
                if !displayedTrips.isEmpty {
                    Button {
                        showManualTrip = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.mtGreen)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
                    }
                    .padding(.trailing, MTSpacing.lg)
                    .padding(.bottom, MTSpacing.lg)
                }
            }
            .background(Color.mtBackground)
            .navigationTitle("Trips")
            .sheet(isPresented: $showManualTrip) {
                ManualTripSheet()
                    .environment(appState)
            }
        }
    }

    private func filterLabel(_ filter: TripFilter) -> String {
        switch filter {
        case .uncategorised:
            let count = appState.tripRepo.uncategorisedTrips.count
            return count > 0 ? "Review (\(count))" : "Review"
        default:
            return filter.rawValue
        }
    }
}

// MARK: - TripRow

private struct TripRow: View {
    @Environment(AppState.self) private var appState
    let trip: Trip

    var body: some View {
        NavigationLink(destination: TripDetailView(trip: trip)) {
            rowContent
        }
        .contextMenu {
            Button {
                appState.tripRepo.categorise(trip, as: .business)
            } label: {
                Label("Mark as Business", systemImage: "briefcase.fill")
            }
            Button {
                appState.tripRepo.categorise(trip, as: .personal)
            } label: {
                Label("Mark as Personal", systemImage: "person.fill")
            }
            Divider()
            Button(role: .destructive) {
                appState.tripRepo.deleteTrip(trip)
            } label: {
                Label("Delete Trip", systemImage: "trash")
            }
        }
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: MTSpacing.md) {
                // Route line — start dot, line, end pin
                VStack(spacing: 0) {
                    Circle()
                        .fill(Color.mtGreen)
                        .frame(width: 8, height: 8)
                    Rectangle()
                        .fill(Color.mtBorder)
                        .frame(width: 1.5, height: 16)
                    Circle()
                        .fill(Color.mtRecording)
                        .frame(width: 8, height: 8)
                }
                .padding(.top, 4)

                // Trip details
                VStack(alignment: .leading, spacing: 0) {
                    // Start row
                    HStack(spacing: 4) {
                        Text(trip.startAddress.isEmpty ? "Unknown" : trip.startAddress)
                            .lineLimit(1)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.mtTextPrimary)
                    }

                    Spacer().frame(height: 12)

                    // End row
                    HStack(spacing: 4) {
                        Text(trip.endAddress.isEmpty ? "Unknown" : trip.endAddress)
                            .lineLimit(1)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.mtTextPrimary)
                    }

                    Spacer().frame(height: 6)

                    // Date + time + meta
                    HStack(spacing: 6) {
                        Text(trip.startedAt.formatted(date: .abbreviated, time: .shortened))
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

                Spacer(minLength: 4)

                // Value + badge column
                VStack(alignment: .trailing, spacing: 4) {
                    if let val = trip.dollarValue {
                        Text("$\(String(format: "%.2f", val))")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.mtGreen)
                    }
                    categoryBadge
                }
            }
            .padding(.vertical, 6)
    }

    private var categoryColor: Color {
        switch trip.category {
        case .business:      return .mtGreen
        case .personal:      return .blue
        case .uncategorised: return .mtWarning
        }
    }

    private var categoryBadge: some View {
        Text(trip.category == .uncategorised ? "Review" : trip.category.rawValue.capitalized)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(categoryColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(categoryColor.opacity(0.12))
            .clipShape(Capsule())
    }
}

// MARK: - Empty State

private struct EmptyTripsPlaceholder: View {
    let filter: TripsView.TripFilter
    var onAddTap: (() -> Void)?

    var body: some View {
        VStack(spacing: MTSpacing.lg) {
            Spacer()

            Image(systemName: "car.2.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.mtBorder)

            VStack(spacing: MTSpacing.sm) {
                Text(filter == .all ? "No trips yet" : "No \(filter.rawValue.lowercased()) trips")
                    .font(.system(size: 18, weight: .semibold))
                Text(filter == .all
                     ? "Auto-tracking will record your first drive."
                     : "Swipe trips left or right to categorise them.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.mtTextSub)
                    .multilineTextAlignment(.center)
            }

            if filter == .all, let onAddTap {
                Button("Add Trip Manually", action: onAddTap)
                    .buttonStyle(MTSecondaryButtonStyle())
                    .padding(.horizontal, MTSpacing.xl)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
