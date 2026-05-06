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
                }

                Section("Profile") {
                    LabeledContent("Jurisdiction", value: appState.profileRepo.jurisdiction.displayName)
                    LabeledContent("Claim Method", value: appState.profileRepo.claimMethod.displayName)
                }

                Section("Vehicles") {
                    if appState.profileRepo.vehicles.isEmpty {
                        Text("No vehicles added").foregroundStyle(Color.mtTextSub)
                    } else {
                        ForEach(appState.profileRepo.vehicles) { v in
                            HStack {
                                Image(systemName: v.type.icon).foregroundStyle(Color.mtGreen)
                                VStack(alignment: .leading) {
                                    Text(v.name).font(.system(size: 15, weight: .medium))
                                    Text(v.registration)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(Color.mtTextSub)
                                }
                                if v.isDefault {
                                    Spacer()
                                    Text("Default")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.mtGreen)
                                }
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
