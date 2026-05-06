# Pre-Release Checklist — MileageTracker

Analysis of what needs to be done before App Store submission.

## 1. App Store Connect Setup

- [ ] Create App Store Connect app record (bundle ID: `com.harryjust.MileageTrackeriOS`)
- [ ] Configure App Privacy labels (location, motion, Bluetooth — all used for core functionality)
- [ ] Upload privacy policy URL (required for Always Allow location)
- [ ] Set age rating (location + motion data = likely 4+ with privacy disclosures)

## 2. Location Permission Justification

Apple rejects apps that request Always Allow location without clear justification. The app's
`Info.plist` must include:
- `NSLocationAlwaysAndWhenInUseUsageDescription` — explains background trip detection
- `NSLocationWhenInUseUsageDescription` — explains in-app location use
- `NSMotionUsageDescription` — explains motion sensor use for automotive detection

The current onboarding explains this well, but the plist strings must match the user-facing
descriptions and clearly state the benefit (automatic trip logging).

## 3. Required Assets

- [ ] App icon (1024×1024, all required sizes) — currently missing or placeholder
- [ ] Launch screen — currently default, should show a simple branded splash
- [ ] App Store screenshots (6.7" and 6.5" minimum) — home screen, trip detail, export
- [ ] App description + keywords (need to write for App Store)

## 4. Testing

- [ ] Test on physical device with real GPS (simulator GPS is deterministic, real GPS is not)
- [ ] Test background trip detection end-to-end (leave house, drive 5+ km, arrive)
- [ ] Test app relaunch after force-kill mid-trip (recovery checkpoint)
- [ ] Test onboarding flow from clean install
- [ ] Test all three claim methods produce correct dollar values
- [ ] Test CSV export opens correctly in Numbers/Excel
- [ ] Test with Low Power Mode enabled
- [ ] Test with Location set to "While Using" only

## 5. Legal & Compliance

- [ ] Privacy policy published and URL reachable
- [ ] Terms of service (if applicable)
- [ ] Disclaimer: app does not provide tax advice — already covered in MethodInfoView
- [ ] Data retention policy documented (personal trips deleted after 7 days)

## 6. Beta Testing (TestFlight)

- [ ] Internal testing: 2–3 devices, 5+ real-world drives
- [ ] External testing: small group of NZ-based users
- [ ] Collect feedback on detection accuracy, battery impact, onboarding clarity

## 7. Technical Debt

- [ ] Remove unused files: `DistanceUnitStep.swift`, `LocationPermissionStep.swift`, `MotionPermissionStep.swift` (superseded by merged steps)
- [ ] Add `NSAppTransportSecurity` exception if any non-HTTPS endpoints exist
- [ ] Verify minimum deployment target (currently iOS 18+ implied by `@Observable` usage)
- [ ] Add crash reporting (optional but recommended for v1)

## 8. Known Pre-Release Risks

1. **CLVisit latency** (5–30 min) means cold-start trip detection is delayed for users without geofence coverage. The app's description should set expectations.
2. **BT identifier stability** on iOS 18 is unverified — documented risk in the design spec.
3. **Low-Power Mode** may reduce GPS sample rate, causing fragmented polylines.
4. **Motion permission denial** degrades detection quality — this is communicated in onboarding but not surfaced later.
