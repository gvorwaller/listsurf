# M5 — Unified Editor UX Overhaul (macOS-first) — Implementation Spec

**Rev 2.5 (2026-07-14).** (2.5: Phase 2 gains iOS double-tap → Details — td-ee5174, Gaylon request — and gate M2 gains the iOS scroll-to-top shake/title check, td-ef3eec: the toolbar/title rebuild may cure it; if not, stop and report rather than patch blind.) (2.2: D10 hover state moved row-local; Phase 1 gains item 6, the indent()-collapses-item bug. 2.4, after Gate M1 failed and four gating designs were falsified empirically: **D10 hover-gated drag arming is RETIRED** — macOS List reads `.moveDisabled` only from the ForEach's direct content and only at diff time; no hover-driven runtime flip can arm a row without risking the in-flight drag session. Drag is armed at rest as M4 shipped; `blocked` terms (text entry, search, multi-selection) are editor-computed and work. B1 click latency is re-judged at the gate and investigated on its own evidence if it regresses. Also from Gate M1 diagnostics: editor-level Escape fallback (field Escape is focus-dependent and the deferred-focus window can eat it), ⇧Tab arrives as backtab U+0019 and needs explicit matching, and clicking the already-selected row cannot dismiss the add flow via selection-change — Escape is that story until Phase 2 revisits.) (2.1 folds in Gaylon's prototype-testing notes: iOS keyboard-dismiss affordance, iOS undo exposure check, platform-scoped help.) Baseline: commit `b9a87a1` (M4 Stage 1 shipped; 192 unit tests, 7 macOS + 5 iOS UI tests green). Planner: Fable (research + design agent), coordinated by CC2. Executor: implementer agent — everything needed is here; `cs.md` rules override defaults. Decisions are final unless marked as an open question; stop-and-report on any spec/code conflict.

**Rev 2.6 (2026-07-16, post-CODEX2 adversarial plan review).** (a) **Gate policy replaced** — see §5 intro: per-phase manual gates are retired in favor of automated-suites-per-phase plus ONE integrated manual/device gate at feature-complete (Gaylon cannot usefully gate intermediate states against the finished prototype). (b) **Phase 2 is not complete**: §1.6(a) keyboard-dismiss shipped missing (td-6a9f9d), §1.6(b) iOS Undo was never phase-assigned (td-d27ad4, semantics now locked in that issue), the prototype's bounded scrollable notes editor contradicted "inspector unchanged" (td-cf54fb, both platforms), and `ListsurfSettingsView.swift:68` still says "edit and check mode" — Settings joins the zero-remnants sweep. All folded into td-a6b856. (c) **CommandCatalog must carry an exact ID inventory** including help-only native entries (navigation arrows, Escape, Settings ⌘,) with a set-equality test — see §3. (d) **Gate M4's "diff against the Item menu" replaced** by an action-to-surface parity matrix — see §5. (e) **Gate M2 gains explicit device gesture steps** (drag, swipe-delete, drag-vs-context-menu arbitration) and an iOS add-field-position test — the §1.6(c) load-bearing behavior had no test. (f) **§6's line numbers are stale** (e.g. OutlineEditorView is 734 lines, not 617; handleReturnKey at :498; focusedCommandActions at :221) — treat the map's deltas as indicative, never navigate by its line numbers. (g) All §2/§5/§7 text presenting hover-gated drag as current design is historical — Rev 2.4's retirement stands; drag is armed at rest. (h) Open question added to §5 Phase 4: iOS help shortcut sentence vs §1.6's no-advertising rule.

**Rev 2.7 (2026-07-17).** td-40102b RESOLVED — Gaylon, after re-reviewing the prototype: the keyboard legend is **adopted, built in Phase 4** ("useful for new users, and can be hidden"). macOS-only toggleable legend generated from `CommandCatalog.macKeyboardHelp`, keys highlight as used — see the Phase 4 section for the design contract. The legend's own toggle command joins the catalog, `expectedIDs`, the parity matrix, and Help.

**Fixed user decisions**: (1) unify edit/check modes into one outline view; (2) Things 3 is the feel benchmark; (3) **Return on a selected row = rename in place**.

**A UI prototype gate precedes Phase 1**: an interactive HTML prototype of this spec's interaction model (macOS + iOS) must be approved by Gaylon before any code is written. If the prototype changes decisions here, this spec is revised first.

## 0. Things 3 research — what we borrow and what we deviate from

Verified against Cultured Code's official shortcut reference ([Keyboard Shortcuts for Mac](https://culturedcode.com/things/support/articles/2785159/), [All Things Speed](https://culturedcode.com/things/blog/2021/10/all-things-speed/)):

| Things 3 behavior | Listsurf disposition |
|---|---|
| **Return opens the selected item for editing**; Esc saves/closes | **Borrowed** — Return = rename in place. Esc cancels, Return/click-away commits (today's rename-field semantics). |
| **⌘N creates a new to-do**; ⇧⌘N creates a new project | **Borrowed** — ⌘N = New Item (below selection, root if none). New List moves to ⇧⌘N (list ≈ Things project — the parallel is exact). |
| **⌘K completes the selected item(s)**, works on multi-selection | **Borrowed** — ⌘K = Toggle Checked (menu-visible equivalent of Space). Multi-selection supported. |
| **Space creates a new to-do below selection** | **Deviated deliberately** — Decision 1 fixes Space = toggle check (checklist muscle memory; Things' capture role goes to ⌘N). |
| Arrows navigate; ⇧-arrows extend selection | Already native via `List(selection:)` — untouched (the 2026-07-09 refactor is load-bearing). |
| ⌘]/⌘[ indent/outdent | Already matches. |
| ⌘↑/⌘↓ moves items | **Not adopted** — Listsurf keeps ⌘⌥↑/↓ (established, documented; ⌘↑/↓ collides with scroll-to-top/bottom conventions). |
| Esc collapses/saves the open item | Borrowed shape: Esc cancels text entry; **new**: Esc with no text entry active clears the selection. |
| Type Travel / type-to-search | **Not adopted**; type-to-rename **rejected**: conflicts with Space/⌘-key handling, and the editor cannot own a `.searchable` (NSToolbar single-search trap). Rename = Return / ⌘E / double-click / menu. |

## 1. Target interaction spec (the contract — every input, decided)

All rows always show: disclosure chevron · **checkbox** · title/notes · quantity/notes-glyph/leaf-progress · ellipsis menu · trash. One `List(selection:)`, one toolbar, one filter control. No modes.

### 1.1 Pointer (macOS)

| Input | Behavior |
|---|---|
| Click row (outside controls) | Native selection (single/⌘/⇧ multi — untouched). |
| Click checkbox | Toggles that row's branch check (existing `toggleCheck` semantics: parent toggles subtree; tri-state `mixed` renders `minus.circle.fill` orange). Does **not** change selection. |
| Double-click title | Rename in place (existing `contextMenu primaryAction` — kept; consistent with Return). |
| Right-click | Selection context menu (`ItemActionsMenu`, hints on). Right-click on an unselected row natively selects it first. |
| Click-drag a row | Reorder (M4 Stage 1) — armed at rest (hover gating retired, Rev 2.4); never lifts when the row is part of a multi-selection (B6 fix), during text entry, or while searching. |

### 1.2 Keyboard (macOS) — final map

| Key | Behavior | Owner |
|---|---|---|
| ↑/↓, ⇧-arrows, ⌘/⇧-click | Navigate/extend selection | Native List (untouched) |
| **Return** | Single selection → **rename in place**. **No selection → begin add at root** (quick capture on a fresh list stays one key; cannot collide with rename, which requires a selection). Multi-selection → `.ignored`. While the add field is armed: commits and re-arms (continuation typing — unchanged, field `onSubmit`). While renaming: commits (field `onSubmit`). | Editor `.onKeyPress`, gated `!isTextInputActive` |
| **Esc** | Cancels rename/add (field-owned, unchanged). New: with no text entry active, clears selection if non-empty, else `.ignored`. | Field / Editor |
| **Space** | Toggles check of all selected rows (rule §1.3). Gated: `.ignored` when `isTextInputActive` or selection empty (Space then does its list-scroll default). | Editor `.onKeyPress` |
| **⌘N** | New Item — arms add field below selection (root if none). | Item menu |
| **⇧⌘N** | New List (remapped from ⌘N). | File menu |
| **⌥⌘N** | Add Item Above — inserts above selection and renames it (today's ⇧Return behavior, rehomed). Bare ⇧Return is **dropped**. | Item menu |
| **⌘Return** | Add Child (unchanged). | Item menu |
| **⌘E** | Rename — the menu-visible equivalent of Return (bare keys cannot be menu equivalents). Routes through `listCommands.rename` (live-read, single selection). Free because ⇧⌘E is retired. | Item menu |
| **Tab / ⇧Tab** | Indent / outdent selection (unchanged). | Editor `.onKeyPress` |
| **⌘] / ⌘[** | Indent / outdent (unchanged bindings, **B3-fixed routing**: act on the live selection). | Item menu |
| **⌘K** | Toggle Checked (menu-visible twin of Space; works on multi-selection). | Item menu |
| **⌘⌥↑ / ⌘⌥↓** | Move among siblings (unchanged). | Item menu |
| **⌘⌫** | Delete selection after confirmation (unchanged). | Item menu |
| **⌥⌘1 / ⌥⌘2 / ⌥⌘3** | Filter All / Remaining / Completed. | View menu |
| **⌥⌘I** | Inspector (unchanged). **⇧⌘E is retired** — deliberately unassigned. | View menu |
| ⌘Z/⇧⌘Z, ⌘?, ⌘, | Unchanged (Settings scene provides ⌘, automatically — `App/ListsurfApp.swift:52-57`). | System/App |

**Return collision sanity (verified):** (a) any focused TextField (add/rename/sidebar search/inspector notes) consumes Return before the editor handler — the `!isTextInputActive` guard is defense-in-depth; (b) SwiftUI's macOS `List` binds no default Return action; the row `contextMenu primaryAction` fires only on double-click; (c) confirmation dialogs present modally — Return there activates the dialog's default button (`ListDetailView.swift:76`), never rename (Phase 3 gate (j) verifies empirically); (d) the menu bar carries no bare-Return equivalent anywhere (⌘Return is the only Return-family menu key).

### 1.3 Check-toggle semantics

**Multi-select toggle rule** (Space/⌘K/menu): if **every** selected row's derived `checkState == .checked` → uncheck all; otherwise → check all. One undo step for the whole batch.

**Selection advance under filter**: after any toggle, if a previously selected row is no longer in `filteredRows`, selection moves to the row now occupying the first removed row's old filtered index (clamped to last row; empty list → empty selection). This makes Space-Space-Space checkoff under Remaining flow like Things' ⌘K. A checkbox click on an *unselected* row never moves selection.

### 1.4 Filter, progress, and what replaces the mode switch

- Toolbar segmented `Picker` — **All / Remaining / Completed** (rename of `CheckFilter` cases `unchecked`→`remaining`, `checked`→`completed`), applied **unconditionally** in `filteredRows` (delete the `isCheckMode` gate at `ListStore.swift:89`). Search composes first, filter second (same order as today).
- Progress `checked/total` text sits beside the filter, always visible.
- Empty states: filter `.remaining` + all checked → "All Done!" view (moved from `CheckModeView.swift:46-58`) with **Show All** button; filter `.completed` + none checked → `ContentUnavailableView("No Completed Items", systemImage: "circle")` with **Show All**.
- **Add-under-filter rule**: `beginAdding` while filter == `.completed` first sets filter to `.all` (a new unchecked item must never be born invisible). `.remaining` needs no rule.
- **Drag-under-filter rule**: filter ≠ `.all` disables drag exactly like search (rows are a non-contiguous excerpt): add to the `.moveDisabled` predicate and the `moveRows` guard (`ListStore.swift:330`). Menu/keyboard moves (⌘⌥↑↓) stay enabled — they operate on true siblings.
- Checked rows render strikethrough + secondary (carried from `CheckRowView`); dogfood may reverse cheaply.
- Filter is in-memory per store (resets to All when a list opens) — not persisted.

### 1.5 Drag (B6 resolved)

Single-item drag only (M4 D6 stands). New: a row that is **part of a multi-row selection** gets `.moveDisabled(true)` on both platforms — the drag never lifts; the silent no-op becomes a visible non-affordance. Store's multi-index guard stays as belt-and-suspenders. Contiguous multi-move is deferred to the M4 Stage 2 design.

### 1.6 iOS (same codebase, defined but not the priority)

Row tap = select (`RowSelectionTapModifier`, unchanged); **double-tap = open the Details sheet** (Rev 2.5, td-ee5174 — wire through the existing showDetails path; single-tap select must not be delayed by double-tap detection: use the tap-count gesture pattern that lets single fire immediately); checkbox tap = toggle (Button wins over the parent tap gesture — same precedence the ellipsis/trash buttons rely on); `Haptics.checkToggle()` fires on toggle; filter picker joins the iOS toolbar; action bar/keyboard accessory unchanged. No hardware-keyboard work this overhaul. iOS inherits the menu-bar ⌘ key equivalents passively via the shared SwiftUI `Commands` scene — this is incidental, not a design goal: no iOS surface advertises shortcuts, and none should. Do not add iOS keyboard UI, hints, or `.keyboardShortcut` modifiers outside `Commands`; suppressing the inheritance is equally out of scope (it would be extra code for negative value). Three iOS items from prototype testing: (a) the keyboard accessory bar gains a **keyboard-dismiss button** (`keyboard.chevron.compact.down`) that resigns focus WITHOUT ending the add flow — Done ends the flow, ⌄ just drops the keyboard (CarbonFin parity; small, Phase 2); (b) **undo on iOS is a confirmed gap, not a verification item**: the registration pipeline exists in code but iOS has ZERO undo affordance today — M5 adds a visible **Undo** (and Redo when available) entry to the iOS toolbar overflow menu unconditionally, wired to the scene UndoManager; shake/three-finger gestures may also work but discoverable UI is required; (c) the add field already renders **at the insertion position** (below its anchor row, indented for child) — stated explicitly because it is load-bearing for intuitive editing; any regression to a bottom-of-list field is a spec violation. Add Above is reachable on iOS via the row context/ellipsis menus and the selection action bar.

## 2. Root-cause fixes woven in

**B1 (click latency ~0.5s) + B4a (flaky double-click)** — **[RETIRED Rev 2.4 — historical record only; hover gating was empirically falsified at Gate M1 and drag is armed at rest. Do NOT implement anything in this block.]** D10's gating, with **row-local hover state** (Rev 2.2 — empirically validated during Phase 1; the original shared-ancestor `hoveredDraggableRowID` in `OutlineEditorView` re-diffs the List on every hover change and invalidates the in-flight AppKit drag session, so `moveRows` never fires): `OutlineRowView` owns `@State private var isContentHovered = false` (macOS), set by `.onHover` on the title/notes region only — not chevron, checkbox, or trailing buttons — and applies the drag gate itself:
```swift
// inside OutlineRowView (macOS): row-local hover; other terms passed in
.moveDisabled(dragBlocked || !isContentHovered)
// dragBlocked (from the editor): isTextInputActive || !searchText.isEmpty
//        || checkFilter != .all (Phase 2+) || rowInMultiSelection(row)
// iOS: .moveDisabled(dragBlocked) — no hover term
```
Updating row-local state re-renders only that row, which is why the native drag survives. The nilcoalescing reference pattern is row-local too; M4 spec D10's shared-state phrasing is superseded by this.

**B2 (Return keystrokes land in sidebar search) + B4b (rename field dead)** — replace both `.onAppear { focused = true }` grabs (`OutlineEditorView.swift:295`, `OutlineRowView.swift:40`) with one editor-owned focus architecture:
```swift
enum EditorFocus: Hashable { case addField; case rename(UUID) }   // internal, in OutlineRowView.swift
@FocusState private var focus: EditorFocus?                        // in OutlineEditorView
```
- Add field: `.focused($focus, equals: .addField)`. Rename field: `OutlineRowView` gains `focus: FocusState<EditorFocus?>.Binding` and applies `.focused(focus, equals: .rename(row.id))` (the row's private `@FocusState` is deleted).
- Driven from store state, **task-deferred** (assignment must land after the field mounts — one runloop hop, not inside the transaction that inserts it):
```swift
.onChange(of: store.addPlacement) { _, newValue in
    if newValue != nil { Task { @MainActor in focus = .addField } }
}
.onChange(of: store.editingItemID) { … existing draft-buffer logic …
    if let newValue { Task { @MainActor in focus = .rename(newValue) } }
}
```
- Transition coverage: `cancelAdding`/`dismissPendingAdd` always nil the placement before any re-add (nil→value always fires); the continuation flow's `.below(a)→.below(b)` is a value change (fires). Delete the dead `addFieldFocused` write in `commitNewItem` (`:355`).
- Field-level `onSubmit`/`.onKeyPress(.escape)` stay as-is. The sidebar `.searchable` (`LibrarySidebar.swift:106`) is untouched — with focus reliably claimed, keystrokes cannot fall through to it.
- **Escalation rule** (only if the Phase 1 gate still shows misses): one bounded retry — `Task { await Task.yield(); focus = X }` then a one-shot re-assert in `.onChange(of: focus)` when the expected target didn't stick. Do not add sleeps; do not invent a third mechanism.

**B3 (stale command routing — ⌘[/⌘] act on the last line)** — rewrite `focusedCommandActions` (`ListDetailView.swift:241-288`): every closure **reads selection live at invocation**:
```swift
actions.indent = {
    guard !store.isTextInputActive, let id = singleSelectedItemID(in: store) else { return }
    store.indent(itemID: id, undoManager: undoManager)
}
```
Presence (`nil` vs non-nil, for menu enablement) is still computed at publish time — a republication lag can only mis-gray a menu item momentarily, never mis-target an action. Apply the live-read shape to every closure including the new `toggleChecked`, `rename`, `resetAllChecks`, `setFilter`.

**B5 (duplicate edit surfaces)** — one obvious way per thing:
- Item **title**: inline rename only (Return / ⌘E / double-click / menu). `InspectorView.swift:24-27` drops the editable Title `TextField` → read-only `LabeledContent` (side benefit: kills per-keystroke undo spam). The inspector section keeps a small "Rename" button calling `store.beginEditing(itemID:)`.
- Item **notes/quantity**: inspector only (unchanged).
- List **identity** (title/notes/icon/color): pencil sheet only (unchanged); inspector list pane stays read-only.
- The bare-key comment block at `ListsurfCommands.swift:45-49` is rewritten to name: Return = rename (or root-add when nothing selected), Tab/⇧Tab = indent/outdent, Space = toggle check.

**B6** — see §1.5. **B7 (menu inconsistencies)** — the check-mode context menu divergence disappears with unification (all rows get `ItemActionsMenu`, which gains Check/Uncheck and Reset Branch). Row ellipsis menu: *select-on-open was investigated and rejected as unimplementable reliably* (SwiftUI `Menu` has no open callback; macOS menus open on mouse-down). Instead: `ItemActionsMenu` gains `selectsTargetOnAct: Bool`; when true (row ellipsis only), every action first sets `store.selectedItemIDs = itemIDs`. Hints stay off there, rationale comment retained, asymmetry documented in Help. Empty-selection context menu (`OutlineEditorView.swift:491-497`) grows Expand All / Collapse All under Add Item.

## 3. Consistency mechanism (registry-lite)

A full data-driven `Commands` registry was assessed and **rejected** (SwiftUI `Commands`/`@FocusedValue` plumbing resists data-driven construction; marginal payoff for ~18 commands). The chosen shape — **new file `Sources/Features/Commands/CommandCatalog.swift`** (~150 lines):
```swift
enum CommandCatalog {
    struct Binding { let key: KeyEquivalent; let modifiers: EventModifiers; let display: String } // "⌘K"
    struct Command {
        let id: String; let title: String; let systemImage: String
        let binding: Binding?          // nil = no menu equivalent
        let editorOwnedKey: String?    // "Return", "Space", "Tab" — help-only, never a menu equivalent
        let helpText: String           // the single help sentence
    }
    static let newItem, addAbove, addChild, rename, toggleChecked, indent, outdent,
               moveUp, moveDown, delete, resetAllChecks, resetBranch,
               filterAll, filterRemaining, filterCompleted,
               toggleInspector, expandAll, collapseAll, newList, help: Command
    // Rev 2.6: help-only entries (binding nil or system-owned) — REQUIRED members, not optional:
    static let navigate, escape, settings: Command
    //   navigate: arrows/⇧-arrows help text (native List); escape: cancel-then-clear-selection;
    //   settings: ⌘, (system-provided scene, but Help must list it — prototype legend + app menu show it)
    static let macKeyboardHelp: [Command]   // ordered; includes editor-owned Return/Tab/Space/Esc entries
    static let expectedIDs: Set<String>     // Rev 2.6: the exact command inventory, hand-maintained
}
```
Key catalog entries reflecting Rev 2: `rename = Command(title: "Rename", binding: ⌘E, editorOwnedKey: "Return", helpText: …)`; `newItem = Command(binding: ⌘N, helpText: "…with nothing selected, Return also starts a new item")`; `newList` → ⇧⌘N; `addAbove` → ⌥⌘N; there is no `returnAdd` entry.

- `ListsurfCommands` buttons use `CommandCatalog.x.title` + `.keyboardShortcut(x.binding!.key, modifiers:)`; `ItemActionsMenu` labels/hints read the same constants; `ListsurfHelpView`'s "Mac keyboard" section becomes `ForEach(CommandCatalog.macKeyboardHelp)` — **help is generated, so it cannot drift**.
- **`Tests/FeaturesTests/CommandCatalogTests.swift`**: (a) no two commands share a `(key, modifiers)` binding; (b) every command with a binding or editor-owned key has non-empty `helpText`; (c) `macKeyboardHelp` contains every bound command; (d) **Rev 2.6: the set of declared command IDs equals `expectedIDs` exactly** — set equality, not subset — so dropping navigation/escape/settings (or any future command) from generated Help is a test failure, not a silent omission (CODEX2 finding 1: without this, an implementer builds only the convenient constants, all original tests pass, and Help silently loses arrows/Esc/Settings). Residual risk (a menu hand-coding a shortcut) is enforced by a header comment in `ListsurfCommands.swift` and review.

## 4. Deleted vs surviving

**Deleted**: `CheckModeView.swift`, `CheckRowView.swift` (checkbox code rehomed into `OutlineRowView`), `ListStore.isCheckMode` + didSet (`ListStore.swift:19-29`), the `isCheckMode` gate in `filteredRows` (`:89`), the mode branch (`ListDetailView.swift:17-27`), mode toggle button + `detail.toggleMode` (`:110-119`), `checkModeToolbar` as a separate builder (`:195-232`, contents merged), `toggleCheckMode` command/action/⇧⌘E (`ListsurfCommands.swift:104-108`, `ListsurfCommandActions.swift:20`), `PreviewFixtures.listStore(checkMode:)` parameter, bare ⇧Return, Help's "Check mode" section, `testEnteringCheckModeClearsTextEntryState`.

**Survives (rehomed)**: Reset All Checks (toolbar button + confirmation, always visible, disabled at 0 checked; also an Item-menu entry), Reset Branch (into `ItemActionsMenu` for parent rows, disabled when branch unchecked; confirmation driven by new store-owned `pendingBranchResetID: UUID?` hosted in `ListDetailView` — same pattern as `pendingDeletionIDs`), progress display, `CheckFilter` (renamed cases, unified filter), the All-Done empty state, `Haptics.checkToggle()`, all `TreeEngine` check functions (**zero Domain changes anywhere in this overhaul**).

## 5. Phased delivery — each phase independently E2E-testable

**Gate policy (rewritten Rev 2.6 — the original per-phase manual-gate rule is retired; it was already being violated de facto and Gaylon has said intermediate-state manual testing is untenable, since he cannot distinguish missing-by-design from broken while comparing against the finished prototype).** The policy now: (a) every phase still ends with the full unit suite and both xctestplans green, a devlog entry, and td closure — that part is unchanged and non-negotiable; (b) narrow architecture/device blockers run immediately when a phase hits them, not at the end — currently: the Phase 3 Space-delivery spike (stop-and-report) and the Phase 2 device gesture arbitration (the P0 td-efdf1e keyboard check passed on hardware 2026-07-17 — closed); (c) the gate scripts below (M2/M3/M4) are preserved as the **content** of ONE integrated manual gate, executed once on real macOS and a real iOS device when Phases 2–4 plus the parity items (td-cf54fb, td-6a9f9d, td-d27ad4, td-40102b decision) are all landed; (d) phase-issue closure = automated green; **M5 epic closure = the integrated gate passing.** Phases 2 and 4 add/delete files → run `xcodegen` in those phases only.

### Phase 0 — Prototype gate (already underway)
Interactive HTML prototype of §1 (macOS + iOS surfaces) approved by Gaylon. Decisions changed by the prototype revise this spec first.

### Phase 1 — Foundations: make TODAY'S two-mode app feel right (no xcodegen)
1. **B1**: hover-gated `.moveDisabled` (D10) — `OutlineEditorView` + `OutlineRowView.onContentHover`.
2. **B6**: multi-selection rows `.moveDisabled`.
3. **B2/B4**: `EditorFocus` architecture (both `.onAppear` grabs deleted).
4. **B3**: live-read command closures in `ListDetailView.focusedCommandActions`.
5. New macOS UI test `testCommandBracketIndentsSelectedRow` (B3 regression: add Alpha/Bravo/Charlie, Esc, click **Bravo** — the middle row, not the last-added — ⌘], poll `bravo.frame.minX` increased ~20pt, Charlie untouched, ⌘Z restores). No Expand All workaround — item 6 makes the indented row stay visible.
6. **(Rev 2.2) Fix the pre-existing `indent()` visibility bug**: `ListStore.indent` (`ListStore.swift:347`) reparents an item under its previous sibling but never inserts the new parent into `expandedIDs`, so indenting under a childless (hence collapsed-by-default) sibling makes the row VANISH — almost certainly a contributor to the original "⌘[/⌘] are unpredictable" complaint. Fix: after a successful engine indent, insert the new parent's id into `expandedIDs` (mirror `addChild`, `ListStore.swift:264`). Unit test `testIndentExpandsNewParent`: two root siblings, indent the second, assert it appears in `flatRows`/`filteredRows` (visible), plus undo restores.

**Gate M1 (manual, macOS)**: (a) click 10 different rows — highlight instant every time; (b) toolbar Add Item → in-field Return commit-and-re-arm chain: 10 rapid tries, zero keystrokes leak to sidebar search (in-field Return is unchanged in all phases; selected-row Return is still add-below through Phases 1–2); (c) double-click rename focuses 10/10; (d) chevron/ellipsis/trash click latency imperceptible; (e) select a middle row, ⌘]/⌘[/⌘⌥↑/⌘⌥↓ act on it — never the last row — including immediately after adding items; (f) drag still reorders (M4 V1-2/V1-3 re-run); (g) with 2 rows selected, drag does not lift. If the macOS drag UI test fails to lift under hover gating, insert `charlie.hover()` before the drag in the test (what a human does anyway).

### Phase 2 — Unification (files deleted → xcodegen). **No key-binding changes this phase.**
Store: delete `isCheckMode`; rename filter cases (`all/remaining/completed`, raw values "All"/"Remaining"/"Completed"); unconditional filter in `filteredRows`; `toggleChecked(ids:undoManager:)` with the multi rule + selection-advance (§1.3) — existing `toggleCheck(itemID:)` becomes a thin wrapper so all call sites/tests keep working; `beginAdding` completed-filter reset; `moveRows`/`.moveDisabled` filter guard; `pendingBranchResetID`.
View: checkbox into `OutlineRowView` (order: chevron · checkbox · title; icon set and `check.item.<uuid>` identifier + "Check/Uncheck \(title)" labels carried verbatim from `CheckRowView.swift:28-41` so the iOS UI test barely changes); strikethrough for checked; both empty states in `editorContent`; `ListDetailView` single toolbar (primary: Inspector, Edit-List pencil; secondary: Add Item, Item Actions, Filter picker `editor.filter`, progress `editor.progress`, Expand All, Collapse All, Reset All) and branch-reset dialog; `ItemActionsMenu` + Check/Uncheck (dynamic label from derived `checkState` — the `flatRows`-with-full-flatten-fallback trick from `ListStore.toggleCheck:413-416`) + Reset Branch; multi-selection menu section gains Check/Uncheck. Inspector title → read-only (B5). Delete the two CheckMode files; fix `PreviewFixtures`. Help: replace "Check mode" section with "Checking off items" (checkbox, filters, reset — no keyboard claims yet). ⇧⌘E/View-menu item removed.
Tests: migrate `testCheckedFilterUsesAggregateParentState` (drop `isCheckMode`, `.checked`→`.completed`); delete `testEnteringCheckModeClearsTextEntryState`; new unit tests: multi-toggle semantics (mixed→all-checked, all-checked→all-unchecked, one undo step, no-op registers no undo), selection-advance under `.remaining` (+ unselected-row-no-move variant), `beginAdding` filter reset, `moveRows` refused under filter; iOS UI `testCreateListAddItemAndCheckIt` drops `detail.toggleMode` (tap the row to dismiss the add flow, then tap "Check Passport"); new macOS UI `testCheckboxAndFilterFlow` (checkbox → strikethrough/Uncheck label; Remaining segment → row gone; Show All path from All-Done).

**Gate M2 additions (Rev 2.5)**: on iOS, scroll the list hard to the top — no shake, and the large title renders (td-ef3eec; if the toolbar merge did not cure it, stop and report with evidence — do not patch blind). Double-tap a row → Details sheet opens; single-tap select is not delayed.

**Gate M2 (manual, both platforms — iOS on a REAL DEVICE via TestFlight or cable, not just the simulator**; drag-reorder and swipe-delete have never been verified on hardware — the M4 drag has never shipped in any TestFlight build)**: create list → add 5 nested items → check leaves and a parent (branch check) and a mixed parent → filter Remaining/Completed/All → check a row under Remaining, watch it animate out → All Done → Show All → Reset Branch via right-click → Reset All from toolbar → ⌘Z through every mutation → relaunch persists. Phase 1 keyboard must still work identically. Zero "Check Mode" remnants anywhere (toolbar, menus, help, **and Settings — `ListsurfSettingsView.swift:68` is a known remnant, Rev 2.6**). iOS: fat-finger pass on checkbox vs chevron targets (≥22pt icon). **Rev 2.6 additions (CODEX2 finding 5 — the original script never exercised the two risks that justify the hardware requirement)**: on device, (i) same-parent drag reorder, including a boundary clamp attempt (drag past first/last sibling); (ii) long-press → context menu vs drag arbitration (td-3960b2 reproduces here — record the observed behavior either way); (iii) swipe-to-delete → confirmation → undo; (iv) the add field appears AT the insertion slot (below anchor / indented child), never at the bottom of the list — §1.6(c) is load-bearing and also gains an iOS UI test asserting position, not just focus; (v) measure inline-rename keystroke lag and record the evidence with build type (td-e7c609 — Gaylon-accepted deferral for M5, non-blocking here, but a hard fix-before-ship item: if a RELEASE build still lags noticeably it becomes an immediate post-M5 P1). Touch multi-select (td-dfb334) is a signed P2 deferral — the gate does not test it; parent-drag is the accepted workaround.

### Phase 3 — Keyboard completion (no xcodegen)
**First task**: verify Space reaches the editor `.onKeyPress` with a row selected inside the focused List — if not, STOP and report (fallback is an NSEvent local monitor, a design change requiring planner sign-off, not improvisation).
`handleReturnKey` rewritten per §1.2 (single selection → `beginEditing`; none → `beginAdding(.root)`; multi → `.ignored`; ⇧Return `.ignored`); Space handler (§1.3); editor-level Esc-deselect; ⌘N New Item + ⇧⌘N New List remap + ⌥⌘N Add Above + ⌘E Rename + ⌘K Toggle Checked + ⌥⌘1/2/3 filter Picker in View menu (`ListsurfCommands`, `ListsurfCommandActions` + `ListDetailView` closures — all live-read per B3); `ItemActionsMenu` hints: ⌘K on Check/Uncheck, ⌘E on Rename; comment blocks at `OutlineEditorView.swift:39-51` and `ListsurfCommands.swift:45-49` rewritten. Help "Mac keyboard" section updated by hand (catalog generation lands in Phase 4).
Tests: `testCommandNOpensNewListSheet` → ⇧⌘N; new macOS UI tests: `testReturnRenamesSelectedRow` (select row, Return → rename field exists; Esc cancels, title unchanged; then ⌘E path asserted in the same test), `testSpaceTogglesCheckAndAdvances` (3 items, Remaining filter, select first, Space ×2 → both gone, third selected), `testCommandNArmsAddFieldBelowSelection`.

**Gate M3 (manual, macOS, mouse untouched)**: full keyboard-only session — ⇧⌘N create list → ⌘N, type, Return-Return-Return continuation → Esc → arrows → Return renames 10/10 → Esc → Space checkoff run under Remaining (selection advances) → ⌘K on a ⇧-extended multi-selection → Tab/⇧Tab/⌘]/⌘[/⌘⌥↑↓ → ⌘⌫ → ⌘Z everything. Plus: (g) Return on empty list arms root add; (h) Return with multi-selection does nothing; (i) Space never fires while renaming/adding or when sidebar search is focused; Space with no selection scrolls; (j) with the delete confirmation open, Return activates the dialog's Delete default — never rename.

### Phase 4 — Consistency + generated help (new file → xcodegen)
`CommandCatalog.swift` (§3); `ListsurfCommands`/`ItemActionsMenu` refactored to reference it; Help keyboard section generated from `macKeyboardHelp`; `⌘?` and `⌘,` entries included; **help sections are platform-scoped**: the keyboard section renders only on macOS. **[RESOLVED — Gaylon, 2026-07-17]**: iOS Help carries **no keyboard-shortcut content at all** — the originally specced "Mac shortcuts work on iPad and iPhone too" sentence is dropped ("makes no practical sense"). §1.6's no-advertising rule now holds without exception; the keyboard section is macOS-only, full stop. Ellipsis `selectsTargetOnAct`; empty-selection context-menu additions; `CommandCatalogTests`. **Keyboard Legend (Rev 2.7, td-40102b adopted)**: macOS-only auxiliary window (SwiftUI `Window` scene, "Keyboard Legend"), toggled from the View menu with **⌥⌘L** (verified free in the §1.2 map); content is `ForEach(CommandCatalog.macKeyboardHelp)` rendering key glyphs + description per row — same rows as generated Help, one source. **Highlight-on-use**: command handlers (the `ListsurfCommandActions` closures and the editor's Return/Space/Tab/Esc handlers) post a lightweight command-id notification on successful invocation; the legend row for that id flashes ~0.9s (prototype behavior). No iOS surface. The `keyboardLegend` toggle command joins the catalog, `expectedIDs`, parity matrix, and Help. If the `Window`-scene toggle proves awkward from a `Commands` context, stop-and-report — do not substitute an ad-hoc panel without sign-off. Restore the iOS "Keyboard accessory" help item (touch UI, deleted in ff8936b as over-application of the no-shortcuts rule) with updated text covering the ⌄ dismiss button.

**Gate M4 (manual, rewritten Rev 2.6 — "diff every surface against the Item menu" was literally unsatisfiable: the toolbar and ellipsis menus legitimately differ from the Item menu, so the gate either fails a correct build or degenerates into hand-waving)**: the consistency audit — read every Help line while performing it in the app; press every advertised shortcut once. Menu surfaces are checked against an **action-to-surface parity matrix** authored alongside CommandCatalog: for each command, its canonical label, binding, and the surfaces it MUST appear on and MUST NOT appear on (menu bar Item/View, row right-click, row ellipsis, toolbar actions, empty-area right-click). Each surface is opened and diffed against the matrix, not against another surface. Settings/help/native commands (⌘,/⌘?/navigation/Esc) are audited as their own matrix rows, separate from item-action parity. Any matrix mismatch is a phase failure. Devlog closes the overhaul; TestFlight build for dogfooding.

## 6. File-by-file change map (rough deltas)

**Rev 2.6 staleness warning**: these line counts and `file:line` anchors predate Phases 1–2 and are now materially wrong (verified at HEAD `2cb9946`: `OutlineEditorView` 734 not 617, `OutlineRowView` 179 not 99, `ListStore` 542 not 491, `ItemActionsMenu` 145 not 115; `handleReturnKey` at `OutlineEditorView.swift:498`, `focusedCommandActions` at `ListDetailView.swift:221`). Use the map for scope/shape only; locate code by symbol search, never by these line numbers.

| File | P1 | P2 | P3 | P4 |
|---|---|---|---|---|
| `Sources/Features/Editor/OutlineEditorView.swift` (617) | +45/−12 (hover, focus, moveDisabled) | +35/−5 (checkbox wiring, empty states) | +55/−25 (Return/Space/Esc handlers) | +8 (context-menu additions) |
| `Sources/Features/Editor/OutlineRowView.swift` (99) | +18/−6 (focus binding, onContentHover) | +50 (checkbox, strikethrough) | — | — |
| `Sources/Features/Editor/ListDetailView.swift` (318) | ~45 rewritten (live closures) | +40/−75 (toolbar merge, mode branch out, branch-reset dialog) | +30 (new closures) | small |
| `Sources/Features/Store/ListStore.swift` (491) | — | +60/−15 (toggleChecked+advance, filter rename/unconditional, guards, pendingBranchResetID, isCheckMode out) | — | — |
| `Sources/Features/Editor/ItemActionsMenu.swift` (115) | — | +40 (Check/Uncheck, Reset Branch, multi section) | +6 (hints) | +12 (selectsTargetOnAct, catalog refs) |
| `Sources/Features/Commands/ListsurfCommands.swift` (130) | — | −6 (⇧⌘E out) | +55/−10 | refactor to catalog |
| `Sources/Features/Commands/ListsurfCommandActions.swift` (45) | — | −1 | +6 | — |
| `Sources/Features/CheckMode/*` (240) | — | **deleted** | — | — |
| `Sources/Features/Inspector/InspectorView.swift` (131) | — | −10 (title read-only) | — | — |
| `Sources/Features/Help/ListsurfHelpView.swift` (228) | — | ~20 | ~25 | −40/+30 (generated) |
| `Sources/Features/PreviewFixtures.swift` | — | −3 | — | — |
| `Sources/Features/Commands/CommandCatalog.swift` | — | — | — | **new ~150** |
| Tests | +1 UI | ~6 unit, 2 UI | 3 UI, 1 edit | `CommandCatalogTests` ~80 |

Reused unchanged: `TreeEngine`/`TreeEngineReorder` (zero Domain changes), `filteredRows` search block, undo pipeline (`registerUndo`/`teardownUndo` untouched — every new mutation follows snapshot→no-op-guard→register→apply→persist), `Haptics`, M4 Stage 1 drag (Stage 2 compatibility: the `.moveDisabled` predicate is exactly the D5 disable set plus D10's hover term and the multi-selection term, which D20 later re-expresses as drag-source inertness).

## 7. Risks & open questions (ranked)

1. **Space `.onKeyPress` inside a focused macOS List** (type-select/scroll defaults). Precedent (Return/Tab handlers) says it works; verified as Phase 3's first task with a stop-and-report rule.
2. **Task-deferred focus may still lose on first-window-appearance** — Phase 1 gate is the detector; bounded escalation rule specced (no sleeps).
3. **Hover-gated drag**: trackpad hover jitter could block a legitimate drag start; D10's pattern is field-proven (nilcoalescing) — dogfood verdict at gate M1.
4. **⌘N remap muscle memory** (New List → ⇧⌘N) — deliberate, Things-aligned, sanctioned by the approved option text.
5. **⌘E overrides the system "Use Selection for Find" convention** — accepted for a personal craft app; documented in the catalog helpText.
6. **Row density** with checkbox + ellipsis + trash always visible — visible-actions philosophy retained (`testCoreActionsAreVisible`); hover-reveal is a possible later refinement, deliberately out of scope.
7. **Structural ops under active filter** (indent/move act on hidden true siblings) — correct but potentially surprising; Help documents it; drag is disabled there.
8. **Strikethrough on checked rows** and **instant hide under Remaining** (vs Things' grace delay) — both cheap to reverse after dogfooding.
9. Open question (the only truly open one): should Completed-filter add-flow edge cases get more than the reset-to-All rule? Specced answer: no; revisit only if dogfooding surfaces confusion.
