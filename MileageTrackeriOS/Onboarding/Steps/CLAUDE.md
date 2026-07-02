# Onboarding/Steps/

Eight step views. All take `vm: OnboardingViewModel` as a parameter. All except `WelcomeStep` use `OnboardingStepShell`.

---

## Step Views

| File | View | Data collected | Notes |
|------|------|---------------|-------|
| `IntroStep.swift` | `IntroStep` | — | Splash screen with app name and value props. "Get Started" advances to jurisdiction. |
| `JurisdictionStep.swift` | `JurisdictionStep` | `vm.regionCode` | Searchable list of all ISO-3166-1 countries (`Locale.Region.isoRegions` filtered to 2-char codes); pre-selected from `Locale.current.region`; flag emoji derived from Unicode regional indicators |
| `AddVehicleStep.swift` | `VehicleAndUnitStep` | `vm.vehicleRegistration` (required), `vm.vehicleName`, `vm.fuelType`, `vm.distanceUnit` | Merges former AddVehicle + DistanceUnit steps; "Continue" disabled until `vm.isVehicleValid`; fuel type grid uses `TypeChip`; distance unit uses `DistanceUnitRow` |
| `ClaimMethodStep.swift` | `ClaimMethodStep` | `vm.claimMethod`, `vm.customRateTiers` | `.customRate` reveals `CustomRateEditor` (tiered rate builder with `+` / `−` stepper and slider per tier) |
| `OdometerStep.swift` | `OdometerStep` | `vm.initialOdometerKm` | `Continue` disabled when field is empty and `.logbook` is selected; `LogbookOdometerTip` info card shown for logbook users |
| `PermissionsStep.swift` | `PermissionsStep` | — | Combined permissions step — location, motion, and notifications on one screen with Skip button |
| `TrackingHoursStep.swift` | `TrackingHoursStep` | `vm.trackingSchedule` | `DayScheduleRow` per weekday with toggle + `HourPicker` wheel pickers |
| `WelcomeStep.swift` | `WelcomeStep` | — | **Final step.** "You're all set!" completion screen. Needs `@Environment(AppState.self)`. "Start Tracking" calls `vm.complete(using: appState)`. Shows odometer summary row if a reading was entered. |
| `DistanceUnitStep.swift` | *(empty)* | — | Merged into `VehicleAndUnitStep`; file kept to avoid Xcode project changes |
| `LocationPermissionStep.swift` | *(orphaned)* | — | Replaced by `PermissionsStep`; file kept to avoid Xcode project changes |
| `MotionPermissionStep.swift` | *(orphaned)* | — | Replaced by `PermissionsStep`; file kept to avoid Xcode project changes |

---

## Shared components (defined here, reused elsewhere)

### DayScheduleRow

`struct DayScheduleRow` — `@Binding var snapshot: DayScheduleSnapshot`. Toggle enables/disables the day; `HourPicker` pair shown when enabled. Clamps end ≥ start + 1 and start ≤ end − 1.

**Reused in:** `TrackingHoursStep` (onboarding, binds to `vm.trackingSchedule`). The live-Realm variant `DayScheduleRowLive` in `Settings/TrackingHoursView.swift` mirrors this pattern but writes directly to the repo.

### HourPicker

`struct HourPicker` — `Picker` with `.wheel` style over 0…23, displays in 12-hour AM/PM format. Used inside `DayScheduleRow` and `DayScheduleRowLive`.

**Reused in:** `Settings/TrackingHoursView.swift`.
