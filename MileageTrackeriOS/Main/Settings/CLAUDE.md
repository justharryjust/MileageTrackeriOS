# Main/Settings/

Five files: `SettingsView.swift`, `TrackingHoursView.swift`, `DebugLogView.swift`, `DebugExtensionsView.swift`, `TripRecorderDebugView.swift`.

---

## SettingsView

`List` with named sections:

| Section | Content |
|---------|---------|
| Tracking | `NavigationLink` → `TrackingHoursView` |
| Profile | Read-only `LabeledContent` for jurisdiction + claim method |
| Vehicles | Active vehicles with type icon, name, registration, default badge |
| Data | Trip counts (all / business / needs review) |
| Diagnostics | Links to `DebugLogView`, `TripRecorderDebugView`, `DebugExtensionsView` |
| Danger | "Reset Onboarding" sets `profileRepo.hasCompletedOnboarding = false` (destructive role) |

---

## TrackingHoursView

Edits the live `UserProfile.trackingSchedule` via `UserProfileRepository`.

- `DayScheduleRowLive` — initialises local `@State` from the `DaySchedule` Realm object; writes back on toggle change and hour change via `repo.setScheduleEnabled` / `repo.setScheduleHours`.
- `HourPicker` (defined in `Onboarding/Steps/TrackingHoursStep.swift`) is reused here.
- "Reset to defaults" calls `profileRepo.applySchedule(DayScheduleSnapshot.defaults)`.

---

## DebugLogView

Live scrollable view of `TripLogger.shared.entries` (in-memory ring buffer, newest first).

- Horizontal category filter chips (All + one per `LogCategory`).
- `.searchable` text filter on message + category.
- Toolbar: share button (`ShareSheet` with `logger.exportURL`) + trash button (`logger.clearLogs()`).

---

## TripRecorderDebugView

Developer tool for injecting simulated OS events into live manager callbacks — **same code path as real events**.

| Section | What it injects |
|---------|----------------|
| Motion Activity | `DetectedActivity` via `motionManager.onActivityUpdate` (stationary low/high, automotive low/high, walking, cycling) |
| Location Events | `CLLocation` via `locationManager.onLocationUpdate` (speed + accuracy sliders, preset speeds) |
| Car Kit Events | `CarKitEvent` via `bluetoothManager.onCarKitConnected/onCarKitDisconnected` |
| Visit & Wake | `locationManager.onVisitDeparture`, `locationManager.onBackgroundWake`, force finalise |

Default fallback coordinates for location injection: Auckland CBD (`-36.8485, 174.7633`).

---

## DebugExtensionsView

Renders `DebugPotentialExtensions.md` from the app bundle as attributed markdown. Shows `ContentUnavailableView` if the file is missing.
