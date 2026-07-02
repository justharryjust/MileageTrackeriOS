import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    /// Compact summary for the Places row: "Home · Work · 3 others" or "Add home & work for commute auto-tag".
    private var placesSummary: String {
        let saved = appState.savedAddressRepo.addresses
        if saved.isEmpty {
            return "Tag commutes automatically"
        }
        var parts: [String] = []
        if saved.contains(where: { $0.isHome }) { parts.append("Home") }
        if saved.contains(where: { $0.isWork }) { parts.append("Work") }
        let others = saved.filter { !$0.isHome && !$0.isWork }.count
        if others > 0 { parts.append("\(others) other\(others == 1 ? "" : "s")") }
        return parts.joined(separator: " \u{00B7} ")
    }

    private var notificationSummary: String {
        let status = appState.notificationManager.authorizationStatus
        if status == .denied { return "Disabled" }
        if status == .notDetermined { return "Not set up" }
        let enabled = [NotificationManager.tripDetectedEnabled,
                       NotificationManager.odometerReminderEnabled,
                       NotificationManager.weeklySummaryEnabled].filter { $0 }.count
        return "\(enabled) of 3 on"
    }

    private var trackingSummary: String {
        let schedule = appState.profileRepo.trackingSchedule
        let enabledDays = schedule.filter { $0.isEnabled }.count
        if enabledDays == 0 { return "Off" }
        return "\(enabledDays) day\(enabledDays == 1 ? "" : "s")"
    }

    private var dataSummary: String {
        let total = appState.tripRepo.allTrips.count
        let business = appState.tripRepo.businessTrips.count
        if total == 0 { return "No trips" }
        return "\(total) total, \(business) business"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        SubscriptionDetailView()
                            .environment(appState)
                    } label: {
                        subscriptionLabel
                    }
                }

                Section("Tracking & Notifications") {
                    NavigationLink {
                        TrackingSettingsView()
                            .environment(appState)
                    } label: {
                        Label("Tracking", systemImage: "clock")
                        Spacer()
                        Text(trackingSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    NavigationLink {
                        NotificationSettingsView()
                            .environment(appState)
                    } label: {
                        Label("Notifications", systemImage: "bell.fill")
                        Spacer()
                        Text(notificationSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Profile") {
                    NavigationLink {
                        ProfileEditView()
                            .environment(appState)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Edit Profile")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.mtTextPrimary)
                            Text("\(appState.profileRepo.jurisdiction.displayName) \u{00B7} \(appState.profileRepo.claimMethod.displayName) \u{00B7} \(appState.profileRepo.distanceUnit.displayName)")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.mtTextSub)
                        }
                    }

                    NavigationLink {
                        RatesListView()
                            .environment(appState)
                    } label: {
                        HStack {
                            Image(systemName: "chart.bar.fill")
                                .foregroundStyle(Color.mtGreen)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("View Rates")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Color.mtTextPrimary)
                                Text("\(appState.profileRepo.jurisdiction.displayName) official rates")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.mtTextSub)
                            }
                        }
                    }

                    NavigationLink {
                        RatesListView()
                            .environment(appState)
                    } label: {
                        HStack {
                            Image(systemName: "chart.bar.fill")
                                .foregroundStyle(Color.mtGreen)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("View Rates")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Color.mtTextPrimary)
                                Text("\(appState.profileRepo.jurisdiction.displayName) official rates")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.mtTextSub)
                            }
                        }
                    }

                    if appState.profileRepo.claimMethod == .logbook {
                        NavigationLink {
                            LogbookPeriodView()
                                .environment(appState)
                        } label: {
                            HStack {
                                Image(systemName: "book.closed.fill")
                                    .foregroundStyle(Color.mtGreen)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Logbook Period")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(Color.mtTextPrimary)
                                    if let v = appState.profileRepo.defaultVehicle,
                                       let p = appState.logbookPeriodRepo.activePeriod(for: v.id) {
                                        Text("\(p.daysRemaining) of \(p.totalDays) days remaining")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Color.mtTextSub)
                                    } else {
                                        Text("No active period")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Color.mtTextSub)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Vehicles") {
                    NavigationLink {
                        VehicleManagementView()
                            .environment(appState)
                    } label: {
                        HStack {
                            if let v = appState.profileRepo.defaultVehicle {
                                Image(systemName: v.type.icon).foregroundStyle(Color.mtGreen)
                                VStack(alignment: .leading) {
                                    Text(v.name.isEmpty ? v.registration : v.name)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(Color.mtTextPrimary)
                                    Text("\(v.registration) \u{00B7} \(v.fuelType.displayName)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.mtTextSub)
                                }
                                Spacer()
                                Text("\(appState.profileRepo.vehicles.count) vehicle\(appState.profileRepo.vehicles.count != 1 ? "s" : "")")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.mtTextSub)
                            } else {
                                Label("Add a vehicle", systemImage: "car.fill")
                            }
                        }
                    }
                }

                Section("Places") {
                    NavigationLink {
                        SavedAddressesView()
                            .environment(appState)
                    } label: {
                        HStack {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundStyle(Color.mtGreen)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Saved Places")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Color.mtTextPrimary)
                                Text(placesSummary)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.mtTextSub)
                            }
                            Spacer()
                            if appState.savedAddressRepo.addresses.count > 0 {
                                Text("\(appState.savedAddressRepo.addresses.count)")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.mtTextSub)
                            }
                        }
                    }
                }

                Section("Reports & Data") {
                    NavigationLink {
                        ReportingHubView()
                            .environment(appState)
                    } label: {
                        Label("Reporting", systemImage: "doc.text.fill")
                        Spacer()
                        Text("\(appState.tripRepo.businessTrips.count) trips")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    NavigationLink {
                        DataSummaryView()
                            .environment(appState)
                    } label: {
                        Label("Data", systemImage: "chart.bar.fill")
                        Spacer()
                        Text(dataSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    NavigationLink {
                        DiagnosticsHubView()
                            .environment(appState)
                    } label: {
                        Label("Help & Diagnostics", systemImage: "wrench.fill")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    // MARK: - Subscription Label

    private var subscriptionLabel: some View {
        let state = appState.subscriptionManager.subscriptionState
        let isOverride = appState.subscriptionManager.isOverrideActive
        return HStack {
            Image(systemName: state.status.icon)
                .foregroundStyle(subscriptionIconColor(state.status))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Mileage Tracker Pro")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.mtTextPrimary)
                    if isOverride {
                        Text("DEBUG")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange)
                            .clipShape(Capsule())
                    }
                }
                Text(subscriptionStatusText(state))
                    .font(.system(size: 12))
                    .foregroundStyle(isOverride ? Color.orange : Color.mtTextSub)
            }
            Spacer()
            if state.status != .active {
                Text("Upgrade")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.mtGreen)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.mtGreen)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.mtBorder)
        }
    }

    private func subscriptionIconColor(_ status: MTSubscriptionStatus) -> Color {
        switch status {
        case .trial: return .purple
        case .active: return .mtGreen
        case .gracePeriod: return .mtWarning
        case .expired: return .red
        }
    }

    private func subscriptionStatusText(_ state: MTSubscriptionState) -> String {
        switch state.status {
        case .trial:
            if let days = state.daysRemainingInTrial {
                return "Free trial \u{00B7} \(days) day\(days == 1 ? "" : "s") remaining"
            }
            return "Free trial"
        case .active:
            return "Active"
        case .gracePeriod:
            if let days = state.daysRemainingInGrace {
                return "Grace period \u{00B7} \(days) day\(days == 1 ? "" : "s") remaining"
            }
            return "Grace period"
        case .expired:
            return "Expired \u{00B7} Subscribe to regain access"
        }
    }
}
