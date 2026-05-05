import SwiftUI

struct WelcomeStep: View {
    let vm: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: MTSpacing.lg) {
                // Logo / Icon
                ZStack {
                    Circle()
                        .fill(Color.mtGreen.opacity(0.15))
                        .frame(width: 100, height: 100)
                    Image(systemName: "car.fill")
                        .font(.system(size: 44, weight: .medium))
                        .foregroundStyle(Color.mtGreen)
                }

                VStack(spacing: MTSpacing.sm) {
                    Text("Mileage Tracker")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Color.mtTextPrimary)

                    Text("Automatic trip tracking for sole traders.\nYour data. Your device. Your iCloud.")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.mtTextSub)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Feature bullets
                VStack(alignment: .leading, spacing: MTSpacing.md) {
                    FeatureBullet(icon: "location.fill",
                                  color: .mtGreen,
                                  title: "Automatic trip detection",
                                  detail: "GPS + motion sensors detect drives — no manual starts needed")
                    
                    // TODO: Move country first & have a dictionary of country -> tax services ready
                    FeatureBullet(icon: "doc.text.fill",
                                  color: .blue,
                                  title: "Tax-ready reports",
                                  detail: "Export IRD or ATO compliant mileage logs as PDF")
                    FeatureBullet(icon: "lock.icloud.fill",
                                  color: .purple,
                                  title: "Privacy first",
                                  detail: "All data stays on your device and your iCloud")
                }
                .padding(MTSpacing.md)
                .mtCard()
            }

            Spacer()

            Button("Get Started") { vm.advance() }
                .buttonStyle(MTPrimaryButtonStyle())
                .padding(.horizontal, MTSpacing.lg)
                .padding(.bottom, MTSpacing.xl)
        }
    }
}

private struct FeatureBullet: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: MTSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(detail).font(.system(size: 13)).foregroundStyle(Color.mtTextSub)
            }
        }
    }
}
