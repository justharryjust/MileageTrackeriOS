# Main/Trips/

Four files: `TripsView.swift`, `TripView.swift` (`TripDetailView`), `AddressSearchScreen.swift`, `ManualTripSheet.swift`.

---

## TripsView

Filterable trip list with horizontal filter pills.

| Filter | Source |
|--------|--------|
| All | `tripRepo.allTrips` |
| Needs Review | `tripRepo.uncategorisedTrips` (badge shows count) |
| Business | `tripRepo.businessTrips` |
| Personal | `tripRepo.allTrips.filter { .personal }` |

**Gestures:**
- Swipe right → `categorise(trip, as: .business)` (green)
- Swipe left → `categorise(trip, as: .personal)` (blue)
- Delete → `deleteTrip(_:)` (removes trip + TripPoints)

Toolbar `+` button presents `ManualTripSheet` as a sheet.

---

## TripDetailView

Full-screen `Map` with a floating `TripInfoCard` at the bottom.

**Map modes** (toggled from the `...` menu):
- **Actual path** (default): teal `MapPolyline` drawn from `tripRepo.tripPoints(for: trip)`.
- **Road route**: `MKDirections` automobile route fetched lazily on first toggle; cached in `@State var route`.

**Annotations:** green start pin (`location.fill`) + red end pin (`flag.checkered`). End pin hidden when `startLat == endLat && startLng == endLng`.

**More menu** (ellipsis icon, top-right):
- Mark as Business / Mark as Personal
- Divider
- Show Road Route / Show Actual Path (toggle)
- Divider
- Delete Trip (destructive, calls `deleteTrip(_:)` then `dismiss()`)

**TripInfoCard:** route addresses, distance, duration, date, category (colour-coded).

---

## AddressSearchScreen

Full-screen search overlay presented modally.

- `AddressSearcher.query` bound to `TextField`; completions update reactively.
- Results rendered in a `List` with `highlightedText(_:ranges:)` — bolds `MKLocalSearchCompletion.titleHighlightRanges` and `subtitleHighlightRanges`.
- Selecting a row calls `onSelect(completion)` then `dismiss()`.
- Auto-focuses the text field on `onAppear`.

---

## ManualTripSheet

Form for logging a trip without GPS.

**Form sections:**
1. **Route** — `AddressField` tapping start/end opens `AddressSearchScreen` sheet; once both are resolved, `MKDirections` calculates driving distance.
2. **Details** — date picker, departed/arrived time pickers (end kept ≥ start + 1 min), category segmented control, optional notes.
3. **Save button** — disabled until both addresses resolved and distance calculated.

**Save flow:** combines `tripDate` + `startTime`/`endTime` into full `Date` values, calls `tripRepo.saveManualTrip(...)`, then dismisses.

Distance display: metres below 1 km, otherwise `"X.X km"`.
