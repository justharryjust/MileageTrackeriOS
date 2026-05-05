# Onboarding/Steps/

Eight step views, each wrapped in `OnboardingStepShell` (except `WelcomeStep`). All take `vm: OnboardingViewModel` as a parameter.

---

## Step Views

| File | View | Data collected | Notes |
|------|------|---------------|-------|
| `WelcomeStep.swift` | `WelcomeStep` | None | Branding, feature bullets, "Get Started" calls `vm.advance()` |
| `JurisdictionStep.swift` | `JurisdictionStep` | `vm.jurisdiction` | Pre-selected from `Locale.current.region`; NZ/AU cards |
| `ClaimMethodStep.swift` | `ClaimMethodStep` | `vm.claimMethod`, `vm.customRateTiers` | `.customRate` reveals `CustomRateEditor` (tiered rate builder with `+` / `−` stepper and slider per tier) |
| `DistanceUnitStep.swift` | `DistanceUnitStep` | `vm.distanceUnit` | km / mi selection cards |
| `AddVehicleStep.swift` | `AddVehicleStep` | `vm.vehicleRegistration` (required), `vm.vehicleName`, `vm.fuelType` | "Continue" disabled until `vm.isVehicleValid`; fuel type grid uses `TypeChip` |
| `TrackingHoursStep.swift` | `TrackingHoursStep` | `vm.trackingSchedule` | `DayScheduleRow` per weekday with toggle + `HourPicker` wheel pickers |
| `LocationPermissionStep.swift` | `LocationPermissionStep` | — | Two-step WhenInUse → Always; denied/restricted shows Settings deep-link; auto-advances 0.8 s on `.authorizedAlways` |
| `MotionPermissionStep.swift` | `MotionPermissionStep` | — | Last step. Calls `motionManager.startActivityUpdates()` for system prompt. Both "Allow" (on grant) and "Skip" call `vm.complete(using: appState)` |

---

## Shared components (defined here, reused elsewhere)

### DayScheduleRow

`struct DayScheduleRow` — `@Binding var snapshot: DayScheduleSnapshot`. Toggle enables/disables the day; `HourPicker` pair shown when enabled. Clamps end ≥ start + 1 and start ≤ end − 1.

**Reused in:** `TrackingHoursStep` (onboarding, binds to `vm.trackingSchedule`). The live-Realm variant `DayScheduleRowLive` in `Settings/TrackingHoursView.swift` mirrors this pattern but writes directly to the repo.

### HourPicker

`struct HourPicker` — `Picker` with `.wheel` style over 0…23, displays in 12-hour AM/PM format. Used inside `DayScheduleRow` and `DayScheduleRowLive`.

**Reused in:** `Settings/TrackingHoursView.swift`.
