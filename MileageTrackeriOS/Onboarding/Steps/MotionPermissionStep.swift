import SwiftUI
import CoreMotion

struct MotionPermissionStep: View {
    @Environment(AppState.self) private var appState
    let vm: OnboardingViewModel

    @State private var hasRequested = false

    var body: some View {
        OnboardingStepShell(
            icon: "figure.walk.motion",
            iconColor: .orange,
            title: "Motion & Activity",
            subtitle: "MileageTracker uses your phone's motion sensors to detect when you start driving — so GPS only activates when needed."
        ) {
            VStack(alignment: .leading, spacing: MTSpacing.md) {
                MotionRow(icon: "battery.75", color: .mtGreen,
                          title: "Saves battery",
                          detail: "GPS only turns on when automotive motion is confirmed, not all the time.")
                MotionRow(icon: "timer", color: .blue,
                          title: "Faster detection",
                          detail: "Motion data catches trips within seconds of leaving, even from a cold start.")
                MotionRow(icon: "xmark.circle", color: .red,
                          title: "Fewer false starts",
                          detail: "Walking to your car won't trigger a recording — only driving will.")
            }
            .padding(MTSpacing.md)
            .mtCard()

            if !CMMotionActivityManager.isActivityAvailable() {
                Text("Motion & Fitness is not available on this device. Trip detection will rely on GPS speed only.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.mtTextSub)
                    .padding(MTSpacing.sm)
                    .background(Color.mtWarning.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: MTRadius.sm))
            }

            Spacer(minLength: MTSpacing.xl)

            if appState.motionManager.isAuthorized {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.mtGreen)
                    Text("Motion access granted").foregroundStyle(Color.mtGreen).font(.system(size: 16, weight: .medium))
                }
                Button("Continue") { vm.advance() }
                    .buttonStyle(MTPrimaryButtonStyle())
            } else {
                Button("Allow Motion Access") {
                    hasRequested = true
                    appState.motionManager.startActivityUpdates()
                }
                .buttonStyle(MTPrimaryButtonStyle())
                .disabled(hasRequested && !appState.motionManager.isAuthorized)

                Button("Skip") { vm.advance() }
                    .buttonStyle(MTSecondaryButtonStyle())
            }
        }
        .onChange(of: appState.motionManager.isAuthorized) { _, granted in
            if granted {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { vm.advance() }
            }
        }
    }
}

private struct MotionRow: View {
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
