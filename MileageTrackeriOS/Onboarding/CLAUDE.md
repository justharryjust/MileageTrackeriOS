# Onboarding/

Two files: `OnboardingView.swift` (coordinator + shell) and the step views in `Steps/`.

---

## OnboardingStep

```swift
enum OnboardingStep: Int, CaseIterable {
    case welcome = 0, jurisdiction, claimMethod, distanceUnit,
         addVehicle, trackingHours, locationPermission, motionPermission
}
```

8 steps, integer raw value drives progress bar calculation.

---

## OnboardingViewModel

`@Observable final class OnboardingViewModel` — owns all data collected during onboarding.

### Collected state

| Property | Step that sets it |
|----------|------------------|
| `jurisdiction` | `JurisdictionStep` (pre-filled from `Locale`) |
| `claimMethod` | `ClaimMethodStep` |
| `customRateTiers: [CustomRateTier]` | `ClaimMethodStep` (if `.customRate`) |
| `distanceUnit` | `DistanceUnitStep` |
| `vehicleName`, `vehicleRegistration`, `fuelType` | `AddVehicleStep` |
| `trackingSchedule: [DayScheduleSnapshot]` | `TrackingHoursStep` |

### Navigation

- `advance()` — increments `currentStep`, sets `goingForward = true`, animates with `.spring(response: 0.45, dampingFraction: 0.82)`.
- `goBack()` — decrements `currentStep`, sets `goingForward = false`, same animation.
- `isVehicleValid` — `true` when `vehicleRegistration` is non-empty after trimming whitespace.

### Completion

`complete(using appState:)` — commits all collected data to `profileRepo`, calls `profileRepo.applySchedule`, sets `hasCompletedOnboarding = true`, then calls `appState.startTracking()`. Sets `isCompleted = true` to dismiss the onboarding flow.

---

## OnboardingView

`ZStack` layout:
- **Top bar**: back chevron (hidden on `.welcome`) + `ProgressBar`.
- **Step content**: switches on `vm.currentStep` with `asymmetric` slide transition — inserts from trailing/leading and removes to leading/trailing based on `vm.goingForward`.
- Each step view is `.id(vm.currentStep)` to force SwiftUI to replace rather than update.

---

## OnboardingStepShell

Reusable container used by every step except `WelcomeStep`.

```swift
OnboardingStepShell(icon:iconColor:title:subtitle:) { /* content */ }
```

Renders icon circle, heading, subtitle, and the provided content in a `ScrollView` with consistent padding.

---

## Permission steps

- **LocationPermissionStep** — triggers two-step WhenInUse → Always flow via `locationManager.requestLocationPermission()`. Auto-advances 0.8 s after `authorizationStatus == .authorizedAlways`. Shows guidance for WhenInUse-only and denied states.
- **MotionPermissionStep** — calls `motionManager.startActivityUpdates()` to trigger the system permission prompt. Auto-advances 0.8 s after `motionManager.isAuthorized`. This is the **final step** — both "granted" and "Skip" call `vm.complete(using: appState)`.
