# 2026-06-20 — Context menu fix & UI automation setup

## Context menu fix (complete)

macOS context menu operations (Add Child, Indent, Outdent, Delete, Move Up/Down) were silently failing. Root cause: SwiftUI button actions wrapped in `Task { await }` are silently swallowed on macOS for context menus and some other action sites.

**Fix:** Refactored all 15 ListStore mutation methods from `async` to synchronous. Split the old `persistChanged(from:to:)` into:
- `applyChanges(to:)` — synchronous, updates `items` and rebuilds rows immediately
- `persistInBackground(from:to:)` — fire-and-forget `Task` that diffs and writes to Core Data

Removed all `Task { await }` wrappers from button actions in:
- `OutlineEditorView.swift` — context menu, swipe actions, commitEdit, commitNewItem
- `CheckModeView.swift` — toggleCheck, resetSubtree
- `InspectorView.swift` — title/notes/quantity bindings
- `ListDetailView.swift` — resetAllChecks toolbar button

**Verified:** User confirmed Add Child works from the context menu on macOS. All 70 unit tests pass. Both iOS and macOS targets build clean.

## UI automation setup (in progress)

### What's installed and configured

1. **XcodeBuildMCP** (v2.6.2) — Xcode build/run/test MCP server
   - Config: `.xcodebuildmcp/config.yaml` with `enabledWorkflows: [simulator, ui-automation, macos]`
   - MCP entry: `.mcp.json` has `xcodebuildmcp` server
   - Session defaults: project path, scheme, simulator ID, bundle ID
   - **Key lesson:** config key is `enabledWorkflows` (not `workflows`), values are hyphenated (`ui-automation` not `uiAutomation`). Found by grepping XcodeBuildMCP source at `/opt/homebrew/Cellar/xcodebuildmcp/2.6.2/libexec/build/utils/project-config.js`.

2. **AXe** (v1.7.1) — Accessibility-based UI automation for simulators
   - Installed: `brew tap cameroncooke/axe && brew trust cameroncooke/axe && brew install cameroncooke/axe/axe`
   - Required by XcodeBuildMCP for tap/type/swipe/long-press operations
   - Without AXe, `snapshot_ui` works (read-only AX tree) but `tap`/`touch`/`type_text` silently no-op

3. **iOS Simulator** — iPhone 16 Pro, iOS 26.5
   - Runtime: downloaded via `xcodebuild -downloadPlatform iOS` (8.52 GB)
   - Device: created via `xcrun simctl create "iPhone 16 Pro"` — UUID `3A9AD36D-0839-4A74-BF52-5CFD3CCBA593`

4. **XcodeBuildMCP daemon** — `xcodebuildmcp daemon start` (needed for some operations)

### What works

- `build_run_sim` / `build_run_macos` — build and launch on both platforms
- `snapshot_ui` — reads AX tree, returns element refs with correct labels
- `screenshot` — captures simulator screen
- `button` (home button) — HID events reach the simulator
- Home screen icon taps — work correctly
- `gesture` presets (scroll, swipe) — HID injection works

### What doesn't work yet (iOS 26.5 simulator)

**In-app taps don't deliver touch events.** Both XcodeBuildMCP `tap`/`touch` and direct AXe `axe tap` report success but no touch actually reaches the app. Tested with all three AXe tap styles (`automatic`, `simulator`, `physical`). Added debug `print()` statements to button actions — no log output, confirming the tap never fires the button closure.

Suspected cause: **AX coordinate space mismatch on iOS 26.5.** The accessibility tree reports the app frame as `{{0, 0}, {320, 480}}` but the actual screen logical resolution is 402x874 (1206x2622 at 3x). AXe finds the button by label and calculates tap coordinates from the (incorrect) AX frame. The coordinates land in the 320x480 space but the HID event may need the 402x874 space. This is likely an iOS 26 beta / Xcode 26 beta compatibility issue with AXe.

### What works for macOS UI automation (workaround)

AppleScript via `System Events` can interact with the native macOS app:
- `click menu item` — triggers menu bar items
- AX hierarchy navigation — found sidebar and detail outlines through `window > group > splitter group > group > scroll area > outline`
- `perform action "AXShowMenu"` on outline rows — **successfully triggers context menus**
- Row selection via `click at {x, y}` coordinates
- Keyboard navigation (Tab, arrow keys) works for focusing sidebar/detail

**AX path to detail outline rows:**
```
window 1 > group 1 > splitter group 1 > group 2 > splitter group 1 > group 1 > scroll area 1 > outline 1
```

### Remaining issues

- **Menu bar commands are fire-and-forget:** `ListsurfCommands.swift` posts notifications (e.g., `.listsurfAddChild`) but no view has `onReceive` handlers. The Item menu keyboard shortcuts (Cmd+Return for Add Child, Tab for Indent, etc.) don't work because nothing listens.
- **`.alert()` on macOS not appearing:** File > New List clicks successfully via AppleScript but the SwiftUI `.alert()` never presents. Checked for sheets, dialogs, additional windows — none found. May need investigation.
- **AXe + iOS 26.5 coordinate mismatch:** Needs testing with a future AXe or iOS release, or a coordinate transform workaround.

### Files changed for automation setup

| File | Change |
|---|---|
| `.mcp.json` | Added `xcodebuildmcp` MCP server entry |
| `.xcodebuildmcp/config.yaml` | Created with enabledWorkflows, session defaults |
