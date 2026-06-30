import Foundation
import RealmSwift

@Observable
final class SubscriptionManager {
    private(set) var subscriptionState = SubscriptionState(
        status: .trial,
        trialEndsAt: nil,
        graceEndsAt: nil
    )

    func configure(profileRepo: UserProfileRepository) {}
    func refreshState() {}
}

struct SubscriptionState {
    let status: SubscriptionStatus
    let trialEndsAt: Date?
    let graceEndsAt: Date?
}

enum SubscriptionStatus: String {
    case trial
    case active
    case gracePeriod
    case expired

    var allowsAccess: Bool {
        switch self {
        case .trial, .active, .gracePeriod: return true
        case .expired: return false
        }
    }
}
