# MileageTracker — Project Brief

**Last Updated:** April 21, 2026

---

## What it is

MileageTracker is a standalone mobile app (iOS first, Android later) that helps sole traders track business travel and claim vehicle expenses at tax time. It automatically records trips in the background using GPS, lets users categorise them as business or personal, and generates tax-compliant mileage reports.

The app is **privacy-first and tracking-first**. All data is owned by the user and stored in their personal iCloud — there is no central server, no account required, and no third-party data sharing. The core experience is seamless, automatic trip capture with zero manual effort.

---

## Who uses it

Freelancers, contractors, and self-employed workers who drive for work — tradies, NDIS workers, wellness professionals, and similar sole traders in New Zealand and Australia.

---

## Core features

### Automatic trip tracking
The app uses GPS and motion sensors to detect driving and record trips in the background. No manual start/stop required. Trips are captured even without connectivity — GPS data is stored locally and synced to the user's iCloud when the phone reconnects.

### Manual trip entry
Users can log trips manually with start and end addresses for anything auto-tracking missed.

### Trip categorisation
Recorded trips appear with a map preview. Users swipe to mark each as business or personal. Only business trips count towards expense claims. Personal trips are deleted after 7 days.

### Multiple vehicles
No limit on vehicles. Supports cars, trucks, and motorcycles across electric, combustion, and hybrid fuel types.

### Saved addresses
Frequently visited locations can be saved for faster manual entry.

### Claim methods
Users select one of three claim methods — available from the start of onboarding:

| Method | Description |
|---|---|
| **Standard Mileage Rate** | Uses the IRD or ATO published cents-per-km rate for the user's jurisdiction |
| **Custom Mileage Rate** | User sets their own rate per kilometre |
| **Logbook** | User records odometer readings (start and end) for each trip or period; the app calculates business-use percentage from those readings |

Logbook mode does **not** require fuel receipts or running cost data — it is based solely on odometer readings provided by the user.

---

## Exporting and reporting

PDF reports and logbooks can be exported containing start/end locations, dates, vehicle registration, distance, and the dollar value of the expense. Reports are generated on-device and shared via the iOS share sheet.

---

## Privacy and data ownership

- All trip data is stored on-device and in the user's **personal iCloud** (private CloudKit database).
- No account or login is required.
- The app does not transmit data to any external server.
- Users can delete all their data at any time.

---

## Access and subscription model

### Free trial
30 days of full access from first launch.

### After the trial
- **Tracking always continues** — the app never stops recording trips, regardless of subscription status.
- **Viewing and exporting are gated**: users can only view, categorise, and export trips that occurred during an **active subscription period**.
- After the trial ends, a **2-week grace period** allows the user to review and categorise trips before the export/view gate activates.
- This model prevents the "track all year, pay for one month to export" abuse pattern — reports only cover the window when a subscription was active.

### Pricing
| Plan | Price |
|---|---|
| Monthly | AUD/NZD $6.99/month |
| Annual | AUD/NZD ~$50–55/year |

---

## Jurisdiction-specific behaviour

Expense calculations use locally correct mileage rates — IRD rates in New Zealand, ATO cents-per-km in Australia. In Australia, the ATO caps claimable kilometres at 5,000 km per vehicle per financial year; once reached, expenses are recorded at $0 for record-keeping purposes. Each jurisdiction has its own set of supported fuel/energy types.

---

## Technical approach

- **Kotlin Multiplatform (KMP)** for shared business logic — data models, calculations, local storage, and sync logic — so the Android version can be built with minimal rework.
- **Native iOS (Swift/SwiftUI)** for anything requiring hardware access or where native performance wins: location services, CoreMotion, background processing, UI, StoreKit, and CloudKit.
- Robustness over shortcuts — where native code offers a meaningful advantage, it is used.
- **Analytics/crash reporting:** TBD — Firebase preferred (free tier is well-suited to early stage).
