# Main/Settings/

Eight files: `SettingsView.swift`, `ProfileEditView.swift`, `VehicleManagementView.swift`, `TrackingHoursView.swift`, `DebugLogView.swift`, `DebugExtensionsView.swift`, `TripRecorderDebugView.swift`, `TipsView.swift`, `ReportExportView.swift`.

---

## SettingsView

`List` with named sections:

| Section | Content |
|---------|---------|
| Tracking | `NavigationLink` → `TrackingHoursView` |
| Notifications | Toggle controls for trip-detected, odometer-reminder, weekly-summary notifications |
| Profile | `NavigationLink` → `ProfileEditView` with summary text showing current jurisdiction, claim method, distance unit |
| Vehicles | `NavigationLink` → `VehicleManagementView` with default vehicle info and count |
| Places | `NavigationLink` → `SavedAddressesView` with home/work/other summary |
| Reporting | `NavigationLink`s to `ReportExportView`, `OdometerLogView`, `MethodInfoView` |
| Data | Trip counts (all / business / needs review) as `LabeledContent` |
| Diagnostics | Links to `DebugLogView`, `TripRecorderDebugView`, `DebugExtensionsView`, plus "Share Debug Data" and "Reset Onboarding" |

---

## ProfileEditView

Edits jurisdiction, claim method, distance unit, and custom rate tiers after onboarding.

- `Picker` for jurisdiction — calls `save()` via `.onChange(of:)`
- `Picker` for distance unit — calls `save()` via `.onChange(of:)`
- Radio-style buttons for claim method — saves immediately on tap
- Custom rate tier editor with sliders, add/delete buttons — shown when `.customRate` is selected
- All changes persist immediately through `UserProfileRepository` computed properties

---

## VehicleManagementView

Full vehicle lifecycle management.

- `List` with "Active Vehicles" section and collapsible "Archived" section
- Each row shows type icon, name/registration, fuel type, and Default badge
- Context menu: Edit, Set as Default, Archive
- Archived rows get a "Restore" button
- **Add sheet**: `VehicleFormView` in `.add` mode — collects name, registration, type, fuelType
- **Edit sheet**: `VehicleFormView` in `.edit(vehicle:)` mode — modifies name, registration, type, fuelType in-place
- All operations go through `UserProfileRepository` methods

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
