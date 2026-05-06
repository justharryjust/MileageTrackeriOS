import SwiftUI

struct WelcomeStep: View {
    @Environment(AppState.self) private var appState
    let vm: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: MTSpacing.lg) {
                ZStack {
                    Circle()
                        .fill(Color.mtGreen.opacity(0.12))
                        .frame(width: 88, height: 88)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44, weight: .medium))
                        .foregroundStyle(Color.mtGreen)
                }

                VStack(spacing: MTSpacing.sm) {
                    Text("You're all set")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color.mtTextPrimary)

                    Text("MileageTracker will automatically detect and log your trips in the background.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.mtTextSub)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, MTSpacing.lg)
                }

                VStack(alignment: .leading, spacing: MTSpacing.sm) {
                    SummaryRow(icon: "location.fill",   color: .mtGreen,  text: "Location access granted")
                    SummaryRow(icon: "figure.walk",     color: .blue,     text: "Motion detection ready")
                    SummaryRow(icon: "car.fill",        color: .orange,   text: "Vehicle added")
                    SummaryRow(icon: "clock.fill",      color: .purple,   text: "Tracking schedule configured")
                }
                .padding(MTSpacing.md)
                .mtCard()
            }

            Spacer()

            Button("Start Tracking") { vm.complete(using: appState) }
                .buttonStyle(MTPrimaryButtonStyle())
                .padding(.horizontal, MTSpacing.lg)
                .padding(.bottom, MTSpacing.xl)
        }
    }
}

private struct SummaryRow: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: MTSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
                .frame(width: 24)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(Color.mtTextPrimary)
        }
    }
}
