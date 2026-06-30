# Repositories/

Three files managing all Realm persistence. Views and managers never touch `Realm` directly.

---

## RealmProvider

`final class RealmProvider` — singleton (`RealmProvider.shared`).

- Opens `Realm` with `schemaVersion = 4` and an explicit `objectTypes` list.
- Migration block is the changelog for schema changes — add an entry for every bump.
- **When you add or rename a `@Persisted` property:** bump `schemaVersion`, add a migration comment, and register the type in `objectTypes` if new.

Current schema history:
```
v0 → v1  initial schema
v1 → v2  Trip.carKitName (optional String — no action needed)
v2 → v3  UserProfile.trackingSchedule (List<DaySchedule>) — populated lazily in UserProfileRepository.init
v3 → v4  UserProfile.customRateThresholds (List<RateThreshold>) — empty list default, no action needed
```

---

## TripRepository

`@Observable final class TripRepository`

### Live collections (auto-updated via Realm notification token)

| Property | Content |
|----------|---------|
| `allTrips` | All trips sorted by `startedAt` descending |
| `uncategorisedTrips` | Filtered to `.uncategorised` |
| `businessTrips` | Filtered to `.business` |
| `weeklyDistanceKm` | Business trips since start of current week |
| `monthlyDistanceKm` | Business trips since start of current month |
| `totalDollarValue` | Sum of `dollarValue` for business trips |

### Key methods

| Method | Called by | Notes |
|--------|-----------|-------|
| `saveTrip(vehicleId:startedAt:endedAt:distanceMetres:locations:startAddress:endAddress:visitDepartureAt:carKitName:)` | `TripRecorder.finaliseTripAndReset()` | Downsamples GPS array to 500 points before writing `TripPoint` objects |
| `saveManualTrip(...)` | `ManualTripSheet` | No `TripPoint` rows — coordinates come from `MKLocalSearch` |
| `categorise(_:as:)` | Swipe actions, `TripDetailView` menu | Sets `category` + `updatedAt` |
| `deleteTrip(_:)` | Swipe-to-delete | Also deletes associated `TripPoint` rows |
| `purgeOldPersonalTrips()` | Background task | Deletes personal trips with `endedAt` > 7 days ago |
| `tripPoints(for:)` | `TripDetailView` map | Returns sorted `TripPoint` array for polyline rendering |
| `trips(for:)` | `UserProfileRepository.deleteVehicle` | Returns all trips for a given vehicleId |

---

## UserProfileRepository

`@Observable final class UserProfileRepository`

- Bootstraps the singleton `UserProfile` row (`id = "singleton"`) if it doesn't exist.
- Populates default `trackingSchedule` (Mon–Fri 08:00–17:00) if list is empty.
- Exposes profile fields as computed `get`/`set` properties that write through to Realm via `write()`.

### Vehicle management

| Method | Notes |
|--------|-------|
| `addVehicle(name:registration:type:fuelType:)` | First vehicle is auto-set as default |
| `setDefaultVehicle(_:)` | Clears `isDefault` on all others |
| `updateVehicle(_:name:registration:type:fuelType:)` | Edits vehicle details in-place |
| `archiveVehicle(_:)` | Sets `isArchived = true`; excluded from `vehicles` collection |
| `unarchiveVehicle(_:)` | Sets `isArchived = false`; reappears in `vehicles` |
| `setVehicleDefaultCategory(_:_:)` | Sets per-vehicle trip categorisation seed (§4.3) |
| `deleteVehicle(_:tripRepo:)` | Permanently deletes vehicle + cascades to trips, TripPoints, and odometer readings. Promotes next vehicle by createdAt if deleted vehicle was default |
| `defaultVehicle` | First vehicle with `isDefault`, fallback to `vehicles.first` |

### Observed collections

| Property | Content |
|----------|---------|
| `vehicles` | Non-archived vehicles, sorted by createdAt |
| `allVehicles` | All vehicles including archived, sorted by createdAt |

### Tracking schedule

- `trackingSchedule` — sorted array of all 7 `DaySchedule` embedded objects.
- `setScheduleEnabled(_:weekday:)` / `setScheduleHours(start:end:weekday:)` — used by `TrackingHoursView`.
- `applySchedule(_:)` — batch-apply `DayScheduleSnapshot` array; used by onboarding.

## Rule

All writes go through the private `write(_ block:)` helper. Never call `realm.write` from outside a repository.
