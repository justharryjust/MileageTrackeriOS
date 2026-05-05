# App/

Single file: `AppState.swift`.

## AppState

`@Observable final class AppState` — root singleton accessed via `AppState.shared`.

### Owned dependencies

| Property | Type | Role |
|----------|------|------|
| `realmProvider` | `RealmProvider` | Opens and vends the shared `Realm` |
| `profileRepo` | `UserProfileRepository` | Singleton user profile + vehicles |
| `tripRepo` | `TripRepository` | Trip CRUD + live collections |
| `locationManager` | `LocationManager` | CLLocationManager wrapper |
| `motionManager` | `MotionManager` | CMMotionActivityManager wrapper |
| `bluetoothManager` | `BluetoothManager` | Car-kit BLE scanning |
| `tripRecorder` | `TripRecorder` | Trip detection state machine |

### Init order (strict)

1. `RealmProvider.shared` — Realm must open before any repo reads it.
2. `UserProfileRepository(realm:)` + `TripRepository(realm:)`.
3. `LocationManager()`, `MotionManager()`, `BluetoothManager()`.
4. `TripRecorder.shared.configure(location:motion:bluetooth:tripRepo:profileRepo:)` — wires all callbacks.
5. If `profileRepo.hasCompletedOnboarding`, call `startTracking()` immediately.

### startTracking()

Starts `motionManager.startActivityUpdates()`, `bluetoothManager.startMonitoring()`, `locationManager.startSignificantLocationMonitoring()`, `locationManager.startVisitMonitoring()`.

Called from `init` (already onboarded) **or** from `OnboardingViewModel.complete(using:)` (end of onboarding).

## Rules

- Never instantiate managers outside `AppState`.
- Inject into SwiftUI via `.environment(appState)` at the root; read in views with `@Environment(AppState.self)`.
