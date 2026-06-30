// Models — Realm-backed persistent entities
// All classes conform to Object (Realm) with @Persisted property wrappers.
// Enums use PersistableEnum so Realm stores them as raw String values.

import Foundation
import RealmSwift

// MARK: - Jurisdiction

enum Jurisdiction: String, CaseIterable, PersistableEnum {
    case newZealand = "NZ"
    case australia  = "AU"
    case other      = "other"

    var displayName: String {
        switch self {
        case .newZealand: return "New Zealand"
        case .australia:  return "Australia"
        case .other:      return "Other"
        }
    }

    var flag: String {
        switch self {
        case .newZealand: return "🇳🇿"
        case .australia:  return "🇦🇺"
        case .other:      return "🌍"
        }
    }
}

struct MileageRates {
    struct Thresholds {
        let centsPerKm: Double
        let lowerBound: Int
        let upperBound: Int
    }
    let name: String?
    let fuelType: [FuelType]?
    let thresholds: [Thresholds]
}

// MARK: - CustomRateTier (value type for OnboardingViewModel — not persisted)

struct CustomRateTier: Identifiable {
    var id = UUID()
    var lowerBound: Int
    var upperBound: Int
    var centsPerUnit: Double

    static var initial: CustomRateTier {
        .init(lowerBound: 0, upperBound: 5000, centsPerUnit: 100)
    }
}

// MARK: - RateThreshold (Realm embedded object — persisted per tier)

final class RateThreshold: EmbeddedObject {
    @Persisted var lowerBound: Int    = 0
    @Persisted var upperBound: Int    = 5000
    @Persisted var centsPerUnit: Double = 100
}


// MARK: - Claim Method

enum ClaimMethod: String, CaseIterable, PersistableEnum {
    case standardRate = "standard"
    case logbook      = "logbook"
    case customRate   = "custom"

    var displayName: String {
        switch self {
        case .standardRate: return "Standard Mileage Rate"
        case .customRate:   return "Custom Rate"
        case .logbook:      return "Logbook"
        }
    }

    var claimDescription: String {
        switch self {
        case .standardRate: return "Uses the official government published cents-per-\(DistanceUnit.kilometres.shortName) rate for your region."
        case .customRate:   return "Set your own rate per distance unit to match your actual vehicle costs."
        case .logbook:      return "Record odometer readings and the app calculates your business-use percentage."
        }
    }

    var icon: String {
        switch self {
        case .standardRate: return "chart.bar.fill"
        case .customRate:   return "slider.horizontal.3"
        case .logbook:      return "book.closed.fill"
        }
    }
}

// MARK: - Vehicle Type & Fuel Type

enum VehicleType: String, CaseIterable, PersistableEnum {
    case car        = "car"
    case truck      = "truck"
    case motorcycle = "motorcycle"

    var displayName: String {
        switch self {
        case .car:        return "Car"
        case .truck:      return "Truck"
        case .motorcycle: return "Motorcycle"
        }
    }

    var icon: String {
        switch self {
        case .car:        return "car.fill"
        case .truck:      return "truck.box.fill"
        case .motorcycle: return "bicycle"
        }
    }
}

enum FuelType: String, CaseIterable, PersistableEnum {
    case petrol       = "petrol"
    case diesel       = "diesel"
    case electric     = "electric"
    case hybrid       = "hybrid"
    case pluginHybrid = "phev"

    var displayName: String {
        switch self {
        case .petrol:       return "Petrol"
        case .diesel:       return "Diesel"
        case .electric:     return "Electric (EV)"
        case .hybrid:       return "Hybrid"
        case .pluginHybrid: return "Plug-in Hybrid (PHEV)"
        }
    }
}

// MARK: - Distance Unit

enum DistanceUnit: String, CaseIterable, PersistableEnum {
    case kilometres = "km"
    case miles      = "mi"

    var displayName: String {
        switch self {
        case .kilometres: return "Kilometres"
        case .miles:      return "Miles"
        }
    }

    var shortName: String {
        switch self {
        case .kilometres: return "km"
        case .miles:      return "mi"
        }
    }

    var icon: String {
        switch self {
        case .kilometres: return "speedometer"
        case .miles:      return "gauge.with.needle"
        }
    }
}

// MARK: - Trip Enums

enum TripCategory: String, CaseIterable, PersistableEnum {
    case business      = "business"
    case personal      = "personal"
    case uncategorised = "uncategorised"
}

enum TripSource: String, PersistableEnum {
    case automatic = "automatic"
    case manual    = "manual"
    case merged    = "merged"
    case inflight  = "inflight"  // trip in progress, not yet committed
}

// MARK: - Vehicle

final class Vehicle: Object, ObjectKeyIdentifiable {
    @Persisted(primaryKey: true) var id: String  = UUID().uuidString
    @Persisted var name: String                   = ""
    @Persisted var registration: String           = ""
    @Persisted var type: VehicleType              = .car
    @Persisted var fuelType: FuelType             = .petrol
    @Persisted var isDefault: Bool                = false
    @Persisted var isArchived: Bool               = false
    @Persisted var createdAt: Date                = Date()
    /// §4.3: per-vehicle default trip category. Work van → .business; family car → .personal.
    /// Used as a seed by the categorisation rules engine on auto-commit.
    @Persisted var defaultCategory: TripCategory  = .uncategorised

    convenience init(name: String, registration: String,
                     type: VehicleType, fuelType: FuelType, isDefault: Bool = false,
                     defaultCategory: TripCategory = .uncategorised) {
        self.init()
        self.name            = name
        self.registration    = registration
        self.type            = type
        self.fuelType        = fuelType
        self.isDefault       = isDefault
        self.defaultCategory = defaultCategory
    }
}

// MARK: - TripPoint

final class TripPoint: Object {
    @Persisted(primaryKey: true) var id: String = UUID().uuidString
    @Persisted var tripId: String                = ""
    @Persisted var latitude: Double              = 0
    @Persisted var longitude: Double             = 0
    @Persisted var altitude: Double              = 0
    @Persisted var speedMs: Double               = -1
    @Persisted var horizontalAccuracy: Double    = -1
    @Persisted var recordedAt: Date              = Date()

    convenience init(tripId: String, latitude: Double, longitude: Double,
                     altitude: Double, speedMs: Double, accuracy: Double, recordedAt: Date) {
        self.init()
        self.tripId             = tripId
        self.latitude           = latitude
        self.longitude          = longitude
        self.altitude           = altitude
        self.speedMs            = speedMs
        self.horizontalAccuracy = accuracy
        self.recordedAt         = recordedAt
    }
}

// MARK: - Trip Processing Status

enum TripProcessingStatus: String, PersistableEnum {
    case complete   // addresses resolved, gaps filled
    case pending    // needs address re-resolution and/or route snap retry
}

// MARK: - Trip

final class Trip: Object, ObjectKeyIdentifiable {
    @Persisted(primaryKey: true) var id: String  = UUID().uuidString
    @Persisted var vehicleId: String              = ""
    @Persisted var startAddress: String           = ""
    @Persisted var endAddress: String             = ""
    @Persisted var startLat: Double               = 0
    @Persisted var startLng: Double               = 0
    @Persisted var endLat: Double                 = 0
    @Persisted var endLng: Double                 = 0
    @Persisted var startedAt: Date                = Date()
    @Persisted var endedAt: Date?
    @Persisted var distanceMetres: Double         = 0
    @Persisted var category: TripCategory         = .uncategorised
    @Persisted var source: TripSource             = .automatic
    @Persisted var notes: String?
    @Persisted var dollarValue: Double?
    @Persisted var isCapExceeded: Bool            = false
    @Persisted var isSyncedToCloud: Bool          = false
    @Persisted var visitDepartureAt: Date?        // set when a CLVisit departure pre-armed this trip
    @Persisted var carKitName: String?            // name of car-kit connected when trip started, if any
    @Persisted var businessUsePercent: Double?    // only set when claim method is .logbook
    @Persisted var processingStatus: TripProcessingStatus = .complete
    @Persisted var processingRetries: Int         = 0
    /// §5.1: free-text business purpose (e.g. "Met client X at SiteY"). The audit-defensibility difference
    /// between a clean claim and a rejected one — surfaced on the "categorise as business" UI path.
    @Persisted var purpose: String?
    /// §5.2: tamper-evident SHA-256 hash captured at commit. Lets a user prove
    /// to IRD/ATO their logbook wasn't backdated. Hash = SHA256(id || startedAt || endedAt || distance || polylineHash).
    @Persisted var commitHash: String?
    /// §5.2 companion: the exact UTC date the hash was first written. Distinct from
    /// `createdAt` because mid-life edits don't change this field — they bust the hash on verification.
    @Persisted var committedAt: Date?
    /// §3.4: GPS-derived distance kept separately from claim distance. When odometer
    /// readings are available, `distanceMetres` may equal max(gps, odometer); this preserves the raw GPS figure.
    @Persisted var gpsDistanceMetres: Double      = 0
    /// §3.4: odometer-derived distance when bookended by readings. nil when no readings.
    @Persisted var odometerDistanceMetres: Double?
    @Persisted var createdAt: Date                = Date()
    @Persisted var updatedAt: Date                = Date()

    // Non-persisted computed helpers
    var distanceKm: Double { distanceMetres / 1000 }

    var distanceString: String {
        if distanceMetres < 1000 { return String(format: "%.0f m", distanceMetres) }
        return String(format: "%.1f km", distanceKm)
    }

    var durationString: String? {
        guard let end = endedAt else { return nil }
        let s = Int(end.timeIntervalSince(startedAt))
        let h = s / 3600; let m = (s % 3600) / 60
        if h > 0 { return String(format: "%dh %02dm", h, m) }
        return String(format: "%dm", m)
    }
}

enum OdometerSource: String, PersistableEnum {
    case manual
    case onboarding
}

// MARK: - SavedAddress
//
// User-defined places (Home, Office, frequent client sites) used by the
// categorisation rules engine. Two special flags — `isHome` / `isWork` — drive
// commute detection: any trip with start/end matched to home↔work is auto-
// categorised .personal, since IRD/ATO do not allow commute to be claimed.
//
// Match radius defaults to 100m — large enough to cover a typical office
// car park, small enough not to overlap neighbouring buildings.

final class SavedAddress: Object, ObjectKeyIdentifiable {
    @Persisted(primaryKey: true) var id: String   = UUID().uuidString
    @Persisted var label: String                   = ""
    @Persisted var address: String                 = ""
    @Persisted var latitude: Double                = 0
    @Persisted var longitude: Double               = 0
    @Persisted var radiusMetres: Double            = 100
    @Persisted var defaultCategory: TripCategory   = .uncategorised
    /// Special role flags. Home + Work together drive commute auto-classification.
    @Persisted var isHome: Bool                    = false
    @Persisted var isWork: Bool                    = false
    /// SF Symbol name for the row icon. Free text — keep to system symbols only.
    @Persisted var icon: String                    = "mappin.circle.fill"
    @Persisted var createdAt: Date                 = Date()

    convenience init(label: String, address: String,
                     latitude: Double, longitude: Double,
                     isHome: Bool = false, isWork: Bool = false,
                     defaultCategory: TripCategory = .uncategorised,
                     icon: String = "mappin.circle.fill") {
        self.init()
        self.label           = label
        self.address         = address
        self.latitude        = latitude
        self.longitude       = longitude
        self.isHome          = isHome
        self.isWork          = isWork
        self.defaultCategory = defaultCategory
        self.icon            = icon
    }
}

// MARK: - OdometerReading

final class OdometerReading: Object, ObjectKeyIdentifiable {
    @Persisted(primaryKey: true) var id: String = UUID().uuidString
    @Persisted var vehicleId: String             = ""
    @Persisted var readingKm: Double             = 0
    @Persisted var recordedAt: Date              = Date()
    @Persisted var tripId: String?
    @Persisted var notes: String?
    @Persisted var source: OdometerSource        = .manual
}

// MARK: - Collection safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - DaySchedule (embedded — one per weekday stored in UserProfile.trackingSchedule)

final class DaySchedule: EmbeddedObject {
    /// Calendar.Component weekday: 1 = Sunday, 2 = Monday … 7 = Saturday
    @Persisted var weekday   : Int  = 0
    @Persisted var isEnabled : Bool = true
    @Persisted var startHour : Int  = 8   // 08:00
    @Persisted var endHour   : Int  = 17  // 17:00

    var weekdayName: String {
        Calendar.current.weekdaySymbols[safe: weekday - 1] ?? "Day \(weekday)"
    }

    var shortName: String {
        Calendar.current.shortWeekdaySymbols[safe: weekday - 1] ?? "—"
    }
}

// MARK: - Subscription Types (Realm-backed for period-gating)
// MARK: - Subscription Types (Realm-backed for period-gating)

enum MTSubscriptionStatus: String, PersistableEnum {
    case trial = "trial"
    case active = "active"
    case gracePeriod = "gracePeriod"
    case expired = "expired"

    var displayName: String {
        switch self {
        case .trial: return "Free Trial"
        case .active: return "Active"
        case .gracePeriod: return "Grace Period"
        case .expired: return "Expired"
        }
    }

    var icon: String {
        switch self {
        case .trial: return "clock.fill"
        case .active: return "checkmark.circle.fill"
        case .gracePeriod: return "hourglass"
        case .expired: return "lock.fill"
        }
    }

    var allowsAccess: Bool {
        switch self { case .trial, .active, .gracePeriod: return true; case .expired: return false }
    }
}

enum MTSubscriptionPlan: String, PersistableEnum {
    case trial = "trial"
    case monthly = "monthly"
    case annual = "annual"
}

final class MTSubscriptionPeriod: Object, ObjectKeyIdentifiable {
    @Persisted(primaryKey: true) var id: String = UUID().uuidString

    @Persisted var startedAt: Date = Date()
    @Persisted var endedAt: Date?
    @Persisted var plan: MTSubscriptionPlan = .monthly
    @Persisted var isActive: Bool = true

    func contains(_ date: Date) -> Bool { date >= startedAt && (endedAt == nil || date <= endedAt!) }
}

// MARK: - UserProfile (singleton row — id always "singleton")

final class UserProfile: Object {
    @Persisted(primaryKey: true) var id: String  = "singleton"
    @Persisted var jurisdiction: Jurisdiction     = .newZealand
    @Persisted var claimMethod: ClaimMethod       = .standardRate
    @Persisted var customRatePerKm: Double?
    @Persisted var customRateLowerBound: Int      = 0
    @Persisted var customRateUpperBound: Int      = 1000
    @Persisted var customRateThresholds: List<RateThreshold>
    @Persisted var distanceUnit: DistanceUnit     = .kilometres
    @Persisted var hasCompletedOnboarding: Bool   = false
    @Persisted var trialStartedAt: Date?
    @Persisted var subscriptionStatus: String     = "trial"
    /// 7 DaySchedule entries (one per weekday). Populated lazily on first read if empty.
    @Persisted var trackingSchedule: List<DaySchedule>
}

// MARK: - DayScheduleSnapshot (value type for OnboardingViewModel -- not persisted)

struct DayScheduleSnapshot: Identifiable {
    var id       : Int { weekday }
    var weekday  : Int
    var isEnabled: Bool
    var startHour: Int
    var endHour  : Int

    var weekdayName: String { Calendar.current.weekdaySymbols[safe: weekday - 1] ?? "" }
    var shortName  : String { Calendar.current.shortWeekdaySymbols[safe: weekday - 1] ?? "" }

    static var defaults: [DayScheduleSnapshot] {
        // Mon(2)…Sat(7), then Sun(1) last. Enabled Mon–Fri, 7am–6pm.
        [(2,true),(3,true),(4,true),(5,true),(6,true),(7,false),(1,false)].map {
            DayScheduleSnapshot(weekday: $0.0, isEnabled: $0.1, startHour: 7, endHour: 18)
        }
    }
}

// MARK: - TripRecorderState (in-memory value type, never persisted)

enum TripRecorderState: Equatable {
    case idle
    case suspected(since: Date, reason: SuspectedReason)
    case active(startedAt: Date, distanceMetres: Double)
    case pausing(startedAt: Date, distanceMetres: Double, pauseStart: Date)
    case ending(startedAt: Date, distanceMetres: Double, reason: EndingReason)

    enum SuspectedReason: Equatable {
        case carPlay
        case knownCarBT
        case geofenceExit
        case visitDeparture
        case motion
        case slcMoving
    }

    enum EndingReason: Equatable {
        case fastPath
        case walkingDetected
        case pauseLimitExceeded
        case userForced
    }

    /// True when a trip is in progress (recording or pausing).
    var isRecording: Bool {
        switch self {
        case .active, .pausing: return true
        default: return false
        }
    }

    /// True when any non-idle state is active, for UI border/pulse.
    var isActive: Bool {
        switch self {
        case .idle: return false
        default: return true
        }
    }

    var displayTitle: String {
        switch self {
        case .idle:      return "No Active Trip"
        case .suspected: return "Detecting Trip…"
        case .active:    return "Recording Trip"
        case .pausing:   return "Trip Paused"
        case .ending:    return "Finishing Trip…"
        }
    }

    /// Returns the startedAt date for any non-idle state.
    var startedAt: Date? {
        switch self {
        case .idle:                                          return nil
        case .suspected(let since, _):                       return since
        case .active(let startedAt, _):                      return startedAt
        case .pausing(let startedAt, _, _):                  return startedAt
        case .ending(let startedAt, _, _):                   return startedAt
        }
    }

    func durationString(now: Date = Date()) -> String? {
        guard let start = startedAt else { return nil }
        let elapsed = now.timeIntervalSince(start)
        let h = Int(elapsed) / 3600
        let m = (Int(elapsed) % 3600) / 60
        let s = Int(elapsed) % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    func distanceString() -> String? {
        switch self {
        case .active(_, let d), .pausing(_, let d, _), .ending(_, let d, _):
            if d < 1000 { return String(format: "%.0f m", d) }
            return String(format: "%.1f km", d / 1000)
        default: return nil
        }
    }
}
