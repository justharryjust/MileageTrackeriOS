import SwiftUI
import CoreLocation
import CoreMotion

import UserNotifications
struct PermissionsStep: View {
    @Environment(AppState.self) private var appState
    let vm: OnboardingViewModel

    @State private var locationStatus: CLAuthorizationStatus = .notDetermined
    @State private var motionGranted = false
    @State private var locationRequested = false
    @State private var notificationGranted = false

    var body: some View {
        OnboardingStepShell(
            icon: "hand.raised.fill",
            iconColor: .blue,
            title: "Permissions",
            subtitle: "A few permissions so the app can detect your drives and keep you informed."
        ) {
            VStack(spacing: MTSpacing.md) {
                // Location card
                permissionCard(
                    icon: "location.fill",
                    color: .mtGreen,
                    title: "Location — Always Allow",
                    description: "Needed to detect trips in the background. Your data never leaves your device.",
                    isGranted: locationStatus == .authorizedAlways,
                    buttonLabel: locationStatus == .authorizedAlways ? "Granted"
                        : locationStatus == .authorizedWhenInUse ? "Upgrade to Always"
                        : locationStatus == .denied ? "Open Settings"
                        : "Allow Location",
                    action: {
                        if locationStatus == .denied || locationStatus == .restricted {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } else {
                            locationRequested = true
                            appState.locationManager.requestLocationPermission()
                        }
                    },
                    isDisabled: locationStatus == .authorizedAlways
                )

                // Motion card
                permissionCard(
                    icon: "figure.walk.motion",
                    color: .orange,
                    title: "Motion & Activity",
                    description: "Detects when you start driving so GPS only activates when needed.",
                    isGranted: motionGranted,
                    buttonLabel: motionGranted ? "Granted"
                        : !CMMotionActivityManager.isActivityAvailable() ? "Not Available"
                        : "Allow Motion",
                    action: {
                        appState.motionManager.startActivityUpdates()
                    },
                    isDisabled: motionGranted
                )

                if locationStatus == .authorizedWhenInUse {
                    HStack(alignment: .top, spacing: MTSpacing.sm) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(Color.blue)
                        Text("Tap \"Upgrade to Always\" then select **Always Allow** to enable background trip detection.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.mtTextSub)
                    }
                    .padding(MTSpacing.sm)
                    .background(Color.blue.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: MTRadius.sm))
                }

                // Notification info
                HStack(alignment: .top, spacing: MTSpacing.sm) {
                    Image(systemName: notificationGranted ? "checkmark.circle.fill" : "bell.fill")
                        .foregroundStyle(notificationGranted ? Color.mtGreen : Color.mtTextSub)
                    Text("Notifications for trip recovery and reminders")
                        .font(.system(size: 13))
                        .foregroundStyle(notificationGranted ? Color.mtGreen : Color.mtTextSub)
                    Spacer()
                    if notificationGranted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.mtGreen)
                    }
                }
                .padding(.horizontal, MTSpacing.sm + 4)
                .padding(.vertical, 6)
                .background(notificationGranted ? Color.mtGreen.opacity(0.08) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: MTRadius.sm))

                Spacer(minLength: MTSpacing.xl)

                Button("Continue") { vm.advance() }
                    .buttonStyle(MTPrimaryButtonStyle())

                Button("Skip for now") { vm.advance() }
                    .buttonStyle(MTSecondaryButtonStyle())
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            locationStatus = appState.locationManager.authorizationStatus
        }
        .onAppear {
            locationStatus = appState.locationManager.authorizationStatus
            motionGranted = appState.motionManager.isAuthorized
            notificationGranted = appState.notificationManager.isAuthorized
            // Request provisional notification permission (silent — no system prompt)
            appState.notificationManager.requestPermission()
        }
        .onChange(of: appState.locationManager.authorizationStatus) { _, new in
            locationStatus = new
        }
        .onChange(of: appState.motionManager.isAuthorized) { _, granted in
            motionGranted = granted
        }
        .onChange(of: appState.notificationManager.authorizationStatus) { _, status in
            notificationGranted = status == .authorized || status == .provisional
        }
    }

    // MARK: - Permission Card

    private func permissionCard(
        icon: String,
        color: Color,
        title: String,
        description: String,
        isGranted: Bool,
        buttonLabel: String,
        action: @escaping () -> Void,
        isDisabled: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: MTSpacing.sm) {
            HStack(spacing: MTSpacing.md) {
                ZStack {
                    Circle()
                        .fill(isGranted ? Color.mtGreen : color.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: isGranted ? "checkmark" : icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(isGranted ? .white : color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.mtTextPrimary)
                    Text(isGranted ? "Access granted" : "Tap to grant permission")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.mtTextSub)
                }
                Spacer()
            }

            Text(description)
                .font(.system(size: 13))
                .foregroundStyle(Color.mtTextSub)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: action) {
                Text(buttonLabel)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isGranted ? Color.mtGreen : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, MTSpacing.sm)
                    .background(isGranted ? Color.mtGreen.opacity(0.12) : color)
                    .clipShape(RoundedRectangle(cornerRadius: MTRadius.sm))
            }
            .disabled(isDisabled)
        }
        .padding(MTSpacing.md)
        .background(Color.mtSurface)
        .clipShape(RoundedRectangle(cornerRadius: MTRadius.md))
    }
}
