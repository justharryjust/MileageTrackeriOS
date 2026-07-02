import SwiftUI

struct NotificationSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            Section {
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
                .tint(.mtGreen)

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
                .tint(.mtGreen)

                Toggle(isOn: Binding(
                    get: { NotificationManager.weeklySummaryEnabled },
                    set: { newValue in
                        NotificationManager.weeklySummaryEnabled = newValue
                        appState.notificationManager.weeklySummaryToggleChanged(isEnabled: newValue)
                    }
                )) {
                    Label("Weekly Summary", systemImage: "chart.bar.fill")
                }
                .tint(.mtGreen)
            } header: {
                Text("Notifications")
            }
        }
        .navigationTitle("Notifications")
    }
}
