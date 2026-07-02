import SwiftUI

struct DiagnosticsHubView: View {
    @Environment(AppState.self) private var appState
    @State private var isSharingDebugData = false
    @State private var debugDataURL: URL?

    var body: some View {
        List {
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

#if DEBUG
                NavigationLink {
                    SubscriptionOverrideView()
                        .environment(appState)
                } label: {
                    Label("Subscription Override", systemImage: "arrow.triangle.swap")
                }
#endif

                Button {
                    debugDataURL = DebugDataCollector.collectDebugData(appState: appState)
                    isSharingDebugData = true
                } label: {
                    Label("Share Debug Data", systemImage: "ladybug")
                }
            }

            Section {
                Button("Reset Onboarding", role: .destructive) {
                    appState.profileRepo.hasCompletedOnboarding = false
                }
            } header: {
                Text("Danger Zone")
            }
        }
        .navigationTitle("Help & Diagnostics")
        .sheet(isPresented: $isSharingDebugData) {
            if let url = debugDataURL {
                ShareSheet(items: [url])
            }
        }
    }
}
