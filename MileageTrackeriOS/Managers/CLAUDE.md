# Managers/

Hardware abstraction layer. All managers are owned by `AppState` and wired together in `TripRecorder.configure()`.

---

## LocationManager

`@Observable final class LocationManager: NSObject, CLLocationManagerDelegate`

Three **silent** background services (no blue status-bar indicator):

| Method | API used | Trigger |
|--------|----------|---------|
| `startSignificantLocationMonitoring()` | `startMonitoringSignificantLocationChanges()` | ~500 m cell-tower shift |
| `startVisitMonitoring()` | `startMonitoringVisits()` | CLVisit arrival/departure |
| `startRegionMonitoring(around:radius:)` | `startMonitoring(for: CLCircularRegion)` | 150 m geofence exit |

Active recording:

- `startHighAccuracyUpdates()` / `stopHighAccuracyUpdates()` — switches `desiredAccuracy` to `kCLLocationAccuracyBestForNavigation`, calls `startUpdatingLocation()`. This **does** show the blue indicator while recording.

### Region monitoring details

- Identifier: `"com.mileagetracker.departureRegion"` — only one region active at a time.
- Exit-only (`notifyOnExit = true`, `notifyOnEntry = false`).
- Re-centered after each exit (`didExitRegion`) and after `stopHighAccuracyUpdates()`.
- `updateRegionIfIdle(to:)` re-centers only when `!isHighAccuracyActive`.
- `startHighAccuracyUpdates()` calls `stopRegionMonitoring()` — no monitoring during active recording.

### Callbacks (wired in TripRecorder.configure)

| Callback | Fires when |
|----------|-----------|
| `onLocationUpdate` | Every accepted CLLocation fix |
| `onVisitDeparture` | CLVisit departure or region exit |
| `onBackgroundWake` | Any background wake (sig-loc, visit, region) |
| `onRegionDeparture` | Region exit — delivers anchor CLLocation at region center |

Init sets `activityType = .automotiveNavigation`.

---

## TripRecorder

`@Observable @MainActor final class TripRecorder` — singleton via `TripRecorder.shared`.

### State machine

```
idle → detecting → recording → ending → idle (trip saved)
```

### Heuristic constants

| Constant | Value |
|----------|-------|
| `minSpeedKmh` | 8 km/h |
| `detectionWindowSeconds` | 30 s |
| `stationaryEndWindowSeconds` | 60 s |
| `resumeWindowSeconds` | 90 s |
| `minimumTripDistanceMetres` | 1 000 m |
| `minimumTripDurationSeconds` | 60 s |

### Fast-track detection

`fastTrackDetection = true` halves the detection window (15 s) when a CLVisit departure or car-kit connect has pre-armed within the last 10 minutes.

### Departure anchor

`departureAnchorLocation: CLLocation?` — stored when `onRegionDeparture` fires. On trip confirmation it is prepended to `collectedLocations`, making the region center (parking spot) the authoritative geographic trip start. Consumed and cleared on confirm or reset.

### Trip start paths

Three independent paths can start a trip — no single signal is required.

| Path | Trigger | Why |
|------|---------|-----|
| A — CMMotion | `handleActivityUpdate`: automotive activity (medium/high confidence, or low when geofence/car-kit backed) → `.detecting` → GPS peak-speed gate → `.recording` | Primary path. Reliable when device motion is clear. Confidence filter blocks buses/trams/elevators. Low-confidence accepted when a geographic or hardware pre-arm backs it. |
| B — Geofence + GPS | `handleRegionDeparture` starts high-accuracy GPS; `handleLocationUpdate` idle: speed ≥ 8 km/h with live region anchor → `.detecting` | Geofence exit proves the car left its parking spot. GPS speed then confirms movement without CMMotion — useful in parking garages or when CMMotion is slow to report. |
| C — Car-kit + GPS | `handleCarKitConnected` starts high-accuracy GPS; `handleLocationUpdate` idle: speed ≥ 8 km/h with live car-kit pre-arm → `.detecting` | Bluetooth car-kit connect is strong driver intent. GPS streams immediately so speed can confirm movement before CMMotion wakes up. |

All paths converge on `.detecting` → GPS speed/window confirmation → `.recording`.

### Trip end paths

Two independent paths can end a trip.

| Path | Trigger | Why |
|------|---------|-----|
| A — CMMotion | `handleActivityUpdate` in recording: stationary/non-automotive (medium/high confidence) → 60 s stationary timer → `.ending` | Primary path. CMMotion reliably detects when the car stops. Medium/high threshold avoids false ends at traffic lights. |
| B — GPS speed | `handleLocationUpdate` in recording: speed below threshold for 60 s (via `lastMovingAt`) → stationary timer | Catches stops where CMMotion is delayed, stuck on automotive, or unavailable. |
| C — Car-kit disconnect | `handleCarKitDisconnected` in recording → immediate stationary timer | Engine off / exiting the car typically disconnects car Bluetooth. Fires the end window immediately rather than waiting for CMMotion to catch up. Disconnect during `.detecting` or `.idle` does **not** end a trip — the user may be changing audio source mid-drive. |

### Pre-arm signals

| Signal | Window | Effect |
|--------|--------|--------|
| CLVisit / region departure | 600 s | Sets `visitDepartureAt`, enables fast-track; region departure also starts high-accuracy GPS immediately (path B) |
| Car-kit connect | 600 s | Sets `carKitConnectExpiry`, enables fast-track, starts high-accuracy GPS immediately (path C) |
| Car-kit disconnect in `.recording` | immediate | Starts stationary timer (end path C) |

---

## MotionManager

`@Observable final class MotionManager`

- Wraps `CMMotionActivityManager` on a dedicated serial `OperationQueue` (background, `.utility` QoS).
- All `@Observable` mutations and `onActivityUpdate` callbacks are dispatched back to `MainActor`.
- `queryRecentActivity(since:)` — batch-replays missed activities in chronological order after a background wake.
- `isAuthorized` flips to `true` on first callback received.

---

## BluetoothManager

Scans for paired Bluetooth devices matching known car-kit profiles (hands-free, A2DP).

| Callback | Fires when |
|----------|-----------|
| `onCarKitConnected` | Car-kit device connects |
| `onCarKitDisconnected` | Car-kit device disconnects |

Both callbacks deliver a `CarKitEvent(type:deviceName:timestamp:)`. TripRecorder uses connect to pre-arm and disconnect to immediately start the end timer.

---

## TrackingScheduleManager

Reads `UserProfile.trackingSchedule` (7 `DaySchedule` entries) to gate whether tracking is active for the current time-of-day and weekday. GPS and motion detection should be paused outside tracking hours.

---

## AddressSearcher

`@Observable` wrapper around `MKLocalSearchCompleter` + `MKDirections`.

- `query: String` — bound to a text field; completions update reactively.
- `completions: [MKLocalSearchCompletion]` — live results.
- `resolve(_:) async throws -> AddressResult` — geocodes a completion to coordinate + address strings.
- `drivingDistance(from:to:) async -> Double` — `MKDirections` automobile route distance in metres; returns 0 on failure.

Used exclusively by `ManualTripSheet`.
