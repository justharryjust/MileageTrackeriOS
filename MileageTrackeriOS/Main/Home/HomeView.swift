import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: MTSpacing.lg) {

                    // MARK: Trip Status Card (hero element)
                    TripStatusCard()
                        .padding(.top, MTSpacing.sm)

                    // MARK: Manual Trip Controls
                    ManualTripControls()
                        .padding(.top, MTSpacing.xs)

                    // MARK: Quick Stats
                    QuickStatsRow()

                    // MARK: Permission warnings
                    PermissionWarnings()

                    // MARK: Recent trips placeholder
                    RecentTripsSection()
                }
                .padding(.horizontal, MTSpacing.md)
                .padding(.bottom, MTSpacing.xl)
            }
            .background(Color.mtBackground)
            .navigationTitle("Mileage Tracker")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // Debug button — only in DEBUG builds
                    #if DEBUG
                    NavigationLink {
                        DebugLogView()
                    } label: {
                        Image(systemName: "terminal")
                            .foregroundStyle(Color.mtTextSub)
                    }
                    #endif
                }
            }
        }
    }
}

// MARK: - Quick Stats Row

private struct QuickStatsRow: View {
    @Environment(AppState.self) private var appState

    private var weekKm  : String { String(format: "%.1f", appState.tripRepo.weeklyDistanceKm) }
    private var monthKm : String { String(format: "%.1f", appState.tripRepo.monthlyDistanceKm) }
    private var totalVal: String {
        let v = appState.tripRepo.totalDollarValue
        return v > 0 ? "$\(String(format: "%.0f", v))" : "$—"
    }

    var body: some View {
        HStack(spacing: MTSpacing.md) {
            StatCard(label: "This Week",   value: weekKm,   unit: "km", icon: "calendar",                   color: .mtGreen)
            StatCard(label: "This Month",  value: monthKm,  unit: "km", icon: "chart.line.uptrend.xyaxis",   color: .blue)
            StatCard(label: "Total Value", value: totalVal, unit: "",   icon: "dollarsign",                  color: .purple)
        }
    }
}

private struct StatCard: View {
    let label: String
    let value: String
    let unit: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: MTSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
            Spacer(minLength: 0)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .bold))
                if !unit.isEmpty {
                    Text(unit).font(.system(size: 11)).foregroundStyle(Color.mtTextSub)
                }
            }
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.mtTextSub)
        }
        .padding(MTSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .mtCard()
    }
}

// MARK: - Permission Warnings

private struct PermissionWarnings: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: MTSpacing.sm) {
            if !appState.locationManager.hasAlwaysAuthorization {
                WarningBanner(
                    icon: "location.slash.fill",
                    message: "Background location is off. Trip auto-detection is disabled.",
                    action: "Fix",
                    onAction: {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                )
            }
            if !appState.motionManager.isAvailable {
                WarningBanner(
                    icon: "exclamationmark.triangle.fill",
                    message: "Motion & Activity is unavailable. Speed-based detection only.",
                    action: nil,
                    onAction: nil
                )
            }
        }
    }
}

private struct WarningBanner: View {
    let icon: String
    let message: String
    let action: String?
    let onAction: (() -> Void)?

    var body: some View {
        HStack(spacing: MTSpacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(Color.mtWarning)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Color.mtTextSub)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let action, let onAction {
                Button(action, action: onAction)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.mtGreen)
            }
        }
        .padding(MTSpacing.md)
        .background(Color.mtWarning.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: MTRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: MTRadius.sm)
                .strokeBorder(Color.mtWarning.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Recent Trips Section

private struct RecentTripsSection: View {
    @Environment(AppState.self) private var appState

    private var recentTrips: [Trip] { Array(appState.tripRepo.allTrips.prefix(5)) }

    var body: some View {
        VStack(alignment: .leading, spacing: MTSpacing.sm) {
            HStack {
                Text("Recent Trips")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                if !recentTrips.isEmpty {
                    Text("\(appState.tripRepo.allTrips.count) total")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.mtTextSub)
                }
            }

            if recentTrips.isEmpty {
                VStack(spacing: MTSpacing.md) {
                    Image(systemName: "car.2.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.mtBorder)
                    Text("No trips recorded yet")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.mtTextSub)
                    Text("Trips will appear here once auto-tracking detects your first drive.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.mtTextSub.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, MTSpacing.xl)
                .mtCard()
            } else {
                VStack(spacing: 6) {
                    ForEach(recentTrips) { trip in
                        HStack(spacing: MTSpacing.md) {
                            Circle()
                                .fill(categoryColor(trip))
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(trip.startedAt, style: .date)
                                    .font(.system(size: 13, weight: .medium))
                                Text(trip.distanceString)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.mtTextSub)
                            }
                            Spacer()
                            if let val = trip.dollarValue {
                                Text("$\(String(format:"%.2f", val))")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.mtGreen)
                            }
                        }
                        .padding(.horizontal, MTSpacing.md)
                        .padding(.vertical, 8)
                        .background(Color.mtSurface)
                        .clipShape(RoundedRectangle(cornerRadius: MTRadius.sm))
                    }
                }

                if appState.tripRepo.uncategorisedTrips.count > 0 {
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(Color.mtWarning)
                        Text("\(appState.tripRepo.uncategorisedTrips.count) trips need review")
                            .font(.system(size: 13))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.mtTextSub)
                    }
                    .padding(MTSpacing.sm + 2)
                    .background(Color.mtWarning.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: MTRadius.sm))
                }
            }
        }
    }

    private func categoryColor(_ trip: Trip) -> Color {
        switch trip.category {
        case .business:      return .mtGreen
        case .personal:      return .blue
        case .uncategorised: return .mtWarning
        }
    }
}

// MARK: - Manual Trip Controls

private struct ManualTripControls: View {
    @Environment(AppState.self) private var appState

    private var state: TripRecorderState { appState.tripRecorder.state }

    var body: some View {
        HStack(spacing: MTSpacing.sm) {
            if state.isRecording {
                // ── Stop Trip ──
                Button {
                    appState.tripRecorder.forceFinaliseFromDebug()
                } label: {
                    Label("Stop Trip", systemImage: "stop.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MTSpacing.sm + 2)
                        .background(Color.mtRecording)
                        .clipShape(RoundedRectangle(cornerRadius: MTRadius.md))
                }
            } else if case .idle = state {
                // ── Start Trip ──
                Button {
                    appState.tripRecorder.forceStartManualTrip()
                } label: {
                    Label("Start Trip", systemImage: "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MTSpacing.sm + 2)
                        .background(Color.mtGreen)
                        .clipShape(RoundedRectangle(cornerRadius: MTRadius.md))
                }
            } else {
                // Suspected or ending — show ghost button
                Button {
                    appState.tripRecorder.forceFinaliseFromDebug()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.mtTextSub)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MTSpacing.sm + 2)
                        .background(Color.mtSurface)
                        .clipShape(RoundedRectangle(cornerRadius: MTRadius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: MTRadius.md)
                                .strokeBorder(Color.mtBorder, lineWidth: 1)
                        )
                }
            }
        }
    }
}
