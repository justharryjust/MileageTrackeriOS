# Debug Panel — Potential Extensions

The debug injection pattern works for any OS event that the app bridges through a callback property on a manager class. Call that callback directly from the debug panel — no swizzling, no test-only build flags needed.

## Already Implemented

| Event | Injected via |
|---|---|
| Automotive / Stationary / Walking / Cycling activity (low & high confidence) | `MotionManager.onActivityUpdate` |
| Location fix (configurable speed & accuracy) | `LocationManager.onLocationUpdate` |
| CLVisit departure | `LocationManager.onVisitDeparture` |
| Significant-location / background wake | `LocationManager.onBackgroundWake` |
| Force trip finalisation | `TripRecorder.finaliseTripAndReset` |

---

## Potential Future Extensions

### Bluetooth / Car Kit
Add a `BluetoothManager` that wraps `CoreBluetooth` or `ExternalAccessory`. Expose an `onCarKitConnected` / `onCarKitDisconnected` callback. Tapping the debug button fires those callbacks — useful for a future "start trip when car Bluetooth connects" heuristic.

### Low Power / Thermal State
`ProcessInfo` publishes `NSProcessInfoPowerStateDidChange` and `ProcessInfo.ThermalState`. Injecting a fake low-power or critical thermal state lets you test whether the app correctly backs off GPS accuracy and defers background work.

### App Lifecycle (Background / Foreground)
Post `UIApplication.didEnterBackgroundNotification` or `willEnterForegroundNotification` manually. Useful for verifying that `queryRecentActivity(since:)` is called on foreground and that timers survive suspension correctly.

### Push / Local Notifications
Construct a `UNNotificationContent` with a known payload and call your `UNUserNotificationCenterDelegate` handler directly. Lets you test notification-driven trip prompts (e.g. "You have an unreviewed trip") without scheduling real notifications.

### Network / Sync State
If a future cloud-sync layer is added, a `NetworkMonitor` with an `onConnectivityChange` callback lets the debug panel toggle online/offline to verify sync queuing and retry logic.

### Realm / Data Events
Write synthetic `Trip` or `TripPoint` objects directly to the in-memory Realm from a debug panel section. Useful for testing the Trips list UI with edge-case data (zero-distance trip, very long trip, many uncategorised trips) without driving.

### Heading / Course Change
Inject a `CLLocation` with a specific `course` value to test the future heading-change dampening heuristic (plan item 4) — simulates a car manoeuvring in a car park mid-end-window.

---

## Pattern Reference

```swift
// 1. On your manager, expose a callback instead of calling the handler directly:
var onSomeEvent: ((EventPayload) -> Void)?

// 2. In the real delegate / notification handler, fire it:
func realOSDelegateMethod(_ payload: EventPayload) {
    onSomeEvent?(payload)
}

// 3. In TripRecorderDebugView, inject synthetically:
DebugButton(label: "Simulate Some Event", icon: "…", color: .blue) {
    manager.onSomeEvent?(SyntheticPayload(…))
}
```
