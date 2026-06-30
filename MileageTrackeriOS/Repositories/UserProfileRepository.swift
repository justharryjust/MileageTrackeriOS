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
    /// All vehicles including archived, for the archived section UI.
    private(set) var allVehicles: [Vehicle] = []

    private let realm: Realm
    private var profileToken: NotificationToken?
    private var vehiclesToken: NotificationToken?
    private var allVehiclesToken: NotificationToken?

    /// Callback fired when claimMethod changes, so AppState can manage logbook period lifecycle.
    var onClaimMethodChange: ((ClaimMethod, Jurisdiction, String?) -> Void)?

    init(realm: Realm) {
        self.realm = realm

        // Bootstrap singleton profile if it doesn't exist
        if realm.object(ofType: UserProfile.self, forPrimaryKey: "singleton") == nil {
            try? realm.write {
                realm.add(UserProfile())
            }
        }

        profile = realm.object(ofType: UserProfile.self, forPrimaryKey: "singleton")!
        hasCompletedOnboarding = profile.hasCompletedOnboarding
        
        
        
        //   Populate default tracking schedule if this is a new or migrated profile
        if profile.trackingSchedule.isEmpty { populateDefaultSchedule() }

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

        // Observe ALL vehicles including archived, for the archived section UI
        let allVehicleResults = realm.objects(Vehicle.self).sorted(byKeyPath: "createdAt", ascending: true)
        allVehiclesToken = allVehicleResults.observe { [weak self] _ in
            guard let self else { return }
            self.allVehicles = Array(self.realm.objects(Vehicle.self).sorted(byKeyPath: "createdAt"))
        }
        allVehicles = Array(allVehicleResults)
    }

    deinit {
        profileToken?.invalidate()
        vehiclesToken?.invalidate()
        allVehiclesToken?.invalidate()
    }

    // MARK: - Profile Updates

    var jurisdiction: Jurisdiction {
        get { profile.jurisdiction }
        set {
            let oldValue = profile.jurisdiction
            write { self.profile.jurisdiction = newValue }
            // AC14: jurisdiction change mid-logbook-period should notify the period manager
            if newValue != oldValue && profile.claimMethod == .logbook {
                onClaimMethodChange?(.logbook, newValue, defaultVehicle?.id)
            }
        }
    }

    var claimMethod: ClaimMethod {
        get { profile.claimMethod }
        set {
            let oldValue = profile.claimMethod
            write { self.profile.claimMethod = newValue }
            if newValue != oldValue {
                onClaimMethodChange?(newValue, profile.jurisdiction, defaultVehicle?.id)
            }
        }
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

    func setCustomRateThresholds(_ tiers: [CustomRateTier]) {
        write {
            self.profile.customRateThresholds.removeAll()
            for tier in tiers {
                let t = RateThreshold()
                t.lowerBound   = tier.lowerBound
                t.upperBound   = tier.upperBound
                t.centsPerUnit = tier.centsPerUnit
                self.profile.customRateThresholds.append(t)
            }
            if let first = tiers.first {
                self.profile.customRatePerKm      = first.centsPerUnit / 100.0
                self.profile.customRateLowerBound = first.lowerBound
                self.profile.customRateUpperBound = first.upperBound
            }
        }
    }

    var distanceUnit: DistanceUnit {
        get { profile.distanceUnit }
        set { write { self.profile.distanceUnit = newValue } }
    }

    var hasCompletedOnboarding: Bool = true {
        didSet { write { self.profile.hasCompletedOnboarding = hasCompletedOnboarding } }
    }

    // MARK: - Vehicle Management

    var defaultVehicle: Vehicle? {
        vehicles.first(where: { $0.isDefault }) ?? vehicles.first
    }

    func addVehicle(name: String, registration: String, type: VehicleType = .car, fuelType: FuelType = .petrol, defaultCategory: TripCategory = .uncategorised) {
        let isFirst = vehicles.isEmpty
        let vehicle = Vehicle(name: name, registration: registration.uppercased(),
                              type: type, fuelType: fuelType, isDefault: isFirst,
                              defaultCategory: defaultCategory)
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

    func unarchiveVehicle(_ vehicle: Vehicle) {
        write { vehicle.isArchived = false }
    }

    func updateVehicle(_ vehicle: Vehicle, name: String, registration: String,
                       type: VehicleType, fuelType: FuelType) {
        write {
            vehicle.name         = name
            vehicle.registration = registration.uppercased()
            vehicle.type         = type
            vehicle.fuelType     = fuelType
        }
    }

    /// §4.3: set the default category for a vehicle. Used as a seed by the
    /// categorisation rules engine — e.g. "Work van" → .business so trips
    /// auto-categorise on commit without user intervention.
    func setVehicleDefaultCategory(_ vehicle: Vehicle, _ category: TripCategory) {
        write { vehicle.defaultCategory = category }
        TripLogger.shared.log("Vehicle \(vehicle.name) default category set to \(category.rawValue)", category: .system)
    }

    /// Permanently deletes the vehicle and cascades: removes all associated trips
    /// (with their TripPoints) and odometer readings. If the deleted vehicle was the
    /// default, promotes the next available vehicle by createdAt.
    func deleteVehicle(_ vehicle: Vehicle, tripRepo: TripRepository) {
        let wasDefault = vehicle.isDefault
        let vehicleName = vehicle.name
        let vehicleReg = vehicle.registration
        write {
            // Delete all trips for this vehicle (cascade to TripPoints)
            let trips = self.realm.objects(Trip.self).where { $0.vehicleId == vehicle.id }
            for trip in trips {
                let pts = self.realm.objects(TripPoint.self).where { $0.tripId == trip.id }
                self.realm.delete(pts)
            }
            self.realm.delete(trips)

            // Delete odometer readings for this vehicle
            let readings = self.realm.objects(OdometerReading.self).where { $0.vehicleId == vehicle.id }
            self.realm.delete(readings)

            // Delete the vehicle itself
            self.realm.delete(vehicle)
        }
        TripLogger.shared.log("Vehicle deleted: \(vehicleName) [\(vehicleReg)]", category: .system)

        // Promote next available vehicle if this was the default.
        // Query Realm directly instead of using cached self.vehicles which is stale until the next runloop.
        if wasDefault {
            if let next = realm.objects(Vehicle.self).where({ !$0.isArchived }).sorted(byKeyPath: "createdAt").first {
                setDefaultVehicle(next)
            }
        }
    }


    // MARK: - Tracking Schedule

    /// Live array of the 7 DaySchedule entries (Sun=1 … Sat=7), always sorted by weekday.
    var trackingSchedule: [DaySchedule] {
        Array(profile.trackingSchedule).sorted { $0.weekday < $1.weekday }
    }

    /// Returns the schedule entry for the given Calendar weekday (1=Sun … 7=Sat).
    func schedule(for weekday: Int) -> DaySchedule? {
        profile.trackingSchedule.first { $0.weekday == weekday }
    }

    func setScheduleEnabled(_ enabled: Bool, weekday: Int) {
        guard let day = schedule(for: weekday) else { return }
        write { day.isEnabled = enabled }
    }

    func setScheduleHours(start: Int, end: Int, weekday: Int) {
        guard let day = schedule(for: weekday) else { return }
        write { day.startHour = start; day.endHour = end }
    }

    /// Saves an array of DaySchedule snapshots (used from onboarding vm).
    func applySchedule(_ snapshots: [DayScheduleSnapshot]) {
        for snap in snapshots {
            guard let day = schedule(for: snap.weekday) else { continue }
            write { day.isEnabled = snap.isEnabled; day.startHour = snap.startHour; day.endHour = snap.endHour }
        }
    }

    // MARK: - Private: default schedule population

    private func populateDefaultSchedule() {
        // Weekdays (Mon-Fri = 2-6): 08:00-17:00 enabled
        // Weekend (Sat=7, Sun=1): disabled
        let defaults: [(weekday: Int, enabled: Bool, start: Int, end: Int)] = [
            (1, false, 8, 17), // Sun
            (2, true,  8, 17), // Mon
            (3, true,  8, 17), // Tue
            (4, true,  8, 17), // Wed
            (5, true,  8, 17), // Thu
            (6, true,  8, 17), // Fri
            (7, false, 8, 17), // Sat
        ]
        write {
            self.profile.trackingSchedule.removeAll()
            for d in defaults {
                let day = DaySchedule()
                day.weekday   = d.weekday
                day.isEnabled = d.enabled
                day.startHour = d.start
                day.endHour   = d.end
                self.profile.trackingSchedule.append(day)
            }
        }
        TripLogger.shared.log("Tracking schedule populated with defaults", category: .system)
    }
    // MARK: - Subscription Support

    func setSubscriptionStatus(_ status: String) {
        write { self.profile.subscriptionStatus = status }
    }

    var trialStartedAt: Date? {
        get { profile.trialStartedAt }
        set { write { self.profile.trialStartedAt = newValue } }
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
