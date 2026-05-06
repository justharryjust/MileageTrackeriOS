# Future Work — Nice-to-Have & Fast Follows

Features and improvements that would meaningfully enhance the app but are not blocking
the core trip-detection + reporting functionality.

## Fast Follows (next 1–3 releases)

### 1. iCloud Sync
Current state: realm file is local-only. Users expect data to survive phone upgrades.
- Sync trips, vehicles, and odometer readings via iCloud
- Handle merge conflicts (rare with single-device usage)

### 2. Trip Auto-Classification
Use machine learning or rule-based heuristics to auto-categorise trips:
- Home → office during weekday mornings = business
- Office → home during weekday evenings = business
- Supermarket → home on Saturday = personal
- User can override; model learns from corrections

### 3. Push Notification Reminders
- "Time for your weekly odometer reading" (logbook users)
- "You drove 340 km this week — 280 km business"
- "Don't forget to categorise 3 uncategorised trips"

### 4. Widget
- Home screen widget showing: trips this week, km driven, $ claimed
- Lock screen widget: current trip duration/distance (when active)

### 5. Trip Editing
- Drag the start/end pin on the map to correct GPS drift
- Merge adjacent trips
- Split a trip at a waypoint
- Add notes and photos (receipt capture) to trips

### 6. Export Format Expansion
- PDF report with branded header, summary page, trip table, map thumbnails
- Direct email to accountant with pre-filled template
- Integration with accounting software (Xero, MYOB, QuickBooks) via CSV import format matching

## Medium Term

### 7. Apple Watch Companion
- Start/stop manual trip recording
- View current trip distance, duration, dollar value
- Complication showing weekly km total

### 8. CarPlay Dashboard
- "Recording trip" indicator on CarPlay home screen
- Quick-categorise last trip as business/personal
- Trip summary displayed at end of drive

### 9. Fleet / Multi-Vehicle Improvements
- Per-vehicle statistics (fuel economy, maintenance reminders based on km)
- Vehicle-specific logbook periods
- Switching default vehicle from the home screen

### 10. Localisation
- Māori (mi_NZ) — NZ government app standard
- French, German, Spanish for broader distribution
- RTL language support audit

### 11. Route Optimisation
- "Estimate trip cost" — enter a destination, see distance + dollar estimate before driving
- Compare actual route vs optimal route (identify inefficient routing)

### 12. Tax-Year Dashboard
- Visual progress bar toward annual kilometre caps (AU: 5,000 km)
- "You're at 4,200 of 5,000 km — 800 km remaining this tax year"
- Projection: "At your current rate, you'll hit the cap on August 15"

## Long Term / Speculative

### 13. Receipt & Expense Capture
- Photograph fuel receipts, maintenance invoices
- OCR to extract amounts, dates, odometer readings
- Link expenses to trips for per-km cost calculation

### 14. Fleet Manager Portal
- Web dashboard for fleet managers to view all drivers
- Approve/reject trip classifications
- Generate consolidated fleet mileage reports

### 15. Public Transport Integration
- Detect bus/train trips via CMMotionActivity + route matching
- Suggestion: "This looks like a train commute — mark as non-car travel?"
- Door-to-door journey tracking (walk → train → walk)

### 16. Carbon Tracking
- Estimate CO₂ per trip based on vehicle fuel type and distance
- Annual emissions summary
- "You saved X kg CO₂ by taking the train on Tuesday"
