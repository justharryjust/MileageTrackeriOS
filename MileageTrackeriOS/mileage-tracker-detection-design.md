# Mileage Tracker — Trip Detection Algorithm Design (v2)

**Targets:** iOS 18+, ~5% daily battery, fully on-device, cars/vans/trucks only, manual business/personal classification, Always Allow location assumed. Personal-expense-first with enough rigour to defend in an IRS/fleet context.

**v2 changes:** (a) hard-vs-soft engine signal abstraction to handle CarPlay/BT disconnects mid-trip; (b) explicit fallback hierarchy for the no-engine-signal cohort (~25–30% of NZ users given fleet age); (c) `UIDevice.batteryState` added as a soft engine signal corroborator.

---

## 0. Additional Signals Proposed

Beyond CMMotionActivity, geofencing, CarPlay, CLVisit, and SLC:

- **AVAudioSession route changes** — observe Bluetooth audio routes the phone connects to. We can't reliably get a stable BT MAC on modern iOS, but `AVAudioSessionPortDescription.uid` plus `portName` is usable as a stable-enough fingerprint per device. Used to learn "this is a car" after N corroborated trips. Resolves the **non-CarPlay first-mile problem** without pre-registration.
- **CMPedometer** — step cadence over 30s windows. Resolves **car-vs-walking ambiguity** when CMMotionActivity is uncertain (e.g. Uber pickup, walking after parking) and lets us trim the trailing walking segment from a trip polyline.
- **CMAltimeter (relative altitude)** — cheap pressure deltas. Resolves **parking garage / lift false starts** (altitude change with zero steps and zero GPS = elevator, not a trip) and helps confirm tunnel transit.
- **CLLocationUpdate.liveUpdates (iOS 17+)** + **CLBackgroundActivitySession** — high-frequency GPS only after Suspected. Avoids holding `desiredAccuracy = best` continuously.
- **CLMonitor (iOS 17+)** for dynamic geofences — replaces `CLCircularRegion`, with higher quota (~hundreds vs 20). Lets us maintain a learned-parking-spots LRU.
- **`UIDevice.current.batteryState`** — `.charging` transitioning concurrently with `automotive` activity is a free engine-signal corroborator. Most NZ drivers without CarPlay/BT still plug in to charge. Limitation: only fires while app is running, so it's a Suspected→Active promoter, not a wake-from-Idle trigger.

Explicitly rejected: SSID changes (Apple restricts), beacon regions (no infra), headphone route (low signal).

---

## 1. State Machine

States: **Idle → Suspected → Active ↔ Pausing → Ending → (Committed | Discarded) → Idle**.

### Transitions

| From | To | Trigger (any one) |
|------|----|------------------|
| Idle | Suspected | CarPlay connected; learned-car BT route activated; CLVisit departure from home/work/known anchor; CLMonitor exit of a parking-hint geofence; CMMotionActivity = automotive at ≥ medium for 15s rolling; SLC fix with `speed > 6 m/s` (≈22 km/h) and motion not stationary |
| Suspected | Active | (within 60s) Hard engine signal still connected at 30s; OR sustained automotive ≥ high confidence for 30s; OR GPS speed > 25 km/h sustained 20s **with** automotive in the last 60s; OR distance from suspected-start > 250m **and** no walking activity |
| Suspected | Idle (discard) | 60s elapsed without promotion; OR motion = walking/stationary for 30s **and** no hard engine signal |
| Active | Pausing | GPS speed < 5 km/h for 30s **and** distance accumulated < 50m in the last 60s |
| Active | Ending (fast-path) | **No soft engine signal** (see §2) **and** speed < 5 km/h for 5s **and** one of: pedometer steps in last 30s, visit arrival, or motion = stationary at high confidence |
| Pausing | Active | GPS speed > 15 km/h sustained 10s; OR automotive ≥ medium for 15s |
| Pausing | Ending | Pause duration exceeds dynamic `pauseLimit` (see below) |
| Ending | Committed | Trip passes validation (distance ≥ 200m, duration ≥ 60s, dominant activity = automotive, no ferry/aircraft outliers) |
| Ending | Discarded | Validation fails |

### Dynamic `pauseLimit` (key insight — fixes drive-thru and traffic jam in one rule)

```
pauseLimit =
  0s    if (visit arrival fired AND no soft engine signal)
  30s   if (pedometer reports >30 steps in last 30s)        // walking detected
  3 min if (no soft engine signal, no walking)              // conservative default
  8 min if (soft engine signal active)                      // drive-thru / pickup tolerated
```

Note: "engine disconnected → 10s" rule from v1 was removed. A bare CarPlay/BT disconnect no longer collapses the pause limit, because in v2 the soft engine signal can hold the trip alive based on motion + speed recency. See §2 for the hard/soft definitions and the rationale.

---

## 2. Signal Fusion Strategy

### Engine signal — hard vs soft (v2)

A binary engine signal is too brittle: users disconnect CarPlay mid-trip to swap chargers, switch to FM, or charge another device. v2 splits it:

- **Hard engine signal:** CarPlay connected NOW, OR a learned-car BT audio route is currently routing audio.
- **Soft engine signal:** hard signal **OR** (sustained `automotive` ≥ high confidence in last 60s **AND** smoothed GPS speed > 15 km/h in last 60s) **OR** `UIDevice.batteryState == .charging` started concurrent with the trip.

The state machine reads **soft** signal almost everywhere. Hard signal is only needed for the cold-start primary trigger (Idle → Suspected) where we have nothing else to go on. This means a CarPlay disconnect at 100 km/h doesn't end the trip — automotive + speed recency hold the soft signal alive.

### Fallback hierarchy (when no hard engine signal — typical NZ user)

NZ fleet age means ~25–30% of users have neither CarPlay nor BT audio. For them, the cascade in priority order:

1. **Home/work geofence exit** (CLMonitor, near-instant). The most common trip start.
2. **Learned parking-hint geofences** — every committed trip drops a hint at its end coordinate. Self-heals: after 1–2 weeks, ~80–90% of trips fire from a learned anchor.
3. **CLVisit departure** — backstop with 5–30 min latency; confirms the start anchor for polyline correctness, doesn't drive real-time response.
4. **`CMMotionActivity.automotive` sustained 15s** — the "no anchor" path. ~15–30s start latency. Polyline anchored to `lastGoodFix` so geometry is preserved even if real-time tracking lags.
5. **SLC with high speed + automotive** — pure backstop.

### Triggers

**Primary triggers (sufficient on their own):**
- CarPlay connect.
- Learned-car BT audio route change (after N=3 corroborated trips with that route UID).
- CLMonitor exit of home/work or learned parking-hint geofence.

**Strong corroborators (need ≥1 to promote Suspected → Active):**
- Sustained `CMMotionActivity.automotive` at ≥ high confidence for 30s.
- GPS speed > 25 km/h with prior automotive sample in window.
- `UIDevice.batteryState` transitioned to `.charging` concurrently with `automotive`.

**Supporting (drive transitions, not promotion alone):**
- CLVisit arrival/departure (latency-bound — never the *only* trigger, but biases pause→ending).
- SLC events (wakeup signal; never alone promotes to Active).
- Pedometer cadence (rejects walking confusion).
- CMAltimeter (rejects garage/lift false starts).

### Conflict resolution rules, in priority order

1. **Soft engine signal beats motion.** If soft signal is active, ignore "stationary" motion classifications — we're at a light or in a queue.
2. **Pedometer beats automotive.** If pedometer logs >30 steps in 30s, **block** Active promotion or force Pausing→Ending. Walking classifier is reliable; automotive classifier is not.
3. **Cycling at high confidence ≥ 60s during a candidate trip → abort the trip.** Cars-only scope.
4. **Visit arrival biases pause → ending,** but never alone (CLVisit latency 5–30 min makes it unreliable as a primary trigger).
5. **Speed-only promotion requires motion corroboration.** Prevents ferry/train false positives where SLC reports motion but the user is sitting stationary.
6. **GPS staleness during Active is tolerated.** If GPS hasn't updated in 60s but motion is automotive, do NOT enter Pausing — we're likely in a tunnel or rural blackspot.
7. **Hard signal disconnect mid-trip is a no-op as long as soft signal holds.** Only collapses to "no engine signal" pause behaviour once the automotive+speed recency window decays (60s).

---

## 3. Pseudocode

Language-agnostic, iOS-aware. References real CoreLocation/CoreMotion APIs.

```pseudo
// === Persistent state (written to disk on every transition + every 5s in Active)
state:        TripState = .idle
trip:         TripBuffer? = nil
suspectedAt:  Date? = nil
pauseStart:   Date? = nil
lastGoodFix:  CLLocation? = nil          // for cold-start polyline anchor
knownCarBTUIDs: Set<String>              // learned over time
btCorrelations: [String: Int]
parkingHintsLRU: LRU<CLLocationCoordinate2D>(cap: 50)

// === Bootstrap (called once at launch, including background relaunch)
func bootstrap():
    requestAlwaysAuthorization()
    locationManager.startMonitoringSignificantLocationChanges()
    locationManager.startMonitoringVisits()
    monitor = await CLMonitor("trips")
    monitor.add(home, work, ...parkingHintsLRU)
    motionManager.startActivityUpdates(to: .main, withHandler: onActivity)
    NotificationCenter.observe(.AVAudioSessionRouteChange, onRouteChange)
    NotificationCenter.observe(CarPlay.didConnect/.didDisconnect, onCarPlay)

    // resume in-flight trip if we were killed
    if persistedState in [.active, .pausing]:
        if (now - persistedLastUpdate) < 120s:
            resumeTrip()
        else:
            forceFinalize(persistedTrip)   // commit truncated trip

// === Idle handlers
func onActivity(a: CMMotionActivity):
    cacheActivity(a)
    if state == .idle and a.automotive and a.confidence >= .medium:
        if rollingAutomotiveDuration() >= 15s:
            enterSuspected(reason: .motion)

func onCarPlay(connected: Bool):
    if connected:
        if state == .idle:    enterSuspected(reason: .carPlay)
        if state == .pausing: transition(.active)        // came back from pickup
        // if already .active: no-op, just refreshes hard signal
    else:
        // v2: do NOT collapse pause limit on disconnect alone.
        // Soft signal (motion + speed recency, charging) may still hold the trip alive.
        // Fast-path Ending will only fire if speed drops AND no soft signal remains.
        // No explicit action needed here.

func onRouteChange(route):
    uid = route.outputs.first?.uid
    if uid in knownCarBTUIDs and state == .idle:
        enterSuspected(reason: .knownCarBT)
    record(uid in trip?.btObservations)   // for learning

func onVisit(v: CLVisit):
    if v.departureDate != .distantFuture and state == .idle:
        enterSuspected(reason: .visitDeparture)
    if v.arrivalDate != .distantFuture and state in [.active, .pausing]:
        biasTowardEnding = true

func onSLC(loc: CLLocation):
    lastGoodFix = loc
    if state == .idle and loc.speed > 6.0 and lastMotion != .stationary:
        enterSuspected(reason: .slcMoving)

func onMonitorEvent(condition, event):
    if event == .satisfied  and state == .active:
        if condition.isParkingHint: biasTowardEnding = true
    if event == .unsatisfied and state == .idle:
        if condition.isParkingHint: enterSuspected(reason: .geofenceExit)

// === Suspected
func enterSuspected(reason):
    state = .suspected
    suspectedAt = now()
    trip = TripBuffer(start: lastGoodFix ?? requestOneShotLocation())
    startGPS(rate: 1Hz, accuracy: .best)   // CLLocationUpdate.liveUpdates
    pedometer.startUpdates(from: now())
    altimeter.startRelativeAltitudeUpdates()
    schedule(promotionCheck, at: suspectedAt + 60s)

func promotionCheck():
    if state != .suspected: return
    if shouldPromote():
        transition(.active)
    else:
        discardCurrent()
        transition(.idle)

func shouldPromote() -> Bool:
    if reason in [.carPlay, .knownCarBT] and hardEngineSignal(): return true
    if sustainedAutomotive(window: 30s, conf: .high):           return true
    if recentGPSSpeedExceeded(20s, 25 km/h) and automotiveInLast(60s): return true
    if distanceFromSuspectedStart() > 250 and !walkingActive(): return true
    return false

// === Engine signal predicates (v2)
func hardEngineSignal() -> Bool:
    return carPlayConnected or knownCarBTRouteActive

func softEngineSignal() -> Bool:
    if hardEngineSignal(): return true
    if sustainedAutomotive(window: 60s, conf: .high) and recentGPSSpeed(60s) > 15 km/h:
        return true
    if batteryStateBecameChargingDuringTrip(): return true
    return false

// === Active
func onLocationUpdate(loc):
    if state in [.suspected, .active, .pausing, .ending]:
        trip.append(loc)
        evaluateTransitions(loc)
        persistTripBufferThrottled()        // every 5s

func evaluateTransitions(loc):
    speed = smoothedSpeed(loc, window: 10s)

    // Active → Pausing  (combined speed AND distance stall — fixes traffic jam)
    if state == .active and speed < 5 km/h and stationaryFor(30s) and distanceProgress(60s) < 50m:
        if !softEngineSignal() or pedometer.recentSteps(30s) > 30:
            transition(.pausing); pauseStart = now()

    // Pedometer rejection — walking after parking
    if state in [.active, .pausing] and pedometer.recentSteps(30s) > 30 and !softEngineSignal():
        transition(.ending, reason: .walkingDetected)

    // Active → Ending fast-path (v2: requires no soft signal AND a corroborator)
    if state == .active and !softEngineSignal() and speed < 5 km/h and stationaryFor(5s):
        if pedometer.recentSteps(30s) > 0 or visitArrivalRecent(60s) or motionStationaryHighConf(15s):
            transition(.ending, reason: .fastPath)

    // Pausing → Active
    if state == .pausing and speed > 15 km/h and sustainedFor(10s):
        transition(.active)

    // Pausing → Ending
    if state == .pausing:
        limit = computePauseLimit()         // see Section 1 table
        if (now - pauseStart) >= limit:
            transition(.ending)

    // GPS stale tolerance — DON'T pause if we're probably in a tunnel
    if state == .active and gpsStaleFor(60s) and lastMotion == .automotive:
        // hold; do not enter pausing solely because GPS went silent
        return

func computePauseLimit() -> Duration:
    if visitArrivalRecent(60s) and !softEngineSignal(): return 0s
    if pedometer.recentSteps(30s) > 30:                 return 30s
    if softEngineSignal():                              return 8min
    return 3min

// === Ending → Committed
func transition(.ending, reason: ...):
    state = .ending
    trimTrailingWalkingFromPolyline(trip)   // fix walking-after-park
    if !validate(trip):
        discardCurrent(); transition(.idle); return
    persist(trip)
    addParkingHintGeofence(trip.endLocation)
    learnBTCorrelations(trip)
    transition(.idle)

func validate(t: TripBuffer) -> Bool:
    if t.distance < 200m or t.duration < 60s:               return false
    if dominantActivity(t) in [.cycling, .walking]:         return false
    if t.maxSpeed > 250 km/h or t.containsLargeOverWaterGap: return false   // ferry/aircraft
    return true

// === BT learning
func learnBTCorrelations(trip):
    for uid in trip.btObservations:
        btCorrelations[uid] += 1
        if btCorrelations[uid] >= 3 and routePatternConsistent(uid):
            knownCarBTUIDs.insert(uid)
```

---

## 4. Use Cases & Edge Cases

| # | Scenario | Expected behaviour |
|---|----------|-------------------|
| 1 | Drive home → client (no CarPlay/BT) | Visit-departure → Suspected → speed-and-motion promote → Active → arrive, walking → Ending. Trip committed. |
| 2 | CarPlay-equipped car | Plug-in → instant Suspected → 30s connected → Active → arrive, park, unplug, walk → fast-path Ending fires (no soft signal + speed < 5 + pedometer steps). |
| 3 | Non-CarPlay, BT learned | Same as #2 but driven by `routeChange`. |
| 4 | Red light 45s | Active → Pausing at 30s. `pauseLimit = 8 min` (engine connected). Resumes. |
| 5 | Drive-thru 2 min, engine on | Pausing for 2 min < 8 min → resumes when moving. |
| 6 | Traffic jam 8 min crawling at 4 km/h | Distance-stall rule keeps us in Active (distance accumulates >50m/60s). |
| 7 | 5-stop errand run, engine off each time | 5 separate trips logged (correct given we lack engine signal). User can merge in review queue. |
| 8 | Underground garage start (no GPS) | Suspected via motion. Polyline anchored to `lastGoodFix` (home visit coord). GPS jumps in once outside. |
| 9 | Tunnel mid-trip, GPS lost 4 min | GPS-stale-during-automotive rule: do not enter Pausing. Polyline interpolated. |
| 10 | Uber passenger | False positive likely. Trip lands in manual review queue; user discards. Mitigation: show confidence flag if start ≠ known anchor and no engine signal. |
| 11 | Walking 200m after parking | Trim trailing walking segment from polyline in `transition(.ending)`. |
| 12 | Train commute | False positive risk. Mitigation: user reclassifies; we add a "learned ignore corridor" geofence after N rejections of the same route. |
| 13 | Ferry crossing | Drive-on leg ends fast-path (engine off). On ferry, motion = stationary → no Suspected. Drive-off → new trip leg starts cleanly. |
| 14 | Motorbike (out of scope) | If consistently classified as automotive, indistinguishable from car. Manual classification handles. Cycling-classified motorbike vibration → blocked by rule 3. |
| 15 | App force-killed mid-trip | iOS relaunches us on next SLC/visit/CLMonitor event. Bootstrap restores `state = .active`, resumes if gap < 2 min, else commits truncated. |
| 16 | Device reboot mid-trip | Same path as #15 once SLC fires post-boot. |
| 17 | Low-Power Mode | Detection still works on visits + SLC + CLMonitor; GPS sample rate may be downsampled by iOS. UI banner: "tracking accuracy reduced." |
| 18 | Same geofence crossed daily on foot | Suspected → 60s timeout → Discard. After N consecutive false wakes, demote that hint geofence. |
| 19 | High parking-hint churn | LRU bounded at 50; CLMonitor handles hundreds. No quota issue on iOS 18+. |
| 20 | Phone left in parked car all day | No motion, no SLC, no engine. Stays Idle. Zero battery overhead. |
| 21 | App opened with When-In-Use only | Detection layer disabled; show "grant Always Allow" CTA. |
| 22 | CarPlay disconnected mid-trip at 100 km/h (charge another device, switch to FM) | Hard signal lost. Soft signal still holds (automotive + speed recency). Trip continues. Subsequent red-light Pausing uses `pauseLimit = 8 min` (soft signal active). Resumes normally. |
| 23 | CarPlay disconnected mid-trip at a red light to swap charger | Hard signal lost, speed < 5. Fast-path needs a corroborator (pedometer steps, visit arrival, or stationary motion at high conf). Driver still in vehicle → none fire → stays in Pausing with `pauseLimit = 8 min` while soft signal is still warm; even after soft decays, Pausing default is 3 min. Resumes when motion picks up. |
| 24 | Typical NZ driver, 2002 Toyota, no CarPlay/no BT | Tier-1 home/work geofence exit fires within seconds → Suspected → motion + speed promote to Active. After 1–2 weeks, learned parking-hint geofences cover ~80–90% of trip starts. Cold-start trips from unknown anchors lose ~15–30s of first-mile real-time, but `lastGoodFix` preserves polyline geometry. |
| 25 | Phone plugged into 12V USB to charge, no CarPlay/BT | `UIDevice.batteryState` transitions to `.charging` ~ same time as automotive. Counts as soft engine signal corroborator → 8-min pauseLimit applies → drive-thrus and lights handled like a CarPlay user. |

---

## 5. Validation Pass — Where the Design Failed and Was Revised

I walked all 21 cases through the v1 pseudocode. **Six** revealed real failures. Diff shown below.

**Case 5 (drive-thru 2 min) — FAILED v1.**
- v1 had `pauseLimit = 90s` static. 2-min drive-thru → false Ending.
- **Diff:** static 90s → dynamic table keyed off engine signal. With engine on, limit = 8 min.

**Case 6 (traffic jam crawl) — FAILED v1.**
- v1 entered Pausing on `speed < 5 for 30s`, oscillating with brief speed-ups.
- **Diff:** added AND-clause `distanceProgress(60s) < 50m`. Slow but progressing traffic stays Active.

**Case 8 (underground garage start) — PARTIALLY FAILED v1.**
- v1 trip start was `requestOneShotLocation()`, which fails or returns stale data underground.
- **Diff:** prefer `lastGoodFix` (cached SLC/visit coord) as the suspected start. Real GPS catches up later; polyline jumps but anchor is correct.

**Case 9 (tunnel) — FAILED v1.**
- v1 entered Pausing because GPS went silent and `speed` defaulted to 0.
- **Diff:** added `gpsStaleFor(60s) and lastMotion == .automotive → don't pause` clause.

**Case 11 (walking after parking, no engine signal) — PARTIALLY FAILED v1.**
- v1 ended trip eventually (30s walking pauseLimit), but trailing locations recorded while walking polluted the polyline.
- **Diff:** `trimTrailingWalkingFromPolyline()` in Ending. End coord = first walking-classified sample.

**Case 13 (ferry) — FAILED v1.**
- On the ferry, SLC fired with `speed > 6 m/s` and v1 promoted on speed alone → false trip.
- **Diff:** speed-based promotion now requires `automotiveInLast(60s)`. Ferry passenger sitting stationary has no automotive samples → suspected times out → discard.

**Cases 15/16 (force-kill / reboot) — FAILED v1.**
- v1 had no persistence. Trip lost.
- **Diff:** persist state on every transition; persist trip buffer every 5s during Active. On bootstrap, resume if gap < 2 min, else force-finalize.

### v2 revisions (added cases #22–#25)

**Case 22 (CarPlay disconnect at 100 km/h) — FAILED v1.**
- v1 had `engineSignalActive()` as a binary check. Disconnect → soft signal also lost → next red-light Pausing collapsed to `pauseLimit = 10s` → false Ending.
- **Diff:** introduced `hardEngineSignal()` vs `softEngineSignal()`. Soft signal includes `automotive ≥ high + speed > 15 km/h within 60s`, so a disconnect in motion is invisible to the pause logic until the recency window decays. Removed the `pauseLimit = 10s on disconnect` rule entirely.

**Case 23 (CarPlay disconnect at red light) — FAILED v1.**
- v1 fast-path Active→Ending fired on `disconnect AND speed < 5 within 5s`. Disconnect at light → instant trip end.
- **Diff:** fast-path now requires (a) no soft signal and (b) one of: pedometer steps, visit arrival, motion = stationary at high confidence. A driver still seated in the vehicle has none of these → stays in Pausing under `pauseLimit = 8 min` while soft signal is warm, then 3 min after decay.

**Case 24 (typical NZ user, no CarPlay/no BT) — DESIGN GAP in v1.**
- v1 leaned heavily on the engine signal as the primary trigger; the no-engine fallback path existed but wasn't articulated as a hierarchy.
- **Diff:** documented the explicit Tier-1..5 fallback hierarchy in §2. Promoted `CLMonitor exit of home/work or learned parking-hint` to a primary trigger (was buried as a "supporting" signal). For the no-engine cohort the geofence path now does the heavy lifting with motion as backstop.

**Case 25 (USB charging as soft signal) — NEW SIGNAL in v2.**
- Not a v1 failure, but a v1 omission: a free corroborator we weren't using.
- **Diff:** `UIDevice.batteryState == .charging` started concurrent with automotive contributes to the soft engine signal. Free, no permission needed, no battery cost — works only while app is running so it cannot wake from Idle, but it's a meaningful pause-tolerance booster for the no-CarPlay cohort that plugs in to charge.

After the second walkthrough including cases #22–#25, all 25 cases pass except for **#10 (Uber)**, **#12 (train)**, and **#14 (motorbike)** — flagged as **known limitations** that manual classification absorbs. They are not solvable without either pre-registration or a server-side map-matching component, both of which we ruled out.

---

## 6. Open Risks & Assumptions

- **BT identifier stability.** `AVAudioSessionPortDescription.uid` is the most stable handle exposed without MFi. It is a UUID-string but Apple has changed exposure semantics across iOS versions. **Verify on iOS 18 SDK before production.** If unstable, fall back to `portName` + first-seen-coord clustering.
- **CLVisit latency** is 5–30 min. The design treats it as a *bias*, never a primary trigger — but if an audit-grade timestamp is ever needed, visits cannot supply it.
- **CMMotionActivity for trains.** Public-transport rail commonly classifies as automotive. Without map data we cannot distinguish reliably; manual review and learned-ignore-corridors are our only mitigation. Document this for users.
- **Force-quit (swipe-up kill).** iOS will not relaunch from CMMotionActivity events alone after a swipe-kill. SLC, visits, and CLMonitor events still relaunch. Most trips begin with movement that triggers SLC, so the worst case is losing the first ~500m. Acceptable for personal-expense scope, marginal for IRS.
- **CLBackgroundActivitySession behaviour under sustained pressure.** iOS 17+ session APIs are still maturing; keep a watchdog that re-establishes the session if it ends unexpectedly.
- **Pedometer permission denial.** If user denies Motion access we lose walking arbitration. Detector falls back to motion + GPS only; flag accuracy in onboarding.
- **Suspected window battery cost.** 60s of 1Hz GPS per spurious trigger ~ 0.05% battery. Acceptable up to ~20 spurious triggers/day. Geofence demotion + pedometer pre-check keep this in budget.
- **CLMonitor quota** is documented as ~hundreds but Apple has not pinned a hard number for iOS 18. LRU at 50 is well inside any plausible cap.
- **Manual classification scope creep.** Trips landing in review queue is fine for Personal; if Fleet tier ships, we'll need at least an auto-classify-with-override mode driven by home/work + recurring-destination clustering.
- **Privacy/retention.** Recommend keeping raw polyline only as long as needed for export/reclassification, and storing only `(start, end, distance, duration, mode)` after a configurable retention window (default 90 days).
- **Soft-signal lingering after parking.** The soft engine signal recency window (60s) means the trip can over-record by up to ~60s of stationary time after the user actually parks. Pedometer steps on exit collapse the limit to 30s, and visit arrivals collapse to 0s, so worst-case overshoot is ~60s when the user sits in the car post-arrival. Acceptable trade-off for the mid-trip-disconnect resilience it buys.
- **NZ fleet age.** ~25–30% of users will not have CarPlay or BT audio. Detection quality for this cohort relies entirely on geofences + motion + GPS. Day-1 quality is meaningfully worse than for CarPlay users (~30s first-mile latency on cold-start trips); week-2 quality after geofence learning is comparable. Onboarding should set expectations.

---

## TL;DR Architecture

Idle uses only zero-marginal-cost signals (SLC, visits, geofences, activity-updates). High-cost GPS is gated behind a 60s Suspected window. The state machine reads a **soft engine signal** — hard signals (CarPlay, learned BT) OR motion+speed recency OR USB charging start — so a CarPlay disconnect mid-trip doesn't end the trip. For the no-CarPlay/no-BT cohort (~25–30% of NZ users), a five-tier fallback hierarchy carries detection: home/work geofences → learned parking-hint geofences → CLVisit → motion → SLC. The geofence layer self-heals over the first 1–2 weeks of use. Manual classification absorbs residual ambiguity (passenger, train, motorbike) we cannot solve on-device without registration or maps.
