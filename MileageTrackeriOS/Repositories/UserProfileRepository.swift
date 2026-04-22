// UserProfileRepository — Manages the singleton UserProfile Realm object.
// Also owns vehicle management since vehicles are closely tied to the profile.

import Foundation
import Realm
import RealmSwift

@Observable
final class UserProfileRepository {
    // MARK: - Observed State (drives SwiftUI)
    private(set) var profile: UserProfile
    private(set) var vehicles: [Vehicle] = []

    private let realm: Realm
    private var profileToken: NotificationToken?
    private var vehiclesToken: NotificationToken?

    init(realm: Realm) {
        self.realm = realm

        // Bootstrap singleton profile if it doesn't exist
        if realm.object(ofType: UserProfile.self, forPrimaryKey: "singleton") == nil {
            try? realm.write {
                realm.add(UserProfile())
            }
        }

        profile = realm.object(ofType: UserProfile.self, forPrimaryKey: "singleton")!

        // Observe profile changes
        profileToken = profile.observe { [weak self] _ in
            self?.profile = self?.realm.object(ofType: UserProfile.self, forPrimaryKey: "singleton") ?? UserProfile()
        }

        // Observe vehicles (non-archived, sorted by createdAt)
        let vehicleResults = realm.objects(Vehicle.self)
            .where { !$0.isArchived }
            .sorted(byKeyPath: "createdAt", ascending: true)

        vehiclesToken = vehicleResults.observe { [weak self] _ in
            guard let self else { return }
            self.vehicles = Array(self.realm.objects(Vehicle.self).where { !$0.isArchived }.sorted(byKeyPath: "createdAt"))
        }
        vehicles = Array(vehicleResults)
    }

    deinit {
        profileToken?.invalidate()
        vehiclesToken?.invalidate()
    }

    // MARK: - Profile Updates

    var jurisdiction: Jurisdiction {
        get { profile.jurisdiction }
        set { write { self.profile.jurisdiction = newValue } }
    }

    var claimMethod: ClaimMethod {
        get { profile.claimMethod }
        set { write { self.profile.claimMethod = newValue } }
    }

    var customRatePerKm: Double? {
        get { profile.customRatePerKm }
        set { write { self.profile.customRatePerKm = newValue } }
    }

    var customRateLowerBound: Int {
        get { profile.customRateLowerBound }
        set { write { self.profile.customRateLowerBound = newValue } }
    }

    var customRateUpperBound: Int {
        get { profile.customRateUpperBound }
        set { write { self.profile.customRateUpperBound = newValue } }
    }

    var distanceUnit: DistanceUnit {
        get { profile.distanceUnit }
        set { write { self.profile.distanceUnit = newValue } }
    }

    var hasCompletedOnboarding: Bool {
        get { profile.hasCompletedOnboarding }
        set { write { self.profile.hasCompletedOnboarding = newValue } }
    }

    // MARK: - Vehicle Management

    var defaultVehicle: Vehicle? {
        vehicles.first(where: { $0.isDefault }) ?? vehicles.first
    }

    func addVehicle(name: String, registration: String, type: VehicleType = .car, fuelType: FuelType = .petrol) {
        let isFirst = vehicles.isEmpty
        let vehicle = Vehicle(name: name, registration: registration.uppercased(),
                              type: type, fuelType: fuelType, isDefault: isFirst)
        write { self.realm.add(vehicle) }
        TripLogger.shared.log("Vehicle added: \(name) [\(registration)]", category: .system)
    }

    func setDefaultVehicle(_ vehicle: Vehicle) {
        write {
            self.vehicles.forEach { $0.isDefault = false }
            vehicle.isDefault = true
        }
    }

    func archiveVehicle(_ vehicle: Vehicle) {
        write { vehicle.isArchived = true }
    }

    // MARK: - Private

    private func write(_ block: () -> Void) {
        do {
            try realm.write(block)
        } catch {
            TripLogger.shared.log("Realm write error: \(error)", category: .error)
        }
    }
}
