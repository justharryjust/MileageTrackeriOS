# MileageTrackeriOS

Automatic mileage tracking for iOS. Records trips in the background using region monitoring and GPS, with configurable claim methods, jurisdiction-based rate calculation, and CSV export.

## Requirements

- Xcode 16+
- iOS 18+
- Swift 6
- [Realm Swift](https://github.com/realm/realm-swift) (SPM, resolved automatically)

## Dependencies

Realm is managed via Swift Package Manager and resolves automatically when you open the project. No additional setup needed.

## Build

### Simulator (primary development target)

```bash
xcodebuild -project MileageTrackeriOS.xcodeproj \
  -scheme MileageTrackeriOS \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

### Widget Extension

```bash
xcodebuild -project MileageTrackeriOS.xcodeproj \
  -scheme MileageTrackerWidgetExtension \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

### Device

```bash
xcodebuild -project MileageTrackeriOS.xcodeproj \
  -scheme MileageTrackeriOS \
  -destination 'generic/platform=iOS' \
  build
```

## Test

```bash
xcodebuild -project MileageTrackeriOS.xcodeproj \
  -scheme MileageTrackeriOS \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test
```

## Run in Simulator

```bash
# Boot the simulator
xcrun simctl boot "iPhone 17"

# Build and install
xcodebuild -project MileageTrackeriOS.xcodeproj \
  -scheme MileageTrackeriOS \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build

# Install the app
xcrun simctl install booted \
  ~/Library/Developer/Xcode/DerivedData/MileageTrackeriOS-*/Build/Products/Debug-iphonesimulator/MileageTrackeriOS.app

# Launch
xcrun simctl launch booted com.justharryjust.MileageTrackeriOS
```

## Project Structure

| Directory | Purpose |
|---|---|
| `MileageTrackeriOS/Main/` | App entry point, routing, app state |
| `MileageTrackeriOS/Managers/` | Core managers: TripRecorder, Location, Bluetooth, Region |
| `MileageTrackeriOS/Repositories/` | Realm-backed data layer |
| `MileageTrackeriOS/Models/` | Trip, Vehicle, OdometerReading, and other models |
| `MileageTrackeriOS/Onboarding/` | Multi-step onboarding flow |
| `MileageTrackeriOS/Calculator/` | MileageCalculator — jurisdiction-aware rate engine |
| `MileageTrackeriOS/Main/Reports/` | Report generation and CSV export |
| `MileageTrackeriOS/Main/Settings/` | User profile, vehicle management, logbook |
| `MileageTrackeriOS/Main/Components/` | Reusable UI components |
| `MileageTrackerWidget/` | Home screen widget extension |
| `MileageTrackeriOSTests/` | Unit tests |
| `MileageTrackeriOSUITests/` | UI tests |
| `Docs/` | Design docs, pre-release checklist, known issues |

## Agent Pipeline

This project uses a local Claude Code agent pipeline to automate development:

| Command | Agent | What it does |
|---|---|---|
| `/orchestrate` | Orchestrator | Polls the board and dispatches agents automatically |
| `/scope <url>` | Scoping | Researches a ticket and writes acceptance criteria |
| `/dev <url>` | Developer | Implements a ticket and opens a PR |
| `/qa <url>` | QA | Reviews, tests, and merges a PR |
| `/test` | Product Tester | Full end-to-end app test using Mobile MCP |

Agent prompts live in `.claude/agents/`. The project board is at `github.com/users/justharryjust/projects/2`.
