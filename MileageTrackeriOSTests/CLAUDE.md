# MileageTrackeriOSTests — Test Target

## File Organisation (MANDATORY)

**Every test suite must be in its own file.** Never append a new `@Suite` to an existing file. Split by feature:

| Pattern | Naming |
|---------|--------|
| One file per feature / area | `TripRecorderTests.swift`, `ReportGeneratorTests.swift`, `WidgetStatStoreTests.swift` |
| One `@Suite` per file | A file contains exactly one top-level `@Suite` (or `XCTestCase` subclass) |
| Auxiliary helpers | `TestHelpers.swift` — shared fixtures/extensions only |

**When creating tests for a new feature:** add a new file. Do NOT append to a mega-file.

**When touching an existing suite that still lives in a shared file:** extract it to its own file first, then modify.

## Testing Framework

- **Swift Testing** (`import Testing`) for all new tests.
- `@Test` and `#expect` — not `XCTAssert`.
- XCTest is only used for UI tests (`XCUITest`).

## Standards

### Test isolation
- Tests must not depend on each other. No shared mutable state.
- Clean up Realm data. If a test writes to Realm, use an in-memory Realm or explicitly delete its data.
- No singletons accessed in tests unless explicitly mocked/stubbed.

### Naming
- Pattern: `@Test("human-readable description")` with a descriptive function name.

### Structure
- Given / When / Then sections via comments for non-trivial tests.
- Avoid DRY at the expense of readability.
- Keep tests fast. No network, no real file I/O, no `sleep()`.

### What to test
- All public API of managers, repositories, and services.
- Edge cases: empty state, nil input, out-of-bounds, concurrent writes.
- Error paths: recovery from failure, graceful degradation.

### What NOT to test
- SwiftUI view bodies (use XCUITest or manual QA).
- Realm itself.
- Generated code or protocol conformance boilerplate.

## Build

- Always build via the wrapper: `.claude/scripts/build.sh build` (app) or `.claude/scripts/build.sh test` (tests).
- Do NOT call `xcodebuild` directly.
- There is no `iPhone 17` simulator. Use `iPhone 16e` or `iPhone 16 Pro`.

## File Template

```swift
import Testing
import Foundation
import RealmSwift
@testable import MileageTrackeriOS

@Suite("<Feature Name>")
struct <Feature>Tests {

    @Test("<scenario description>")
    func <scenarioName>() {
        // Given
        // ...

        // When
        // ...

        // Then
        #expect(...)
    }
}
```
