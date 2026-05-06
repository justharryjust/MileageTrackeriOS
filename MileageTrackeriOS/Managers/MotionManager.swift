// MotionManager — CoreMotion wrapper
// Classifies physical activity (automotive, walking, stationary, etc.),
// tracks pedometer step cadence, relative altitude changes, and battery state.
// Feeds all signals into TripRecorder for trip start/end decisions.
//
// BACKGROUND BEHAVIOUR:
//  • Activity updates are delivered to a dedicated serial background OperationQueue.
//  • Pedometer & altimeter updates run on their own internal queues.
//  • @Observable state mutations are dispatched back to @MainActor explicitly.
//  • queryRecentActivity(since:) replays missed activities after background wakes.

import Foundation
import CoreMotion
import UIKit

// MARK: - Detected Activity

struct DetectedActivity: CustomStringConvertible {
    let type      : ActivityType
    let confidence: CMMotionActivityConfidence
    let timestamp : Date

    enum ActivityType {
        case automotive
        case cycling
        case walking
        case running
        case stationary
        case unknown
    }

    var isAutomotive: Bool { type == .automotive }
    var isStationary: Bool { type == .stationary }

    var description: String {
        let conf: String
        switch confidence {
        case .low:    conf = "low"
        case .medium: conf = "medium"
        case .high:   conf = "high"
        @unknown default: conf = "?"
        }
        return "\(type) (\(conf))"
    }
}

// MARK: - MotionManager

@Observable
final class MotionManager {
    // MARK: Published state
    var currentActivity: DetectedActivity?
    var isAvailable: Bool = CMMotionActivityManager.isActivityAvailable()
    var isAuthorized: Bool = false
    var isPedometerAvailable: Bool = CMPedometer.isStepCountingAvailable()
    var isAltimeterAvailable: Bool = CMAltimeter.isRelativeAltitudeAvailable()

    // Callbacks — wired by TripRecorder
    var onActivityUpdate: ((DetectedActivity) -> Void)?
    var onPedometerUpdate: ((Int) -> Void)?       // step count in last 30s
    var onAltimeterUpdate: ((Double) -> Void)?     // relative altitude change (m)
    var onBatteryStateChange: ((UIDevice.BatteryState) -> Void)?

    // MARK: Private
    private let activityManager = CMMotionActivityManager()
    private let pedometer = CMPedometer()
    private let altimeter = CMAltimeter()
    private let logger = TripLogger.shared
    private var isActivityStarted = false
    private var isPedometerStarted = false
    private var isAltimeterStarted = false
    private var isBatteryObserving = false

    /// Rolling window of pedometer data for recent-step queries.
    private var pedometerHistory: [(timestamp: Date, steps: Int)] = []
    private let pedometerHistoryLock = NSLock()

    private let motionQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.mileagetracker.motionqueue"
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .utility
        return q
    }()

    // MARK: - Activity Updates

    func startActivityUpdates() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            logger.log("CMMotionActivityManager not available on this device", category: .motion)
            return
        }
        guard !isActivityStarted else { return }
        isActivityStarted = true

        activityManager.startActivityUpdates(to: motionQueue) { [weak self] activity in
            guard let self, let activity else { return }
            let detected = self.classify(activity)
            DispatchQueue.main.async {
                self.currentActivity = detected
                self.isAuthorized    = true
                self.logger.log("Motion activity: \(detected)", category: .motion)
                self.onActivityUpdate?(detected)
            }
        }
        logger.log("Started CMMotionActivityManager updates (background queue)", category: .motion)
    }

    func stopActivityUpdates() {
        guard isActivityStarted else { return }
        isActivityStarted = false
        activityManager.stopActivityUpdates()
        logger.log("Stopped CMMotionActivityManager updates", category: .motion)
    }

    // MARK: - Catch-up query for background wakes

    func queryRecentActivity(since: Date) {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        guard CMMotionActivityManager.authorizationStatus() == .authorized else {
            logger.log("Motion not authorized — skipping catch-up query", category: .motion)
            return
        }
        let now = Date()
        logger.log("Querying missed motion activities from \(since) to \(now)", category: .motion)

        activityManager.queryActivityStarting(from: since, to: now, to: motionQueue) { [weak self] activities, error in
            guard let self else { return }
            if let error {
                self.logger.log("Motion query error: \(error.localizedDescription)", category: .motion)
                return
            }
            guard let activities, !activities.isEmpty else {
                self.logger.log("Motion query: no missed activities", category: .motion)
                return
            }
            self.logger.log("Motion query: replaying \(activities.count) missed activities", category: .motion)
            let detected = activities.map { self.classify($0) }
            DispatchQueue.main.async {
                for activity in detected {
                    self.currentActivity = activity
                    self.isAuthorized    = true
                    self.onActivityUpdate?(activity)
                }
            }
        }
    }

    // MARK: - Pedometer

    func startPedometerUpdates(from start: Date) {
        guard CMPedometer.isStepCountingAvailable(), !isPedometerStarted else { return }
        isPedometerStarted = true

        pedometer.startUpdates(from: start) { [weak self] data, error in
            guard let self, let data, error == nil else { return }
            let steps = data.numberOfSteps.intValue
            let now = Date()
            self.pedometerHistoryLock.lock()
            self.pedometerHistory.append((now, steps))
            // Keep only last 120s
            while let first = self.pedometerHistory.first, now.timeIntervalSince(first.timestamp) > 120 {
                self.pedometerHistory.removeFirst()
            }
            self.pedometerHistoryLock.unlock()

            let recent = self.recentSteps(window: 30)
            DispatchQueue.main.async {
                self.onPedometerUpdate?(recent)
            }
        }
        logger.log("Started pedometer updates from \(start)", category: .motion)
    }

    func stopPedometerUpdates() {
        guard isPedometerStarted else { return }
        isPedometerStarted = false
        pedometer.stopUpdates()
        pedometerHistory.removeAll()
        logger.log("Stopped pedometer updates", category: .motion)
    }

    /// Steps counted in the last `window` seconds.
    func recentSteps(window: TimeInterval = 30) -> Int {
        pedometerHistoryLock.lock()
        defer { pedometerHistoryLock.unlock() }
        let cutoff = Date().addingTimeInterval(-window)
        guard let newest = pedometerHistory.last,
              let oldestIdx = pedometerHistory.lastIndex(where: { $0.timestamp <= cutoff }) else {
            // No data yet or all data is within window — return latest cumulative
            return pedometerHistory.last?.steps ?? 0
        }
        let oldest = pedometerHistory[oldestIdx]
        return max(0, newest.steps - oldest.steps)
    }

    // MARK: - Altimeter

    func startAltimeterUpdates() {
        guard CMAltimeter.isRelativeAltitudeAvailable(), !isAltimeterStarted else { return }
        isAltimeterStarted = true

        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
            guard let self, let data, error == nil else { return }
            let delta = data.relativeAltitude.doubleValue
            self.onAltimeterUpdate?(delta)
        }
        logger.log("Started altimeter updates", category: .motion)
    }

    func stopAltimeterUpdates() {
        guard isAltimeterStarted else { return }
        isAltimeterStarted = false
        altimeter.stopRelativeAltitudeUpdates()
        logger.log("Stopped altimeter updates", category: .motion)
    }

    // MARK: - Battery State

    func startBatteryMonitoring() {
        guard !isBatteryObserving else { return }
        isBatteryObserving = true
        UIDevice.current.isBatteryMonitoringEnabled = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(batteryStateDidChange),
            name: UIDevice.batteryStateDidChangeNotification,
            object: nil
        )

        // Fire current state immediately
        let state = UIDevice.current.batteryState
        DispatchQueue.main.async {
            self.onBatteryStateChange?(state)
        }
        logger.log("Started battery state monitoring (current: \(label(for: state)))", category: .motion)
    }

    func stopBatteryMonitoring() {
        guard isBatteryObserving else { return }
        isBatteryObserving = false
        UIDevice.current.isBatteryMonitoringEnabled = false
        NotificationCenter.default.removeObserver(self, name: UIDevice.batteryStateDidChangeNotification, object: nil)
        logger.log("Stopped battery state monitoring", category: .motion)
    }

    @objc private func batteryStateDidChange(_ notification: Notification) {
        let state = UIDevice.current.batteryState
        DispatchQueue.main.async { [weak self] in
            self?.logger.log("Battery state changed: \(self?.label(for: state) ?? "?")", category: .motion)
            self?.onBatteryStateChange?(state)
        }
    }

    /// Whether the device was observed to begin charging during the current trip context.
    /// TripRecorder manages the "during trip" part — this is just the current state.
    var isCharging: Bool {
        UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
    }

    private func label(for state: UIDevice.BatteryState) -> String {
        switch state {
        case .unknown:    return "unknown"
        case .unplugged:  return "unplugged"
        case .charging:   return "charging"
        case .full:       return "full"
        @unknown default: return "?"
        }
    }

    // MARK: - Classification

    private func classify(_ activity: CMMotionActivity) -> DetectedActivity {
        let type: DetectedActivity.ActivityType
        if activity.automotive {
            type = .automotive
        } else if activity.cycling {
            type = .cycling
        } else if activity.running {
            type = .running
        } else if activity.walking {
            type = .walking
        } else if activity.stationary {
            type = .stationary
        } else {
            type = .unknown
        }
        return DetectedActivity(type: type, confidence: activity.confidence, timestamp: activity.startDate)
    }
}
