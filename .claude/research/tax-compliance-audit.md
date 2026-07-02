# Tax-Compliance Audit — 16 Supported Countries

Companion to [`mileage-rates-by-country.md`](mileage-rates-by-country.md). Rate figures themselves are audited in that file and are only referenced here for context. This doc audits the **compliance surface around** the rate — which claim methods are legal, whether a logbook is mandatory and in what form, record-retention periods, required per-trip fields, and currency — against what the app supports today.

The app's goal is to make it **possible/easy** for a user to be compliant, **not** to enforce compliance.

## Verdict

**All 16 supported countries have the core covered.** Every one has an official rate (from PR #52), all three claim methods available (Standard / Logbook / Custom), per-tax-year handling, and per-trip record fields (date, distance, origin/destination, purpose, business/private category, odometer, notes). So a user **can** produce a substantiating claim in every supported country today.

The audit found **4 systemic gaps** (below) plus some **per-country method caveats** worth surfacing. None of the gaps stop a diligent user from being compliant, but three of them make it harder than it should be, and one (onboarding) blocks the compliant path out of the box for 13 of 16 countries.

## Per-country compliance

| Country | Flat per-km for self-employed? | Logbook style required | Retention | Currency | Key caveat |
|---|---|---|---|---|---|
| United States (US) | ✅ IRS standard mileage | Every-trip, ongoing (no sample) | 3y | USD | Must elect standard rate in first year; disallowed if operating 5+ cars |
| Canada (CA) | ❌ **Not** a self-employed deduction — 73/67¢ is an employer-**reimbursement** allowance (deduction = business-% of actual costs) | 12-month base year + 3-month sample, valid while within ±10% of base | 6y | CAD | App's Standard-rate = reimbursement, not a deduction |
| United Kingdom (GB) | ✅ Simplified expenses | Every-trip, ongoing | 5y | GBP | Method is locked per-vehicle once chosen |
| New Zealand (NZ) | ✅ km-rate method | 90-day sample, valid 3y (redo if business use shifts >20%) | 7y | NZD | **Matches the app's logbook-period model** |
| Australia (AU) | ✅ cents-per-km (capped 5,000 business km/yr) | 12 continuous weeks, valid 5y | 5y | AUD | **Matches app model**; above 5,000 km must use logbook method |
| Germany (DE) | ✅ €0.30/km business trips | Full-year every-trip Fahrtenbuch; contemporaneous (within 7 days); tamper-evident | 10y (business) / 6y (employee) | EUR | Business-trip mileage vs commuter Entfernungspauschale are distinct; must record business partner/customer visited |
| Austria (AT) | ✅ €0.50/km (capped 30,000 km/yr) | Full-year every-trip | 7y | EUR | 30,000 km cap |
| Switzerland (CH) | ✅ CHF 0.75/km (accepted admin rate, not rigid statute) | Daily, gap-free | 10y | CHF | Employer Spesenreglement may set a different rate |
| Belgium (BE) | ✅ ~€0.44/km | Substantiate business km (no gazetted format) | 7y (10y for fraud cases) | EUR | None major |
| Netherlands (NL) | ✅ €0.25/km — **sole** method for a privately-owned car | Ongoing rittenregistratie | 7y | EUR | Actual-cost is **disallowed** for own car — don't offer that add-on |
| Spain (ES) | ❌ Not for autónomos — only an **employee** reimbursement exemption (~€0.26/km) | Ongoing + odometer | 4y tax (6y commercial) | EUR | Autónomo deduction requires ~100% exclusive business use; often not deductible at all |
| Sweden (SE) | ✅ 2.50 SEK/km — effectively **mandatory** for a private car | Ongoing körjournal | 7y | SEK | Actual-cost only if the car is a business asset |
| Norway (NO) | ✅ 3.50 NOK/km | Daily kjørebok + monthly odometer reading | 5y | NOK | ≥6,000 business km/yr shifts the car to a business-asset regime |
| Denmark (DK) | ✅ 3.94 / 2.28 DKK/km (tiered at 20,000 km) | Contemporaneous kørebog — a log written up afterwards is **not** accepted | 5y | DKK | Strict contemporaneous-entry rule |
| Finland (FI) | ✅ €0.55/km | Ongoing ajopäiväkirja with monthly business/private split | 6y | EUR | Also requires start/end **time** and route per trip |
| South Africa (ZA) | ✅ 495c/km simplified (only if no other travel allowance) **or** deemed-cost vehicle-value-band method | Full-year, **redone annually** (no multi-year validity); odometer opening/closing is load-bearing | 5y | ZAR | Strictest — a logbook is effectively mandatory to claim; home-to-work excluded |

## The 4 systemic gaps

Ranked by impact on *can the user actually reach a compliant state*.

### 1. Onboarding can only select 3 of 16 jurisdictions — HIGH
`OnboardingViewModel.jurisdiction` maps everything except NZ/AU to `.other` (which uses UK rates), and `JurisdictionStep` only lists NZ / AU / Other. New users in the other 13 countries silently land on **UK rates** until they discover the Settings picker (which *does* expose all 16 via `Jurisdiction.allCases`). This is the only gap that blocks the compliant path out of the box.

### 2. Currency is hard-coded `$` everywhere — MEDIUM-HIGH
`HomeView`, `TripsView`, `TripView`, `ReportGenerator` (CSV) and `ReportExportView` all format values as `$`. Correct only for the 4 dollar countries (US/CA/AU/NZ); wrong for the other 12 (GBP, 7× EUR, CHF, SEK, NOK, DKK, ZAR). No currency is modelled on `OfficalMileageRate` or `UserProfile`. Affects the credibility of the exported claim a user hands to their tax authority.

### 3. The "logbook period" concept fits only NZ/AU — MEDIUM
The app's logbook-period model (a fixed sample window that expires, driven by `Jurisdiction.logbookPeriodDays` / `logbookValidityYears`) only genuinely fits NZ (90d/3y), AU (84d/5y) and loosely CA. The other 11 countries require **ongoing, every-trip** records with no expiring sample — yet all 13 new countries were defaulted to 90 days / 3 years, so `LogbookPeriodView` would misdescribe their rule ("Start a 90-day logbook period"). Needs either real per-country values or a distinct "continuous log" mode.

### 4. Record-retention period is not modelled at all (0/16) — LOW-MEDIUM
Retention varies 3–10 years (US 3; ES 4; AU/GB/NO/DK/ZA 5; CA/FI 6; NZ/AT/SE/BE/NL 7; DE/CH 10). The app keeps the data regardless, but never tells the user how long they must retain records to stay defensible.

## Compliance assets the app already has

- **All three claim methods** (Standard / Logbook / Custom) are offered in every jurisdiction — a user whose country requires the logbook/actual-cost route can choose it.
- **Per-trip fields already cover the universal requirement:** date, distance, `startAddress`/`endAddress`, `purpose`, `category` (business/private), odometer (`OdometerReading` + `odometerDistanceMetres`), `notes`.
- **Tamper-evident, contemporaneous records** via the existing `commitHash` + `committedAt` (SHA-256) — directly supports Germany's "tamper-proof, within 7 days", Switzerland's "gap-free", and Denmark's "no retroactive logs" requirements.
- **Logbook-period lifecycle + business-use-% calculation** already exist (correct for NZ/AU).
- **Per-country compliance info screen** (`MethodInfoView`) is reachable from Settings and now covers all 16 with agency name, URL and cap text.

## Recommended additions (prioritized — not yet built)

1. **Onboarding jurisdiction picker over all 16** (and map `regionCode` → the real `Jurisdiction` case, not `.other`).
2. **Currency field on the rate model + a shared currency formatter** replacing hard-coded `$`.
3. **A "continuous log" vs "sample-period" distinction** on `Jurisdiction` (or corrected per-country logbook values) so the logbook UI stops misdescribing 11 countries.
4. **An optional retention-period field**, surfaced as guidance ("keep these records until …").
5. **Per-country method caveats surfaced in `MethodInfoView`** — especially CA (reimbursement vs deduction), ES (autónomo exclusive-use), NL (no actual-cost for own car), ZA (annual logbook).
