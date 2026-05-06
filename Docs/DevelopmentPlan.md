# MileageTracker — Development Plan

**Date:** April 21, 2026
**Author:** Harry Just
**Status:** Draft v1.2

---

## 1. Project Overview

### Goals
MileageTracker is a **tracking-first, privacy-first** mobile mileage and vehicle expense tracking app for sole traders, freelancers, and contractors. It automatically records business trips via GPS, lets users categorise and annotate those trips, and produces tax-compliant mileage reports.

All data is owned by the user and stored in their personal iCloud — there is no central server, no account required, and no third-party data sharing.

The primary markets are **New Zealand** (IRD) and **Australia** (ATO), with currency, rate tables, and compliance rules varying by jurisdiction.

### Platforms
| Platform | Timeline | UI Framework |
|---|---|---|
| iOS | MVP + full release | SwiftUI |
| Android | Post-iOS v1 | Jetpack Compose |

### Tech Stack Rationale
| Layer | Technology | Why |
|---|---|---|
| Shared business logic | Kotlin Multiplatform (KMP) | Single source of truth for models, calculations, storage, sync logic |
| iOS UI & hardware | Swift / SwiftUI | CoreLocation, CoreMotion, background modes, StoreKit — native wins here |
| Android UI & hardware | Kotlin / Jetpack Compose | Fused Location, ActivityRecognition — native for same reasons |
| Local database | Realm Kotlin SDK (KMP) | Official KMP support (iOS + Android), object-oriented model, reactive Flows, no SQL required |
| iCloud sync (iOS) | CloudKit | User-owned data, no server cost, privacy-first |
| Subscription | StoreKit 2 (iOS) | Modern async API, receipt-less validation |
| DI | Koin (KMP + native) | Lightweight, KMP-compatible |
| Analytics / crash reporting | TBD — Firebase preferred | Free tier well-suited to early stage; address post-core build |

---

## 2. Architecture

### 2.1 KMP Module Breakdown

```
:shared
├── :shared:domain          # Entities (Realm objects), use cases, repository interfaces
├── :shared:data            # Realm DB, repository impls
├── :shared:calculations    # Mileage rate logic, ATO cap, IRD/ATO rules, logbook %
└── :shared:sync            # Sync queue, conflict resolution logic
```

iOS and (future) Android apps each depend on `:shared` for all business logic.

### 2.2 iOS Native Layer Responsibilities

| Responsibility | Module/Framework |
|---|---|
| GPS & background trip detection | CoreLocation + significant location change |
| Motion activity (driving detection) | CoreMotion / CMMotionActivityManager |
| Background processing | BGTaskScheduler, background location entitlement |
| UI | SwiftUI |
| Subscription | StoreKit 2 |
| iCloud sync | CloudKit (CKDatabase) |
| Local keychain | Security framework |
| Push / local notifications | UserNotifications |

### 2.3 Shared vs Native Responsibility Matrix

| Concern | KMP Shared | iOS Native |
|---|---|---|
| Trip data model & persistence | ✅ | |
| Rate calculations | ✅ | |
| Logbook business-use % calculation | ✅ | |
| Sync queue logic | ✅ | |
| GPS raw data capture | | ✅ |
| Motion detection | | ✅ |
| Background wake-up | | ✅ |
| StoreKit / IAP | | ✅ |
| CloudKit record mapping | | ✅ |
| SwiftUI views | | ✅ |

### 2.4 Data Flow — Automatic Trip

```
CoreLocation (iOS)
  → TripRecorder (iOS native)
      → accumulates CLLocations, detects trip start/end via motion + geofence inactivity
  → TripRepository (KMP :shared:data)
      → Realm local DB
  → SyncQueue (KMP :shared:sync)
      → CloudKit (iOS) on reconnect
```

---

## 3. Feature Breakdown

### 3.1 Automatic Trip Tracking

**Description:** Background GPS + motion sensor detection. No manual start/stop required.

**Implementation Notes:**
- iOS: Use `CLLocationManager` in always-on background mode + `CMMotionActivityManager` to classify `automotive` activity.
- Trip start heuristic: sustained `automotive` activity + speed > ~10 km/h for >30 seconds.
- Trip end heuristic: activity stops + stationary for >2 minutes OR significant location change event.
- Raw GPS points stored as `TripPoint` Realm objects; trip distance calculated in KMP using Haversine formula.
- Background wake via significant location change (`startMonitoringSignificantLocationChanges`) as low-power fallback.
- `BGProcessingTask` for post-processing/sync when app is backgrounded.

**Complexity:** High — multi-state machine, battery sensitivity, edge cases (tunnels, multi-stop, parking).

---

### 3.2 Manual Trip Entry

**Description:** User logs a trip with start address, end address, date, distance, and vehicle.

**Implementation Notes:**
- Address autocomplete via MapKit `MKLocalSearch` (no API key, on-device).
- Saved addresses pulled from `Address` Realm objects.
- Distance can be entered manually or calculated from addresses via MapKit directions.
- KMP use case: `CreateManualTripUseCase`.

**Complexity:** Low–Medium.

---

### 3.3 Trip Categorisation

**Description:** Swipe-to-categorise (Business / Personal) on trip list. Personal trips auto-deleted after 7 days.

**Implementation Notes:**
- SwiftUI `swipeActions` on trip list row.
- `Trip.category` enum: `.business`, `.personal`, `.uncategorised`.
- Scheduled `BGAppRefreshTask` to purge personal trips older than 7 days.
- Uncategorised trips shown in a dedicated "Needs Review" section.

**Complexity:** Low.

---

### 3.4 Multiple Vehicles

**Description:** Users can register multiple vehicles. Each trip is assigned to one vehicle.

**Implementation Notes:**
- `Vehicle` Realm object: `id`, `name`, `registration`, `type` (car/truck/motorcycle), `fuelType` (petrol/diesel/EV/hybrid/PHEV), `isDefault`.
- Fuel/energy type list is jurisdiction-aware.
- Default vehicle pre-selected on new trips.

**Complexity:** Low.

---

### 3.5 Saved Addresses

**Description:** Frequently used locations (home, office, client sites) stored for fast manual entry.

**Implementation Notes:**
- `Address` Realm object: `id`, `label`, `fullAddress`, `latitude`, `longitude`, `usageCount`.
- Shown as suggestions in address fields in manual entry.
- "Save this address" prompt after repeated use of the same location (frequency tracked in KMP).

**Complexity:** Low.

---

### 3.6 Claim Methods

**Description:** Three claim methods selectable from the start of onboarding. The user can change their method later.

| Method | Description |
|---|---|
| Standard Mileage Rate | Uses IRD/ATO published cents-per-km rates |
| Custom Mileage Rate | User sets their own rate per km |
| Logbook | User records odometer readings; app derives business-use percentage |

**Implementation Notes:**
- Method stored in `UserProfile.claimMethod`.
- Calculations in `:shared:calculations` — `MileageCalculator` interface with concrete impls per method.
- Rate tables bundled as JSON in KMP; updated from remote versioned config on app launch.

**Logbook mode (odometer-based):**
- User enters an **odometer reading** at the start and end of each trip (or period).
- App tracks total km driven and business km driven across those readings.
- Business-use percentage = business km ÷ total km.
- `OdometerReading` Realm object: `id`, `vehicleId`, `readingKm`, `recordedAt`, `tripId?`.
- No fuel receipts or running cost data required.
- `LogbookCalculator` in KMP computes percentage and dollar values.

**Complexity:** Medium (standard/custom); Medium (logbook — odometer approach is straightforward).

---

### 3.7 Offline Tracking & Sync

See Sections 8 and 9.

---

### 3.8 PDF Report Generation

**Description:** Generate a PDF mileage logbook with date, start/end, vehicle reg, distance, and dollar value.

**Implementation Notes:**
- iOS: `UIGraphicsPDFRenderer` in Swift — native PDF generation.
- Report data aggregated in KMP (`ReportUseCase`) and passed to iOS PDF renderer.
- Report includes tax period, jurisdiction, totals, per-trip rows, and odometer summary (logbook mode).
- Export via `ShareSheet` (iOS share extension).
- Only trips within **active subscription periods** are included in exported reports.

**Complexity:** Medium.

---

### 3.9 Subscription & Free Tier

See Section 7.

---

## 4. Phased Roadmap

### Phase 1 — Foundation (Weeks 1–4)
- KMP shared module scaffold (`:shared:domain`, `:shared:data`)
- Realm Kotlin SDK setup and schema: `Trip`, `TripPoint`, `Vehicle`, `Address`, `UserProfile`, `OdometerReading`, `SubscriptionPeriod`, `RateTable`
- iOS project setup: KMP integration, Koin DI, basic SwiftUI shell
- Manual trip entry (core flow, no address autocomplete yet)
- Vehicle management (add/edit/delete)
- Basic trip list UI

**Exit criteria:** Can manually log a trip, assign to a vehicle, see it in a list.

---

### Phase 2 — Automatic Tracking (Weeks 5–9)
- iOS `TripRecorder`: CoreLocation + CoreMotion state machine
- Background location entitlement + BGTask setup
- Trip start/end heuristics + raw `TripPoint` storage in Realm
- Trip categorisation (swipe UI + 7-day purge)
- Saved addresses + MapKit autocomplete
- Distance calculation (Haversine in KMP)

**Exit criteria:** App auto-detects and records a real drive without user interaction.

---

### Phase 3 — Calculations, Reports & Subscription (Weeks 10–15)
- Mileage rate engine in KMP (standard + custom + logbook/odometer modes)
- Onboarding: claim method selection from day one (all three available)
- Logbook odometer entry UI + `LogbookCalculator` in KMP
- IRD and ATO rate tables, jurisdiction selection
- ATO 5,000 km cap enforcement
- PDF report generation (iOS native)
- StoreKit 2 subscription (monthly + annual, 30-day trial)
- Subscription period gating: trips viewable/exportable only within active subscription windows
- 2-week grace period post-trial before view gate activates
- iCloud sync (Realm → CloudKit — see Section 8)

**Exit criteria:** Subscriber can generate and share a PDF logbook; lapsed user is shown the correct gating state.

---

### Phase 4 — Polish & App Store (Weeks 16–20)
- Onboarding flow refinement (jurisdiction, claim method, first vehicle, permissions)
- Settings screen (vehicles, saved addresses, subscription management)
- Notifications (uncategorised trip reminders, ATO cap warnings)
- Accessibility (VoiceOver, Dynamic Type)
- App Store submission prep (privacy manifest, location justification)

**Exit criteria:** TestFlight beta ready for external testers.

---

### Phase 5 — Beta & Hardening (Weeks 21–24)
- Beta feedback integration
- Performance profiling (battery, memory — background location is critical)
- Analytics/crash reporting integration (TBD — Firebase preferred)
- App Store release

---

### Phase 6 — Android (Post-iOS v1)
- KMP shared Realm modules reused as-is (local Realm only — no CloudKit on Android)
- Android native: Fused Location Provider, ActivityRecognition API
- Jetpack Compose UI
- Google Play Billing for subscriptions
- Cloud sync deferred — see Section 9 for Android sync options

---

## 5. Data Model

### `UserProfile`
| Field | Type | Notes |
|---|---|---|
| id | String (ObjectId) | |
| jurisdiction | String (enum: NZ, AU) | Determines rate tables and rules |
| claimMethod | String (enum: standard, custom, logbook) | Chosen during onboarding; changeable |
| customRatePerKm | Double? | Only if claimMethod = custom |
| financialYearStart | Int (month) | AU: 7 (July), NZ: 4 (April) |
| subscriptionStatus | String (enum: trial, active, gracePeriod, expired) | Mirrored from StoreKit |
| trialStartedAt | RealmInstant | First app launch |
| trialEndedAt | RealmInstant? | Set at day 30 |
| gracePeriodEndedAt | RealmInstant? | Set at day 44 (trial + 14 days) |

---

### `SubscriptionPeriod`
| Field | Type | Notes |
|---|---|---|
| id | String (ObjectId) | |
| startedAt | RealmInstant | Subscription activated |
| endedAt | RealmInstant? | Lapsed (null = currently active) |
| plan | String (enum: monthly, annual, trial) | |

> Trips are viewable/exportable only if their `startedAt` falls within a `SubscriptionPeriod` interval.

---

### `Vehicle`
| Field | Type | Notes |
|---|---|---|
| id | String (ObjectId) | |
| name | String | e.g. "My Ute" |
| registration | String | Shown on PDF |
| type | String (enum: car, truck, motorcycle) | |
| fuelType | String (enum: petrol, diesel, EV, hybrid, PHEV) | |
| isDefault | Boolean | |
| isArchived | Boolean | Soft delete |

---

### `Trip`
| Field | Type | Notes |
|---|---|---|
| id | String (ObjectId) | |
| vehicleId | String | FK → Vehicle |
| startAddress | String | Reverse-geocoded or entered |
| endAddress | String | |
| startLat / startLng | Double | |
| endLat / endLng | Double | |
| startedAt | RealmInstant | |
| endedAt | RealmInstant? | |
| distanceKm | Double | Calculated from TripPoints or entered |
| category | String (enum: business, personal, uncategorised) | |
| source | String (enum: automatic, manual) | |
| notes | String? | |
| dollarValue | Double? | Calculated from rate × distance |
| isCapExceeded | Boolean | ATO cap — dollar value set to $0 |
| isSyncedToCloud | Boolean | CloudKit sync flag |
| createdAt | RealmInstant | |
| updatedAt | RealmInstant | |

---

### `TripPoint`
| Field | Type | Notes |
|---|---|---|
| id | String (ObjectId) | |
| tripId | String | FK → Trip |
| latitude | Double | |
| longitude | Double | |
| altitude | Double? | |
| speed | Double? | m/s |
| accuracy | Double | |
| recordedAt | RealmInstant | |

---

### `OdometerReading`
| Field | Type | Notes |
|---|---|---|
| id | String (ObjectId) | |
| vehicleId | String | FK → Vehicle |
| readingKm | Double | Odometer value in km |
| recordedAt | RealmInstant | |
| tripId | String? | Optional link to a specific trip |
| notes | String? | |

---

### `Address`
| Field | Type | Notes |
|---|---|---|
| id | String (ObjectId) | |
| label | String | e.g. "Home", "Office" |
| fullAddress | String | |
| latitude | Double | |
| longitude | Double | |
| usageCount | Int | For frequency-based suggestions |

---

### `RateTable`
| Field | Type | Notes |
|---|---|---|
| id | String (ObjectId) | |
| jurisdiction | String (enum: NZ, AU) | |
| financialYear | String | e.g. "2024-25" |
| vehicleType | String | |
| fuelType | String | |
| ratePerKm | Double | Cents per km |
| effectiveFrom | String (ISO date) | |

---

## 6. Realm Kotlin SDK — Persistence Layer

### Why Realm over SQLDelight
| Concern | Realm Kotlin SDK | SQLDelight |
|---|---|---|
| KMP support | ✅ Official iOS + Android | ✅ |
| API style | Object-oriented (`RealmObject`) | SQL schema + generated Kotlin |
| Reactive queries | ✅ Native `Flow` support | Manual |
| Relationships | ✅ Native (RealmList, backlinks) | Manual FK joins |
| Migration tooling | ✅ Built-in schema migration API | Manual |
| Binary size | Slightly larger | Lightweight |
| Atlas Device Sync | Available but not used (see below) | N/A |

**Verdict:** Realm Kotlin SDK is the better fit. The object-oriented model maps directly to domain entities, reactive queries simplify UI state management, and the official KMP support means the same schema compiles for both iOS and Android.

### Setup
- Dependency: `io.realm.kotlin:library-base` (KMP, local-only variant — no sync module).
- Realm database initialised in `:shared:data` via a `RealmConfiguration` with a platform-specific file path via `expect/actual`.
- **Atlas Device Sync is explicitly not used.** Realm is local-only. iCloud (CloudKit) is the sync layer for iOS, preserving the privacy-first, no-account model.

### Schema Definition (example)
```kotlin
// :shared:domain
class Trip : RealmObject {
    @PrimaryKey var id: String = ObjectId().toHexString()
    var vehicleId: String = ""
    var startAddress: String = ""
    var endAddress: String = ""
    var startedAt: RealmInstant = RealmInstant.now()
    var endedAt: RealmInstant? = null
    var distanceKm: Double = 0.0
    var category: String = "uncategorised"
    var source: String = "automatic"
    var notes: String? = null
    var dollarValue: Double? = null
    var isCapExceeded: Boolean = false
    var isSyncedToCloud: Boolean = false
    var createdAt: RealmInstant = RealmInstant.now()
    var updatedAt: RealmInstant = RealmInstant.now()
}
```

### Migrations
- Schema changes increment the `schemaVersion` in `RealmConfiguration`.
- Migration callbacks written in KMP shared code — applied equally on iOS and Android.

### Reactive UI Integration
- **iOS:** Realm `Flow` bridged to Swift `AsyncStream` via Kotlin/Swift concurrency interop; consumed in SwiftUI `@Observable` view models.
- **Android:** Realm `Flow` consumed directly in Jetpack Compose via `collectAsState`.

### Realm + iCloud (CloudKit) — iOS Interplay

There is **no official Realm ↔ CloudKit integration**. Realm acts as the local source of truth; a hand-rolled iOS sync layer maps Realm objects to CloudKit records:

```
Realm (local, KMP)  ←→  iOS SyncManager (Swift, native)  ←→  CloudKit (user's private iCloud)
```

**How it works:**
1. All writes go to Realm first — instant, offline-safe.
2. Realm change notifications enqueue changed object IDs into the `SyncQueue` Realm object.
3. iOS `SyncManager` (Swift, native) drains the queue on connectivity, mapping each Realm object to a `CKRecord` and calling `CKDatabase.modifyRecords`.
4. On first launch or a new device, `SyncManager` performs a full CloudKit fetch and writes records into Realm.
5. Conflicts resolved by `updatedAt` timestamp (last-write-wins for MVP).

This is a well-established pattern. The engineering cost is the sync layer itself — estimated ~1 week of focused work in Phase 3.

**What syncs to CloudKit:**
| Entity | Synced | Reason |
|---|---|---|
| `Trip` | ✅ | Core user data |
| `OdometerReading` | ✅ | Required for logbook reports |
| `Vehicle` | ✅ | Referenced by trips |
| `Address` | ✅ | Saved locations |
| `SubscriptionPeriod` | ✅ | Required for gating on a second device |
| `UserProfile` | ✅ | Jurisdiction, claim method |
| `TripPoint` | ❌ | Too many records; not needed post-processing |
| `RateTable` | ❌ | Bundled in app — not user data |
| `SyncQueue` | ❌ | Local processing queue only |

---

## 7. Subscription & Monetisation

### Pricing
| Plan | Price | Notes |
|---|---|---|
| Monthly | AUD/NZD $6.99/month | |
| Annual | AUD/NZD ~$50–55/year | ~35% saving |
| Free Trial | 30 days | Full access from first launch |

### Subscription Access Model

**Tracking always continues** regardless of subscription status — the app never stops recording trips.

Access to **view, categorise, and export** trips is gated by subscription period:

| State | Tracking | View/Categorise Trips | Export Reports |
|---|---|---|---|
| Trial (days 1–30) | ✅ | ✅ All trips | ✅ |
| Grace period (days 31–44) | ✅ | ✅ All trips | ✅ |
| Expired (day 45+) | ✅ | ⛔ Paywall | ⛔ Paywall |
| Active subscriber | ✅ | ✅ Trips in subscription window | ✅ Trips in subscription window |

**Key design decision — period-gating prevents abuse:**
Reports only cover trips that occurred during an active `SubscriptionPeriod`. A user who tracks all year and pays for a single month can only export that month's trips — not the whole year. This removes the incentive to track for free all year and pay one month at tax time.

### Grace Period
After the 30-day trial ends, a **14-day grace period** gives the user time to review, categorise, and subscribe before the view gate activates. A local notification is sent at trial end and again 3 days before the grace period expires.

### StoreKit 2 Integration (iOS)
- Product IDs: `com.mileagetracker.monthly`, `com.mileagetracker.annual`.
- `Product.purchase()` async API.
- `Transaction.updates` async sequence for renewal/cancellation/expiry.
- On each transaction event, write a `SubscriptionPeriod` Realm object.
- `SubscriptionGate` use case in KMP: given a `Trip.startedAt`, returns whether that trip is accessible.

---

## 8. Offline & Sync Strategy — iOS

### Local-First with Realm
- All entities stored in on-device Realm database (shared KMP).
- `TripPoint` objects written immediately during recording; rolled up into a `Trip` object on trip end.
- No data loss if offline — GPS points buffer in Realm until trip completes.
- Realm's reactive queries ensure the UI reflects current local state instantly.

### iCloud Sync — CloudKit
- `Trip`, `Vehicle`, `Address`, `OdometerReading`, `SubscriptionPeriod`, and `UserProfile` synced to the user's **private** CloudKit database.
- Raw `TripPoint` objects are **not** synced (record volume; only the processed `Trip` row is needed).
- `CKRecord` mapping layer in iOS native Swift (maps Realm objects ↔ `CKRecord`).
- Sync triggered: on app foreground, on trip categorisation, on report export.
- Conflict resolution: `updatedAt` wins (last-write-wins for MVP).
- Sync status tracked via `isSyncedToCloud` flag; failed syncs queued in `SyncQueue`.

### Sync Queue
- `SyncQueue` Realm object: `entityType`, `entityId`, `operation` (upsert/delete), `attemptCount`, `lastAttemptAt`.
- iOS `SyncManager` (native Swift) drains the queue when connectivity is available.
- Exponential backoff for failed attempts.

---

## 9. Cloud Sync — Android & The Gap

### Android Has No iCloud Equivalent

Android has **no built-in, free, private cloud database** equivalent to CloudKit. Options assessed:

| Android Option | Verdict |
|---|---|
| **Google Drive App Data folder** | File-based, not a database. Not viable for relational trip data at scale. |
| **Android Auto Backup** | Restores app data on reinstall only — not real-time sync, not queryable. |
| **Firebase Firestore** | Proper cloud database with offline-first + real-time sync. Breaks the privacy-first / no-central-server model unless used opt-in. |
| **Supabase** | Open-source Postgres-based alternative. Same concern — requires a central server. |
| **Realm Atlas Device Sync** | MongoDB's cloud sync on top of Realm. Requires a MongoDB Atlas account and central server. Same concern. |

### Decision for Android v1

Android v1 launches as **local Realm only** — full trip tracking and all app features work, just no cross-device sync. This is acceptable for the majority of sole traders who use a single phone.

Cloud sync for Android is a post-v1 decision. Options at that point:

1. **Firebase Firestore (opt-in)** — most likely path. Firebase is already the preferred choice for analytics/crash reporting, so the SDK is already present. Data can be scoped to the user's Google account region. Using it as an opt-in sync layer is a reasonable privacy compromise.
2. **Self-hosted Supabase** — maximum privacy control, but adds operational overhead.
3. **Local-only permanently** — valid if user research shows Android users don't need cross-device sync.

### KMP Sync Architecture Is Backend-Agnostic

The `SyncQueue` and sync logic in `:shared:sync` contain no iOS or CloudKit assumptions. The iOS `SyncManager` is a native-layer implementation detail. A future Android `SyncManager` can target any backend (Firebase, Supabase, etc.) without touching shared KMP code.

---

## 10. Jurisdiction & Compliance

### Rate Handling

| Jurisdiction | Authority | Rate Basis | Cap | Financial Year |
|---|---|---|---|---|
| New Zealand | IRD | Tier 1 / Tier 2 per km by vehicle type | None | 1 April – 31 March |
| Australia | ATO | Cents per km (single rate, all vehicles) | 5,000 km/vehicle/FY | 1 July – 30 June |

### ATO Cap Logic (`:shared:calculations`)
- `ATOCapEnforcer`: tracks cumulative business km per vehicle per ATO financial year.
- Warns user when approaching 5,000 km (notification at 4,500 km).
- Exported reports cap at 5,000 km and note the cap in the PDF.
- Trips beyond the cap are tracked but marked `isCapExceeded = true`; dollar value set to $0.

### IRD Tier Logic
- IRD uses a two-tier rate: Tier 1 (first ~14,000 km/year), Tier 2 (beyond that) — rates vary by vehicle type.
- `IRDRateCalculator` applies tier breakpoints from `RateTable`.

### Rate Table Updates
- Rates bundled as JSON in KMP for offline use.
- On app launch (with connectivity), check a remote versioned config endpoint for updated rates.
- Updated rates stored in Realm `RateTable` objects.

### Fuel/Energy Types by Jurisdiction
- **ATO:** petrol, diesel, EV, hybrid (single rate currently; tracked for future changes).
- **IRD:** petrol/diesel, EV, plug-in hybrid — each has its own rate tier.

---

## 11. Testing Strategy

### Unit Tests
| Layer | Tool | Coverage Target |
|---|---|---|
| KMP calculations | kotlin.test | Rate calc, ATO cap, Haversine, IRD tiers, logbook % |
| KMP use cases | kotlin.test + MockK | Trip creation, categorisation, subscription gating |
| KMP data / Realm | kotlin.test + in-memory Realm config | Repository CRUD |
| iOS ViewModels | XCTest | SwiftUI observable state |

### Integration Tests
| Layer | Tool | What |
|---|---|---|
| KMP + Realm | kotlin.test + in-memory Realm config | Full use-case → DB round trip |
| iOS + KMP | XCTest | iOS native calls KMP use cases |
| Subscription gating | XCTest + StoreKit testing | Period-gating logic across trial/active/expired states |
| CloudKit sync | XCTest + CloudKit sandbox | Record push/pull |

### UI Tests (iOS)
- XCUITest for critical journeys: onboarding (all three claim methods), manual trip entry, categorisation swipe, subscription paywall, PDF export.
- Snapshot tests (`swift-snapshot-testing`) for PDF output consistency.

### Trip Detection Testing
- Simulated GPS routes via `.gpx` files fed to `CLLocationManager` in Simulator.
- Manual test matrix: short trips, tunnels, multi-stop journeys, phone-in-pocket walks.

---

## 12. Open Questions & Risks

| # | Question / Risk | Impact | Recommendation |
|---|---|---|---|
| 1 | **Background location battery drain** — always-on GPS is the top battery risk. | High | Use significant location change as primary wake; activate full GPS only on confirmed automotive activity. Profile early in Phase 2. |
| 2 | **iOS background execution limits** — Apple may kill the app during long trips. | High | Use `BGTaskScheduler` + significant location change to re-wake. Test edge cases (1-hour drive, screen off). |
| 3 | **ATO rate: single rate for all vehicles** — fuel type matters for IRD but ATO currently uses one rate. | Medium | Track fuel type regardless; apply single ATO rate for now, ready for future changes. |
| 4 | **Logbook mode — odometer accuracy** — relies entirely on user entering correct readings. | Low | No validation possible; document in UI that accuracy is the user's responsibility. Consider prompting at trip start/end. |
| 5 | **Realm ↔ CloudKit sync layer** — hand-rolled, no official library. Schema changes require updating both Realm objects and CKRecord mappings. | Medium | Build a clean mapping abstraction from the start. Test thoroughly with CloudKit sandbox. Keep CKRecord field names stable post-release. Estimated ~1 week to build in Phase 3. |
| 6 | **Android cloud sync gap** — no free iCloud equivalent on Android. | Medium | Android v1 launches local-only. Decide on sync approach (Firebase Firestore most likely) post-iOS v1. KMP sync architecture is backend-agnostic. |
| 7 | **iCloud multi-device conflict** — two devices writing trips simultaneously could conflict. | Medium | `updatedAt` last-write-wins for MVP. If conflicts become an issue, evaluate operational transforms or server-side merge. |
| 8 | **App Store location permission approval** — Apple reviews always-on location use strictly. | High | Prepare a privacy justification for App Store review. GPS must activate only on confirmed automotive activity, not continuous polling. |
| 9 | **Subscription jurisdiction pricing** — AUD and NZD App Store tiers differ. | Low | Use App Store Connect pricing tiers; set both currencies explicitly. |
| 10 | **Period-gating UX complexity** — users may find "subscription window" concept confusing. | Medium | Clearly communicate in paywall UI: "Reports cover your active subscription period." Show a timeline if helpful. |
| 11 | **Analytics/crash reporting** | Low (deferred) | TBD — Firebase preferred (Crashlytics + Analytics free tier). Integrate in Phase 5 post-core build. |
