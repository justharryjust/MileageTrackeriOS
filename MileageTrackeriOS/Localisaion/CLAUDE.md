# Localisaion/

> Note: directory name has a typo (one `i`) — keep it as-is to avoid breaking Xcode project references.

Single file: `MileageRates.swift`.

---

## Types

`OfficalMileageRate` — top-level struct grouping rates for one country:

```swift
struct OfficalMileageRate {
    let countryCode: String
    let defaultDistanceUnit: DistanceUnit
    let mileageRates: [MileageRates]
}
```

`MileageRates` and its nested `Thresholds` struct are defined in **`Models/Models.swift`**, not here.

---

## officialRates

Global constant `[OfficalMileageRate]`. Current data:

| Country | Fuel | Rate | Cap |
|---------|------|------|-----|
| NZ | Diesel | 79 c/km | 140 000 km |
| NZ | Petrol | 100 c/km | 140 000 km |

---

## Adding a new jurisdiction

1. Add a new `.init(countryCode:defaultDistanceUnit:mileageRates:)` entry to `officialRates`.
2. Add the corresponding case to `enum Jurisdiction` in `Models/Models.swift` with `displayName` and `flag`.
3. Hook up the rate lookup in wherever `officialRates` is consumed (rate calculation logic).
