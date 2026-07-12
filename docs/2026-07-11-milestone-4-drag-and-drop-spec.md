# Milestone 4 — Drag-and-Drop Reordering: Implementation Spec

**Rev 2 (2026-07-12)**: amended after Codex adversarial plan review — five findings, all confirmed: session-authenticated drag payload (D12), explicit spring-task/teardown lifecycle replacing "nothing lingers" (D16/D17/D23), the dragged-item's-own-gap slot formula defined (§10.2 step 4), four dynamic-mutation spike criteria added (§10.1), and the updatedAt invariant reconciled with normalization's exhaustion case (D18, invariant 3). The Stage 1 flat-move mapper survived the review unchanged.

**Date**: 2026-07-11
**Author**: Claude (planning agent; every anchor verified against the working tree at commit `719aa32`, clean)
**Scope sources**: `docs/CC-listsurf-V1-plan.md` §Drag-and-Drop Feedback (lines 303–309), §Outline Editor (line 294), §Haptic Feedback (line 336), §UI Tests (line 560); `docs/2026-07-08-independent-plan-fixes-usability-edge.md` Milestone 4 (line 46, line 104: "staged: `.onMove` first, reparenting drag later"); original testing note (2026-07-07): "want drag-n-drop to move items (at least, up/down)".
**Executor**: an implementation model with no access to this spec's research — everything needed is in this document. Follow `cs.md` rules; they override defaults.

**Staging is fixed — do not merge the stages.**

- **Stage 1** — same-parent sibling reordering via native `.onMove` (delivers the "at least up/down by drag" ask). Ships, gets reviewed, goes to TestFlight, and is dogfooded.
- **Checkpoint** — the Stage 2 go/no-go checklist (§9) must pass before any Stage 2 work starts.
- **Stage 2** — full reparenting drag with a custom insertion indicator and horizontal depth targeting. Runs as a separate sprint with its own tasks.

Each stage has its own td breakdown, verification plan, and acceptance criteria. Stage 1 must not "get a head start" on Stage 2 UI (no drop delegates, no indicators, no draggable payloads in Stage 1) — the one deliberate exception is the Domain `reparent` function (§5.1), which Stage 1 builds and tests because Stage 1's mapper is a special case of it and Stage 2 reuses it unchanged.

---

## 0. What this milestone delivers

1. **Stage 1**: Drag a row up or down within its sibling group in the outline editor, on macOS (click-drag) and iOS (long-press-drag). A drag that crosses a parent boundary lands at the nearest legal slot inside the item's own sibling group (clamping — never reparenting, never a cycle). Dragging a collapsed or expanded parent moves its whole subtree. One undo step per completed drag; identity drags register nothing.
2. **Stage 2**: Full reparenting drag: a custom horizontal insertion indicator indented to the proposed depth; horizontal drag movement selects sibling-vs-child depth (V1 plan honored); prohibition feedback for illegal targets (own subtree); spring-loaded expansion of collapsed parents on hover-dwell; drop commits through `TreeEngine.validateReparent` and the existing undo/persist pipeline. Stage 2 replaces Stage 1's `.onMove` wiring entirely (§10, D20).

Not delivered by this milestone (see §13): cross-list drag, multi-item drag, drag in check mode or the archive, library-sidebar list reordering.

---

## 1. Current-code anchor map (verified)

| Concern | Anchor |
|---|---|
| Editor list: `List(selection: $store.selectedItemIDs)` | `Sources/Features/Editor/OutlineEditorView.swift:118` |
| `ForEach(store.filteredRows)` + `.tag(row.id)` | `OutlineEditorView.swift:119-121` |
| Row indent via `listRowInsets`: `leading: 16 + Double(row.depth) * 20` | `OutlineEditorView.swift:122-127` |
| Swipe delete action on rows | `OutlineEditorView.swift:128-134` |
| **Add-field row interleaved inside the ForEach body** (`addFieldPlacement(after:)`) | `OutlineEditorView.swift:136-138`, placement logic `:297-306` |
| Root add-field row (outside the ForEach) | `OutlineEditorView.swift:141-143`, `shouldShowRootAddField :311-320` |
| `.listStyle(.sidebar)`; animation keyed on `filteredRows.map(\.id)` | `OutlineEditorView.swift:145-146` |
| Selection-driven context menu; **macOS double-click = rename** (`primaryAction`) | `OutlineEditorView.swift:147-150`, modifier `:459-499`, primaryAction `:469-473` |
| Row composition: `OutlineRowView` + ellipsis `Menu` + trash `Button` + `contentShape` | `OutlineEditorView.swift:153-197` |
| iOS tap-to-select (`RowSelectionTapModifier`, iOS-only `onTapGesture`) | `OutlineEditorView.swift:196, 503-516` |
| macOS Return/Tab key ownership (deliberately not menu equivalents) | `OutlineEditorView.swift:39-51` |
| Click-away rename commit / add dismiss via `onChange(of: store.selectedItemIDs)` | `OutlineEditorView.swift:89-100` |
| macOS has **no** `.searchable` in the editor (sidebar owns the window's one) | `OutlineEditorView.swift:594-608` |
| Row content is gesture-free by design ("selection, click handling… belong to the owning List") | `Sources/Features/Editor/OutlineRowView.swift:4-6` |
| Disclosure chevron `Button`, rename `TextField` inside rows | `OutlineRowView.swift:57-69, 33-41` |
| Parent rows show trailing leaf progress `"checked/total"` | `OutlineRowView.swift:90-96` |
| `ListStore` presentation state: `selectedItemIDs :18`, `isCheckMode` didSet clears text-entry state `:19-29`, `searchText :31`, `editingItemID`/`addPlacement`/`pendingDeletionIDs :35-37`, `isTextInputActive :39-41` | `Sources/Features/Store/ListStore.swift` |
| `filteredRows` (search filter `:76-87`; check filter applies **only in check mode** `:89-97` — in edit mode with empty search, `filteredRows == flatRows`) | `ListStore.swift:73-100` |
| `moveUp`/`moveDown` store commands (the pattern `moveRows` must mirror) | `ListStore.swift:310-324` |
| **No-op guard before undo registration** (the invariant new code must keep) | `ListStore.swift:330-335` |
| Snapshot undo with synchronous redo re-registration; `teardownUndo` | `ListStore.swift:444-461, 466-468` |
| `persistInBackground` diff/queue pipeline | `ListStore.swift:150-180` |
| `toggleExpanded` / `expandAll` / `collapseAll` | `ListStore.swift:423-440` |
| `TreeEngine.flatten` (parents before descendants; sibling sort = position asc, uuidString tie-break) | `Sources/Domain/Tree/TreeEngine.swift:60-95`, sort `:70-73` |
| `FlatRow` (id, item, depth, hasChildren, isExpanded) | `TreeEngine.swift:3-39` |
| `validateReparent` (self/cycle/cross-list/missing) | `TreeEngine.swift:228-257` |
| Position helpers: `midpoint`, `nextPosition`, `normalizeSiblingPositions` | `TreeEngine.swift:261-309` |
| `moveUp`/`moveDown` engine (midpoint-between-neighbors rationale comment) | `TreeEngine.swift:399-445` |
| `indent`/`outdent` (the only reparenting operations that exist today — **there is no general `reparent` function**; verified by grep) | `TreeEngine.swift:449-512` |
| `descendants(of:in:)` (cycle-safe) | `TreeEngine.swift:196-210` |
| `sortedSiblingGroup(of:in:)` | `TreeEngine.swift:386-395` |
| Mode switch: `CheckModeView` vs `OutlineEditorView` are separate views | `Sources/Features/Editor/ListDetailView.swift:17-27` |
| Edit/check toolbars (unchanged this milestone) | `ListDetailView.swift:106-232` |
| Focused commands gate on `isTextInputActive`; Move Up/Down commands | `ListDetailView.swift:253, 274-279` |
| Check-mode list has no move/drag modifiers (nothing to disable) | `Sources/Features/CheckMode/CheckModeView.swift:60-85` |
| Shared action builder (Move Up/Down with ⌘⌥↑/↓ hints — the accessible/keyboard alternative to drag) | `Sources/Features/Editor/ItemActionsMenu.swift:63-75` |
| Structural menu actions are **single-item only** (`singleID` gate) | `ItemActionsMenu.swift:19-24` |
| `Haptics.checkToggle()` (Platform, `#if os(iOS)`) | `Sources/Platform/Haptics.swift:7-14` |
| Archived lists are never opened in the editor (ArchiveView sets no `selectedListID`; archiving deselects) | `Sources/Features/Store/AppStore.swift:97`; grep of `ArchiveView.swift` finds no navigation |
| Detail view entry | `Sources/Features/ContentView.swift:60` |
| Module rules: Domain imports Foundation only; Platform imports no Domain | `Package.swift` targets block |
| Domain test fixture style (`makeItem`, single shared `listID`) | `Tests/DomainTests/TreeEngineTests.swift:4-23` |
| ListStore test harness (`makeStore` with `InMemoryOutlineRepository`, `UndoManager()` direct) | `Tests/FeaturesTests/ListStoreUndoTests.swift:9-24` |
| macOS UI test helpers (`launchApp(store:reset:)`, `createList`, `addItem`, lookups by `staticTexts["Title"]`) | `Tests/macOSUITests/Listsurf_macOSUITests.swift:91-156` |
| Current UI-test baseline: 6 macOS + 4 iOS tests (must stay green) | devlog `2026-07-11.md` ("125 unit + 6 UI / + 4 UI") |

---

## 2. API research findings (verified 2026-07-11 — do not re-research)

1. **`.onMove` works without EditMode on iOS.** Long-press a row, then drag; no `EditButton` required. EditMode only adds the trailing drag-handle affordance. The app has no EditButton anywhere and does not add one. (Sarunw, "How to Reorder List rows in SwiftUI List".) Old claims that iPhone needs edit mode are outdated.
2. **`.onMove` works on macOS `List`**, with the native row-drag and insertion-line indicator, and coexists with `List(selection:)`. Known caveat: the move gesture recognizer can **delay clicks on interactive controls inside rows** (text fields worst; documented by nilcoalescing, "Reorder List rows … on macOS", with a `moveDisabled` + `onHover` workaround). This is the biggest Stage 1 risk because Milestone 2's Mac interaction quality is the app's crown jewel — see D10 and verification V1-4.
3. **`.moveDisabled(_:)`** is the per-row switch for conditionally disabling drag; it is the sanctioned mechanism for the search/text-entry gating in D5.
4. **iOS 27 / macOS 27 APIs are out of reach.** WWDC26 introduced `reorderable()` / `reorderContainer(for:)` (reordering for any container) and brought `dragContainer(for:)` / `draggable(containerItemID:)` / `onDragSessionUpdated` to iOS 27 (previously macOS-only). Listsurf's minimum OS is iOS 26/macOS 26 and OS 27 has not shipped (today is 2026-07-11; fall release). None of these APIs may be used. If the project's minimum OS is raised to 27 before Stage 2 begins, the planner revisits D11 (go/no-go item G6) — the implementer does not.
5. **`DropDelegate`/`DropInfo`** (`onDrop(of:delegate:)`, iOS 13.4+/macOS 10.15.4+) is the only SwiftUI drop API that delivers **continuous position updates during hover** (`dropUpdated(info:)`), which depth targeting requires. `DropInfo.location` is in the coordinate space of the view carrying the `.onDrop` modifier. `dropUpdated` returns a `DropProposal` whose `.forbidden` operation produces the system "not allowed" cursor on macOS. `dropDestination(for:)` gives only a boolean `isTargeted` during hover — insufficient for Stage 2; do not use it.
6. **`.onDrag` has no drag-cancelled callback** on iOS 26 (`onDragSessionUpdated` is macOS-only at our floor). Stage 2's state design must not depend on observing drag-session end (see D17, D23).

Sources: [Sarunw — SwiftUI List onMove](https://sarunw.com/posts/swiftui-list-onmove/), [nilcoalescing — Reorder List rows on macOS](https://nilcoalescing.com/blog/ListReorderingWhileStillBeingAbleToEditTheListItems/), [nilcoalescing — New reordering/drag APIs on iOS 27](https://nilcoalescing.com/blog/NewSwiftUIAPIsForReorderingAndDragAndDropOniOS27/), [WWDC25 What's new in SwiftUI (256)](https://developer.apple.com/videos/play/wwdc2025/256/), [WWDC26 Code-along: drag and drop (271)](https://developer.apple.com/videos/play/wwdc2026/271/), [Apple — Adopting drag and drop using SwiftUI](https://developer.apple.com/documentation/SwiftUI/Adopting-drag-and-drop-using-SwiftUI).

---

## 3. V1-plan reconciliation (§Drag-and-Drop Feedback, plan lines 303–309 — each rule honored or superseded)

| V1 plan rule | Disposition |
|---|---|
| "Insertion indicator: a horizontal line at the proposed drop position, indented to child level for nesting, sibling level for sibling placement" (line 305) | **Honored in Stage 2** (D14). Stage 1 uses the platform's native flat insertion line — a deliberate interim state. |
| "Nesting intent: horizontal drag position determines sibling vs. child. Dragging right proposes nesting under the row above; dragging left proposes sibling" (line 306) | **Honored in Stage 2, refined** (D13): depth follows *relative* horizontal movement since the drag entered the list (±20 pt per level), not absolute pointer column. Rationale: rows are wide; the absolute pointer x sits right of the deepest indent column almost always, which would degenerate to "always nest". Relative movement is what "dragging right/left" actually describes. |
| "Invalid drops: dragging onto own descendant (cycle) shows prohibition indicator" (line 307) | **Honored in Stage 2** (D15): `DropProposal(operation: .forbidden)` → system NO cursor on macOS; on both platforms the insertion indicator disappears and the drop is inert. Stage 1 cannot produce an invalid drop at all (it never reparents). |
| "Multi-row drag: selected rows stack visually during drag" (line 308) | **Superseded — both stages are single-item drag** (D6/D21). Rationale: every structural command in the app is single-item today (`ItemActionsMenu.swift:19-24` gates structure on `singleID`); a multi-parent selection has no defined drop semantics; and the visual-stack API (`dragPreviewsFormation`) is not available at our OS floor. Revisit post-V1 alongside multi-select structural commands as one design. |
| "Drag pickup: medium impact" haptic (plan line 336) | **Honored in Stage 2** (D19). Stage 1 relies on the system's native reorder-session feedback (D7). |
| UI-test criterion "Drag within a sibling group and into/out of a parent with correct insertion indicators" (plan line 560) | Split across stages: "within a sibling group" = Stage 1 acceptance; "into/out of a parent with correct insertion indicators" = Stage 2 acceptance. |

The 2026-07-08 plan's staging directive (".onMove first, reparenting drag later", lines 46 and 104) is followed exactly.

---

## 4. Design decisions (decided — do not reopen)

### Stage 1

**D1 — Stage 1 uses native `.onMove` on the existing `ForEach`.** Research (§2.1–2.2) confirms it fits: iOS long-press drag without EditMode, macOS click-drag with native insertion line, coexistence with `List(selection:)`. Alternatives rejected: custom drag gestures (that is Stage 2's job); iOS 27 `reorderable()` (§2.4, unavailable).

**D2 — Cross-boundary destinations clamp to the nearest legal same-parent slot; never snap back, never reparent.** `.onMove` reports a destination in the *flattened* visible rows. Stage 1 interprets any destination as: "the dragged item keeps its parent; its new position within its sibling group is determined by which siblings precede the drop gap in visible order." Implemented by simulating the flat move (`ids.move(fromOffsets:toOffset:)`) and reading the resulting relative order of the sibling group out of it (§5.1). Consequences, all intended:
- Dropping between another parent's children lands the item immediately after (or before) that parent among its own siblings — the nearest legal slot.
- Dropping an expanded parent into its own subtree is an identity move (its sibling order didn't change) → no-op. **Stage 1 structurally cannot create a cycle: `parentID` is never written.**
- A collapsed parent occupies one visible row; dropping below it lands after its entire subtree, because positions are sibling-level.
Rationale vs. snap-back: the native insertion line will happily point at illegal gaps; refusing after the OS showed a willing indicator reads as "broken". Clamping always does *something* ordered and undoable, and matches the "at least up/down" ask. The clamp's feel is an explicit dogfooding question at the checkpoint (G5).

**D3 — Engine shape: build `reparent` now, express Stage 1 through it.** New file `Sources/Domain/Tree/TreeEngineReorder.swift` adds `reparent(itemID:toParent:atSiblingSlot:in:)` (general, validating, Stage 2's workhorse) and `moveVisibleRow(at:toVisibleDestination:visibleRows:in:)` (the flat-index mapper, which resolves to a same-parent `reparent`). This makes Stage 1's engine work Stage 2's foundation instead of throwaway; only the mapper is retired at Stage 2 (D20).

**D4 — Store API: `moveRows(from:to:undoManager:)`**, mirroring `moveUp` (`ListStore.swift:310-316`): snapshot → engine → no-op guard → `registerUndo` → `applyChanges` → `persistInBackground`. An identity or refused drag returns before `registerUndo` — **a cancelled/identity drop registers nothing** (same invariant as the indent guard, `ListStore.swift:330-335`).

**D5 — When drag is disabled** (all enforced twice: `.moveDisabled` in the view *and* a guard in the store — belt and suspenders):
- **Search active** (`!store.searchText.isEmpty`): filtered rows are a non-contiguous excerpt (ancestor-context rows, `ListStore.swift:76-87`); hidden siblings make any drop ambiguous. Decided: fully disabled.
- **Text entry active** (`store.isTextInputActive`): protects the rename field, and — critically — guarantees the add-field row never coexists with an enabled drag (D9).
- **Check mode**: structural change is not checking. No code needed — `CheckModeView` is a separate view with no move modifiers (`CheckModeView.swift:60-85`); state this in the PR, don't "add a disable".
- **Archive**: archived lists never open in the editor at all (`AppStore.swift:97`, ArchiveView has no detail navigation) — structural, no code needed.

**D6 — Single-item drag only.** On macOS, dragging one row of a multi-row selection may deliver a multi-index `IndexSet`. `moveRows` guards `source.count == 1` and returns (with an `os.Logger` debug line) otherwise. Consistent with app-wide single-item structural commands; Stage 2 keeps this (D21).

**D7 — No custom haptics in Stage 1.** The native reorder session already provides system feedback on iOS. (Stage 2's custom pipeline adds them, D19.)

**D8 — Accessibility story (state verbatim in the PR and any App Review notes):** drag is an *enhancement*, never the only path. Move Up/Down exists in the shared actions menu with ⌘⌥↑/⌘⌥↓ (`ItemActionsMenu.swift:63-75`), in the Item menu on macOS, and in the iOS action bar (`OutlineEditorView.swift:233-245`). VoiceOver users reorder through those. No new accessibility work is required for parity; do not remove or gate the button paths.

**D9 — The interleaved add-field rows and `.onMove` index math.** `.onMove` indices are offsets into the ForEach's data (`store.filteredRows`). The ForEach body can emit a *second* row (the add field, `OutlineEditorView.swift:136-138`), whose interaction with move indices is undocumented. This never matters because of D5: the add field exists only while `addPlacement != nil` ⇒ `isTextInputActive` ⇒ drag disabled. The root add field (`:141-143`) is outside the ForEach and irrelevant to its indices. **Invariant: whenever `moveRows` executes, `filteredRows[i]` corresponds 1:1 to the List's ForEach rows.** The store guard in D5 is what makes this an invariant rather than a hope.

**D10 — macOS row-control latency contingency.** Research §2.2: the move recognizer can delay clicks in row controls (chevron, ellipsis, trash, double-click rename). Verification V1-4 measures this. If (and only if) a perceptible regression appears, apply the prescribed contingency — do not invent another: macOS-only, add view-local `@State private var hoveredDraggableRowID: UUID?` set by `.onHover` on the `OutlineRowView` content area (title/notes region only, not the trailing buttons), and change the row's modifier to `.moveDisabled(isMacDragBlocked(row))` so drag is armed only while hovering the content area (pattern from nilcoalescing, §2.2; hover state persists through the drag because hover updates pause during drags). iOS is untouched by the contingency.

### Stage 2

**D11 — Architecture: stay inside `List`; custom drag = `.onDrag` sources + per-row `.onDrop(of:delegate:)` targets.** Rejected alternatives, with what they'd cost:
- *Custom `ScrollView`/`LazyVStack` container*: loses native `List(selection:)` — macOS arrow-key navigation, ⌘/⇧-click multi-select, focus behavior — i.e., the entire Milestone 2 refactor; loses `.swipeActions`, `.listStyle(.sidebar)` row chrome, and `contextMenu(forSelectionType:)` with its double-click rename. Unacceptable; not negotiable.
- *iOS 27 `reorderable()`/`dragContainer`*: unavailable at min OS 26 (§2.4).
- *`dropDestination(for:)`*: no continuous hover location (§2.5) — cannot do depth targeting.
- *Keep native `.onMove` and add drop-on-row nesting*: `.onMove` installs its own row-drag recognizer; a second drag source on the same rows conflicts. `.onMove` is removed in Stage 2 (D20).
Because per-row `DropDelegate` behavior inside `List` has platform-specific sharp edges, **Stage 2 opens with a mandatory spike (S2-1) with concrete pass criteria (§10.1). If the spike fails on either platform, STOP and return to planning — do not improvise a different architecture.** The fallback space (drop-on-row-nesting, AppKit `NSOutlineView` wrapper, min-OS bump to 27) is a product decision, not an implementation detail.

**D12 — Drag payload: session-authenticated. `draggedItemID: UUID?` names the local candidate; the payload proves the session.** (Rev 2 — the original "title-only payload, never parsed" design let a STALE `draggedItemID` from a cancelled drag validate an EXTERNAL drag session: `.onDrag` has no cancel callback, so after Esc the ID lingers, and a later plain-text drag from another app — or another Listsurf window — over a row would have reparented the stale item.)
- Declare an exported UTType `net.vorwaller.listsurf.outline-item` (add `UTExportedTypeDeclarations` to App/Info.plist — mirror the imported OPML declaration pattern — plus a `UTType.listsurfOutlineItem` extension next to `UTType+OPML.swift`).
- `.onDrag` returns an `NSItemProvider` registering BOTH representations: the custom type carrying the item's UUID string (the authentication token) and `.plainText` carrying the title (so cross-app drops still paste something human-useful).
- `.onDrop(of: [UTType.listsurfOutlineItem], delegate:)` — external text/files never conform, so foreign sessions can't even reach `validateDrop`, stale local ID or not.
- `performDrop` DEFERS the commit behind payload verification: capture the proposal and `draggedItemID`, return `true`, then asynchronously load the custom-type payload; commit via `store.performDrop` ONLY if the loaded UUID equals `draggedItemID`. Mismatch or load failure → log, clear drag state, mutate nothing. This kills the cross-window case: the other window's session conforms, but its payload UUID cannot match this window's `draggedItemID`.
(Cross-list drag remains a non-goal, §13. The spike §10.1 uses the custom type from the start.)

**D13 — Drop-proposal geometry.** Proposals are expressed as *gaps*: pointer in the top half of a row targets the gap above it; bottom half, the gap below. The gap below visible row `G` (with next visible row `N`) admits depths `[minDepth, maxDepth]` where `maxDepth = G.depth + 1` (child of G, slot 0) and `minDepth = N?.depth ?? 0`. Each depth `d ≤ G.depth` maps to: let `A` = the ancestor-or-self of `G` at depth `d`; parent = `A.parentID`; slot = (index of `A` in its sibling group, dragged item excluded) + 1 — i.e., "insert immediately after A". The gap above the first row admits exactly depth 0, parent `nil`, slot 0. `requestedDepth` comes from horizontal movement: the view records `xRef` (list-space x) at the session's first `dropUpdated`, and `requestedDepth = startDepth + Int(round((xNow − xRef) / 20))`, clamped into `[minDepth, maxDepth]`, where `startDepth` is the dragged item's depth at pickup and list-space x = `DropInfo.location.x + Double(row.depth) * 20` (the constant 16 cancels in deltas; 20 matches the per-level inset at `OutlineEditorView.swift:122-127`). Depths whose computed parent is the dragged item or one of its descendants are invalid; the requested depth clamps to the nearest valid depth in range, and if none is valid the proposal is `.forbidden`. All of this is a pure Domain function (§10.2) — the view supplies geometry, Domain decides meaning.

**D14 — Insertion indicator**: a 2 pt rounded rectangle in the accent color, rendered by the anchor row (the row owning the targeted gap edge) while a valid proposal targets it. Binding requirement: **the indicator's absolute leading edge = `16 + indicatorDepth * 20`** from the list's leading edge — the title column of the target depth, matching `listRowInsets` (`OutlineEditorView.swift:122-127`). Since the overlay lives in row-content space (already inset by `16 + row.depth * 20`), the relative x-offset is `(indicatorDepth − row.depth) * 20`, which may be negative — use `.overlay(alignment:)` + `.offset(x:)` (negative offsets are legal) or `.listRowBackground`; implementer's choice, the alignment formula is the contract. Top edge for `.above` (first-row gap only), bottom edge for `.below`.

**D15 — Illegal-target UX**: `dropUpdated` returns `DropProposal(operation: .forbidden)` when the Domain function returns `nil` → macOS shows the system prohibition cursor; on iOS the indicator's absence plus the inert drop is the communication (local drags don't render a reliable system badge — accepted). `performDrop` re-validates through `TreeEngine.validateReparent` regardless; a throw logs and aborts with zero mutation. The hover proposal is UX; the engine is the law.

**D16 — Spring-loaded expansion**: hovering a *nest-depth* proposal (`indicatorDepth == G.depth + 1`) over a collapsed parent for **0.7 s** expands it (Finder-like dwell). Implemented as a view-local `Task.sleep` held in `@State`. (Rev 2 — lifecycle made explicit; see D23's cleanup contract.) The task is cancelled on: proposal change, `dropExited`, `performDrop`, view `.onDisappear`, and any change of `store.isCheckMode`/`store.isTextInputActive`. **At fire time it re-guards**: `draggedItemID != nil`, the drag generation matches (D23), the same row is still the proposal anchor, and `!store.isCheckMode` — only then `store.setExpanded(id, true)`. An unstructured Task outlives a destroyed view's `@State` reference; the fire-time guard is what actually prevents a stale expansion after a mid-drag mode switch.

**D17 — Auto-collapse on pickup, no auto-restore.** Dragging an expanded parent collapses it at drag start (`store.setExpanded(id, false)`) so the subtree visually travels as one row. It stays collapsed after the drop *and* after a cancelled drag — because `.onDrag` provides no cancellation callback at our OS floor (§2.6), auto-restoring only on success would make cancel behave differently from drop. Staying collapsed is consistent, harmless (expansion is per-device presentation state), and one click to reverse.

**D18 — Drop commit semantics**: nest-depth drops insert at slot 0 (first child) — including into collapsed parents (which D16 usually expands first). The store expands the target parent on drop so the moved item is always visible. Positions: midpoint between new neighbors / ±1.0 at ends, then `normalizeSiblingPositions` — all inside `reparent`. (Rev 2) `updatedAt` changes on the moved item only **in the common case**; when midpoint exhaustion (neighbor gap < 1e-10) triggers target-group normalization, the repositioned siblings also receive new `position`/`updatedAt` — that is the existing engine contract (`normalizeSiblingPositions` is conditional and returns `items` unchanged otherwise, `TreeEngine.swift:294-296`), and drag inherits it rather than inventing a second timestamp policy. Descendants of the dragged item ride along untouched in all cases. `testReparentMidpointExhaustionNormalizes` must assert BOTH halves: common case = only the moved item's `updatedAt` changes; exhaustion case = the target group renumbers 1…n with fresh timestamps on repositioned members.

**D19 — Haptics (iOS only, in Platform)**: `Haptics.dragPickup()` = `UIImpactFeedbackGenerator(style: .medium)` fired in the `.onDrag` closure (V1 plan line 336 honored); `Haptics.dropCompleted()` = light impact fired in `performDrop` after a successful commit. No-op on macOS, `#if os(iOS)` like `checkToggle` (`Haptics.swift:7-14`).

**D20 — Stage 2 replaces Stage 1's UI wiring.** Remove: the `.onMove`/`.moveDisabled` modifiers, `ListStore.moveRows`, `TreeEngine.moveVisibleRow`, and their specific tests. Keep: `reparent` and all its tests (they are Stage 2's core), the undo/persist pattern, D5's disable conditions (now expressed as "drag sources/drop targets inert" under the same predicates). No dead code ships.

**D21 — Still single-item drag** (see reconciliation table §3). `draggedItemID` is the row the drag started on, regardless of selection.

**D22 — Auto-scroll near list edges during drag is acceptance-required.** Expected free: platform drag sessions over `NSTableView`/`UITableView`-backed lists auto-scroll natively. S2-1 verifies. Prescribed fallback if absent on a platform: wrap the List in `ScrollViewReader`; when the active proposal anchors to the first or last *visible* row continuously for 0.4 s, `withAnimation { proxy.scrollTo(rowID, anchor: …) }` two rows beyond, repeating while the condition holds. Do not build the fallback speculatively.

**D23 — Drag-in-progress state is view-local `@State` in `OutlineEditorView`, not `ListStore`.** The full set: `draggedItemID: UUID?`, `dropProposal: OutlineDropTarget?`, `dragSession: (startDepth: Int, xRef: CGFloat)?`, the spring-load `Task`, and (Rev 2) `dragGeneration: Int`. Justification against the store-owned rule: store-owned presentation state exists so *multiple surfaces* (toolbar, menus, commands) read one truth (`ListStore.swift:33-34`); drag hover state has exactly one consumer (the editor's rows), must die with the view, and must never gate commands. The *commit* goes through store API (`performDrop`), preserving the explicit commit lifecycle — the same split as view-local `editingText` draft vs store-owned `editingItemID`.

**(Rev 2) Cleanup contract — `dropExited` + `performDrop` is NOT a complete teardown path** (`DropDelegate` does not promise `dropExited` on an Esc-cancel while still over a row, and `.onDrag` has no cancel callback at OS 26), so the following are the required invalidation mechanisms, all mandatory:
- `dragGeneration` increments on every `.onDrag` start AND on every reset; the spring task and any deferred `performDrop` verification capture the generation at creation and no-op if it no longer matches.
- A single `resetDragState()` (nil the ID/proposal/session, cancel the spring task, bump the generation) is called from: `performDrop` (both commit and abort paths), `dropExited` when the session leaves the list, view `.onDisappear`, and `.onChange` of `store.isCheckMode` and `store.isTextInputActive`.
- Because a stale `dropProposal` can keep an indicator rendered after an unsignalled cancel, each row's indicator also self-suppresses when `draggedItemID == nil`.
- V2-5 (acceptance) is extended: Esc-cancel WHILE hovering a row, then immediately switch to Check Mode — no indicator remnants, no stray expansion fires, next drag works.

---

# STAGE 1 — Same-parent sibling reordering

## 5. Stage 1 implementation

### 5.1 Domain — new file `Sources/Domain/Tree/TreeEngineReorder.swift`

```swift
import Foundation

extension TreeEngine {

    /// Moves `itemID` under `newParentID` at `slot` within the target sibling
    /// group (slot counted with the moved item excluded; clamped to
    /// 0...group.count). Throws `TreeError` for self/cycle/cross-list/missing
    /// targets via `validateReparent`. Returns `items` unchanged (same array
    /// value) when the move is an identity — same parent, same resulting
    /// sibling order — so callers can no-op-guard exactly like indent does.
    public func reparent(
        itemID: UUID,
        toParent newParentID: UUID?,
        atSiblingSlot slot: Int,
        in items: [OutlineItem]
    ) throws -> [OutlineItem]

    /// Maps a flat-list `.onMove` (source row index, destination gap index in
    /// `visibleRows`) to a same-parent sibling reorder per D2. Returns nil
    /// for: invalid indices, identity moves, or anything else that should be
    /// a silent no-op. Never changes parentID.
    public func moveVisibleRow(
        at sourceIndex: Int,
        toVisibleDestination destination: Int,
        visibleRows: [FlatRow],
        in items: [OutlineItem]
    ) -> [OutlineItem]?
}
```

`moveVisibleRow` algorithm (D2, spelled out):
1. Guard `visibleRows.indices.contains(sourceIndex)` and `(0...visibleRows.count).contains(destination)`; else nil.
2. `let moved = visibleRows[sourceIndex]`; `let parentID = moved.item.parentID`.
3. `var ids = visibleRows.map(\.id)`; `ids.move(fromOffsets: IndexSet(integer: sourceIndex), toOffset: destination)` — this reuses Swift's own `.onMove` destination semantics instead of re-deriving them (off-by-one bugs die here).
4. `let groupIDs = Set(sortedSiblingGroup(of: moved.id, in: items).map(\.id))`; `let desiredOrder = ids.filter { groupIDs.contains($0) }`. Because search is disabled during drag (D5) and the moved item is visible, its parent is expanded, so *every* sibling is visible — `desiredOrder` is the complete group. (Roots are always all visible.)
5. `let newSlot = desiredOrder.firstIndex(of: moved.id)!`; if `newSlot` equals the item's current index in `sortedSiblingGroup` (which includes it), return nil (identity). Note the slot conventions differ: `reparent` counts slots with the item excluded — convert: `slotExcludingSelf = newSlot` (desiredOrder minus self, positions before it are unchanged since only one item moved; equivalently `desiredOrder.prefix(newSlot).count` of non-self items — they're all non-self).
6. `return try? reparent(itemID: moved.id, toParent: parentID, atSiblingSlot: newSlot, in: items)` — a same-parent reparent can only throw `itemNotFound`, which step 1–2 already precludes; `try?` documents the impossibility without crashing.

`reparent` algorithm:
1. `try validateReparent(itemID:newParentID:items:)` (`TreeEngine.swift:228-257`).
2. Build target group: `items.filter { $0.parentID == newParentID && $0.id != itemID }`, sorted by the canonical sort (position asc, uuidString tie-break — copy the comparator from `TreeEngine.swift:70-73`).
3. Clamp `slot` to `0...group.count`.
4. Identity check: if the item's current parent == `newParentID` and its current index within the *full* current group equals the index it would land at, return `items` as-is.
5. New position: empty group → `1.0`; slot 0 → `group[0].position − 1.0`; slot == count → `group.last!.position + 1.0`; else `midpoint(group[slot−1].position, group[slot].position)` (`TreeEngine.swift:266-268`).
6. Map items: set the moved item's `parentID`, `position`, `updatedAt = Date()`.
7. `return normalizeSiblingPositions(in: updated, parentID: newParentID)` (`TreeEngine.swift:286-309`) — and, when the parent changed, also normalize the *old* parent's group is unnecessary (removal never breaks that group's invariants; do not add it).

### 5.2 Store — `Sources/Features/Store/ListStore.swift`

Add one method next to `moveDown` (`:318-324`):

```swift
/// Handles a flat-list drag from `.onMove`. Same-parent clamp semantics
/// (spec D2). Refused/identity drags return silently: no undo entry, no
/// persistence, and SwiftUI animates the row back on its own.
public func moveRows(from source: IndexSet, to destination: Int, undoManager: UndoManager? = nil) {
    guard searchText.isEmpty, !isTextInputActive else { return }   // D5 defense-in-depth; keeps D9's invariant
    guard source.count == 1, let sourceIndex = source.first else {
        logger.debug("Drag move ignored: multi-index selection drags are not supported")
        return
    }
    guard let moved = engine.moveVisibleRow(
        at: sourceIndex,
        toVisibleDestination: destination,
        visibleRows: filteredRows,
        in: items
    ) else { return }
    let oldItems = items
    registerUndo(undoManager: undoManager, oldItems: oldItems)
    applyChanges(to: moved)
    persistInBackground(from: oldItems, to: moved)
}
```

No other store changes. Do not touch `registerUndo`/`teardownUndo` (`:444-468`).

### 5.3 View — `Sources/Features/Editor/OutlineEditorView.swift`

Two edits inside `outlineList` (`:117-151`):

1. On the row inside the ForEach body (the `outlineRow(row).tag(row.id)…` chain, before/after `swipeActions` — order irrelevant), add:
   `.moveDisabled(store.isTextInputActive || !store.searchText.isEmpty)`
2. On the `ForEach` itself (after the closing brace at `:139`), add:
   `.onMove { source, destination in store.moveRows(from: source, to: destination, undoManager: undoManager) }`

Do **not** attach anything to the add-field rows, do not restructure the ForEach, do not add gestures to `OutlineRowView` (its header comment at `OutlineRowView.swift:4-6` stays true). No toolbar changes, no menu changes, no new keyboard shortcuts.

### 5.4 Help — `Sources/Features/Help/ListsurfHelpView.swift`

Add one bullet to the editor section: macOS "Drag a row to reorder it among its siblings"; iOS "Touch and hold a row, then drag to reorder". Keep it to a sentence; the collapsible-section structure is already there.

## 6. Stage 1 testing

### 6.1 Unit tests — new file `Tests/DomainTests/TreeEngineReorderTests.swift`

Mirror `TreeEngineTests` conventions exactly (`Tests/DomainTests/TreeEngineTests.swift:4-23`): `XCTestCase`, shared `let engine = TreeEngine()`, `let listID = UUID()`, a `makeItem(id:parentID:title:isChecked:position:)` helper, string-literal fixtures only (no bundle resources — the xcodegen logic-test targets have no resource plumbing; same rule as M3 spec §10). Build visible rows via `engine.flatten(items:expandedIDs:)` so fixtures and mapper agree on order.

`reparent` tests:
1. `testReparentToNewParentAppendsAtSlot` — move a root under another root at slot 0 / mid / end; assert parentID, resulting sibling order, positions normalized-sane.
2. `testReparentToRootAtSlot` — child → `nil` parent at a given slot among roots.
3. `testReparentSubtreeTravelsIntact` — reparent an expanded parent; all descendants still under it, relative order preserved.
4. `testReparentIdentityReturnsUnchanged` — same parent, same resulting order → return value `==` input array (this is the no-op contract D4 depends on).
5. `testReparentSlotClampsOutOfRange` — slot −5 and slot 99 clamp to ends, no crash.
6. `testReparentSelfParentingThrows`, `testReparentOntoOwnDescendantThrows` (cycle), `testReparentCrossListThrows`, `testReparentMissingItemThrows` — assert the specific `TreeError` cases (`TreeEngine.swift:41-46`).
7. `testReparentMidpointExhaustionNormalizes` — craft sibling positions within `1e-10` (`needsRebalance`, `TreeEngine.swift:270-272`); assert displayed order preserved after normalize.

`moveVisibleRow` tests (fixture: roots A, B(children B1, B2), C — B expanded unless stated):
8. `testMoveDownWithinSiblings` / `testMoveUpWithinSiblings` — A↔C order changes; parentIDs untouched.
9. `testIdentityMoveReturnsNil` — destination == source and destination == source+1 both nil.
10. `testMoveAcrossCollapsedParentHopsSubtree` — B collapsed; drag A below B's row → order B, A, C (whole subtree hopped).
11. `testDropInsideOtherParentsChildrenClampsAdjacent` — drag A to the gap between B1 and B2 → A lands as root immediately after B (nearest legal slot), parentID still nil.
12. `testDraggedExpandedParentIntoOwnSubtreeIsNil` — drag B to the gap between B1 and B2 → nil (its root-sibling order didn't change).
13. `testMoveToListStartAndEnd` — destination 0 and `visibleRows.count`.
14. `testChildDraggedBeyondParentRegionClampsToOwnGroupEnds` — drag B1 above A → B1 becomes first child of B (clamped to slot 0 of its own group); drag B1 below C → last child of B.
15. `testInvalidIndicesReturnNil` — sourceIndex −1 / out of range; destination out of `0...count`.

### 6.2 Store tests — extend `Tests/FeaturesTests/` (new file `ListStoreMoveRowsTests.swift`, harness copied from `ListStoreUndoTests.swift:9-24`)

16. `testMoveRowsRegistersOneUndoStepAndRedoes` — drag, `undoManager.undo()` restores order, `canRedo` true, redo reapplies (mirrors `testUndoThenRedoRoundTripsAdd`).
17. `testIdentityMoveRegistersNoUndo` — after an identity drag, `undoManager.canUndo` is false (the no-op invariant).
18. `testMultiIndexSourceIsNoOp` — `IndexSet([0, 2])` → items unchanged, no undo.
19. `testMoveRowsRefusedWhileSearching` / `testMoveRowsRefusedWhileTextEntryActive` — set `searchText` / `addPlacement`; items unchanged.
20. `testMoveRowsPersists` — `await store.waitForPendingPersistence()`; repo state matches new order (pattern: `ListStorePersistenceTests`).

### 6.3 macOS UI test — `Tests/macOSUITests/Listsurf_macOSUITests.swift`

Add `testDragReordersSiblings`: `launchApp(store: "mac-drag-reorder", reset: true)`, `createList`, `addItem` × "Alpha", "Bravo", "Charlie"; then drag by title lookup (existing convention — `staticTexts["Charlie"]`):

```swift
let charlie = app.staticTexts["Charlie"]
let alpha = app.staticTexts["Alpha"]
charlie.click(forDuration: 0.3, thenDragTo: alpha)
```

Assert order by geometry: `charlie.frame.minY < app.staticTexts["Bravo"].frame.minY` (poll with `waitForExistence` first; frames after animation). Then `app.typeKey("z", modifierFlags: .command)` and assert the original order returns (undo through the real menu path). No new accessibility identifiers are needed — title-based `staticTexts` lookup is the file's existing convention (`:19-20`); do not add per-row identifiers speculatively. **All 6 existing macOS UI tests and 4 iOS UI tests must stay green.**

### 6.4 Manual verification (simulator + Mac, before review)

- V1-1 (iOS sim, drive via XcodeBuildMCP/axe): long-press-drag reorders; plain tap still selects (`RowSelectionTapModifier`); long-press-and-hold still opens the context menu; swipe-delete still works. This is the gesture-precedence check: tap < long-press-hold (menu) < long-press-drag (move) < swipe.
- V1-2 (macOS): click-drag reorders with native insertion line; click still selects; ⇧/⌘-click multi-select intact; double-click rename intact; right-click menu intact.
- V1-3: drag a collapsed parent — subtree hops as one unit; drag an expanded parent between its own children — snaps back (no-op); relaunch the app — order persisted.
- V1-4 (**D10 gate**): with `.onMove` attached, click latency on the disclosure chevron, ellipsis menu, trash button, and double-click rename is imperceptibly different from a pre-Stage-1 build. If it regresses perceptibly, apply the D10 contingency and re-verify.
- V1-5: with two rows selected (macOS), dragging does nothing destructive (no-op per D6).
- V1-6: while the add field is open or a rename is active, rows cannot be dragged; while searching, rows cannot be dragged.
- V1-7: drag on the large fixture (1,000 items / 10 levels, plan §Performance) does not stutter unacceptably.

## 7. Stage 1 acceptance criteria

1. On macOS and iOS, a row can be dragged up/down within its sibling group; the reorder persists across relaunch.
2. A drag crossing a parent boundary lands at the nearest legal same-parent slot; `parentID` never changes in Stage 1 (assert via export or repo inspection during review).
3. One ⌘Z undoes exactly one completed drag; redo works; identity/refused drags consume no undo step.
4. No interaction regression on either platform (V1-1/V1-2/V1-4).
5. `swift test` green (including ≥ 20 new tests above); both xctestplans green including the new macOS UI test; both app targets build.
6. Devlog entry written; Help updated.

## 8. Stage 1 td task breakdown (create under epic `td-0f2c1a`; sized for implementer execution)

| # | Title | Depends on | Verify by | Size |
|---|-------|-----------|-----------|------|
| M4-S1-1 | Domain: `TreeEngineReorder.swift` — `reparent` + `moveVisibleRow` (§5.1) | — | `TreeEngineReorderTests` 1–15 green via `swift test` | M |
| M4-S1-2 | Store: `ListStore.moveRows` (§5.2) + `ListStoreMoveRowsTests` 16–20 | M4-S1-1 | new Features tests green | S |
| M4-S1-3 | View: `.onMove` + `.moveDisabled` wiring (§5.3) + Help line (§5.4) | M4-S1-2 | manual V1-1…V1-3, V1-6 | S |
| M4-S1-4 | macOS UI test `testDragReordersSiblings` (§6.3) + full verification pass (V1-1…V1-7, `swift test`, both xctestplans, both builds) + devlog | M4-S1-3 | acceptance criteria §7; D10 contingency applied only if V1-4 fails | M |

Then: review (hostile-review loop as per project workflow), TestFlight build, dogfood. **Stage 2 does not start until §9 passes.**

---

# CHECKPOINT — Stage 2 go/no-go checklist

## 9. What dogfooding must confirm before Stage 2 begins

Record answers in the devlog; any "no" blocks Stage 2 and goes back to the planner.

- **G1 — Data integrity**: after several days of real use on both platforms, no misplaced rows, no lost items, order after relaunch always matches the last drag (spot-check with a JSON export before/after a session).
- **G2 — No interaction regressions in daily use**: rename double-click, chevron, ellipsis, swipe, context menus, arrow-key navigation all feel identical to pre-Stage-1. If D10's contingency was applied, confirm it feels natural.
- **G3 — Undo trust**: undo/redo of drags behaved correctly every time it was used in anger.
- **G4 — Suite health**: full test suite + both UI plans green on the shipped Stage 1 commit; TestFlight build actually dogfooded (not just uploaded).
- **G5 — Clamp verdict**: does the D2 clamp feel like help or like a bug? (Either answer is fine — Stage 2 removes the limitation — but if it confused the user, prioritize Stage 2's indicator work and say so in the Stage 2 kickoff note. If it caused *wrong-looking data*, that's a G1 failure instead.)
- **G6 — Platform check**: minimum OS still iOS 26/macOS 26 and no relevant new API shipped? If the floor moved to 27, return to the planner to reconsider D11 against `reorderable()`/`dragContainer` before building S2-2+.
- **G7 — Appetite**: confirm Stage 2 is still wanted next (vs. Milestone 5 run-lifecycle). It's the hardest UI work in the app; sequencing is the user's call.

---

# STAGE 2 — Reparenting drag with insertion indicator and depth targeting

## 10. Stage 2 implementation

### 10.1 S2-1 — Mandatory spike (timeboxed; throwaway branch)

Build a minimal harness *inside the real editor list* (behind a temporary local branch, not merged): `.onDrag` on rows returning a title `NSItemProvider`, `.onDrop(of: [.plainText], delegate:)` per row with a delegate that records `dropUpdated` locations and draws a plain top/bottom-edge overlay line. Pass criteria — all must hold on **both** platforms:

1. `dropUpdated(info:)` fires continuously with usable `location` while hovering a row inside `List` (macOS `.sidebar` style; iOS default), and top/bottom-half detection is stable.
2. The overlay line renders between rows without breaking row layout, selection painting, or swipe actions.
3. Native auto-scroll occurs when hovering near the list's top/bottom edges during the drag (else: D22 fallback is confirmed feasible in the same spike).
4. Row-control click latency on macOS with `.onDrag` attached passes the V1-4 bar (same test as Stage 1; `.onDrag` uses a different recognizer than `.onMove` — measure, don't assume).
5. iOS: long-press lifts the row for drag while long-press-hold still opens the context menu, and tap-select still works.

(Rev 2 — the architecture mutates the List's row set DURING an active drag; a static-list spike would pass and Stage 2 could still fail deep in. These are architecture gates, not polish:)

6. Collapse-on-pickup: remove an expanded parent's descendant rows at drag start (simulating D17) while the pointer stays down — the drag session survives, remaining rows' delegates keep receiving `dropUpdated`.
7. Expansion-during-hover: insert rows mid-drag (simulating D16) — the newly created rows' drop delegates function, and `DropInfo.location` remains coherent for rows above and below the insertion.
8. Cancellation-while-over-a-row: Esc (macOS) / system cancel (iOS) with the pointer still inside a row — record exactly which delegate callbacks fire (expect possibly none); confirm the D23 reset mechanisms can clear the overlay without relying on `dropExited`.
9. Auto-scroll still functions after a mid-drag expansion changed the content height (re-run criterion 3 post-mutation).

**If any criterion fails on either platform: stop, write findings to the devlog, return to planning (D11). Do not improvise.** If all pass: record the observed coordinate spaces/quirks in the devlog and proceed.

### 10.2 Domain — extend `Sources/Domain/Tree/TreeEngineReorder.swift`

```swift
public enum OutlineDropEdge: Equatable, Sendable { case above, below }

/// A fully resolved drop proposal. `parentID`/`siblingSlot` are the commit
/// coordinates (UUIDs and slots — never flat indices); `indicatorDepth`/
/// `anchorRowID`/`anchorEdge` are the rendering coordinates.
public struct OutlineDropTarget: Equatable, Sendable {
    public let parentID: UUID?
    public let siblingSlot: Int      // counted with the dragged item excluded
    public let indicatorDepth: Int
    public let anchorRowID: UUID
    public let anchorEdge: OutlineDropEdge
    public init(parentID: UUID?, siblingSlot: Int, indicatorDepth: Int,
                anchorRowID: UUID, anchorEdge: OutlineDropEdge)
}

extension TreeEngine {
    /// Resolves the gap below visibleRows[gapIndex] (nil = the gap above the
    /// first row) at `requestedDepth` into a drop target, clamping the depth
    /// into the gap's legal range (D13) and skipping depths whose parent
    /// would be the dragged item or one of its descendants. Returns nil when
    /// no depth in the gap is legal (forbidden proposal).
    public func dropTarget(
        draggedID: UUID,
        gapBelowVisibleIndex gapIndex: Int?,
        requestedDepth: Int,
        visibleRows: [FlatRow],
        items: [OutlineItem]
    ) -> OutlineDropTarget?
}
```

Algorithm (D13, spelled out):
1. Compute `forbidden = Set(descendants(of: draggedID, in: items).map(\.id)).union([draggedID])` (callers may hover many times per second — it is fine to recompute; if profiling ever objects, the *view* caches it per session, not the engine).
2. `gapIndex == nil`: the only candidate is depth 0, parent nil, slot 0, anchor = first row, edge `.above`. (Empty list: no rows → no drops; the view never asks.)
3. Else `G = visibleRows[gapIndex]`, `N = visibleRows[safe: gapIndex + 1]`; `maxDepth = G.depth + 1`, `minDepth = N?.depth ?? 0`.
4. Candidate depths, ordered by distance from `clamp(requestedDepth, minDepth...maxDepth)` (nearest-first, preferring the shallower on ties): for each depth `d`:
   - `d == G.depth + 1`: parent = `G.id`, slot 0. Illegal if `forbidden.contains(G.id)`.
   - `d ≤ G.depth`: walk G's ancestor chain (`ancestorIDs(of:in:)`, `TreeEngine.swift:212-224`, prepend G itself) to find `A`, the ancestor-or-self of G whose depth == `d` (compute depths from `visibleRows`/parent chain, not by trusting indices). Parent = `A.parentID`. Illegal if parent is in `forbidden`. Slot: **(Rev 2 — the A == draggedID case was undefined: A has no index in a group that excludes it, and naive handling either crashes, force-rejects, or lands one slot low.)**
     - If `A.id != draggedID`: slot = (index of `A` within `parentID`'s sibling group with the dragged item excluded) + 1 — "insert immediately after A".
     - If `A.id == draggedID` (hovering the dragged row's own gap at its own depth): slot = the count of **non-dragged** members of the sibling group that precede A in the ORIGINAL canonical order — **no +1**. This is the identity-adjacent proposal ("stay where you are"); `reparent`'s identity guard (step 4) turns the commit into a no-op with no undo registration.
5. First legal candidate wins: `OutlineDropTarget(parentID:…, siblingSlot:…, indicatorDepth: d, anchorRowID: G.id (or first row), anchorEdge: .below (or .above))`. None legal → nil.

Commit path reuses Stage 1's `reparent` unchanged.

### 10.3 Store — `Sources/Features/Store/ListStore.swift`

```swift
/// Non-toggle expansion setter (spring-loading and drop-reveal need
/// idempotent semantics; `toggleExpanded` is for the chevron).
public func setExpanded(_ id: UUID, _ expanded: Bool) {
    if expanded { expandedIDs.insert(id) } else { expandedIDs.remove(id) }
    rebuildRows()
}

/// Commits a reparenting drop. Identity drops and validation failures
/// mutate nothing and register no undo entry.
public func performDrop(itemID: UUID, target: OutlineDropTarget, undoManager: UndoManager? = nil) {
    guard searchText.isEmpty, !isTextInputActive else { return }
    do {
        let oldItems = items
        let moved = try engine.reparent(
            itemID: itemID, toParent: target.parentID,
            atSiblingSlot: target.siblingSlot, in: items
        )
        guard moved != oldItems else { return }              // no-op ⇒ no undo (ListStore.swift:330-335 pattern)
        if let parentID = target.parentID { expandedIDs.insert(parentID) }
        registerUndo(undoManager: undoManager, oldItems: oldItems)
        applyChanges(to: moved)                              // applyChanges rebuilds rows; insert expandedIDs BEFORE it
        persistInBackground(from: oldItems, to: moved)
        Haptics.dropCompleted()
    } catch {
        logger.warning("Drop rejected by engine: \(error.localizedDescription)")
    }
}
```

(Note: `expandedIDs.insert` must precede `applyChanges` so the single `rebuildRows` sees it; match the `addChild` ordering at `ListStore.swift:262-267`. Remove `moveRows` per D20.)

### 10.4 Platform — `Sources/Platform/Haptics.swift`

Add `dragPickup()` (medium impact) and `dropCompleted()` (light impact), `@MainActor`, `#if os(iOS)` bodies, exactly in the style of `checkToggle` (`Haptics.swift:7-14`). Platform still imports no Domain.

### 10.5 View — `Sources/Features/Editor/OutlineEditorView.swift`

Remove Stage 1's `.onMove`/`.moveDisabled`. Add (all view-local per D23):

```swift
@State private var draggedItemID: UUID?
@State private var dragStartDepth = 0
@State private var dragReferenceX: CGFloat?
@State private var dropProposal: OutlineDropTarget?
@State private var springLoadTask: Task<Void, Never>?
```

Per row (inside the ForEach body, on the `outlineRow(row)` chain):

- **Drag source** — inert under the D5 predicates:
  ```swift
  .onDrag {
      guard !store.isTextInputActive, store.searchText.isEmpty else { return NSItemProvider() }
      draggedItemID = row.id
      dragStartDepth = row.depth
      dragReferenceX = nil
      if row.isExpanded { store.setExpanded(row.id, false) }   // D17
      Haptics.dragPickup()                                     // D19
      return NSItemProvider(object: row.item.title as NSString) // D12: title for external drops; never parsed locally
  }
  ```
  (Returning an empty provider when gated: `.onDrag` cannot conditionally detach; an empty provider plus a nil `draggedItemID` makes every drop target refuse — verify in S2-1 that this reads as "drag doesn't start / does nothing".)
- **Drop target**: `.onDrop(of: [.plainText], delegate: OutlineRowDropDelegate(rowID: row.id, rowDepth: row.depth, callbacks…))` — a small struct in `OutlineEditorView.swift` (or a sibling file `OutlineDragDrop.swift` in `Sources/Features/Editor/`) whose callbacks close over the view's state and `store`. Responsibilities:
  - `validateDrop`: `draggedItemID != nil && store.items.contains(where: { $0.id == draggedItemID })` (D12 — rejects external and cross-list drags).
  - `dropUpdated`: derive `edge` from `info.location.y` vs row midheight; `gapIndex` = this row's index in `store.filteredRows` (edge `.below`) or index − 1 / nil-for-first-row (edge `.above`); list-space x = `info.location.x + CGFloat(rowDepth) * 20`; set `dragReferenceX` on first call; `requestedDepth = dragStartDepth + Int(round((x − dragReferenceX!) / 20))`; call `engine.dropTarget…` **via a store-exposed helper** `store.dropTarget(draggedID:gapBelowVisibleIndex:requestedDepth:)` (one-liner forwarding to the engine with `filteredRows`/`items` — keeps the engine and item snapshot access in the store, views never import the engine); publish to `dropProposal`; manage the spring-load task (D16: proposal is nest-depth on a collapsed `hasChildren` row → start 0.7 s task → `store.setExpanded(G.id, true)`; any other proposal cancels it). Return `.move` or `.forbidden` (D15).
  - `dropExited`: clear `dropProposal` if it anchors this row; cancel the spring-load task.
  - `performDrop`: `guard let id = draggedItemID, let target = dropProposal else { return false }`; `store.performDrop(itemID: id, target: target, undoManager: undoManager)`; clear all drag state; return true.
- **Indicator** (D14): on each row, `.overlay(alignment: …)` rendering the accent line when `dropProposal?.anchorRowID == row.id`, with relative offset `(dropProposal.indicatorDepth − row.depth) * 20`; edge from `anchorEdge`.

Stale-state hygiene (D23 + §2.6): a cancelled drag leaves `draggedItemID` set. This is harmless — it is overwritten at the next `.onDrag` and only ever *enables* proposals for an ID that still exists in `store.items` — but the indicator must not linger: `dropProposal` is cleared by `dropExited`/`performDrop`, and additionally clear all drag state in `.onChange(of: store.filteredRows.map(\.id))`-adjacent events? **No — keep it simple**: `dropExited` + `performDrop` clearing is sufficient because the indicator only renders while a proposal exists, and proposals die on exit. Do not add speculative cleanup hooks.

### 10.6 Help

Update the Stage 1 bullets: macOS "Drag rows to reorder; drag right while dragging to nest under the row above, left to un-nest"; iOS equivalent with touch-and-hold phrasing.

## 11. Stage 2 testing

### 11.1 Unit tests — extend `Tests/DomainTests/TreeEngineReorderTests.swift`

Fixture (string-literal, flatten-derived visible rows): roots A, B(B1, B2(B2a)), C; expansion varied per test.

1. `testGapBelowExpandedParentNestDepth` — gap below B at depth B+1 → parent B, slot 0.
2. `testGapBelowExpandedParentSiblingDepth` — same gap at depth of B → parent nil, slot after B.
3. `testGapAtSubtreeEndOffersDepthLadder` — gap below B2a (deepest, next row C at depth 0): every depth 0…3 maps to the correct ancestor-adjacent (parent, slot) pair.
4. `testGapAboveFirstRow` — `gapIndex: nil` → root slot 0, edge `.above`.
5. `testEndOfListRange` — gap below last row: `minDepth` 0, `maxDepth` last.depth + 1.
6. `testRequestedDepthClampsBothDirections` — requested −3 and +9 clamp into range.
7. `testNestUnderDraggedItselfIsSkipped` — gap below the dragged row: nest depth (parent = dragged) skipped, nearest legal depth returned instead.
8. `testNestUnderOwnDescendantForbidden` — drag B, gap below B2 (B expanded) where every candidate parent is B or a descendant → nil.
9. `testCollapsedParentNestSlotZero` — nest into collapsed B → slot 0 (before its hidden children).
10. `testSlotCountingExcludesDraggedItem` — drag A to sibling-depth gap just below A → slot equals A's own slot → `reparent` identity → unchanged array.
10a. (Rev 2) `testOwnGapSlotWhenDraggedIsFirstSibling` / `10b. …MiddleSibling` / `10c. …LastSibling` — the A == draggedID slot formula (§10.2 step 4): for each position, hovering the dragged row's own below-gap at its own depth yields slot = count of non-dragged preceding siblings (no +1), no crash, no force-reject, and the commit is an engine identity no-op with zero undo registrations.

### 11.2 Store tests — new file `Tests/FeaturesTests/ListStorePerformDropTests.swift`

11. `testPerformDropReparentsAndExpandsTarget` — item lands under new parent; `expandedIDs` contains parent; visible in `flatRows`.
12. `testPerformDropUndoRestoresParentPositionSelection` — one undo step; redo works (mirror `ListStoreUndoTests`).
13. `testIdentityDropRegistersNoUndo`.
14. `testEngineRejectionMutatesNothing` — forged cycle target: items unchanged, `canUndo` false.
15. `testPerformDropRefusedDuringSearchOrTextEntry`.
16. `testPerformDropPersists` — repo state matches after `waitForPendingPersistence()`.

### 11.3 macOS UI test

`testDragNestsUnderSibling`: create list; add "Parent Row", "Child Candidate"; drag "Child Candidate" onto the lower half of "Parent Row" **with a rightward offset** using coordinate drags (`element.coordinate(withNormalizedOffset:)` → `press(forDuration:thenDragTo:)` on coordinates — plain element-to-element drags can't express the horizontal component). Assert nesting via the parent's new trailing leaf-progress text `"0/1"` (`OutlineRowView.swift:90-96`) and the appearance of a disclosure chevron. Then ⌘Z and assert `"0/1"` disappears. If coordinate-drag proves too flaky after honest effort (>2 stabilization attempts), keep the test for sibling reorder only, document the gap in the devlog, and rely on V2 manual items — do not ship a flaky test. All prior UI tests stay green.

### 11.4 Manual verification

- V2-1 (both platforms): indicator appears between rows, indented correctly at every depth of a 4-level list; dragging right/left walks the depth ladder one 20 pt step per level.
- V2-2: drop as child of a collapsed parent — spring-load expands after ~0.7 s hover; drop before dwell completes still nests correctly (slot 0) and the parent expands on drop.
- V2-3: attempt to drop a parent into its own subtree — macOS shows the prohibition cursor, no indicator; releasing does nothing; no undo step consumed.
- V2-4: drag an expanded parent — it collapses on pickup; subtree intact after drop wherever it lands.
- V2-5: cancel a drag (Esc on macOS / drop outside on iOS) — no indicator remnants, next drag works, no data change.
- V2-6: auto-scroll during drag at both list edges (D22; if fallback was built, verify the 0.4 s dwell nudge).
- V2-7: gesture precedence re-run (Stage 1's V1-1/V1-2 list) — tap, menus, swipe, rename, keyboard nav all intact with `.onDrag`/`.onDrop` attached.
- V2-8: undo/redo a chain: reorder → nest → un-nest → ⌘Z ×3 → ⌘⇧Z ×3; tree correct at every step.
- V2-9: iOS haptics fire on pickup and drop (physical device if available; else note as TestFlight-verify).
- V2-10: large-fixture drag hover performance (dropTarget runs per `dropUpdated` — must not stutter on 1,000 items; if it does, cache the forbidden-descendants set per drag session in the view, per §10.2 note).

## 12. Stage 2 acceptance criteria & td breakdown

Acceptance: V1-plan §Drag-and-Drop Feedback honored as reconciled in §3; plan line 560's UI-test criterion met ("drag within a sibling group and into/out of a parent with correct insertion indicators"); all §11 tests green; existing suites green; no Stage 1 dead code remains (D20); devlog written.

| # | Title | Depends on | Verify by | Size |
|---|-------|-----------|-----------|------|
| M4-S2-1 | **Spike**: per-row DropDelegate in List, both platforms, pass criteria §10.1 (timebox; findings → devlog; STOP on failure) | checkpoint §9 | all 5 spike criteria recorded | M |
| M4-S2-2 | Domain: `OutlineDropTarget` + `dropTarget` (§10.2) + tests 1–10 | M4-S2-1 | `swift test` | M |
| M4-S2-3 | Store/Platform: `performDrop`, `setExpanded`, `dropTarget` forwarder, haptics (§10.3–10.4) + tests 11–16 | M4-S2-2 | `swift test` | S |
| M4-S2-4 | View: remove `.onMove`+`moveRows`+`moveVisibleRow` (D20); `.onDrag`/`OutlineRowDropDelegate`/indicator overlay (§10.5) | M4-S2-3 | manual V2-1, V2-3, V2-5, V2-7 | L |
| M4-S2-5 | Spring-load expand, auto-collapse-on-pickup, auto-scroll verification (+D22 fallback only if S2-1 required it), Help (§10.6) | M4-S2-4 | manual V2-2, V2-4, V2-6 | M |
| M4-S2-6 | macOS UI test `testDragNestsUnderSibling` + full verification pass (V2-1…V2-10, `swift test`, both xctestplans, both builds) + devlog | M4-S2-5 | acceptance above | M |

---

## 13. Non-goals & guardrails (both stages — do NOT do these)

- **No cross-list drag** (no drop targets on sidebar rows; drop delegates reject unknown IDs per D12). Moving items between lists is a different feature with its own UX.
- **No drag in check mode** (`CheckModeView` gets no drag modifiers) and **no archive editing** (structurally impossible today — leave it so).
- **No multi-item drag** in either stage (D6/D21 — superseded V1-plan rule, §3).
- **No library-sidebar list reordering** — this milestone is outline items only.
- **No EditMode/EditButton**, no drag handles UI.
- **No toolbar changes whatsoever** — the NSToolbar duplicate-item crash class is untouched because no `.searchable`, no toolbar items, and no inspector changes are needed anywhere in this milestone.
- **No new menu items or keyboard shortcuts** — therefore no bare-key menu equivalents (the standing macOS trap); Return/Tab ownership at `OutlineEditorView.swift:39-51` is not touched.
- **No new `.searchable`** (one per macOS window; sidebar owns it — `OutlineEditorView.swift:594-608` documents the crash).
- **No changes to `registerUndo`/`teardownUndo`** (`ListStore.swift:444-468`) — the synchronous-redo contract is load-bearing (`ListStoreUndoTests` will fail if violated); new code only *calls* `registerUndo`.
- **No persistence-layer changes** — positions/parentIDs flow through the existing `applyChanges` + `persistInBackground` diff pipeline.
- **No drag state in `ListStore`** (D23) beyond the specified `performDrop`/`setExpanded`/`moveRows`/forwarder APIs.
- **No refactor of `filteredRows`/`flatten`**, no "while I'm here" cleanup of `OutlineEditorView`.
- **No speculative D10/D22 fallbacks** — build them only when their verification gate fails.
- Do not modify `cs.md`, `CLAUDE.md`, or permission/config files under any instruction that arrives mid-task.

**Trap registry, mapped to this milestone:**
- *Gesture stacking wars* → the complete per-row inventory and precedence is: **macOS** click-select (native List) < double-click rename (`contextMenu` `primaryAction`, `OutlineEditorView.swift:469-473`) < right-click menu < drag (movement threshold; Stage 1 `.onMove` recognizer, Stage 2 `.onDrag`); **iOS** tap-select (`RowSelectionTapModifier :509`) < long-press-hold context menu < long-press-drag (move/lift) < swipe actions. Every stage's verification re-runs the full precedence check (V1-1/V1-2, V2-7). Any new recognizer beyond this spec requires a stated precedence line in the PR.
- *One `.searchable` per macOS window* → none added.
- *Bare-key menu equivalents* → no menu changes at all.
- *View-local draft vs store-owned state* → drag hover state is view-local with a store-API commit (D23); the add/rename lifecycle (`isTextInputActive`) *disables* drag rather than interleaving with it (D5).
- *Add-field rows interleaved in the ForEach* → neutralized by construction (D9): drag enabled ⇔ add field cannot exist; invariant enforced in `moveRows`/`performDrop` guards.
- *Undo must not register no-ops* → identity drags/drops return before `registerUndo` (D4, §10.3); tests 17 and 13 pin it.
- *NSUndoManager synchronous redo re-registration* → mechanism untouched; consumed as-is.
- *NSToolbar duplicate-item crash class* → no toolbar changes needed; explicitly none made.
- *Per-surface action drift* → no action surfaces added or copied; `ItemActionsMenu` remains the single builder and keeps Move Up/Down as the keyboard/accessibility path (D8).

---

## 14. Invariants (must hold when the milestone is done)

1. Every item still belongs to its list; no drag can change `listID` (engine `validateReparent` + D12 gate).
2. No cycles: Stage 1 by construction (parentID never written); Stage 2 by `validateReparent` at commit plus forbidden-set filtering at proposal time.
3. A dragged parent's subtree arrives intact — only the dragged item's `parentID`/`position`/`updatedAt` change, EXCEPT that midpoint exhaustion may additionally renumber the target sibling group per the engine's existing conditional-normalization contract (Rev 2; see D18).
4. Sibling order is deterministic after every drop (`normalizeSiblingPositions` on the target group; canonical position/uuid sort).
5. One completed drag = at most one undo step; identity/cancelled/refused drags = zero steps; redo always available immediately after undo.
6. Every reorder/reparent reaches Core Data through the existing queued pipeline; kill-and-relaunch after a drag always shows the dropped state.
7. Drag is never the only way to do anything (D8): Move Up/Down, Indent/Outdent buttons, menus, and shortcuts remain fully functional.
8. The pre-existing UI test suites pass unmodified (except the additions specified here).
