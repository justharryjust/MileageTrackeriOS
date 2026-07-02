import SwiftUI

struct TrackingSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            Section {
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
                .tint(.mtGreen)
            } header: {
                Text("Tracking")
            }
        }
        .navigationTitle("Tracking")
    }
}
