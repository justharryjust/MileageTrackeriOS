// BluetoothManager — Detects car kit (hands-free audio) connect/disconnect events.
//
// Uses AVAudioSession route-change notifications rather than CoreBluetooth.
// CoreBluetooth requires the user to explicitly pair in-app and runs a continuous
// BLE scan which is expensive. AVAudioSession receives a system notification the
// moment the audio route changes — zero ongoing battery cost, no extra permissions,
// and it catches all audio output sources (Bluetooth HFP, CarPlay, wired CarKit).
//
// HOW IT INFORMS TRIP DETECTION:
//  • Connect  → pre-arms TripRecorder (same window as a CLVisit departure).
//              If automotive motion follows within 10 min, the trip start is
//              anchored to the connection time.
//  • Disconnect → if currently recording, starts the stationary-end window
//              immediately (no need to wait for the motion heuristic).
//              This mirrors what happens when you turn the engine off.
//
// BACKGROUND BEHAVIOUR:
//  AVAudioSession route-change notifications are delivered on a background
//  queue while the app is running. When the app is suspended the notification
//  is not delivered — however a CLVisit departure or significant-location wake
//  will occur shortly after driving starts, so the motion catch-up query
//  fills the gap. The car-kit connect time is still stored on the Trip for
//  analytics even when detected post-hoc via the debug injector.

import Foundation
import AVFoundation

// MARK: - CarKit Event

struct CarKitEvent {
    enum EventType { case connected, disconnected }
    let type      : EventType
    let deviceName: String
    let portUID   : String?   // AVAudioSessionPortDescription.uid — stable-enough BT fingerprint
    let timestamp : Date
}

// MARK: - BluetoothManager

@Observable
final class BluetoothManager {

    // MARK: Published state
    /// Name of the currently connected car-kit device, nil when none.
    private(set) var connectedCarKitName: String?

    // MARK: Callbacks — wired by TripRecorder.configure
    var onCarKitConnected   : ((CarKitEvent) -> Void)?
    var onCarKitDisconnected: ((CarKitEvent) -> Void)?

    private let logger = TripLogger.shared
    private var isObserving = false

    // MARK: - Start / Stop

    func startMonitoring() {
        guard !isObserving else { return }
        isObserving = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(routeDidChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )

        // Capture whatever is already connected at launch
        refreshCurrentRoute(reason: "initial")
        logger.log("BluetoothManager: started AVAudioSession route monitoring", category: .system)
    }

    func stopMonitoring() {
        guard isObserving else { return }
        isObserving = false
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
        logger.log("BluetoothManager: stopped route monitoring", category: .system)
    }

    // MARK: - Route Change Handler

    @objc private func routeDidChange(_ notification: Notification) {
        guard
            let info   = notification.userInfo,
            let reason = info[AVAudioSessionRouteChangeReasonKey] as? UInt
        else { return }

        let changeReason = AVAudioSession.RouteChangeReason(rawValue: reason) ?? .unknown

        switch changeReason {
        case .newDeviceAvailable:
            // A new output was added — check if it's a car-kit type
            let session  = AVAudioSession.sharedInstance()
            let carPorts = carKitPorts(in: session.currentRoute.outputs)
            if let port = carPorts.first {
                let name = port.portName
                let uid  = port.uid
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.connectedCarKitName = name
                    let event = CarKitEvent(type: .connected, deviceName: name, portUID: uid, timestamp: Date())
                    self.logger.log("Car kit connected: \"\(name)\" uid:\(uid)", category: .system)
                    self.onCarKitConnected?(event)
                }
            }

        case .oldDeviceUnavailable:
            // A device was removed — check if it was our car kit
            guard let previous = info[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription else { return }
            let removedCarPorts = carKitPorts(in: previous.outputs)
            if let port = removedCarPorts.first {
                let name = port.portName
                let uid  = port.uid
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.connectedCarKitName = nil
                    let event = CarKitEvent(type: .disconnected, deviceName: name, portUID: uid, timestamp: Date())
                    self.logger.log("Car kit disconnected: \"\(name)\" uid:\(uid)", category: .system)
                    self.onCarKitDisconnected?(event)
                }
            }

        default:
            break
        }
    }

    // MARK: - Helpers

    private func refreshCurrentRoute(reason: String) {
        let outputs  = AVAudioSession.sharedInstance().currentRoute.outputs
        let carPorts = carKitPorts(in: outputs)
        DispatchQueue.main.async { [weak self] in
            self?.connectedCarKitName = carPorts.first?.portName
        }
        if let name = carPorts.first?.portName {
            logger.log("BluetoothManager (\(reason)): car kit already connected — \"\(name)\"", category: .system)
        }
    }

    /// Returns any output ports that represent a car-kit / hands-free audio route.
    /// Only includes profiles that are near-universal in cars and absent from
    /// consumer headphones. A2DP and BLE are excluded — AirPods, Beats, and other
    /// headphones use them and would false-trigger car-kit detection.
    private func carKitPorts(in outputs: [AVAudioSessionPortDescription]) -> [AVAudioSessionPortDescription] {
        let carKitTypes: Set<AVAudioSession.Port> = [
            .bluetoothHFP,   // Hands-Free Profile — phone calls in car
            .carAudio,       // CarPlay
        ]
        return outputs.filter { carKitTypes.contains($0.portType) }
    }
}
