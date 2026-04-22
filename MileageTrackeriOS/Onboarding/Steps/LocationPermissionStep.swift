import SwiftUI
import CoreLocation

struct LocationPermissionStep: View {
    @Environment(AppState.self) private var appState
    let vm: OnboardingViewModel

    @State private var authStatus: CLAuthorizationStatus = .notDetermined
    @State private var hasRequested = false

    var body: some View {
        OnboardingStepShell(
            icon: "location.fill",
            iconColor: .mtGreen,
            title: "Background location",
            subtitle: "MileageTracker needs to track your location in the background to automatically detect and record trips while you drive."
        ) {
            // Privacy explanation card
            VStack(alignment: .leading, spacing: MTSpacing.md) {
                PrivacyRow(icon: "icloud.fill", color: .blue,
                           title: "Stays on your device",
                           detail: "Location data is stored in your private iCloud. Never on our servers.")
                PrivacyRow(icon: "battery.50", color: .mtGreen,
                           title: "Battery friendly",
                           detail: "We use motion sensors to activate GPS only when you're driving.")
                PrivacyRow(icon: "eye.slash.fill", color: .purple,
                           title: "No tracking, just recording",
                           detail: "Personal trips are deleted after 7 days automatically.")
            }
            .padding(MTSpacing.md)
            .mtCard()

            // Always-allow guidance shown when only WhenInUse has been granted
            if authStatus == .authorizedWhenInUse {
                HStack(alignment: .top, spacing: MTSpacing.sm) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(Color.blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Change to \"Always Allow\"")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.mtTextPrimary)
                        Text("To auto-detect trips, go to **Settings > Privacy & Security > Location Services > MileageTracker** and select **Always**.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.mtTextSub)
                    }
                }
                .padding(MTSpacing.md)
                .background(Color.blue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: MTRadius.sm))
            }

            // Denied state
            if authStatus == .denied {
                HStack(spacing: MTSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.mtWarning)
                    Text("Location access was denied. Open **Settings > Privacy & Security > Location Services** to enable it for MileageTracker.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.mtTextSub)
                }
                .padding(MTSpacing.md)
                .background(Color.mtWarning.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: MTRadius.sm))
            }

            Spacer(minLength: MTSpacing.xl)

            switch authStatus {
            case .authorizedAlways:
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.mtGreen)
                    Text("Always Allow granted — you're all set!").foregroundStyle(Color.mtGreen).font(.system(size: 16, weight: .medium))
                }
                Button("Continue") { vm.advance() }
                    .buttonStyle(MTPrimaryButtonStyle())

            case .authorizedWhenInUse:
                Button("Upgrade to Always Allow") {
                    appState.locationManager.requestLocationPermission()
                }
                .buttonStyle(MTPrimaryButtonStyle())
                Button("Continue anyway") { vm.advance() }
                    .buttonStyle(MTSecondaryButtonStyle())

            case .denied, .restricted:
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(MTPrimaryButtonStyle())
                Button("Skip for now") { vm.advance() }
                    .buttonStyle(MTSecondaryButtonStyle())

            default:
                Button("Allow Location Access") {
                    hasRequested = true
                    appState.locationManager.requestLocationPermission()
                }
                .buttonStyle(MTPrimaryButtonStyle())
                .disabled(hasRequested)

                Button("Skip for now") { vm.advance() }
                    .buttonStyle(MTSecondaryButtonStyle())
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            authStatus = appState.locationManager.authorizationStatus
        }
        .onAppear {
            authStatus = appState.locationManager.authorizationStatus
        }
        .onChange(of: appState.locationManager.authorizationStatus) { _, new in
            authStatus = new
            if new == .authorizedAlways {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { vm.advance() }
            }
        }
    }
}

private struct PrivacyRow: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: MTSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.system(size: 13)).foregroundStyle(Color.mtTextSub)
            }
        }
    }
}
