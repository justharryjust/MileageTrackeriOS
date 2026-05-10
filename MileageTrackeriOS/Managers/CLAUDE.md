# Managers/

Hardware abstraction layer + business logic managers. All are owned by `AppState` and wired together in `TripRecorder.configure()`.

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

- `startHighAccuracyUpdates()` / `stopHighAccuracyUpdates()` — switches `desiredAccuracy` to `kCLLocationAccuracyBestForNavigation`, calls `startUpdatingLocation()`. Shows the blue indicator while recording.

### Region monitoring details

- Identifier: `"com.mileagetracker.departureRegion"` — only one region active at a time.
- Exit-only (`notifyOnExit = true`, `notifyOnEntry = false`).
- Re-centered after each exit (`didExitRegion`) and after `stopHighAccuracyUpdates()`.
- `updateRegionIfIdle(to:)` re-centers only when `!isHighAccuracyActive`.
- `startHighAccuracyUpdates()` calls `stopRegionMonitoring()` — no monitoring during active recording.

### Additional state

| Property | Purpose |
|----------|---------|
| `lastGoodFix: CLLocation?` | Cached from the most recent accepted fix — used as cold-start polyline anchor |
| `requestOneShotLocation()` | Single high-accuracy fix with 5s timeout — fallback when `lastGoodFix` is nil |

### Callbacks (wired in TripRecorder.configure)

| Callback | Fires when |
|----------|-----------|
| `onLocationUpdate` | Every accepted CLLocation fix |
| `onVisitDeparture` | CLVisit departure or region exit |
| `onVisitArrival` | CLVisit arrival |
| `onBackgroundWake` | Any background wake (sig-loc, visit, region) |
| `onRegionDeparture` | Region exit — delivers anchor CLLocation at region center |

Init sets `activityType = .automotiveNavigation`.

---

## TripRecorder

`@Observable @MainActor final class TripRecorder` — singleton via `TripRecorder.shared`.

### State machine (v2)

```
Idle → Suspected → Active ↔ Pausing → Ending → Idle (trip saved or discarded)
```

| State | Meaning |
|-------|---------|
| `.idle` | Waiting for any trigger signal |
| `.suspected(since:reason:)` | 60s window — accumulating signals, GPS warming up |
| `.active(startedAt:distanceMetres:)` | Trip confirmed, recording GPS polyline |
| `.pausing(startedAt:distanceMetres:pauseStart:)` | Speed dropped, waiting to see if trip resumes |
| `.ending(startedAt:distanceMetres:reason:)` | Trip finalising — trim walking, validate, save |

### Heuristic constants (v2)

| Constant | Value |
|----------|-------|
| `slcSpeedKmh` | 22 km/h (SLC → Suspected) |
| `promotionSpeedKmh` | 25 km/h (Suspected → Active) |
| `pauseSpeedKmh` | 5 km/h (Active → Pausing) |
| `resumeSpeedKmh` | 15 km/h (Pausing → Active) |
| `suspectedWindow` | 60 s |
| `minTripDistanceM` | 200 m |
| `minTripDuration` | 60 s |

### Dynamic pause limits

| Condition | Limit |
|-----------|-------|
| Visit arrival + no soft engine signal | 0 s |
| Pedometer > 30 steps in 30 s | 30 s |
| No soft engine signal, no walking | 3 min |
| Soft engine signal active | 8 min |

### Engine signal — hard vs soft

- **Hard engine signal:** CarPlay connected OR learned-car BT audio route active.
- **Soft engine signal:** hard signal OR (automotive ≥ high + speed > 15 km/h within 60s) OR battery began charging during trip.

Soft signal is read everywhere. Hard signal is only needed for Idle → Suspected cold start. A CarPlay/BT disconnect mid-trip does NOT collapse the pause limit — soft signal (motion + speed recency) holds the trip alive.

### Trip start paths (Idle → Suspected)

| Path | Trigger |
|------|---------|
| A — CarPlay | CarPlay connected |
| B — Known car BT | Learned BT audio route activated (N=3 corroborated trips) |
| C — Geofence exit | Region departure (home/work/parking-hint) |
| D — Visit departure | CLVisit departure |
| E — Motion | `CMMotionActivity.automotive` ≥ medium for 15s rolling |
| F — SLC + speed | SLC fix with speed > 22 km/h and motion not stationary |

### Trip end paths

| Path | Trigger |
|------|---------|
| A — Speed stall | speed < 5 km/h for 30s AND distance < 50m in 60s → Pausing |
| B — Pause timeout | Dynamic pause limit exceeded → Ending |
| C — Fast-path | No soft signal + speed < 5 for 5s + corroborator (pedometer, visit, stationary motion) |
| D — Walking detected | Pedometer > 30 steps in 30s with no soft engine signal |

### New v2 features

| Feature | Detail |
|---------|--------|
| BT audio route learning | `portUID` tracked across trips; after 3 corroborations → `knownCarBTUIDs` |
| Parking hint geofences | LRU of 50 coordinates; trim walking segment on trip end |
| Walking trim | `trimTrailingWalkingFromPolyline()` removes walking-classified trailing samples before save |
| Checkpoint recovery | Persisted every 5s in active, every transition. On launch: resume if gap < 120s, else force-finalize |
| Departure anchor | `departureAnchorLocation` (geofence center) preferred over `lastGoodFix` for trip start coordinate |

### Removed from v1

`detectionBuffer` (replaced by `lastGoodFix` anchor), `fastTrackDetection`, `stationaryTimer`/`resumeTimer` (replaced by dynamic pause limits), `peakSpeedKmhDuringDetection`, `visitDepartureExpiry`/`carKitConnectExpiry`/`departureAnchorExpiry` (replaced by `suspectedAt` + 60s window), 10s-disconnect collapse rule.

---

## MotionManager

`@Observable final class MotionManager`

### Activity monitoring (existing)

- Wraps `CMMotionActivityManager` on a dedicated serial `OperationQueue` (background, `.utility` QoS).
- All `@Observable` mutations and `onActivityUpdate` callbacks are dispatched back to `MainActor`.
- `queryRecentActivity(since:)` — batch-replays missed activities in chronological order after a background wake.
- `isAuthorized` flips to `true` on first callback received.

### Pedometer (v2)

| Method | Notes |
|--------|-------|
| `startPedometerUpdates(from:)` | Called when entering `.suspected` — starts `CMPedometer` updates |
| `stopPedometerUpdates()` | Stops pedometer, clears history |
| `recentSteps(window:)` | Returns step count in last N seconds (default 30). Thread-safe rolling window. |
| `isPedometerAvailable: Bool` | `CMPedometer.isStepCountingAvailable()` |

Callback: `onPedometerUpdate: ((Int) -> Void)?` — fires with step count in the window.

### Altimeter (v2)

| Method | Notes |
|--------|-------|
| `startAltimeterUpdates()` | Called when entering `.suspected` — `CMAltimeter.startRelativeAltitudeUpdates()` |
| `stopAltimeterUpdates()` | Stops altimeter |
| `isAltimeterAvailable: Bool` | `CMAltimeter.isRelativeAltitudeAvailable()` |

Callback: `onAltimeterUpdate: ((Double) -> Void)?` — fires with relative altitude delta in metres.

### Battery state (v2)

| Method | Notes |
|--------|-------|
| `startBatteryMonitoring()` | Observes `UIDevice.batteryStateDidChangeNotification`. Fires current state immediately. |
| `stopBatteryMonitoring()` | Removes observer |
| `isCharging: Bool` | `true` when state is `.charging` or `.full` |

Callback: `onBatteryStateChange: ((UIDevice.BatteryState) -> Void)?`.

Used as a soft engine signal corroborator — charging concurrent with automotive counts toward soft signal.

---

## BluetoothManager

`@Observable final class BluetoothManager`

Scans for paired Bluetooth devices matching known car-kit profiles (HFP, A2DP, CarPlay, BLE audio).

| Callback | Fires when |
|----------|-----------|
| `onCarKitConnected` | Car-kit device connects; delivers `CarKitEvent(type:deviceName:portUID:timestamp:)` |
| `onCarKitDisconnected` | Car-kit device disconnects |

### `CarKitEvent`

| Field | Type | Notes |
|-------|------|-------|
| `type` | `.connected` / `.disconnected` | |
| `deviceName` | `String` | `AVAudioSessionPortDescription.portName` |
| `portUID` | `String?` | `AVAudioSessionPortDescription.uid` — stable-enough BT fingerprint for learning |
| `timestamp` | `Date` | |

TripRecorder uses `portUID` for BT audio route learning: after N=3 corroborated trips with the same UID, it's promoted to a `knownCarBTUID` and can trigger Idle → Suspected on connect.

---

## MileageCalculator (v2 — new)

`@Observable final class MileageCalculator`

Rate lookup and dollar-value computation for all three claim methods.

| Method | Returns |
|--------|---------|
| `rateEntry(for:fuelType:)` | `MileageRates?` — matching rate entry for jurisdiction + fuel type |
| `centsPerKm(at:profile:fuelType:)` | `Double?` — tiered rate at a given cumulative annual distance |
| `dollarValue(for:profile:fuelType:cumulativeKm:)` | `Double` — computed dollar value for a single trip |
| `businessUsePercent(readings:trips:)` | `Double` — business-use % from odometer readings (0–1) |

Standard rate: `km × c/km ÷ 100`. Logbook: `km × c/km × businessUsePercent ÷ 10000`. Custom rate: tiered user-defined cents-per-unit.

---

## ReportGenerator (v2 — new)

`final class ReportGenerator`

Builds tax-agent-ready CSV mileage expense reports.

| Method | Returns |
|--------|---------|
| `exportCSV(trips:calculator:profile:dateRange:)` | `URL` — temp file ready for `ShareSheet` |

CSV columns: Date, Start Address, End Address, Distance, Rate, Value, Category, Business Use %, Notes. Includes summary rows with totals.

---

## LiveActivityManager (v2 — new)

`@Observable final class LiveActivityManager`

Bridges TripRecorder state to Live Activities (Lock Screen + Dynamic Island). Gracefully no-ops when ActivityKit is unavailable.

| Method | Called from |
|--------|------------|
| `startTrip(vehicleName:startedAt:)` | `promoteToActive()` |
| `updateTrip(distanceMetres:startedAt:)` | `handleLocationUpdate()` during `.active`/`.pausing` (throttled to 5s) |
| `endTrip()` | `reset()`, `discardCurrent()` |

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
