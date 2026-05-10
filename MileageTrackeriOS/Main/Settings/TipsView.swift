import SwiftUI

struct TipsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MTSpacing.lg) {
                // Header
                VStack(alignment: .leading, spacing: MTSpacing.sm) {
                    Text("Tips for Best Results")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.mtTextPrimary)
                    Text("Simple things that make trip tracking more accurate and reliable.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.mtTextSub)
                }

                // Tips
                TipCard(
                    icon: "car.2.fill", color: .mtGreen,
                    title: "Mount or place your phone where it can see the sky",
                    detail: "The centre console, dashboard mount, or cup holder gives the clearest GPS signal and most reliable motion detection. A pocket or bag is fine for most trips, but GPS accuracy may be reduced."
                )

                TipCard(
                    icon: "location.fill", color: .blue,
                    title: "Keep location set to Always Allow",
                    detail: "Trip detection works in the background — you don't need to open the app. If you accidentally set it to \"While Using,\" the app can only track trips while it's open on screen."
                )

                TipCard(
                    icon: "antenna.radiowaves.left.and.right", color: .orange,
                    title: "Leave Bluetooth on",
                    detail: "Even if your car doesn't have CarPlay or a Bluetooth kit, having Bluetooth enabled helps iOS understand when you're in a vehicle. If your car does have Bluetooth, connecting to it makes detection nearly instant."
                )

                TipCard(
                    icon: "battery.100.bolt", color: .mtGreen,
                    title: "Plug in to charge while you drive",
                    detail: "Charging during a drive confirms you're in a vehicle and helps the app tolerate longer pauses — like drive-thrus and traffic lights — without ending the trip early."
                )

                TipCard(
                    icon: "hand.raised.slash.fill", color: .red,
                    title: "Don't force-quit the app",
                    detail: "Swipe-killing the app prevents it from relaunching for motion events. The app can still wake for significant location changes and geofence exits, but detection may be delayed. Just let it run in the background."
                )

                TipCard(
                    icon: "battery.25", color: .orange,
                    title: "Avoid Low Power Mode if you want the best tracking",
                    detail: "Low Power Mode reduces how often iOS samples GPS and motion data. The app still works, but trip polylines may be less detailed and start detection may be slower."
                )

                TipCard(
                    icon: "speedometer", color: .blue,
                    title: "If you use the logbook method, record odometer readings regularly",
                    detail: "A quick reading once a week — especially at the start and end of your logbook period — gives you an accurate total-distance figure that the tax department expects."
                )

                TipCard(
                    icon: "tag.fill", color: .purple,
                    title: "Categorise trips promptly",
                    detail: "Swipe trips as Business or Personal soon after they appear. Personal trips are automatically deleted after 7 days, but business trips are kept for your records and reports."
                )

                TipCard(
                    icon: "play.fill", color: .mtGreen,
                    title: "Use manual start as a backup",
                    detail: "If you know you're about to drive and want to be certain it's tracked, tap Start Trip on the home screen. You can stop it manually when you arrive — it's a reliable fallback."
                )

                TipCard(
                    icon: "arrow.triangle.2.circlepath", color: .teal,
                    title: "The first few trips teach the app where you park",
                    detail: "After a week or two of driving, the app learns your regular parking spots and can detect trip starts almost instantly. The experience improves the more you use it."
                )

                Spacer(minLength: MTSpacing.xxl)
            }
            .padding(MTSpacing.lg)
        }
        .background(Color.mtBackground)
        .navigationTitle("Tips")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Tip Card

private struct TipCard: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: MTSpacing.md) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(color)
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.mtTextPrimary)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.mtTextSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(MTSpacing.md)
        .background(Color.mtSurface)
        .clipShape(RoundedRectangle(cornerRadius: MTRadius.md))
    }
}
