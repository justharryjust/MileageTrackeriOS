# Missing Core Features & Known Bugs

Analysis based on current codebase (2026-05-06).

## Missing Core Features

### 1. Manual Trip Editing (High Priority)
The `TripDetailView` toolbar has a placeholder "Fix start/end" button (line 106) that is not implemented.
Users cannot edit trip addresses, recategorise trips with notes, or adjust start/end points
when GPS drift produces incorrect locations. A trip editor sheet is needed.

### 2. Trip Merge (Medium Priority)
The v2 design doc explicitly calls out case #7: "5-stop errand run, engine off each time — 5 separate
trips logged." The plan says "user can merge in review queue." No merge UI or logic exists.
This is a core UX gap for users without CarPlay/BT.

### 3. User Profile Editing (High Priority)
Jurisdiction, claim method, distance unit, and vehicle details are set during onboarding and
cannot be changed afterward. The SettingsView shows them as read-only labels. Users who move
countries, switch claim methods, or change vehicles need edit capability.

### 4. Vehicle Management (Medium Priority)
- Add a second/third vehicle is not exposed in the UI
- Archive/delete vehicles not available
- Switch default vehicle not available
- The `addVehicle` repo method exists but only the onboarding flow calls it

### 5. Dollar Value Persistence & Display (High Priority)
The `MileageCalculator.dollarValue()` computes values correctly, but:
- Dollar values are not stored on `Trip` objects after trip completion
- `Trip.dollarValue` field exists but is never written to
- The trip list and detail views don't show dollar values for existing trips
- Values should be recalculated on trip save and periodically for logbook method

### 6. Logbook Period Management (Medium Priority)
The logbook method requires a 90-day continuous logbook period. Current implementation:
- Initial odometer is captured at onboarding
- No "start logbook period" / "end logbook period" UI
- No 90-day countdown or reminder
- Business-use percentage is not stored or applied to trips
- Periodic odometer reminders not scheduled

### 7. Personal Trip Auto-Purge (Low Priority)
`TripRepository.purgeOldPersonalTrips()` exists but is never called. No background task
schedules it. Personal trips will accumulate indefinitely until manually deleted.

### 8. Notification Permissions (Medium Priority)
No notification permission request. Missing:
- Periodic odometer reading reminders (logbook users)
- Weekly mileage summary
- Tracking-status-change notifications (e.g., "trip detected")

## Known Bugs

### 1. Trip Point Data Loss (FIXED)
Previously: `saveTrip()` captured coordinates correctly but `collectedLocations` was
cleared by `reset()` before the async `Task` ran → zero `TripPoint` rows saved.
**Status: Fixed** by capturing `let locations = collectedLocations` before the Task.

### 2. Late Trip Start Anchor (FIXED)
Previously: `promoteToActive()` used `lastGoodFix` (first GPS fix passing accuracy filters)
instead of `departureAnchorLocation` (geofence center where the car was parked).
**Status: Fixed** by preferring `departureAnchorLocation` as the anchor.

### 3. GPS Cold-Start Accuracy Filter (Open)
`LocationManager.didUpdateLocations` filters out fixes with `horizontalAccuracy >= 100m`.
During GPS cold start (parking garage, urban canyon), the first 2–10 fixes may all be
discarded. Combined with the anchor fix, the trip start now has the correct coordinate
(anchor), but the first few seconds of polyline are still missing. Consider relaxing
the accuracy filter to 200m during the first 30s of the Suspected window.

### 4. OdometerReading Notification Token (Open)
`OdometerReadingRepository` uses a notification token observing all readings. When
the user has readings for multiple vehicles, the `readings(for:)` filter re-sorts on
every change. This is fine at small scale but could be optimised with per-vehicle queries.

### 5. ReportExportView Tax Year Default (Open)
The `ReportExportView` defaults to NZ tax year until `onAppear` updates it from the profile.
On first render, the date pickers briefly show the wrong period. Fixed by initialising from
the current profile jurisdiction in `init()` — but `init()` doesn't have access to `AppState`.

### 6. ShareSheet Duplicate Definition (Open)
`ShareSheet` is defined in both `DebugLogView.swift` and was (temporarily) duplicated in
`ReportExportView.swift`. The duplicate was removed but the type should be extracted to
`Shared/` to avoid future issues.

### 7. DistanceUnit Inconsistency for UK (Open)
UK HMRC rates are in pence per mile, but `MileageCalculator.dollarValue()` converts
miles to km before applying the rate. For UK users with miles as their distance unit,
the reported value will be incorrect. The rate unit must match the distance unit.

### 8. Onboarding Step Order With Logbook (Open)
When the user selects `.logbook` in ClaimMethodStep (step 4), the initial odometer field
appears. But the vehicle hasn't been confirmed yet (vehicle step was step 2). If the
user goes back to change the vehicle, the odometer reading stays but may no longer
apply. The odometer reading should be tied to the vehicle selection.
