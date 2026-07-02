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

Global constant `[OfficalMileageRate]`. Covers 16 countries — see `.claude/research/mileage-rates-by-country.md` for full sourced rates, tiers, and citations (kept separate so the audit trail doesn't need to move in lockstep with the Swift). Quick index:

| Country | ISO2 | Authority |
|---------|------|-----------|
| New Zealand | NZ | IRD |
| Australia | AU | ATO |
| United Kingdom | GB | HMRC |
| United States | US | IRS |
| Canada | CA | CRA |
| Germany | DE | BMF |
| Belgium | BE | SPF/BOSA |
| Netherlands | NL | Belastingdienst |
| Switzerland | CH | EFD/ESTV |
| Austria | AT | BMF |
| Sweden | SE | Skatteverket |
| Norway | NO | Skatteetaten |
| Denmark | DK | Skattestyrelsen |
| Finland | FI | Verohallinto |
| Spain | ES | Agencia Tributaria |
| South Africa | ZA | SARS (simplified opt-in method only — the primary vehicle-value-banded method needs a data-model extension) |

Ireland, France, and Italy have genuine official rates but were deliberately excluded — their tiering (engine-size bands, fiscal-horsepower bands, per-vehicle-model tables) doesn't fit `MileageRates.Thresholds`, which only represents cumulative-distance tiers.

**Known limitation:** rate segmentation by *vehicle type* (e.g. GB/DE/AT Motorcycle, GB Bicycle) is currently unreachable at runtime. `MileageCalculator.rateFor(fuelType:)` only keys off fuel type, never `Vehicle.type`, so whichever entry's `fuelType` list happens to cover every case (e.g. "Car / Van") always wins the lookup first — the vehicle-type-only rows are stored correctly but never selected.

---

## Adding a new jurisdiction

1. Add a new `.init(countryCode:defaultDistanceUnit:mileageRates:)` entry to `officialRates`.
2. Add the corresponding case to `enum Jurisdiction` in `Models/Models.swift` with `displayName` and `flag` (logbookPeriodDays/logbookValidityYears fall back to the `default:` arm unless researched).
3. If the jurisdiction's reimbursement year isn't the calendar year, or it has an annual distance cap, add a case to `taxYear`/`annualKilometreCap` in this file.
4. Hook up the rate lookup in wherever `officialRates` is consumed (rate calculation logic).
