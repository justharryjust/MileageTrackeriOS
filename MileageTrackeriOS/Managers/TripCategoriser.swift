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
/// ("Auto-categorised because: home → work commute").
enum CategorisationRuleHit: Equatable {
    /// Home ↔ work commute — both endpoints matched saved addresses tagged home/work.
    /// IRD (NZ) and ATO (AU) do not allow commute to be claimed, so this is always .personal.
    case commute(start: String, end: String)
    /// Both endpoints matched saved addresses with the same defaultCategory.
    case savedAddressPair(TripCategory, start: String, end: String)
    /// Trip end matched a saved address with an explicit default category.
    case savedEndAddress(TripCategory, label: String)
    case vehicleDefault(TripCategory)
    case sameRouteHistory(TripCategory, occurrences: Int)
    case businessAddressHistory(TripCategory, address: String)
    case weekdayHours(TripCategory)
    case none
}

struct TripCategoriser {
    let tripRepo: TripRepository?
    let profileRepo: UserProfileRepository?
    let savedAddressRepo: SavedAddressRepository?

    /// Maybe-construct: returns nil when tripRepo or profileRepo is missing.
    /// SavedAddressRepository is optional — categoriser still works without it,
    /// just doesn't apply commute / saved-address rules.
    init?(tripRepo: TripRepository?, profileRepo: UserProfileRepository?,
          savedAddressRepo: SavedAddressRepository? = nil) {
        guard let tripRepo = tripRepo, let profileRepo = profileRepo else { return nil }
        self.tripRepo = tripRepo
        self.profileRepo = profileRepo
        self.savedAddressRepo = savedAddressRepo
    }

    /// Run the rules and apply the first match (if any) to the trip in-place.
    /// `vehicleDefault` is passed in because the Vehicle may be detached from Realm
    /// by the time this runs in a Task — TripRecorder snapshots it before reset().
    func categorise(trip: Trip, vehicleDefault: TripCategory) {
        let hit = evaluate(trip: trip, vehicleDefault: vehicleDefault)
        guard let suggested = suggestion(for: hit) else { return }
        // Only auto-apply if trip is currently uncategorised — never overwrite an explicit user choice
        guard trip.category == .uncategorised else { return }
        // Preserve provenance — write the rule reason into trip.purpose if empty.
        // Makes the auto-decision visible in exports and helps the user verify.
        let provenance = describe(hit)
        tripRepo?.applyCategory(suggested, to: trip, purpose: trip.purpose?.isEmpty == false ? trip.purpose : provenance)
        TripLogger.shared.log("Categoriser hit: \(hit) → \(suggested.rawValue)", category: .trip)
    }

    /// Run the rules but don't apply — returns the suggestion + reason for UI display.
    /// Order matters: most-specific rules first. Saved-address rules win because they
    /// represent an explicit user signal ("this is my office") vs heuristics.
    func evaluate(trip: Trip, vehicleDefault: TripCategory) -> CategorisationRuleHit {
        // Rule 0 (NEW, highest priority): home ↔ work commute — always .personal
        if let hit = commuteRule(trip: trip) { return hit }
        // Rule 1: both endpoints match saved addresses with consistent defaultCategory
        if let hit = savedAddressPairRule(trip: trip) { return hit }
        // Rule 2: trip end matches a saved address with explicit default category
        if let hit = savedEndAddressRule(trip: trip) { return hit }
        // Rule 3: same start+end address visited 3+ times with consistent category
        if let hit = sameRouteHistoryRule(trip: trip) { return hit }
        // Rule 4: same end address with consistent business categorisation 3+ times
        if let hit = businessAddressHistoryRule(trip: trip) { return hit }
        // Rule 5: vehicle default category
        if vehicleDefault != .uncategorised {
            return .vehicleDefault(vehicleDefault)
        }
        // Rule 6: weekday business hours → business; weekend → personal
        if let hit = weekdayHoursRule(trip: trip) { return hit }
        return .none
    }

    private func suggestion(for hit: CategorisationRuleHit) -> TripCategory? {
        switch hit {
        case .commute:                                            return .personal
        case .savedAddressPair(let c, _, _):                      return c
        case .savedEndAddress(let c, _):                          return c
        case .vehicleDefault(let c):                              return c
        case .sameRouteHistory(let c, _):                         return c
        case .businessAddressHistory(let c, _):                   return c
        case .weekdayHours(let c):                                return c
        case .none:                                               return nil
        }
    }

    /// Human-readable provenance string — written into Trip.purpose when auto-applied.
    /// Lets the user (and tax agent) see WHY a category was picked.
    private func describe(_ hit: CategorisationRuleHit) -> String {
        switch hit {
        case .commute(let s, let e):                  return "Auto: commute (\(s) ↔ \(e)) — not claimable"
        case .savedAddressPair(_, let s, let e):      return "Auto: matched saved addresses \(s) → \(e)"
        case .savedEndAddress(_, let label):          return "Auto: end matched saved \"\(label)\""
        case .vehicleDefault(let c):                  return "Auto: vehicle default \(c.rawValue)"
        case .sameRouteHistory(_, let n):             return "Auto: matched \(n) prior trips on this route"
        case .businessAddressHistory(_, let addr):    return "Auto: end address \"\(addr)\" categorised business previously"
        case .weekdayHours(let c):                    return "Auto: weekday-hours rule → \(c.rawValue)"
        case .none:                                   return ""
        }
    }

    // MARK: - Rule 0: home ↔ work commute (NZ/AU non-claimable)

    /// Matches when start AND end both correspond to saved addresses tagged
    /// isHome/isWork (either direction). Always returns .personal because IRD/ATO
    /// explicitly exclude commute from business mileage claims.
    private func commuteRule(trip: Trip) -> CategorisationRuleHit? {
        guard let repo = savedAddressRepo else { return nil }
        let startMatch = repo.match(latitude: trip.startLat, longitude: trip.startLng)
        let endMatch   = repo.match(latitude: trip.endLat,   longitude: trip.endLng)
        guard let s = startMatch, let e = endMatch else { return nil }
        let isCommute = (s.isHome && e.isWork) || (s.isWork && e.isHome)
        guard isCommute else { return nil }
        return .commute(start: s.label, end: e.label)
    }

    // MARK: - Rule 1: saved-address pair

    /// Both endpoints match saved addresses; if both share a defaultCategory other
    /// than .uncategorised, use it. Example: "Auckland Office" (business) → "Wellington Office" (business)
    /// → auto-business. Skips commute case (handled by Rule 0).
    private func savedAddressPairRule(trip: Trip) -> CategorisationRuleHit? {
        guard let repo = savedAddressRepo else { return nil }
        guard let s = repo.match(latitude: trip.startLat, longitude: trip.startLng),
              let e = repo.match(latitude: trip.endLat,   longitude: trip.endLng) else { return nil }
        // Commute would have caught this already; skip if home/work pair
        if (s.isHome && e.isWork) || (s.isWork && e.isHome) { return nil }
        // Need agreement on a non-uncategorised category
        guard s.defaultCategory == e.defaultCategory, s.defaultCategory != .uncategorised else { return nil }
        return .savedAddressPair(s.defaultCategory, start: s.label, end: e.label)
    }

    // MARK: - Rule 2: end matched a saved address

    /// Single endpoint match — useful for "trip ending at my client site" auto-business.
    /// End is more meaningful than start (the destination is where work happens).
    private func savedEndAddressRule(trip: Trip) -> CategorisationRuleHit? {
        guard let repo = savedAddressRepo,
              let e = repo.match(latitude: trip.endLat, longitude: trip.endLng) else { return nil }
        guard e.defaultCategory != .uncategorised else { return nil }
        return .savedEndAddress(e.defaultCategory, label: e.label)
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
