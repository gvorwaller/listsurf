# Listsurf — Critical Full-Repo Review & Consolidation Plan

**Date**: 2026-07-09
**Scope**: Entire repo at working-tree state (committed base `fdabebe` **plus** ~500 lines of uncommitted changes: Group A fixes, settings surface, notes preview, Mac keyboard work). Four independent subsystem reviews (stores/persistence, editor/check-mode views, library/settings/commands, domain/tests) plus direct verification of the highest-stakes findings.
**Trigger**: Owner's assessment that recent fixes are introducing regressions patched over with more fixes, producing patchwork.

## Verdict

The suspicion is justified — and the patchwork has a recognizable signature: **fixes applied at the presentation layer, per-surface, by copy-paste, with band-aids layered over root causes that remain in place.** The clearest specimens:

- An app-global `NSEvent` key monitor added to rescue keystrokes from menu shortcuts that should never have owned them.
- Two undo systems: a dead one that is tested, and a live one that is broken (redo never works) and untested.
- The same item-action menu maintained in 3–5 hand-synced copies, already diverged.
- Selection written by both store and view in the same changeset; list metadata owned by two stores and synced by a view `.onChange`.
- A notes-preview feature shipped with its "off" state amputated but the off-state code left dead in three files.
- Context rollback added only to the three methods where a bug previously bit, not as policy.

**What is genuinely good** (verified, worth keeping): the Core Data model and `replaceAllListsAndItems` transactional import; export validation (cycles, cross-list parents, duplicate IDs all rejected); position rebalancing implemented and wired; duplicate naming correct and in the right layer; the Details→inspector fix root-fixed; archive rename/restore-button/empty-state fixes real; the `AppStorage` settings key properly centralized; `testRapidEditsPersistInMutationOrder` a genuinely meaningful test.

---

## Part A — Systemic inconsistencies (the patchwork patterns)

### A1. Keyboard input: four competing layers for the same keys (macOS) — HIGH

The same keystrokes (Return, ⇧Return, ⌘Return, Tab, ⇧Tab) are claimed by four mechanisms:

1. **Menu-bar key equivalents** — `ListsurfCommands.swift:42-68` gives menu items *bare* Return and Tab equivalents. On macOS these match before the field editor sees the key, so **Return in any unprotected text field fires "Add Item Below" instead of committing** — this is the root cause of "edit in place doesn't work."
2. **`MacOutlineTabKeyMonitor.swift`** (new) — an app-global `NSEvent.addLocalMonitorForEvents` that swallows Tab/Return (keyCodes 48/36/76) to rescue the *add field* from layer 1. It sniffs `firstResponder is NSTextView/NSTextField` (:89-92) — a written admission that the SwiftUI focus state feeding it isn't trusted. It protects only the add field: **the rename TextField, the Inspector title field, and sidebar fields still lose Return to the menu.** One field was patched; the rest stayed broken.
3. **`.onKeyPress` handlers** — `OutlineEditorView.swift:78-93` (new). The Tab handler is dead code (layer 2 swallows Tab first). All handlers return `.handled` unconditionally even when their guards no-op, so keys are consumed with no effect. The ↑/↓ handlers fire while typing in the add field, yanking focus and canceling empty entries.
4. **Context-menu `.keyboardShortcut` hints** — 16 duplicated lines across `OutlineEditorView.swift` and `ListDetailView.swift`.

Additional seam: `focusedCommandActions` (`ListDetailView.swift:298-341`) can't see `editingItemID`/`showingAddField` (they live in a child view), so menu commands stay enabled mid-rename — the exact window where layer 1 hijacks typing.

**Root fix**: remove bare-key equivalents from the CommandMenu (Apple's own guidance — unmodified keys belong to views, not menus). Then delete `MacOutlineTabKeyMonitor.swift` entirely, keep one `.onKeyPress`-based owner in the editor with honest `.ignored` returns, and lift editing state into the focused-values contract so command enablement is truthful.

### A2. Selection and inline editing: the original pathology got a third layer — HIGH

The pre-existing conflict (custom tap gestures fighting `List(selection:)`) was not fixed; it deepened:

- **Three stacked tap layers**: `OutlineEditorView.swift:187-188` (HStack), `OutlineRowView.swift:35-36` (row body), `OutlineRowView.swift:57-58` (inner VStack — redundant on the same tree).
- Every layer hard-sets `selectedItemIDs = [row.id]`, so **⌘-click/⇧-click multi-select is impossible** — yet the multi-select machinery ("Delete Items", "N selected items", `deleteSelected`) all still exists for a state the UI can't produce.
- A custom selection highlight (`OutlineRowView.swift:29-34`) paints over the native List selection highlight — double highlight.
- **Selection is now written in two layers at once** (this changeset): `ListStore.addItem/addChild/insertAbove` each end with `selectedItemIDs = [newItem.id]` *and* `OutlineEditorView.commitNewItem:387` sets it again. Undo restores `items` but not selection, so ⌘Z after an insert leaves selection pointing at a deleted item, nil-ing out `selectedRow` and silently disabling the command layer.
- **Silent regression**: double-click was repurposed from Rename to Details (`OutlineRowView`: `onStartEdit` → `onShowDetails`). Inline rename is now reachable *only* via context menu → Rename, has no Escape-to-cancel on macOS, and `select()` never clears `editingItemID`, so an open rename field can linger on a row you've navigated away from. The "double-tap swallowed" bug was resolved by deleting the feature.
- The fragile `.onAppear { isFocused = true }` rename focus remains (`OutlineRowView.swift:45`), now joined by a wrapper-level `.focusable()` + `editorFocused` tug-of-war (`OutlineEditorView.swift:57,72-77`) — two competing focus targets around one List.

**Root fix** (= plan Milestone 2, now with more debris to clear): native `List(selection:)` as sole selection owner; delete all row tap gestures and the custom highlight; selection policy lives in the store only; rename gets explicit affordances (Return-to-rename or double-click) with correct FocusState sequencing and Escape-to-cancel; undo snapshots include selection.

### A3. Undo: the tested system is dead, the live system is broken — HIGH

- **`TreeCommand.swift` (119 lines) has zero production callers.** `ListStore` implements undo via full-array snapshots instead. Four tests in `TreeEngineTests.swift:687-752` exercise only the dead path; the live path has **zero tests**. The dead path's inverses are also wrong three ways (no-op moves return active inverses; reset-checks undo is a guaranteed no-op because `restoreItems` only appends missing IDs; `setChecked` inverse blanket-cascades, losing mixed subtree state).
- **The live path cannot redo** (`ListStore.swift:354-366`, verified directly): the re-registration runs inside `Task { @MainActor }` — i.e. *after* `undo()` returns. `NSUndoManager` only converts registrations made *during* undo into redo entries, so ⌘⇧Z never works and ⌘Z toggles between two states while the stack grows.
- **All registrations target `UndoProxy.shared`** (a process-global singleton), so per-store cleanup via `removeAllActions(withTarget:)` is impossible and never attempted. After switching lists, stale menu Undo stays enabled and either no-ops or mutates an off-screen list.

**Root fix**: delete `TreeCommand.swift` and its tests; fix redo by registering synchronously inside the undo closure; give each store its own NSObject undo target with teardown cleanup; test the live path (add→undo→redo, cross-mode undo).

### A4. Duplicated state ownership — HIGH

- `AppStore.lists` vs `ListStore.list` hold the same record; coherence is maintained by `ListDetailView.syncListMetadata` in an `.onChange` (`ListDetailView.swift:48-50, 360-363`) — a view responsible for store consistency, working only while that view is mounted.
- Selection dual-write (A2).
**Root fix**: single owner per fact. `ListStore` derives its list from `AppStore` (or observes the repo), and views never mediate store-to-store sync.

### A5. Action surfaces: 3–5 hand-synced copies, already diverged — MEDIUM-HIGH

Item actions exist in the row context menu, the toolbar "Item Actions" menu, the menu bar, the iOS action bar, and the iOS keyboard accessory. Divergences already shipped in this changeset:

- **The ⌘⌫ hint lies**: the context-menu Delete shows ⌘⌫ but deletes the right-clicked row; the real ⌘⌫ deletes the *selection*. With 3 selected and a right-click on a 4th, hint and shortcut do different things.
- Context menu has Rename + Details; toolbar copy has neither.
- ⇧Return via the key handler inserts above *and starts editing*; the menu's Add Above just inserts.
- The library sidebar has the same utility actions in five placements; the Archive rename had to be applied four times in one file, and `.badge()` was pasted onto four surfaces of which only the List-row one renders (toolbar/safeAreaInset badges are decorative no-ops).

**Root fix**: one `ItemActionsBuilder` (ViewBuilder or Commands-driven) consumed by every surface; shortcut hints only where the shortcut's semantics match; one canonical placement per library utility.

### A6. Error handling: four regimes and retries that don't retry — MEDIUM

- **TreeEngine drift**: same class of bad input → four behaviors: `moveUp/moveDown` return nil; `indent/outdent` throw (and throw `itemNotFound` for items that *are* found, at boundary no-ops — `TreeEngine.swift:435-437, 460-461`); `insertAbove/Below` silently append unnormalized; `deleteSubtree`/`setChecked` silently no-op. Callers can't distinguish "nothing to do" from "stale snapshot."
- **View-context saves have no rollback** (`CoreDataListRepository.swift:48-54,135-144`; `CoreDataOutlineRepository.swift:31-37,57-66`): a failed save leaves pending garbage in the shared main context that rides along with the next save. The background-context methods *do* rollback — added where a bug bit, not as policy.
- **Present-AND-throw hybrid** (`AppStore.exportLibrary/importLibrary`) already produces swallowed errors at call sites (`ContentView.swift:156-158` catch-and-ignore with an excusing comment; `:239-241` unobserved throwing Task).
- **Retry buttons don't retry**: every failure gets `loadLists()` as "recovery" (`AppStore.presentSaveError:236-244`) — a failed create retried this way *discards the user's list*; a failed export offers "Retry Load."
- `AppErrorStore.present` clobbers the current error and its retry closure (no queue).

**Root fix**: one error contract (present internally, don't also throw); rollback in every repository catch; retry closures capture the actual failed operation; TreeEngine settles on one signaling style (typed no-op vs error) and callers surface staleness.

### A7. Core Data context policy applied backwards — MEDIUM

Every keystroke-sized outline edit spins up a background context (`ListStore.persistInBackground`), while whole-library export runs as an N+1 read on the main context with no snapshot isolation (`AppStore.exportLibrary:117-140`) — a background save can commit between fetches, exporting cross-list inconsistent state. cs.md specifies exactly the opposite assignment. Also: one logical mutation can be two transactions (`saveAll` then `deleteAll`, `ListStore.swift:131-139`) — survives today only because no current op both saves and deletes.

### A8. Data-integrity gaps at write time — MEDIUM (HIGH once multi-window is real)

- `insertChild` with a nonexistent parent **persists an orphan** (`TreeEngine.swift:549-559` sets `parentID` unconditionally; `ListStore.addChild` feeds it unvalidated UI IDs). The invariant "every item's parent exists" is enforced only on reparent and by post-hoc repair on next load.
- `load()` doesn't await `persistenceTail`, so the error-retry path can overwrite in-memory state with a stale fetch while a queued save then commits on top — silent UI/DB divergence (`ListStore.swift:76-100,144-147`).
- Import preserves incoming UUIDs verbatim; the plan's "UUID collisions create new UUIDs" rule is unimplemented — the planned per-list *additive* import has nothing to build on and would clobber.
- Dead-but-loaded footgun: `ListRepository.delete(id:)` deletes a list *without its items* (the orphan-maker), implemented, stubbed in four fakes, called by nothing.
- `moveUp/moveDown` use ±0.5 arithmetic instead of midpoints (`TreeEngine.swift:408,424`); with midpoint-produced fractional gaps this creates position *ties* broken by UUID — an item can leap two slots. All move tests use integer positions and can't catch it.

### A9. Notes-preview feature: shipped with dead limbs — MEDIUM

- The "0 = off" state was removed from the picker (1–5 only) and clamped away in **three** places (`ListsurfSettingsView.swift:13-16`, `ListDetailView.swift:348-350`, `NotePreviewView.swift:8`), yet the `== 0` note-icon branch and `> 0` guards remain in the rows — dead code, and **users can no longer hide notes at all**.
- `NotePreviewView` nests a `ScrollView` with a hardcoded `lineCount * 16` height inside every list row: steals scroll gestures on macOS, fights three tap gestures, breaks under Dynamic Type. The root-cause version is `Text(notes).lineLimit(lineCount)` — no ScrollView, no fixed height.
- Naming drift: key is `notesPreviewLineLimit`, consumers call it `notePreviewLineCount`.

### A10. Smaller inconsistencies (fix opportunistically)

- Empty state promises multiline paste ("or paste multiple lines", `OutlineEditorView.swift:141`) — no paste handling exists anywhere (grep-verified).
- ⌘N during store-corruption recovery arms a sheet with no host; it pops unprompted after recovery (`ContentView.swift:56-77`).
- Settings sheet chrome built at call site; Help sheet builds its own — two conventions; neither sets detents while every other sheet does.
- macOS-dead settings path compiled everywhere (`onShowSettings` never invoked on macOS).
- Help: still says "Archive" (renamed in this same tree); documents 3 of ~12 shortcuts; new Settings/notes features undocumented; per-section `@State isExpanded` resets every open.
- In-list search is iOS-only; `ListStore.searchText` machinery is dead on macOS.
- Vestigial code: `items.filter { _ in true }` (`ListStore.swift:343`); `listContextMenu` one-line passthrough; hardcoded `appVersion "0.1.0"` default in export; two divergent app-version readers; `AppError.importPartial` constructed nowhere; `repairOrphans` near-duplicate of `repairInvalidParents` with an inconsistent count.
- `CheckModeView`/`OutlineEditorView` animate on `flatRows` while rendering `filteredRows` — filter transitions don't animate.
- `PersistenceStack.init`: dead semaphore scaffolding around a synchronous load; `try? createDirectory` swallows failure.

### A11. Tests that don't test — MEDIUM

- The duplicate-list tests' fake discards the `items:` argument (`AppStoreExportImportTests.swift:167-169` → `save(list)` only), so item duplication/persistence breakage is invisible — only title strings are asserted.
- Four tests cover the dead undo system; zero cover the live one.
- Move tests use integer positions only (can't catch A8's tie bug); `testIndentFirstSiblingThrows` locks in the wrong error type; export validation branches for cycles/self-parent/quantity/position are untested; a few tautologies (`testExportEnvelope` asserts hardcoded constants).
- **Top untested dangers**: live undo/redo; fractional-position moves; addChild with stale parent ID; duplicated-item persistence through a real repository; export validation branches.

---

## Part B — Consolidation plan (supersedes Milestone 2's scope; ordered)

Each phase is one coherent unit of work with a clear invariant at the end. Don't interleave.

**Phase 1 — Keyboard unification (macOS).**
Remove bare Return/Tab key equivalents from `ListsurfCommands` (keep ⌘/⌥-modified ones). Delete `MacOutlineTabKeyMonitor.swift`. Single `.onKeyPress` owner in the editor; handlers return `.ignored` when they don't act. Lift `isEditingText` into focused values so menu enablement is truthful during rename/add. Fix the ⌘⌫ hint/semantics mismatch. *Invariant: every key has exactly one owner; every menu hint tells the truth.*

**Phase 2 — Selection & inline editing.**
Native `List(selection:)` sole owner; delete all row tap gestures + custom highlight; selection set only in the store (remove the view's duplicate write); restore double-click-to-rename (Details stays in context menu/inspector button) with correct FocusState sequencing, Escape-to-cancel, and `editingItemID` cleared on selection change; multi-select either works (keep batch ops) or the plural machinery goes. Undo snapshots include selection. *Invariant: selection has one writer; rename is reachable and cancelable.*

**Phase 3 — Undo repair.**
Fix redo (synchronous re-registration inside the undo closure); per-store undo target + `removeAllActions(withTarget:)` on teardown; delete `TreeCommand.swift` and its tests; add live-path tests (add→⌘Z→⌘⇧Z, cross-mode). *Invariant: ⌘Z/⌘⇧Z round-trip; closing a list clears its undo stack.*

**Phase 4 — Store/state unification & error contract.**
Single owner for list metadata (kill `syncListMetadata`); one error API (present internally, no rethrow); rollback in every repository catch; retries retry the failed operation; `load()` awaits `persistenceTail`; TreeEngine one signaling style; remove `ListRepository.delete(id:)` and other dead repo API. *Invariant: no view mediates store coherence; a failed save can't poison the next one.*

**Phase 5 — Persistence & integrity hardening.**
Validate parent existence at insert; midpoint math for moveUp/moveDown + fractional-position tests; single transaction for mixed save+delete; export snapshots consistently (background context); UUID-remap import plumbing (prerequisite for Milestone 3's additive import). *Invariant: no write path can create an orphan; export is internally consistent.*

**Phase 6 — Surface & feature consolidation.**
Shared item-action builder for all five surfaces; notes preview: restore an Off state, replace ScrollView-in-row with `lineLimit`, Dynamic-Type-safe; badge only where it renders; help regenerated from `ListsurfCommands` (single source); sheet-chrome convention picked once; delete vestigial code (A10 list). *Invariant: an action is defined once; help matches reality.*

**Test debt (parallel to phases 3–5)**: fix the item-discarding fake; Core Data-backed duplicate/persistence tests; export-validation branch tests.

## Part C — What to do with the current uncommitted work

Worth keeping largely as-is: settings scaffold (scene + sheet), archive fixes, Details fix, duplicate naming + its tests, expand/collapse symbol swap, check-mode expand/collapse buttons, help DisclosureGroups.
Needs rework before commit: the entire macOS keyboard stack (Phase 1 deletes most of it), the double-click→Details repurposing (Phase 2 reverses it), notes `NotePreviewView` internals (Phase 6), store-side selection writes (Phase 2 picks one owner).
Recommendation: split the working tree into "keep" and "rework" commits rather than committing wholesale — the keep-list is genuinely good work and shouldn't be held hostage by the rework-list.
