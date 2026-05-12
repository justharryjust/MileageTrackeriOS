// TripCategoriser — Auto-categorisation rules engine.
//
// §4.1 implementation: applies a ranked set of rules to suggest a category
// (.business / .personal / .uncategorised) for a freshly-committed trip.
// The first rule that matches wins. Rules ordered most-specific → least-specific.
//
// The categoriser is invoked once at trip commit. Its decision is auto-applied;
// the user can always override via the categorise UI. Confidence is implicit in
// rule ordering — explicit "I told you so" rules (history match, vehicle default)
// win over heuristic rules (time-of-day).

import Foundation
import CoreLocation

/// Reason a trip was auto-categorised — useful for debugging and surfacing in UI
/// ("Auto-categorised because: vehicle default 'Work van'").
enum CategorisationRuleHit: Equatable {
    case vehicleDefault(TripCategory)
    case sameRouteHistory(TripCategory, occurrences: Int)
    case businessAddressHistory(TripCategory, address: String)
    case weekdayHours(TripCategory)
    case none
}

struct TripCategoriser {
    let tripRepo: TripRepository?
    let profileRepo: UserProfileRepository?

    /// Maybe-construct: returns nil when either dependency is missing.
    init?(tripRepo: TripRepository?, profileRepo: UserProfileRepository?) {
        guard let tripRepo = tripRepo, let profileRepo = profileRepo else { return nil }
        self.tripRepo = tripRepo
        self.profileRepo = profileRepo
    }

    /// Run the rules and apply the first match (if any) to the trip in-place.
    /// `vehicleDefault` is passed in because the Vehicle may be detached from Realm
    /// by the time this runs in a Task — TripRecorder snapshots it before reset().
    func categorise(trip: Trip, vehicleDefault: TripCategory) {
        let hit = evaluate(trip: trip, vehicleDefault: vehicleDefault)
        guard let suggested = suggestion(for: hit) else { return }
        // Only auto-apply if trip is currently uncategorised — never overwrite an explicit user choice
        guard trip.category == .uncategorised else { return }
        tripRepo?.applyCategory(suggested, to: trip)
        TripLogger.shared.log("Categoriser hit: \(hit) → \(suggested.rawValue)", category: .trip)
    }

    /// Run the rules but don't apply — returns the suggestion + reason for UI display.
    func evaluate(trip: Trip, vehicleDefault: TripCategory) -> CategorisationRuleHit {
        // Rule 1: same start+end address visited 3+ times with consistent category
        if let hit = sameRouteHistoryRule(trip: trip) { return hit }
        // Rule 2: same end address with consistent business categorisation 3+ times
        if let hit = businessAddressHistoryRule(trip: trip) { return hit }
        // Rule 3: vehicle default category
        if vehicleDefault != .uncategorised {
            return .vehicleDefault(vehicleDefault)
        }
        // Rule 4: weekday business hours → business; weekend → personal
        if let hit = weekdayHoursRule(trip: trip) { return hit }
        return .none
    }

    private func suggestion(for hit: CategorisationRuleHit) -> TripCategory? {
        switch hit {
        case .vehicleDefault(let c), .sameRouteHistory(let c, _),
             .businessAddressHistory(let c, _), .weekdayHours(let c):
            return c
        case .none:
            return nil
        }
    }

    // MARK: - Rule 1: same start→end address history

    /// If the user has driven this exact start→end pairing ≥3 times before and
    /// categorised the majority of them the same way, suggest that category.
    /// Effective for commutes (auto-flagging them as personal so the user doesn't
    /// have to manually skip every weekday morning).
    private func sameRouteHistoryRule(trip: Trip) -> CategorisationRuleHit? {
        guard let repo = tripRepo, !trip.startAddress.isEmpty, !trip.endAddress.isEmpty else { return nil }
        let historic = repo.allTrips.filter { other in
            other.id != trip.id
                && other.startAddress.caseInsensitiveCompare(trip.startAddress) == .orderedSame
                && other.endAddress.caseInsensitiveCompare(trip.endAddress) == .orderedSame
                && other.category != .uncategorised
        }
        guard historic.count >= 3 else { return nil }
        // Majority vote
        let businessCount = historic.filter { $0.category == .business }.count
        let personalCount = historic.filter { $0.category == .personal }.count
        guard businessCount + personalCount >= 3 else { return nil }
        let winner: TripCategory = businessCount > personalCount ? .business : .personal
        return .sameRouteHistory(winner, occurrences: historic.count)
    }

    // MARK: - Rule 2: business end-address history

    /// If the same end address has been categorised business ≥3 times,
    /// new trips ending there default to business. Captures the "weekly client
    /// site" pattern without needing route-pair history.
    private func businessAddressHistoryRule(trip: Trip) -> CategorisationRuleHit? {
        guard let repo = tripRepo, !trip.endAddress.isEmpty else { return nil }
        let endHistory = repo.allTrips.filter { other in
            other.id != trip.id
                && other.endAddress.caseInsensitiveCompare(trip.endAddress) == .orderedSame
                && other.category == .business
        }
        guard endHistory.count >= 3 else { return nil }
        return .businessAddressHistory(.business, address: trip.endAddress)
    }

    // MARK: - Rule 4: weekday business hours

    /// Default: Mon–Fri 07:00–19:00 → business, weekends + nights → personal.
    /// Only fires when no stronger rule has matched. Effective as a "you forgot to
    /// categorise" backstop. Never decisive — user can override anytime.
    private func weekdayHoursRule(trip: Trip) -> CategorisationRuleHit? {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: trip.startedAt)
        let hour = calendar.component(.hour, from: trip.startedAt)
        let isWeekday = (weekday >= 2 && weekday <= 6)
        let isBusinessHour = (hour >= 7 && hour < 19)
        if isWeekday && isBusinessHour {
            return .weekdayHours(.business)
        }
        if !isWeekday {
            return .weekdayHours(.personal)
        }
        return nil
    }
}
