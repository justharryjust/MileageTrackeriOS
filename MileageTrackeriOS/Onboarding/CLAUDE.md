# Onboarding/

Two files: `OnboardingView.swift` (coordinator + shell) and the step views in `Steps/`.

---

## OnboardingStep

```swift
enum OnboardingStep: Int, CaseIterable {
    case jurisdiction      = 0
    case vehicleAndUnit    = 1
    case claimMethod       = 2
    case locationPermission = 3
    case motionPermission  = 4
    case trackingHours     = 5
    case welcome           = 6
}
```

7 steps, integer raw value drives progress bar calculation.

---

## OnboardingViewModel

`@Observable final class OnboardingViewModel` — owns all data collected during onboarding.

### Collected state

| Property | Type | Step that sets it |
|----------|------|------------------|
| `regionCode` | `String` | `JurisdictionStep` (pre-filled from `Locale.current.region`) |
| `jurisdiction` | `Jurisdiction` (computed) | Derived from `regionCode`: NZ→`.newZealand`, AU→`.australia`, else→`.other` |
| `claimMethod` | `ClaimMethod` | `ClaimMethodStep` |
| `customRateTiers: [CustomRateTier]` | — | `ClaimMethodStep` (if `.customRate`) |
| `distanceUnit` | `DistanceUnit` | `VehicleAndUnitStep` |
| `vehicleName`, `vehicleRegistration`, `fuelType` | — | `VehicleAndUnitStep` |
| `trackingSchedule: [DayScheduleSnapshot]` | — | `TrackingHoursStep` |

### Navigation

- `advance()` — increments `currentStep`, sets `goingForward = true`, animates with `.spring(response: 0.45, dampingFraction: 0.82)`.
- `goBack()` — decrements `currentStep`, sets `goingForward = false`, same animation.
- `isVehicleValid` — `true` when `vehicleRegistration` is non-empty after trimming whitespace.

### Completion

`complete(using appState:)` — commits all collected data to `profileRepo`, calls `profileRepo.applySchedule`, sets `hasCompletedOnboarding = true`, then calls `appState.startTracking()`. Sets `isCompleted = true` to dismiss the onboarding flow. Called from `WelcomeStep` (final step).

---

## OnboardingView

`ZStack` layout:
- **Top bar**: back chevron (hidden on `.jurisdiction`) + `ProgressBar`.
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
- **MotionPermissionStep** — calls `motionManager.startActivityUpdates()` to trigger the system permission prompt. Auto-advances 0.8 s after `motionManager.isAuthorized`. Calls `vm.advance()` on both grant and Skip — **not** `vm.complete()`.
