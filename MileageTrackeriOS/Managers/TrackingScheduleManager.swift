// TrackingScheduleManager — Enforces the user's per-day tracking hour windows.
//
// DESIGN:
//  • isCurrentlyAllowed  → computed live from profile schedule + current time
//  • startMonitoring()   → schedules a Timer that fires at the next boundary
//    (start-of-window or end-of-window), then calls onBecameAllowed / onBecameDisallowed
//  • TripRecorder wires the callbacks to pause/resume trip detection
//
// BATTERY IMPACT:
//  A single Timer fires at most twice per day (window open, window close).
//  No polling, no location usage — effectively zero battery cost.

import Foundation

@Observable
final class TrackingScheduleManager {

    // MARK: Callbacks — wired by TripRecorder / AppState
    var onBecameAllowed   : (() -> Void)?
    var onBecameDisallowed: (() -> Void)?

    // MARK: Live state (read by UI and TripRecorder)
    private(set) var isCurrentlyAllowed: Bool = true

    private weak var profileRepo: UserProfileRepository?
    private var boundaryTimer: Timer?
    private let logger = TripLogger.shared

    // MARK: - Setup

    func configure(profileRepo: UserProfileRepository) {
        self.profileRepo = profileRepo
        refresh()
    }

    func startMonitoring() {
        refresh()
        scheduleNextBoundary()
        logger.log("TrackingScheduleManager: monitoring started (allowed=\(isCurrentlyAllowed))", category: .system)
    }

    func stopMonitoring() {
        boundaryTimer?.invalidate()
        boundaryTimer = nil
    }

    // MARK: - Public query

    /// Returns true if tracking is allowed right now according to the user's schedule.
    func isAllowed(at date: Date = Date()) -> Bool {
        guard let repo = profileRepo else { return true }
        let cal     = Calendar.current
        let weekday = cal.component(.weekday, from: date)   // 1=Sun…7=Sat
        guard let day = repo.schedule(for: weekday), day.isEnabled else { return false }
        let hour = cal.component(.hour, from: date)
        // startHour <= hour < endHour  (end is exclusive — "5pm" means tracking stops at 17:00)
        return hour >= day.startHour && hour < day.endHour
    }

    // MARK: - Private

    private func refresh() {
        let was = isCurrentlyAllowed
        isCurrentlyAllowed = isAllowed()
        if isCurrentlyAllowed != was {
            if isCurrentlyAllowed {
                logger.log("Tracking window opened", category: .system)
                onBecameAllowed?()
            } else {
                logger.log("Tracking window closed", category: .system)
                onBecameDisallowed?()
            }
        }
    }

    /// Schedules a one-shot Timer to fire at the next start or end boundary for today/tomorrow.
    private func scheduleNextBoundary() {
        boundaryTimer?.invalidate()

        guard let next = nextBoundaryDate() else {
            logger.log("TrackingScheduleManager: no future boundary found (schedule all-off?)", category: .system)
            return
        }

        let interval = next.timeIntervalSinceNow
        guard interval > 0 else {
            refresh()
            scheduleNextBoundary()
            return
        }

        logger.log("TrackingScheduleManager: next boundary in \(Int(interval/60))min", category: .system)

        boundaryTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.refresh()
            self?.scheduleNextBoundary()   // chain to the next boundary
        }
    }

    /// Returns the Date of the next tracking boundary (open or close) within the next 8 days.
    private func nextBoundaryDate() -> Date? {
        guard let repo = profileRepo else { return nil }
        let cal  = Calendar.current
        let now  = Date()

        for dayOffset in 0..<8 {
            guard let day = cal.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            let weekday = cal.component(.weekday, from: day)
            guard let sched = repo.schedule(for: weekday), sched.isEnabled else { continue }

            // Try start boundary
            if let startDate = cal.date(bySettingHour: sched.startHour, minute: 0, second: 1, of: day),
               startDate > now {
                return startDate
            }
            // Try end boundary
            if let endDate = cal.date(bySettingHour: sched.endHour, minute: 0, second: 0, of: day),
               endDate > now {
                return endDate
            }
        }
        return nil
    }
}
