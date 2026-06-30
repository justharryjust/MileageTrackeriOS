import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var isSharingDebugData = false
    @State private var debugDataURL: URL?

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
        return parts.joined(separator: " · ")
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Tracking") {
                    NavigationLink {
                        TrackingHoursView()
                            .environment(appState)
                    } label: {
                        Label("Tracking Hours", systemImage: "clock")
                    }

                    Toggle(isOn: Binding(
                        get: { LiveActivityManager.isEnabled },
                        set: { UserDefaults.standard.set($0, forKey: LiveActivityManager.liveActivityEnabledKey) }
                    )) {
                        Label("Live Activity", systemImage: "car.window.right")
                    }
                    .tint(Color.mtGreen)
                }

                Section("Notifications") {
                    let status = appState.notificationManager.authorizationStatus
                    if status == .denied || status == .notDetermined {
                        Button {
                            if status == .denied {
                                appState.notificationManager.openSystemSettings()
                            } else {
                                appState.notificationManager.requestPermission()
                            }
                        } label: {
                            Label(status == .denied ? "Enable in Settings" : "Enable Notifications", systemImage: "bell.badge")
                        }
                    }

                    Toggle(isOn: Binding(
                        get: { NotificationManager.tripDetectedEnabled },
                        set: { NotificationManager.tripDetectedEnabled = $0 }
                    )) {
                        Label("Trip Started", systemImage: "car.fill")
                    }
                    .tint(Color.mtGreen)

                    Toggle(isOn: Binding(
                        get: { NotificationManager.odometerReminderEnabled },
                        set: { newValue in
                            NotificationManager.odometerReminderEnabled = newValue
                            let vehicleName = appState.profileRepo.defaultVehicle?.name ?? ""
                            appState.notificationManager.odometerToggleChanged(isEnabled: newValue, vehicleName: vehicleName)
                        }
                    )) {
                        Label("Odometer Reminder", systemImage: "speedometer")
                    }
                    .tint(Color.mtGreen)

                    Toggle(isOn: Binding(
                        get: { NotificationManager.weeklySummaryEnabled },
                        set: { newValue in
                            NotificationManager.weeklySummaryEnabled = newValue
                            appState.notificationManager.weeklySummaryToggleChanged(isEnabled: newValue)
                        }
                    )) {
                        Label("Weekly Summary", systemImage: "chart.bar.fill")
                    }
                    .tint(Color.mtGreen)
                }

                Section("Profile") {

                    NavigationLink {
                        ProfileEditView()
                            .environment(appState)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Edit Profile")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Color.mtTextPrimary)
                                Text("\(appState.profileRepo.jurisdiction.displayName) · \(appState.profileRepo.claimMethod.displayName) · \(appState.profileRepo.distanceUnit.displayName)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.mtTextSub)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.mtBorder)
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
                                    Text("\(v.registration) · \(v.fuelType.displayName)")
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

                Section("Reporting") {
                    NavigationLink {
                        ReportExportView()
                            .environment(appState)
                    } label: {
                        Label("Mileage Report", systemImage: "doc.text.fill")
                    }

                    NavigationLink {
                        OdometerLogView()
                            .environment(appState)
                    } label: {
                        Label("Odometer Log", systemImage: "speedometer")
                    }

                    NavigationLink {
                        MethodInfoView()
                            .environment(appState)
                    } label: {
                        Label("Which method to choose?", systemImage: "questionmark.circle")
                    }
                }

                Section("Data") {
                    LabeledContent("Total trips", value: "\(appState.tripRepo.allTrips.count)")
                    LabeledContent("Business trips", value: "\(appState.tripRepo.businessTrips.count)")
                    LabeledContent("Needs review", value: "\(appState.tripRepo.uncategorisedTrips.count)")
                }

                // Debug / Diagnostics
                Section("Help") {
                    NavigationLink {
                        TipsView()
                    } label: {
                        Label("Tips for Best Results", systemImage: "lightbulb.fill")
                    }
                }

                Section("Diagnostics") {
                    NavigationLink {
                        DebugLogView()
                    } label: {
                        Label("Debug Log", systemImage: "terminal")
                    }

                    NavigationLink {
                        TripRecorderDebugView()
                    } label: {
                        Label("Trip Recorder State", systemImage: "waveform")
                    }

                    NavigationLink {
                        DebugExtensionsView()
                    } label: {
                        Label("Potential Extensions", systemImage: "lightbulb")
                    }

                    Button {
                        debugDataURL = DebugDataCollector.collectDebugData(appState: appState)
                        isSharingDebugData = true
                    } label: {
                        Label("Share Debug Data", systemImage: "ladybug")
                    }
                }

                // Danger zone
                Section {
                    Button("Reset Onboarding", role: .destructive) {
                        appState.profileRepo.hasCompletedOnboarding = false
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $isSharingDebugData) {
                if let url = debugDataURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }
}
