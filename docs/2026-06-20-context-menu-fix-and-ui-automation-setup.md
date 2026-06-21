# 2026-06-20 — Context menu fix and UI automation setup

## Context menu fix (complete)

macOS context menu operations (Add Child, Indent, Outdent, Delete, and Move Up/Down) were silently failing. The cause was SwiftUI button actions wrapped in `Task { await ... }`; those actions were not reliably executed from macOS context menus and some related action sites.

The fix refactored all 15 `ListStore` mutation methods from asynchronous to synchronous entry points. The old `persistChanged(from:to:)` behavior was split into:

- `applyChanges(to:)`, which updates `items` and rebuilds rows synchronously.
- `persistInBackground(from:to:)`, which starts the Core Data diff and write in a background task.

The unnecessary `Task { await ... }` wrappers were removed from actions in:

- `OutlineEditorView.swift`: context menus, swipe actions, `commitEdit`, and `commitNewItem`.
- `CheckModeView.swift`: `toggleCheck` and `resetSubtree`.
- `InspectorView.swift`: title, notes, and quantity bindings.
- `ListDetailView.swift`: the Reset All Checks toolbar action.

The user verified Add Child from the macOS context menu. The existing 70 logic tests passed and both application targets built successfully.

## Native UI automation setup (complete)

The initial effort used XcodeBuildMCP, AXe, screenshots, and AppleScript to drive the applications directly. Those tools were useful for inspecting accessibility trees and diagnosing the app, but they were too sensitive to simulator coordinate behavior and macOS accessibility hierarchy details to be the primary regression-test mechanism.

The durable solution is native XCTest UI automation integrated into the Xcode project. XcodeBuildMCP can invoke these tests, but the tests themselves use Apple's `XCUIApplication` and `XCUIElement` APIs and run the same way from Xcode or `xcodebuild`.

### Xcode project and test configuration

Four platform-specific test targets are configured:

- `Listsurf_iOSLogicTests`
- `Listsurf_iOSUITests`
- `Listsurf_macOSLogicTests`
- `Listsurf_macOSUITests`

The shared schemes `Listsurf_iOS` and `Listsurf_macOS` were added under `Listsurf.xcodeproj/xcshareddata/xcschemes`. Each scheme uses its corresponding checked-in test plan:

- `Listsurf_iOS.xctestplan`
- `Listsurf_macOS.xctestplan`

Each plan runs the platform's logic and UI targets with code coverage enabled. The UI targets are non-parallel because they launch and control a single application instance and persistent store.

### Deterministic UI-test storage

UI tests must not read, modify, or depend on the developer's normal app data. `ListsurfApp` and `PersistenceStack` now support a test-only launch environment:

- `LISTSURF_UI_TEST_STORE=<identifier>` selects a named SQLite store dedicated to that test scenario.
- `--ui-testing-reset` removes that store before launch, giving the test a known empty starting state.

Each UI test uses its own store identifier. Persistence tests launch once with reset enabled, terminate the app, and relaunch without reset to verify that data survives a real application restart. This tests the actual persistent-store path while keeping runs reproducible and isolated.

### Stable accessibility surface

Identifiers were added to controls that UI tests need to address reliably, including:

- New List and Create controls.
- The new-list title field.
- Add Item and Add First Item controls.
- The new-item editor.
- The Edit/Check mode toggle.
- Check-mode item controls.

The tests prefer these identifiers and retain limited label-based fallbacks for native controls whose representation differs between iOS and macOS. This avoids coordinate-based tapping and dependence on the exact SwiftUI accessibility hierarchy.

### UI coverage added

The iOS UI suite verifies:

1. Creating a list, adding an item, switching to Check mode, and checking the item.
2. Creating a list and confirming that it remains after terminating and relaunching the app.

The macOS UI suite verifies:

1. Creating a list and adding an item.
2. Creating a list and confirming that it remains after terminating and relaunching the app.

### SwiftUI previews

`PreviewFixtures.swift` provides in-memory sample stores for SwiftUI previews. Previews were added or updated for the main content, outline editor, and check mode. This gives a fast way to inspect important states in Xcode without launching the complete app or touching persistent data.

## Verification results

Both complete platform suites passed:

- iOS Simulator: 72 tests passed, 0 failed (70 logic tests and 2 UI tests).
- macOS: 72 tests passed, 0 failed (70 logic tests and 2 UI tests).

The tests exercised actual app launches on both platforms, creation and editing flows, and persistence across relaunches. The iOS suite additionally exercised the Edit-to-Check mode flow and check-state mutation.

XcodeBuildMCP successfully built, launched, and tested both targets. Native Xcode MCP macOS UI automation did not fully initialize during the exploratory session, but that does not block the XCTest suites or normal testing from Xcode and `xcodebuild`.

## How to run the tests

In Xcode, select either the `Listsurf_iOS` or `Listsurf_macOS` shared scheme and run Product > Test (`Command-U`). The selected scheme automatically uses the appropriate checked-in test plan.

From the command line, use the corresponding scheme and destination, for example:

```sh
xcodebuild test \
  -project Listsurf.xcodeproj \
  -scheme Listsurf_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

xcodebuild test \
  -project Listsurf.xcodeproj \
  -scheme Listsurf_macOS \
  -destination 'platform=macOS'
```

The iOS simulator name must match an installed simulator. Xcode's Test navigator is the simplest way to run one test, one target, or the whole plan and inspect failures, screenshots, and activity logs.

## Files added or changed for testing

| File | Purpose |
|---|---|
| `Listsurf.xcodeproj/project.pbxproj` | Defines the platform-specific logic and UI test targets. |
| `Listsurf.xcodeproj/xcshareddata/xcschemes/` | Contains the shared iOS and macOS schemes. |
| `Listsurf_iOS.xctestplan` | Runs iOS logic and UI tests with coverage. |
| `Listsurf_macOS.xctestplan` | Runs macOS logic and UI tests with coverage. |
| `Tests/iOSUITests/Listsurf_iOSUITests.swift` | iOS creation, editing, check-mode, and persistence flows. |
| `Tests/macOSUITests/Listsurf_macOSUITests.swift` | macOS creation, editing, and persistence flows. |
| `App/ListsurfApp.swift` | Selects and optionally resets an isolated UI-test store at launch. |
| `Sources/Persistence/PersistenceStack.swift` | Supports named, resettable persistent stores for UI tests. |
| `Sources/Features/PreviewFixtures.swift` | Supplies in-memory sample data for previews. |
| Feature view files | Add previews and stable accessibility identifiers. |

## Follow-up coverage

The current suites establish reliable cross-platform smoke and persistence coverage. Useful next additions are context-menu operations on macOS, indentation and reordering, deletion, quantity editing, Check-mode subtree behavior, and iCloud/CloudKit synchronization tests. Cloud synchronization requires a separate integration-test strategy because deterministic multi-device CloudKit behavior is outside the scope of local XCTest UI runs.
