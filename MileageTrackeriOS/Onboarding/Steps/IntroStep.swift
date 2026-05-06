import SwiftUI

struct IntroStep: View {
    let vm: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: MTSpacing.lg) {
                ZStack {
                    Circle()
                        .fill(Color.mtGreen.opacity(0.12))
                        .frame(width: 88, height: 88)
                    Image(systemName: "gauge.with.dots.needle.33percent")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(Color.mtGreen)
                }

                VStack(spacing: MTSpacing.sm) {
                    Text("Mileage Tracker")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(Color.mtTextPrimary)
                    Text("Automatically track your drives and simplify your mileage claims.")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.mtTextSub)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, MTSpacing.lg)
                }

                // Quick value props
                VStack(alignment: .leading, spacing: MTSpacing.md) {
                    IntroRow(icon: "car.fill", color: .mtGreen, text: "Detects trips automatically")
                    IntroRow(icon: "bolt.shield.fill", color: .blue, text: "Stays private on your device")
                    IntroRow(icon: "battery.75", color: .orange, text: "Battery-friendly background tracking")
                }
                .padding(MTSpacing.lg)
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

private struct IntroRow: View {
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
