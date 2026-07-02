# Onboarding/

Two files: `OnboardingView.swift` (coordinator + shell) and the step views in `Steps/`.

---

## OnboardingStep

```swift
enum OnboardingStep: Int, CaseIterable {
    case intro          = 0
    case jurisdiction   = 1
    case vehicleAndUnit = 2
    case claimMethod    = 3
    case odometer       = 4
    case permissions    = 5
    case trackingHours  = 6
    case welcome        = 7
}
```

8 steps, integer raw value drives progress bar calculation.

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
| `initialOdometerKm` | `String` | `OdometerStep` (required for `.logbook`, optional otherwise) |
| `trackingSchedule: [DayScheduleSnapshot]` | — | `TrackingHoursStep` |

### Navigation

- `advance()` — increments `currentStep`, animates with `.spring(response: 0.35, dampingFraction: 0.85)`.
- `goBack()` — decrements `currentStep`, same animation.
- `isVehicleValid` — `true` when `vehicleRegistration` is non-empty after trimming whitespace.

### Completion

`complete(using appState:)` — commits all collected data to `profileRepo`, calls `profileRepo.applySchedule`, sets `hasCompletedOnboarding = true`. If `.logbook` and `initialOdometerKm` is valid, records the initial odometer reading via `appState.odometerRepo.recordReading(source: .onboarding)`. Then calls `appState.startTracking()`. Sets `isCompleted = true` to dismiss the onboarding flow. Called from `WelcomeStep` (final step).

---

## OnboardingView

`ZStack` layout:
- **Top bar**: back chevron (hidden on `.intro`) + progress dots.
- **Step content**: switches on `vm.currentStep` with opacity + offset transition.
- Each step view is `.id(vm.currentStep)` to force SwiftUI to replace rather than update.

---

## OnboardingStepShell

Reusable container used by every step except `WelcomeStep`.

```swift
OnboardingStepShell(icon:iconColor:title:subtitle:) { /* content */ }
```

Renders icon circle, heading, subtitle, and the provided content with consistent padding.
