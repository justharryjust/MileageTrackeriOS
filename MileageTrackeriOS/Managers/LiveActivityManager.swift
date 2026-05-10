// LiveActivityManager — Bridges TripRecorder state to Live Activities (Lock Screen + Dynamic Island).
// Gracefully does nothing on iOS < 16.2 or when ActivityKit is unavailable.

import Foundation
import ActivityKit

// MARK: - Shared Activity Attributes
// This type must be identical in both the main app and the Widget Extension target.
// When creating the Widget Extension in Xcode, add a reference to this file in that target too.

struct TripActivityAttributes: ActivityAttributes {
    var vehicleName: String

    struct ContentState: Codable, Hashable {
        var startedAt: Date
        var distanceMetres: Double
        var elapsedSeconds: Int { Int(Date().timeIntervalSince(startedAt)) }

        var distanceKm: Double { distanceMetres / 1000 }

        var distanceDisplay: String {
            if distanceMetres < 1000 {
                return String(format: "%.0f m", distanceMetres)
            }
            return String(format: "%.1f km", distanceKm)
        }

        var durationDisplay: String {
            let h = elapsedSeconds / 3600
            let m = (elapsedSeconds % 3600) / 60
            let s = elapsedSeconds % 60
            if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
            return String(format: "%02d:%02d", m, s)
        }
    }
}

@Observable
final class LiveActivityManager {
    private var currentActivity: Activity<TripActivityAttributes>?
    private var lastUpdateTimestamp: Date?
    private let minimumUpdateInterval: TimeInterval = 5  // throttle updates

    /// UserDefaults key — toggle in Settings.
    static let liveActivityEnabledKey = "com.mileagetracker.liveActivityEnabled"

    /// Whether the user has enabled Live Activities in Settings. Defaults to true.
    static var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: liveActivityEnabledKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: liveActivityEnabledKey)
    }

    /// Start a Live Activity when the trip enters Active state.
    func startTrip(vehicleName: String, startedAt: Date) {
        guard Self.isEnabled else {
            TripLogger.shared.log("Live Activity: disabled in Settings — skipping", category: .system)
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            TripLogger.shared.log("Live Activity: not authorised — skipping", category: .system)
            return
        }

        let attributes = TripActivityAttributes(vehicleName: vehicleName)
        let state = TripActivityAttributes.ContentState(
            startedAt: startedAt,
            distanceMetres: 0
        )

        do {
            let activity = try Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: nil))
            currentActivity = activity
            lastUpdateTimestamp = Date()
            TripLogger.shared.log("Live Activity started — vehicle: \"\(vehicleName)\"", category: .system)
        } catch {
            TripLogger.shared.log("Live Activity start failed: \(error.localizedDescription)", category: .error)
        }
    }

    /// Update distance while the trip is Active or Pausing. Throttled to every 5s.
    func updateTrip(distanceMetres: Double, startedAt: Date) {
        guard let activity = currentActivity else { return }
        if let last = lastUpdateTimestamp, Date().timeIntervalSince(last) < minimumUpdateInterval { return }

        let state = TripActivityAttributes.ContentState(
            startedAt: startedAt,
            distanceMetres: distanceMetres
        )

        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
            lastUpdateTimestamp = Date()
        }
    }

    /// End the Live Activity when the trip completes or is discarded.
    func endTrip() {
        guard let activity = currentActivity else { return }

        let finalState = activity.content.state
        Task {
            await activity.end(ActivityContent(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
            TripLogger.shared.log("Live Activity ended", category: .system)
        }
        currentActivity = nil
    }
}
