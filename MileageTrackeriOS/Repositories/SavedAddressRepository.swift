// SavedAddressRepository — CRUD for user-defined SavedAddress entries.
//
// SavedAddress is the foundation of NZ-relevant commute auto-classification:
// when a trip's start and end both match saved addresses tagged Home/Work,
// the categoriser auto-marks it .personal (non-claimable). Generally, marking
// places saves the user from manually triaging recurring trips.

import Foundation
import Realm
import RealmSwift
import CoreLocation

@Observable
final class SavedAddressRepository {
    private(set) var addresses: [SavedAddress] = []

    private let realm: Realm
    private var token: NotificationToken?

    init(realm: Realm) {
        self.realm = realm
        observe()
    }

    deinit { token?.invalidate() }

    private func observe() {
        let results = realm.objects(SavedAddress.self).sorted(byKeyPath: "createdAt", ascending: true)
        token = results.observe { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    private func refresh() {
        addresses = Array(realm.objects(SavedAddress.self).sorted(byKeyPath: "createdAt", ascending: true))
    }

    // MARK: - Computed helpers

    var homeAddress: SavedAddress? { addresses.first { $0.isHome } }
    var workAddress: SavedAddress? { addresses.first { $0.isWork } }

    // MARK: - CRUD

    /// Adds a new SavedAddress. If `isHome` is set and another address is already
    /// the home, this clears the old one (only one home at a time). Same for `isWork`.
    @discardableResult
    func add(label: String, address: String,
             latitude: Double, longitude: Double,
             isHome: Bool = false, isWork: Bool = false,
             defaultCategory: TripCategory = .uncategorised,
             icon: String = "mappin.circle.fill") -> SavedAddress {
        let new = SavedAddress(
            label: label, address: address,
            latitude: latitude, longitude: longitude,
            isHome: isHome, isWork: isWork,
            defaultCategory: defaultCategory, icon: icon
        )
        write {
            // Enforce single home / single work
            if isHome {
                realm.objects(SavedAddress.self).where { $0.isHome }.forEach { $0.isHome = false }
            }
            if isWork {
                realm.objects(SavedAddress.self).where { $0.isWork }.forEach { $0.isWork = false }
            }
            realm.add(new)
        }
        TripLogger.shared.log("SavedAddress added: \(label) (home:\(isHome) work:\(isWork))", category: .system)
        return new
    }

    /// Update fields. Same single-home / single-work enforcement.
    func update(_ address: SavedAddress,
                label: String? = nil,
                isHome: Bool? = nil,
                isWork: Bool? = nil,
                defaultCategory: TripCategory? = nil,
                icon: String? = nil,
                radiusMetres: Double? = nil) {
        write {
            if let label = label              { address.label = label }
            if let icon = icon                { address.icon = icon }
            if let cat = defaultCategory      { address.defaultCategory = cat }
            if let r = radiusMetres           { address.radiusMetres = max(50, min(500, r)) }
            if let isHome = isHome {
                if isHome {
                    realm.objects(SavedAddress.self).where { $0.isHome }.forEach { $0.isHome = false }
                }
                address.isHome = isHome
            }
            if let isWork = isWork {
                if isWork {
                    realm.objects(SavedAddress.self).where { $0.isWork }.forEach { $0.isWork = false }
                }
                address.isWork = isWork
            }
        }
    }

    func delete(_ address: SavedAddress) {
        write { realm.delete(address) }
    }

    // MARK: - Match

    /// Returns the saved address whose centre is within its radius of (lat, lng), or nil.
    /// If multiple match (unlikely with 100m default radius), returns the closest centre.
    func match(latitude: Double, longitude: Double) -> SavedAddress? {
        let here = CLLocation(latitude: latitude, longitude: longitude)
        var best: (address: SavedAddress, distance: Double)?
        for saved in addresses {
            let there = CLLocation(latitude: saved.latitude, longitude: saved.longitude)
            let d = here.distance(from: there)
            if d <= saved.radiusMetres {
                if best == nil || d < best!.distance {
                    best = (saved, d)
                }
            }
        }
        return best?.address
    }

    // MARK: - Private

    private func write(_ block: () -> Void) {
        do { try realm.write(block) } catch {
            TripLogger.shared.log("SavedAddress write error: \(error)", category: .error)
        }
    }
}
