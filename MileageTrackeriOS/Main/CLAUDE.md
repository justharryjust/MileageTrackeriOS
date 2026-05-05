# Main/

Post-onboarding UI. Entry view is `MainTabView`.

## MainTabView

3-tab `TabView` tinted `.mtGreen`. `selectedTab: Int` drives the filled/outline icon variant for each tab item.

| Tab | Index | Root view |
|-----|-------|-----------|
| Home | 0 | `HomeView` |
| Trips | 1 | `TripsView` |
| Settings | 2 | `SettingsView` |

## Subdirectories

| Directory | Content |
|-----------|---------|
| `Home/` | Live trip status card + quick stats + recent trips |
| `Trips/` | Trip list, trip detail map, manual trip entry |
| `Settings/` | Profile/vehicle display, tracking hours, debug tools |

## Rule

All views read data from `AppState` via `@Environment(AppState.self)`. Never pass managers or repositories as direct view parameters — access them through `appState.locationManager`, `appState.tripRepo`, etc.
