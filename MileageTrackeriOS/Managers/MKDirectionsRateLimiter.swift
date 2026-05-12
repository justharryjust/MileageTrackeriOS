// MKDirectionsRateLimiter — Token bucket for MKDirections requests.
//
// §6.5 fix: MKDirections is rate-limited by Apple at roughly 50 req/min per app.
// On app foreground after a long offline period, reprocessPendingTrips() could
// burst through quota and silently fail half the requests. This actor enforces
// a conservative ceiling (8 req/min, refilling 1 token every 7.5s) so calls
// queue gracefully instead of hitting the wall.
//
// Trips that can't be snapped on the current pass are marked `processingStatus = .pending`
// and re-tried on the next foreground notification.

import Foundation

actor MKDirectionsRateLimiter {
    static let shared = MKDirectionsRateLimiter()

    private let maxTokens: Int
    private let refillIntervalSec: Double
    private var availableTokens: Int
    private var lastRefillAt: Date

    init(maxTokens: Int = 8, refillIntervalSec: Double = 7.5) {
        self.maxTokens = maxTokens
        self.refillIntervalSec = refillIntervalSec
        self.availableTokens = maxTokens
        self.lastRefillAt = Date()
    }

    /// Try to take a token. Returns true if one was acquired; false if quota exhausted.
    /// Non-blocking — callers should treat false as "skip this call, mark pending".
    func tryAcquire() -> Bool {
        refillIfNeeded()
        if availableTokens > 0 {
            availableTokens -= 1
            return true
        }
        return false
    }

    /// Current available token count (for debug / metrics).
    var available: Int {
        refillIfNeeded()
        return availableTokens
    }

    private func refillIfNeeded() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRefillAt)
        guard elapsed >= refillIntervalSec else { return }
        let tokensToAdd = Int(elapsed / refillIntervalSec)
        availableTokens = min(maxTokens, availableTokens + tokensToAdd)
        lastRefillAt = now
    }
}
