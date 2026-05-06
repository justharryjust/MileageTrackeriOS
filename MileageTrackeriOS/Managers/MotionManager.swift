// MotionManager — CMMotionActivityManager wrapper
// Classifies current physical activity (automotive, walking, stationary, etc.)
// and feeds that signal into TripRecorder to make trip start/end decisions.
//
// BACKGROUND BEHAVIOUR:
//  • Updates are delivered to a dedicated serial background OperationQueue, not .main.
//    This ensures the M-series coprocessor can deliver batched updates during brief
//    background wakes (visit departure, significant-location) without waiting for the
//    main run loop to resume.
//  • @Observable state mutations are dispatched back to @MainActor explicitly.
//  • queryRecentActivity(since:) should be called whenever the app is woken from
//    background (AppDelegate/SceneDelegate applicationDidBecomeActive or background task)
//    to catch up on any activities that occurred while the app was fully suspended.

import Foundation
import CoreMotion

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

    // Callback fires on each new activity — TripRecorder subscribes
    var onActivityUpdate: ((DetectedActivity) -> Void)?

    // MARK: Private
    private let activityManager = CMMotionActivityManager()
    private let logger = TripLogger.shared
    private var isStarted = false

    /// Dedicated background queue for CMMotionActivityManager delivery.
    /// Using a background queue means updates are processed even during brief
    /// background wakes — the coprocessor doesn't wait for the main run loop.
    private let motionQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.mileagetracker.motionqueue"
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .utility
        return q
    }()

    // MARK: - Start / Stop

    func startActivityUpdates() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            logger.log("CMMotionActivityManager not available on this device", category: .motion)
            return
        }
        guard !isStarted else { return }
        isStarted = true

        activityManager.startActivityUpdates(to: motionQueue) { [weak self] activity in
            guard let self, let activity else { return }
            let detected = self.classify(activity)
            // Dispatch @Observable mutations and callbacks back to MainActor
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
        guard isStarted else { return }
        isStarted = false
        activityManager.stopActivityUpdates()
        logger.log("Stopped CMMotionActivityManager updates", category: .motion)
    }

    // MARK: - Catch-up query for background wakes
    //
    // Call this when the app is woken from background (e.g. visit departure,
    // significant-location change). It queries the coprocessor history for
    // activities since `since` and replays them through the normal callback
    // in chronological order, so TripRecorder can reconstruct what happened
    // while the app was suspended.

    func queryRecentActivity(since: Date) {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        // queryActivityStarting triggers the system permission dialog on first call —
        // same as startActivityUpdates. Only run the catch-up query once the user has
        // explicitly granted access, otherwise a background location wake during
        // onboarding would show the motion prompt before the user reaches that step.
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
            // Replay in order on MainActor so TripRecorder state machine processes them sequentially
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

    // MARK: - Classification

    private func classify(_ activity: CMMotionActivity) -> DetectedActivity {
        let type: DetectedActivity.ActivityType
        // Priority order: automotive > cycling > running > walking > stationary
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
