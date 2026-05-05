# Models/

Single file: `Models.swift`. All Realm-backed types, domain enums, and shared in-memory value types.

---

## Realm Objects

| Class | Key fields | Notes |
|-------|-----------|-------|
| `Vehicle` | `id` (PK), `name`, `registration`, `type`, `fuelType`, `isDefault`, `isArchived` | First vehicle added becomes default |
| `Trip` | `id` (PK), `vehicleId`, `startedAt`, `endedAt`, `distanceMetres`, `category`, `source`, `startLat/Lng`, `endLat/Lng`, `visitDepartureAt?`, `carKitName?` | Start/end coords stored flat — separate from TripPoints |
| `TripPoint` | `id` (PK), `tripId` (FK), lat/lng/altitude/speedMs/accuracy/`recordedAt` | GPS breadcrumb; queried by `tripId` |
| `OdometerReading` | `id`, `vehicleId`, `readingKm`, `recordedAt`, `tripId?` | Logbook method support |
| `UserProfile` | `id = "singleton"` (PK), jurisdiction, claimMethod, distanceUnit, `hasCompletedOnboarding`, `trackingSchedule: List<DaySchedule>`, `customRateThresholds: List<RateThreshold>` | **Always exactly one row** |
| `DaySchedule` | `weekday` (1=Sun…7=Sat), `isEnabled`, `startHour`, `endHour` | `EmbeddedObject` inside `UserProfile.trackingSchedule` |
| `RateThreshold` | `lowerBound`, `upperBound`, `centsPerUnit` | `EmbeddedObject` inside `UserProfile.customRateThresholds` |

---

## PersistableEnum (stored as raw String)

| Enum | Cases |
|------|-------|
| `Jurisdiction` | `.newZealand` ("NZ"), `.australia` ("AU") |
| `ClaimMethod` | `.standardRate`, `.logbook`, `.customRate` |
| `VehicleType` | `.car`, `.truck`, `.motorcycle` |
| `FuelType` | `.petrol`, `.diesel`, `.electric`, `.hybrid`, `.pluginHybrid` |
| `DistanceUnit` | `.kilometres` ("km"), `.miles` ("mi") |
| `TripCategory` | `.business`, `.personal`, `.uncategorised` |
| `TripSource` | `.automatic`, `.manual` |

---

## Value Types (never persisted)

| Type | Used by |
|------|---------|
| `TripRecorderState` | `TripRecorder`, `TripStatusCard`, all state-observing views |
| `CustomRateTier` | `OnboardingViewModel`, `ClaimMethodStep` |
| `DayScheduleSnapshot` | `OnboardingViewModel`, `TrackingHoursStep` |
| `MileageRates` / `MileageRates.Thresholds` | Rate lookup; data lives in `Localisaion/` |

### TripRecorderState

```swift
enum TripRecorderState: Equatable {
    case idle
    case detecting(since: Date)
    case recording(startedAt: Date, distanceMetres: Double)
    case ending(recordingStartedAt: Date, stoppedAt: Date, distanceMetres: Double)
}
```

Provides `isActive`, `displayTitle`, `durationString()`, `distanceString()`.

---

## Invariants

- `UserProfile` primary key is always `"singleton"` — never create a second row.
- `Trip.startLat/startLng/endLat/endLng` are stored flat on the `Trip` object for map display; full breadcrumbs live in `TripPoint`.
- `Trip.visitDepartureAt` and `carKitName` are optional metadata written at save time by `TripRecorder`.
- Schema version is managed in `RealmProvider` (currently **4**). Bump it there whenever you add or rename a persisted property.
