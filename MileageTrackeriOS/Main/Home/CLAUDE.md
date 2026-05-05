# Main/Home/

Two files: `HomeView.swift`, `TripStatusCard.swift`.

---

## HomeView

`NavigationStack` with a vertical scroll layout. Sections top-to-bottom:

| Section | Source |
|---------|--------|
| `TripStatusCard` | `appState.tripRecorder.state` |
| `QuickStatsRow` | `appState.tripRepo.weeklyDistanceKm`, `monthlyDistanceKm`, `totalDollarValue` |
| `PermissionWarnings` | `appState.locationManager.hasAlwaysAuthorization`, `appState.motionManager.isAvailable` |
| `RecentTripsSection` | `appState.tripRepo.allTrips.prefix(5)` |

Toolbar: DEBUG-only `NavigationLink` to `DebugLogView` (terminal icon).

---

## TripStatusCard

The most important live UI element in the app. Displays the current `TripRecorderState` with animated feedback.

### StatusDot colours

| State | Dot colour |
|-------|-----------|
| `.idle` | `Color.mtBorder` |
| `.detecting` | `Color.mtWarning` |
| `.recording` | `Color.mtRecording` |
| `.ending` | `Color.mtGreenDark` |

### Animations

- **Pulse**: `pulseScale` animates 1.0 → 1.35 with `repeatForever(autoreverses: true)` during `.recording`.
- **Border**: `RoundedRectangle` stroke appears in `mtRecording.opacity(0.4)` when `state.isActive`.
- **Transition**: `.easeInOut(duration: 0.3)` on `isActive` changes.

### Timer

A 1-second repeating `Timer` increments `elapsedSeconds` while `state.isActive`. Started in `onAppear` and `onChange(of: state)`. Stopped in `onDisappear`.

### Sub-views

- `VehicleBadge` — shows `defaultVehicle.type.icon` + `registration`.
- `RecordingStrip` — shown only during `.recording`; displays speed from `locationManager.lastKnownSpeed` and location auth status.
