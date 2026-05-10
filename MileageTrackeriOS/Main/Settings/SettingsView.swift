import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

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
                    if !appState.notificationManager.isAuthorized {
                        Button {
                            appState.notificationManager.requestPermission()
                        } label: {
                            Label("Enable Notifications", systemImage: "bell.badge")
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
                        set: { NotificationManager.odometerReminderEnabled = $0 }
                    )) {
                        Label("Odometer Reminder", systemImage: "speedometer")
                    }
                    .tint(Color.mtGreen)

                    Toggle(isOn: Binding(
                        get: { NotificationManager.weeklySummaryEnabled },
                        set: { NotificationManager.weeklySummaryEnabled = $0 }
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
                }

                // Danger zone
                Section {
                    Button("Reset Onboarding", role: .destructive) {
                        appState.profileRepo.hasCompletedOnboarding = false
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
