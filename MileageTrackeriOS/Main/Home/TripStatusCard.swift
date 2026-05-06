// TripStatusCard — The most important piece of live UI in the app.
// Shows the current TripRecorderState with animated indicators.

import SwiftUI

struct TripStatusCard: View {
    @Environment(AppState.self) private var appState
    @State private var elapsedSeconds: Int = 0
    @State private var timer: Timer?
    @State private var pulseScale: CGFloat = 1.0

    private var state: TripRecorderState {
        appState.tripRecorder.state
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top status row
            HStack(alignment: .center, spacing: MTSpacing.md) {
                // Animated status dot
                StatusDot(state: state, pulseScale: pulseScale)

                // Title + subtitle
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.displayTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.mtTextPrimary)

                    Group {
                        switch state {
                        case .idle:
                            Text("Waiting for your next drive")
                        case .suspected(let since, _):
                            Text("Confirming drive… \(Int(Date().timeIntervalSince(since)))s")
                        case .active:
                            HStack(spacing: MTSpacing.sm) {
                                if let dist = state.distanceString() {
                                    Label(dist, systemImage: "arrow.right")
                                }
                                if let dur = state.durationString() {
                                    Label(dur, systemImage: "timer")
                                }
                            }
                        case .pausing(_, _, let pauseStart):
                            Text("Paused — \(Int(Date().timeIntervalSince(pauseStart)))s")
                        case .ending(_, _, let reason):
                            Text(reason == .walkingDetected ? "Walking detected — finishing…" : "Finishing trip…")
                        }
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Color.mtTextSub)
                }

                Spacer()

                // Vehicle badge
                if let vehicle = appState.profileRepo.defaultVehicle {
                    VehicleBadge(vehicle: vehicle)
                }
            }
            .padding(MTSpacing.md)

            // Expanded recording info strip
            if state.isRecording {
                Divider().padding(.horizontal, MTSpacing.md)
                RecordingStrip(locationManager: appState.locationManager)
                    .padding(MTSpacing.md)
            }
        }
        .mtCard()
        .overlay(
            RoundedRectangle(cornerRadius: MTRadius.lg)
                .strokeBorder(
                    state.isActive ? Color.mtRecording.opacity(0.4) : Color.clear,
                    lineWidth: 1.5
                )
        )
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        .onAppear { startTimerIfNeeded() }
        .onDisappear { stopTimer() }
        .onChange(of: state) { _, _ in startTimerIfNeeded() }
        .animation(.easeInOut(duration: 0.3), value: state.isActive)
    }

    // MARK: - Timer for elapsed display

    private func startTimerIfNeeded() {
        stopTimer()
        if state.isActive {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                elapsedSeconds += 1
            }
        }
        // Pulse animation for recording states
        if state.isRecording {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulseScale = 1.35
            }
        } else {
            pulseScale = 1.0
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Status Dot

private struct StatusDot: View {
    let state: TripRecorderState
    let pulseScale: CGFloat

    var dotColor: Color {
        switch state {
        case .idle:      return Color.mtBorder
        case .suspected: return Color.mtWarning
        case .active:    return Color.mtRecording
        case .pausing:   return Color.orange
        case .ending:    return Color.mtGreenDark
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(dotColor.opacity(0.25))
                .frame(width: 36, height: 36)
                .scaleEffect(state.isActive ? pulseScale : 1.0)

            Circle()
                .fill(dotColor)
                .frame(width: 14, height: 14)
        }
    }
}

// MARK: - Vehicle Badge

private struct VehicleBadge: View {
    let vehicle: Vehicle

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Image(systemName: vehicle.type.icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.mtGreen)
            Text(vehicle.registration)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.mtTextSub)
        }
    }
}

// MARK: - Recording Strip (speed, accuracy)

private struct RecordingStrip: View {
    let locationManager: LocationManager

    private var speedText: String {
        let speed = locationManager.lastKnownSpeed
        guard speed >= 0 else { return "—" }
        return String(format: "%.0f km/h", speed * 3.6)
    }

    var body: some View {
        HStack {
            StatPill(icon: "speedometer", label: speedText, color: .mtGreen)
            Spacer()
            StatPill(icon: "location.fill", label: locationManager.hasAlwaysAuthorization ? "Always" : "When In Use", color: .blue)
        }
    }
}

private struct StatPill: View {
    let icon: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(color)
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.mtTextSub)
        }
        .padding(.horizontal, MTSpacing.sm)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }
}
