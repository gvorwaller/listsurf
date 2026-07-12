# 2026-07-12 — M4 Stage 1 verification (drag & drop)

**Status: Stage 1 code-complete and fully verified by automated tests on both
platforms. Commits held pending Gaylon's macOS eyeball pass (V1-4 latency gate)
and the CODEX2 edit/checkoff test matrix.**

## Verification matrix

| Check | Result |
|---|---|
| `swift test` (package: Domain + Features) | 192/192 green |
| iOS app build | green |
| macOS app build | green |
| iOS UI test plan (incl. new `testDragReordersSiblings`) | 5/5 green |
| macOS UI test plan (incl. new `testDragReordersSiblings` + ⌘Z undo) | 7/7 green |

## Getting the iOS drag UI test to pass (three fixes, all evidence-driven)

Programmatic sim drags are impossible (`FBSimulatorHIDEvent does not support
touch move events` — both `axe drag` and XcodeBuildMCP `drag`), so an XCUITest
twin is the executable substitute for the manual iOS drag check. Debugging used
the xcresult **screen recording** (ffmpeg frame extraction) rather than guesses:

1. **Keyboard-focus race**: each `\n` commit recreates the add field below the
   new item; the recreated field's focus re-grab can race the test. Fix: re-resolve
   AND tap the field before each `typeText`.
2. **Add-flow dismissal**: the keyboard-accessory Cancel button only exists
   while the software keyboard shows. Fix: dismiss by tapping a row (click-away),
   which doesn't depend on the accessory.
3. **The drag gesture itself**: rows carry a context menu, so a stationary press
   ≥0.5s risks the menu, while 0.3s degrades into a scroll. Working incantation:
   `press(forDuration: 0.6, thenDragTo: alpha, withVelocity: .slow, thenHoldForDuration: 0.5)`.

The macOS twin failed its first-ever run for the same root cause as (2): the
`addItem` helper commits with Return, which re-arms the add flow, and rows are
`.moveDisabled` while text entry is active. One `Escape` before the drag fixed
it. Pleasant side effect: **V1-6 (no dragging during text entry) is empirically
proven on both platforms** — the tests failed precisely because the guard works.

## One-time flake, investigated to the ground

In a single early run, Charlie's row visibly disappeared after tapping Alpha
while the add field was armed (video frames show it clearly at t=24.9→25.1).
Investigation: instrumented `ListStore.applyChanges` to stack-trace any shrink
of the items array, reran the exact test (zero hits — the store never lost an
item), and manually reproduced the same steps (correct behavior). Unreproduced
across three subsequent runs. Verdict: one-time presentation glitch under the
armed-add-field + software-keyboard condition, **not data loss**. Instrumentation
removed. Evidence archived in session scratchpad (`dragfail/`).

## td-336bcd: title-leak false alarm (lesson recorded)

During manual sim checks the editor title showed "List Info"/"Item Details"
instead of the list name. Filed as td-336bcd, then root-caused: the manual repro
was unknowingly driving a **stale pre-790ea81 build** under the old bundle ID
`com.listsurf.app`, left on the simulator by an earlier XcodeBuildMCP session.
Both strings were removed from source in 790ea81 (the M3-7 title-leak fix).
The current app (`net.vorwaller.listsurf`) shows the correct title on create and
reopen, verified via an XCUITest navigation-bar dump. Closed as not-a-bug; stale
app uninstalled from the simulator.

**Trap for future sessions**: XcodeBuildMCP session defaults can point at a
stale bundle ID. When manually driving the sim app, verify the bundle ID matches
the current project (`net.vorwaller.listsurf`) before trusting any observed bug.

## Manual V1 checks — scriptable portion done

- V1-1 (iOS gesture precedence): tap-select ✓, long-press-hold context menu ✓
  (axe stationary touch), long-press-drag reorder ✓ (UI test), swipe-delete ✓
  (axe swipe works; only touch-*move* drags are blocked in the sim).
- V1-3 (partial): order persists across relaunch ✓.
- V1-6: proven empirically (see above).

## Outstanding before commit

- Gaylon's eyeball pass on the Mac app: V1-4 (D10 latency gate), V1-2 feel
  check, V1-3 collapsed-parent drag, V1-7 large-fixture smoothness.
- Gaylon found issues in macOS edit/checkoff functions during testing; CODEX2
  is producing a test matrix (expected functionality × found issues × help doc ×
  context menus). Stage 1 commits held until that lands, for clean attribution.
- Then: phased commits (Domain+tests, Store+tests, View/Help/UI-tests+pbxproj,
  spec rev 3 edits), td approvals (td-ce3d10, td-ebd60e, td-df425b, td-4e578f),
  CODEX2 hostile review of the commits.
