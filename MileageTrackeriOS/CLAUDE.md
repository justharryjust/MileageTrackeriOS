# MileageTrackeriOS — App Target Root

## Entry Point

`MileageTrackeriOSApp.swift` — `@main` SwiftUI `App`. Creates `AppState.shared`, injects it into the view tree via `.environment(appState)`. `RootView` reads `appState.profileRepo.hasCompletedOnboarding` and routes to either `OnboardingView` or `MainTabView`.

## Invariants

- `AppState.shared` owns **all** managers and repositories. Nothing else should instantiate them.
- `AppState` must be created before any view accesses managers or repos.
- `@Observable` is used throughout — **not** `ObservableObject`/`@Published`.
- All Realm writes go through repository `write()` helpers. Views never call `realm.write` directly.

## Directory Map

| Directory | Purpose |
|-----------|---------|
| `App/` | `AppState` — root singleton, wires all dependencies |
| `Managers/` | Hardware abstraction: location, motion, Bluetooth, trip recording |
| `Models/` | Realm objects, enums, and in-memory value types |
| `Repositories/` | Realm CRUD — `TripRepository`, `UserProfileRepository`, `RealmProvider` |
| `Main/` | Post-onboarding tab UI: Home, Trips, Settings |
| `Onboarding/` | 8-step first-run flow and `OnboardingViewModel` |
| `Shared/` | Design system tokens (colours, spacing, radii, button styles) |
| `Logging/` | `TripLogger` — persistent ring-buffer debug log |
| `Localisaion/` | Official mileage rate tables per jurisdiction |
