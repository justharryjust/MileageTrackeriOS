// TripRecorderDebugView — Developer tool for injecting simulated OS events
// into the live TripRecorder state machine.
//
// Events injected here travel through exactly the same code paths as real OS events,
// making this the fastest way to exercise the detection heuristics without getting
// in a car.
//
// Visible only via Settings → Diagnostics → Trip Recorder State.

import SwiftUI
import CoreLocation
import CoreMotion
struct TripRecorderDebugView: View {
    @Environment(AppState.self) private var appState
    @State private var simulatedSpeedKmh: Double = 50
    @State private var simulatedAccuracy: Double = 10
    @State private var eventLog: [DebugEvent] = []

    private var recorder: TripRecorder { appState.tripRecorder }
    private var location: LocationManager { appState.locationManager }
    private var motion: MotionManager  { appState.motionManager }
    private var bluetooth: BluetoothManager { appState.bluetoothManager }

    var body: some View {
        List {
            stateSection
            statusSection
            motionSection
            locationSection
            carKitSection
            visitSection
            pedometerBatterySection
            logSection
        }
        .navigationTitle("Trip Recorder Debug")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Live Status (Location & Motion)

    private var statusSection: some View {
        Section {
            DebugRow(label: "Location Auth", value: location.authorizationStatus.debugLabel)
            DebugRow(label: "High Accuracy GPS", value: location.isHighAccuracyActive ? "ON ▲" : "off ▼")
            if let loc = location.currentLocation {
                DebugRow(label: "Lat / Lng", value: String(format: "%.5f, %.5f", loc.coordinate.latitude, loc.coordinate.longitude))
                DebugRow(label: "Speed", value: loc.speed >= 0 ? String(format: "%.1f km/h", loc.speed * 3.6) : "—")
                DebugRow(label: "Accuracy", value: String(format: "±%.0fm", loc.horizontalAccuracy))
            }
            DebugRow(label: "Motion Available", value: motion.isAvailable ? "yes" : "no")
            DebugRow(label: "Motion Auth", value: motion.isAuthorized ? "yes ✅" : "no ⚠️")
            if let act = motion.currentActivity {
                DebugRow(label: "Last Activity", value: "\(act)")
            }
            DebugRow(label: "Trip Duration", value: recorder.state.durationString() ?? "—")
            DebugRow(label: "Trip Distance", value: recorder.state.distanceString() ?? "—")
        } header: {
            Label("Live Status", systemImage: "chart.bar.xaxis")
        }
    }

    // MARK: - Current State

    private var stateSection: some View {
        Section {
            HStack {
                Circle()
                    .fill(stateColor)
                    .frame(width: 10, height: 10)
                Text(stateLabel)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                Spacer()
                Text("GPS: \(appState.locationManager.isHighAccuracyActive ? "HIGH ▲" : "low ▼")")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(appState.locationManager.isHighAccuracyActive ? Color.mtGreen : Color.mtTextSub)
            }
            if let loc = appState.locationManager.currentLocation {
                LabeledContent("Last fix") {
                    Text(String(format: "%.5f, %.5f  ±%.0fm  %.1f km/h",
                                loc.coordinate.latitude, loc.coordinate.longitude,
                                loc.horizontalAccuracy,
                                max(loc.speed, 0) * 3.6))
                    .font(.system(size: 11, design: .monospaced))
                }
            }
            if let activity = appState.motionManager.currentActivity {
                LabeledContent("Last activity") {
                    Text("\(activity.description)")
                        .font(.system(size: 11, design: .monospaced))
                }
            }
        } header: {
            Label("Current State", systemImage: "waveform")
        }
    }

    // MARK: - Motion Activity Injection

    private var motionSection: some View {
        Section {
            // The four buttons you asked for
            Group {
                DebugButton(
                    label: "Stationary — Low Confidence",
                    icon: "pause.circle", color: .gray
                ) { inject(.stationary, .low) }

                DebugButton(
                    label: "Stationary — High Confidence",
                    icon: "pause.circle.fill", color: .orange
                ) { inject(.stationary, .high) }

                DebugButton(
                    label: "Automotive — Low Confidence",
                    icon: "car", color: .gray
                ) { inject(.automotive, .low) }

                DebugButton(
                    label: "Automotive — High Confidence",
                    icon: "car.fill", color: .mtGreen
                ) { inject(.automotive, .high) }
            }

            // Additional useful activity types
            Group {
                DebugButton(
                    label: "Walking — High Confidence",
                    icon: "figure.walk", color: .blue
                ) { inject(.walking, .high) }

                DebugButton(
                    label: "Cycling — High Confidence",
                    icon: "bicycle", color: .purple
                ) { inject(.cycling, .high) }
            }
        } header: {
            Label("Motion Activity Events", systemImage: "figure.run")
        } footer: {
            Text("Events are routed through MotionManager.onActivityUpdate — identical path to real CMMotionActivityManager callbacks.")
                .font(.caption)
        }
    }

    // MARK: - Location Injection

    private var locationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Speed")
                    Spacer()
                    Text(String(format: "%.0f km/h", simulatedSpeedKmh))
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Color.mtGreen)
                }
                Slider(value: $simulatedSpeedKmh, in: 0...140, step: 5)
                    .tint(Color.mtGreen)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Accuracy")
                    Spacer()
                    Text(String(format: "±%.0f m", simulatedAccuracy))
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Color.mtGreen)
                }
                Slider(value: $simulatedAccuracy, in: 5...500, step: 5)
                    .tint(simulatedAccuracy > 100 ? .orange : Color.mtGreen)
            }

            DebugButton(label: "Inject Location Fix", icon: "location.fill", color: .mtGreen) {
                injectLocation(speedKmh: simulatedSpeedKmh, accuracy: simulatedAccuracy)
            }

            DebugButton(label: "Inject Slow Crawl (3 km/h)", icon: "location", color: .orange) {
                injectLocation(speedKmh: 3, accuracy: 15)
            }

            DebugButton(label: "Inject Motorway Speed (100 km/h)", icon: "road.lanes", color: .blue) {
                injectLocation(speedKmh: 100, accuracy: 8)
            }

            DebugButton(label: "Inject Stationary Fix (0 km/h)", icon: "location.slash", color: .gray) {
                injectLocation(speedKmh: 0, accuracy: 20)
            }
        } header: {
            Label("Location Events", systemImage: "location")
        } footer: {
            Text("Fixes use device's current coordinates (or a default if unavailable). Routed through LocationManager.onLocationUpdate.")
                .font(.caption)
        }
    }

    // MARK: - Car Kit Injection

    private var carKitSection: some View {
        Section {
            if let name = bluetooth.connectedCarKitName {
                DebugRow(label: "Connected Kit", value: name)
            } else {
                DebugRow(label: "Connected Kit", value: "none")
            }

            DebugButton(
                label: "Simulate Car Kit Connected",
                icon: "car.side.and.exclamationmark", color: .mtGreen
            ) {
                let event = CarKitEvent(type: .connected, deviceName: "Debug Car Kit", portUID: "debug.uid", timestamp: Date())
                log("Car kit connected: \"\(event.deviceName)\"")
                bluetooth.onCarKitConnected?(event)
            }

            DebugButton(
                label: "Simulate Car Kit Disconnected",
                icon: "car.side.and.exclamationmark", color: .red
            ) {
                let name = bluetooth.connectedCarKitName ?? "Debug Car Kit"
                let event = CarKitEvent(type: .disconnected, deviceName: name, portUID: "debug.uid", timestamp: Date())
                log("Car kit disconnected: \"\(event.deviceName)\"")
                bluetooth.onCarKitDisconnected?(event)
            }
        } header: {
            Label("Car Kit Events", systemImage: "car.side")
        } footer: {
            Text("Connect fires pre-arm and anchors trip start. Disconnect mid-trip no longer ends immediately — soft signal (motion + speed recency, charging) holds the trip alive per v2 rules.")
                .font(.caption)
        }
    }

    private var visitSection: some View {
        Section {
            DebugButton(
                label: "Simulate Visit Departure (now)",
                icon: "figure.walk.departure", color: .indigo
            ) {
                let now = Date()
                log("Visit departure injected at \(now.formatted(date: .omitted, time: .standard))")
                location.onVisitDeparture?(now)
                location.onBackgroundWake?(Date(timeIntervalSinceNow: -300))
            }

            DebugButton(
                label: "Simulate Visit Arrival (now)",
                icon: "figure.walk.arrival", color: .teal
            ) {
                log("Visit arrival injected")
                location.onVisitArrival?()
            }

            DebugButton(
                label: "Simulate Significant Location Wake",
                icon: "antenna.radiowaves.left.and.right", color: .teal
            ) {
                let since = Date(timeIntervalSinceNow: -300)
                log("Significant-location wake injected (since 5 min ago)")
                location.onBackgroundWake?(since)
            }

            DebugButton(
                label: "Force Trip Finalisation",
                icon: "stop.fill", color: .red
            ) {
                if recorder.state.isRecording {
                    log("Force finalise — state: \(recorder.state.displayTitle)")
                    recorder.forceFinaliseFromDebug()
                } else {
                    log("⚠️ Not recording — cannot finalise")
                }
            }
        } header: {
            Label("Visit & Wake Events", systemImage: "bell.and.waveform")
        } footer: {
            Text("Visit departure triggers the pre-arm window AND the motion catch-up query — same as a real background wake.")
                .font(.caption)
        }
    }

    // MARK: - Pedometer / Battery Injection

    private var pedometerBatterySection: some View {
        Section {
            DebugButton(
                label: "Inject Pedometer Steps (0)",
                icon: "shoeprints.fill", color: .gray
            ) {
                log("Pedometer: 0 steps in 30s")
                motion.onPedometerUpdate?(0)
            }

            DebugButton(
                label: "Inject Pedometer Steps (15)",
                icon: "shoeprints.fill", color: .blue
            ) {
                log("Pedometer: 15 steps in 30s")
                motion.onPedometerUpdate?(15)
            }

            DebugButton(
                label: "Inject Pedometer Steps (45) — triggers walking",
                icon: "shoeprints.fill", color: .red
            ) {
                log("Pedometer: 45 steps in 30s — walking threshold")
                motion.onPedometerUpdate?(45)
            }

            DebugButton(
                label: "Inject Battery: Charging",
                icon: "battery.100.bolt", color: .mtGreen
            ) {
                log("Battery state: charging")
                motion.onBatteryStateChange?(.charging)
            }

            DebugButton(
                label: "Inject Battery: Unplugged",
                icon: "battery.75", color: .orange
            ) {
                log("Battery state: unplugged")
                motion.onBatteryStateChange?(.unplugged)
            }
        } header: {
            Label("Pedometer & Battery", systemImage: "sensor.fill")
        } footer: {
            Text("Pedometer steps > 30 in 30s triggers walking rejection. Battery charging during trip counts as soft engine signal.")
                .font(.caption)
        }
    }

    // MARK: - Event Log

    private var logSection: some View {
        Section {
            if eventLog.isEmpty {
                Text("No events yet").foregroundStyle(Color.mtTextSub).font(.caption)
            } else {
                ForEach(eventLog.reversed()) { event in
                    HStack(alignment: .top, spacing: 8) {
                        Text(event.time)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.mtTextSub)
                            .frame(width: 60, alignment: .leading)
                        Text(event.message)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Color.mtTextPrimary)
                    }
                }
            }
        } header: {
            HStack {
                Label("Event Log", systemImage: "list.bullet.rectangle")
                Spacer()
                if !eventLog.isEmpty {
                    Button("Clear") { eventLog.removeAll() }
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - Injection Helpers

    private func inject(_ type: DetectedActivity.ActivityType, _ confidence: CMMotionActivityConfidence) {
        let confLabel = confidence == .high ? "high" : confidence == .medium ? "medium" : "low"
        log("\(type) (\(confLabel))")
        let activity = DetectedActivity(type: type, confidence: confidence, timestamp: Date())
        motion.onActivityUpdate?(activity)
    }

    private func injectLocation(speedKmh: Double, accuracy: Double) {
        let base = appState.locationManager.currentLocation?.coordinate
            ?? CLLocationCoordinate2D(latitude: -36.8485, longitude: 174.7633) // Auckland CBD default
        let loc = CLLocation(
            coordinate       : base,
            altitude         : 10,
            horizontalAccuracy: accuracy,
            verticalAccuracy : 5,
            course           : 0,
            speed            : speedKmh / 3.6,
            timestamp        : Date()
        )
        log("location fix — \(String(format: "%.0f km/h ±%.0fm", speedKmh, accuracy))")
        location.onLocationUpdate?(loc)
    }

    private func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let event = DebugEvent(time: formatter.string(from: Date()), message: message)
        eventLog.append(event)
        if eventLog.count > 50 { eventLog.removeFirst() }
    }

    // MARK: - State Helpers

    private var stateLabel: String {
        switch recorder.state {
        case .idle:                                    return "idle"
        case .suspected(let since, let reason):        return "suspected (\(Int(abs(since.timeIntervalSinceNow)))s \(reason))"
        case .active(_, let dist):                     return "active (\(String(format: "%.0f", dist / 1000))km)"
        case .pausing(_, let dist, let ps):            return "pausing (\(String(format: "%.0f", dist / 1000))km paused \(Int(abs(ps.timeIntervalSinceNow)))s)"
        case .ending(_, let dist, let reason):         return "ending (\(String(format: "%.0f", dist / 1000))km \(reason))"
        }
    }

    private var stateColor: Color {
        switch recorder.state {
        case .idle:        return .gray
        case .suspected:   return .orange
        case .active:      return .mtGreen
        case .pausing:     return .orange
        case .ending:      return .red
        }
    }
}

private struct DebugButton: View {
    let label: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
        }
    }
}

private struct DebugEvent: Identifiable {
    let id = UUID()
    let time: String
    let message: String
}

// MARK: - DebugRow

struct DebugRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Color.mtTextSub)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.mtTextPrimary)
        }
    }
}

// MARK: - CLAuthorizationStatus debug label

extension CLAuthorizationStatus {
    var debugLabel: String {
        switch self {
        case .notDetermined:       return "notDetermined"
        case .restricted:          return "restricted"
        case .denied:              return "denied ⚠️"
        case .authorizedAlways:    return "always ✅"
        case .authorizedWhenInUse: return "whenInUse"
        @unknown default:          return "unknown"
        }
    }
}
