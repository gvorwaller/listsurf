# Listsurf Codebase Review Remediation Plan

**Date:** June 21, 2026  
**Source:** Full repository review at commit `d5ac6c8`  
**Status:** Implementation started; first remediation slice implemented and tested

## Objective

Bring the current prototype from a functioning feature baseline to a trustworthy
local-first application. Data integrity and recoverability come before adding
more interaction polish or CloudKit synchronization.

The review baseline passed all existing tests:

- iOS Simulator: 72 passed, 0 failed
- macOS: 72 passed, 0 failed
- SwiftPM Release: 70 passed, 0 failed

Those tests establish a useful baseline, but they do not cover rapid-write
ordering, transaction rollback, application-store error presentation, desktop
command routing, aggregate parent checking, collapsed-tree search, or most
destructive actions.

## Implementation principles

1. Never acknowledge an edit in the UI unless it is queued for durable,
   ordered persistence.
2. Operations spanning lists and outline items must succeed or fail as one
   transaction.
3. Persistence failures must be visible and actionable; logging alone is not
   sufficient.
4. Tree behavior must have one canonical interpretation shared by rendering,
   filtering, and mutation.
5. Commands must be scoped to the focused scene rather than broadcast globally.
6. Add regression coverage with each correction instead of relying on smoke
   tests to catch data-integrity failures.
7. Do not enable CloudKit until the schema, migrations, transactions, and
   conflict-sensitive ordering behavior are stable.

## Phase 1 — Persistence integrity and error visibility

### Ordered outline writes

- Replace fire-and-forget mutation saves with a serialized persistence queue.
- Preserve UI responsiveness by applying changes optimistically on the main
  actor while processing snapshots in mutation order.
- Ensure a late completion can never overwrite a newer edit.
- Track pending persistence and expose failures through observable store state.
- Flush or otherwise account for pending changes during lifecycle transitions.

### Atomic list operations

- Add repository-level operations for:
  - deleting a list and all of its items;
  - duplicating a list and all of its items.
- Execute each operation in one managed-object context and one save.
- Roll back the context on failure.
- Move orchestration out of `AppStore`; it should request one atomic operation.

### Error presentation

- Introduce a shared, observable error-presentation state.
- Route `AppStore` and `ListStore` load/save failures into that state.
- Present a persistent banner for recoverable failures.
- Provide dismiss and retry/reload actions where meaningful.
- Replace the production `fatalError` store-load path with an initialization
  failure that the app can present. Keep explicit failure behavior in tests.

### Tests

- Verify ordered writes using a controllable delayed repository.
- Verify failed transactions do not leave partial list or item records.
- Verify `ListStore` and `AppStore` publish failures.
- Verify bulk context saves merge into reads correctly.

## Phase 2 — Tree, checking, search, and ordering correctness

### Aggregate check semantics

- Use `FlatRow.checkState`, not stored parent `isChecked`, when deciding the
  next parent toggle state.
- Filter parent rows using aggregate check state.
- Define mixed-state behavior explicitly: tapping a mixed parent checks the
  entire subtree.
- Add tests for checked, unchecked, and mixed parent toggles and filters.

### Expansion and search

- Put expansion state into `FlatRow` or pass it explicitly to row views.
- Fix disclosure indicators so collapsed and expanded states are represented.
- Search the full tree, include matching descendants and required ancestors,
  and reveal the matching path without destroying the user's prior expansion
  state.
- Add an in-list `.searchable` UI and Command-F integration.
- Highlight matching text where practical.

### Position management

- Centralize sibling insertion and movement position calculation.
- Detect insufficient midpoint precision and rebalance the affected sibling
  group in the same transaction.
- Prevent repeated inserts after one reference from producing duplicate
  positions.
- Add long-sequence tests for insert, move, indent, and outdent ordering.

### Corruption resilience

- Add visited-node detection to recursive traversal and ancestor walks.
- Run deterministic orphan/cycle repair during load or an explicit repair
  operation.
- Surface repaired-item counts to the user.

## Phase 3 — Scene-scoped commands and undo

- Replace `NotificationCenter` command broadcasts with `FocusedValue` /
  `FocusedBinding` command targets.
- Enable and disable menu items based on focused selection and legal actions.
- Wire New List, add sibling/child, indent/outdent, move, delete, check mode,
  inspector, expand, and collapse commands.
- Make selection, expansion, inspector visibility, check mode, and undo
  scene/window scoped.
- Register undo at the command/mutation boundary.
- Coalesce inspector typing into meaningful undo groups rather than one entry
  per keystroke.
- Add macOS UI tests for menu commands and keyboard shortcuts.

## Phase 4 — Destructive-action safety and core UX completion

- Add confirmation for permanent list deletion, archive/restore where required,
  subtree deletion, multi-delete, and reset operations.
- Do not allow full-swipe permanent deletion without confirmation.
- Disable reset when there is nothing to reset.
- Wire list rename, notes, icon, and color editing using the existing identity
  editor.
- Make archive controls visibly discoverable on macOS and iPad.
- Make archive and inspector presentation responsive on compact iPhone widths.
- Preserve scroll and edit state when changing Edit/Check mode.
- Add platform-appropriate haptics for iPhone check interactions.
- Add VoiceOver labels, values, hints, and selected-state announcements for
  icon/color pickers and structural controls.

## Phase 5 — Performance and Core Data hardening

- Compute check state and leaf progress once per tree rebuild rather than once
  per rendered row.
- Avoid rebuilding the full flattened tree for every inspector keystroke.
- Replace per-object bulk fetches with set-based fetches keyed by UUID.
- Add UUID uniqueness constraints and useful fetch indexes.
- Move from an entirely programmatic anonymous model to a versioned model and
  committed migration fixtures, or provide an equivalent explicit versioning
  mechanism.
- Add deterministic tie-break sorting everywhere position is used.
- Add performance baselines for large edits, search, expansion, and bulk saves,
  not only flatten and duplicate.

## Phase 6 — Import/export, recovery, and project reproducibility

- Wire full-library JSON export and validated import.
- Add OPML and Markdown interchange after JSON recovery is complete.
- Ensure malformed imports never partially modify the store.
- Add a diagnostics/settings surface with store location, size, counts, and
  last-export metadata.
- Add explicit backup/export before CloudKit activation.
- Update `project.yml` so it fully describes logic tests, UI tests, schemes,
  test plans, entitlements, and current deployment targets.
- Resolve the deployment-target comment mismatch in `Package.swift`.
- Add actual app icon assets and complete release metadata.

## Phase 7 — CloudKit readiness and synchronization

Begin only after Phases 1, 2, 5, and the JSON recovery portion of Phase 6 are
stable.

- Validate the model against CloudKit constraints.
- Introduce `NSPersistentCloudKitContainer`.
- Add persistent history and remote-change processing where required.
- Test two-device offline edits, deletes, reordering, duplicate positions,
  archive state, and eventual convergence.
- Add sync status and recovery diagnostics.
- Delay production schema promotion until destructive schema changes are
  unlikely.

## Verification gates

Every phase must:

1. pass focused unit tests for its failure modes;
2. pass the complete SwiftPM suite;
3. pass both iOS and macOS Xcode test plans;
4. leave the worktree free of generated or unrelated changes;
5. update this devlog with completed work, remaining risks, and test results.

## Initial implementation slice

Implementation begins with Phase 1. The first code change will establish a
transactional persistence API and ordered outline-mutation persistence, then
add regression tests before any broader UI work.

## Progress update — June 21, 2026

The first implementation slice is complete. It covers the highest-risk data-integrity problems and a small amount of tree/UI correctness that was blocking reliable tests.

### Implemented

- Added transactional repository operations for saving a duplicated list with its items and deleting a list with all of its items.
- Updated duplicate and delete flows to use those atomic operations instead of multi-step orchestration in `AppStore`.
- Serialized `ListStore` background persistence so rapid edits are saved in mutation order instead of racing independent tasks.
- Added a shared `AppErrorStore` plus a visible SwiftUI error banner for load/save failures from app and list stores.
- Added user-facing `LocalizedError` descriptions to `AppError`.
- Fixed aggregate check behavior so filters and parent toggles use computed `FlatRow.checkState` rather than stale parent storage.
- Added expansion state to `FlatRow` and wired editor/check disclosure indicators to real expanded/collapsed state.
- Fixed outline search model so collapsed descendant matches are revealed with required ancestors.
- Added iOS outline search UI. macOS in-list search is intentionally deferred because the direct SwiftUI `.searchable` integration triggered an AppKit toolbar crash in the macOS UI test host.
- Added a visible macOS sidebar `New List` action and slightly increased UI-test startup wait time to make full-suite macOS launch tests stable.
- Added SwiftPM-only `FeaturesTests` coverage for write ordering, error publication, aggregate check filtering/toggling, and collapsed-tree search.
- Added persistence tests for atomic list+item save and delete.

### Deferred from Phase 1

- Production persistent-store initialization still needs a non-`fatalError` recovery path. This remains part of the next persistence-hardening slice.
- Error banners are dismissible but do not yet include retry/reload actions.
- Core Data uniqueness constraints, explicit model versioning, and migration fixtures remain Phase 5 work.
- Xcode project/test-plan generation does not yet include the new `FeaturesTests` target; those tests currently run through `swift test`.

### Verification

- `swift test`: 77 passed, 0 failed.
- Xcode iOS `test_sim`: 74 passed, 0 failed.
- Xcode macOS `test_macos`: 74 passed, 0 failed.

### Tooling note

The local `apply_patch` helper failed because the installed Codex package references a missing executable. File edits in this slice were made with scoped local script edits instead. That should be fixed separately if we want the standard patch workflow back.

## Progress update — June 22, 2026

The remaining Phase 1 closeout items were implemented, and the first Phase 2
data-integrity slice was completed.

### Implemented

- Reinstalled the real `@openai/codex` npm package so `apply_patch` works
  normally again; no symlink workaround is in use.
- Replaced the production persistent-store `fatalError` path with captured
  store-load failure state.
- Added a store-corruption recovery screen so a persistent-store load failure is
  presented instead of crashing the app.
- Added retry/reload actions to error presentations:
  - app/list load errors can retry load;
  - app save errors can reload lists;
  - list save errors can reload the current list.
- Replaced the new-list alert with a stable sheet-based prompt. This fixed
  flaky macOS alert text-field automation and leaves room for richer list
  identity editing later.
- Added cycle-safe tree traversal for descendants, ancestors, check state, and
  leaf progress.
- Added invalid-parent repair for missing-parent, self-parent, and cycle cases.
  Repaired items are promoted to root, persisted, and surfaced through the
  repair notification.
- Added sibling position normalization when positions are duplicated or midpoint
  gaps collapse.
- Included `FeaturesTests` in both iOS and macOS Xcode logic-test bundles.
- Updated `project.yml` with explicit logic-test targets that include
  `Tests/FeaturesTests`.
- Added tests for retry actions, load-time invalid-parent repair, cycle-safe
  descendants, cycle repair, duplicate-position rebalance, and collapsed
  midpoint rebalance.

### Verification

- `swift test`: 83 passed, 0 failed.
- Xcode iOS `test_sim`: 85 passed, 0 failed.
- Xcode macOS `test_macos`: 85 passed, 0 failed.
- iOS manual smoke launch: `build_run_sim` succeeded; screenshot captured at
  `/var/folders/wv/4ds24crj46n6dk__gc2ysywm0000gn/T/screenshot_optimized_801d4b7b-a48c-473b-8ec3-36268bbfe6eb.jpg`.
- macOS manual smoke launch: `build_run_macos` succeeded; screenshot captured
  at `/private/tmp/listsurf-macos-launch.jpg`.
- `git diff --check`: clean.

### Remaining risks

- Core Data still uses a programmatic model without UUID uniqueness constraints,
  indexes, or explicit migration fixtures. That remains Phase 5 work.
- Scene-scoped commands and robust undo are still Phase 3 work.
- Destructive confirmation flows and broader UX/accessibility polish are still
  Phase 4 work.

## Progress update — June 22, 2026, Phase 3 command-routing slice

The first Phase 3 command-routing slice is complete.

### Implemented

- Replaced global `NotificationCenter` menu-command broadcasts with
  focused scene command actions.
- Added separate focused command action models for app-level commands and
  list/editor-level commands.
- Replaced the system New command group with Listsurf's scene-routed New List
  command so Cmd-N opens the app's New List sheet.
- Moved New List sheet ownership from `LibrarySidebar` to `ContentView` so it is
  scene-wide instead of sidebar-local.
- Routed item commands through the focused selected-list scene:
  - add item below;
  - add item above;
  - add child;
  - indent/outdent;
  - move up/down;
  - delete selection;
  - toggle check mode;
  - toggle inspector;
  - expand/collapse all.
- Changed the editor add trigger from a Boolean to a request carrying the target
  item ID, so command-driven "Add Item Below" can add beneath the selected row.
- Added a macOS UI regression proving Cmd-N opens the New List sheet and creates
  a list through the command path.

### Verification

- `swift test`: 83 passed, 0 failed.
- Xcode iOS `test_sim`: 85 passed, 0 failed.
- Xcode macOS `test_macos`: 86 passed, 0 failed.

### Remaining Phase 3 work

- Add focused command coverage for row-level keyboard shortcuts beyond Cmd-N.
- Tighten command enable/disable semantics for mixed or multi-selection cases.
- Improve undo grouping for text-field editing; current undo is functional but
  still coarse.

## Progress update — June 22, 2026, Phase 4 destructive-action safety slice

The first Phase 4 safety slice is complete.

### Implemented

- Added explicit confirmation before deleting an active list from the library
  context menu.
- Added explicit confirmation before permanently deleting an archived list from
  the archive context menu or swipe action.
- Disabled full-swipe destructive deletion for archived lists and outline rows.
- Added explicit confirmation before deleting an outline item from its context
  menu or swipe action.
- Routed the focused Command-Delete item command through the same confirmation
  flow instead of deleting the selection immediately.
- Added explicit confirmation before resetting all checks in Check Mode.
- Added explicit confirmation before resetting a checked branch.
- Disabled Reset All when no items are checked.
- Disabled Reset Branch for already-unchecked branches.
- Added a macOS UI regression for Command-Delete to prove the command presents
  confirmation before deleting the selected item.
- Refactored the macOS UI test helper for adding an item so destructive-action
  tests can reuse the same setup path.

### Verification

- `swift test`: 83 passed, 0 failed.
- Xcode iOS `test_sim`: 85 passed, 0 failed.
- Xcode macOS `test_macos`: 87 passed, 0 failed.

### Notes

- A direct sandboxed `xcodebuild -list` attempt failed because Xcode needed to
  write outside the workspace (`~/Library`, CoreSimulator, SwiftPM caches). The
  verified app-target runs used XcodeBuildMCP session defaults instead.
- Confirmation dialogs use explicit Boolean bindings rather than
  `confirmationDialog(item:)` because this project's deployment/toolchain setup
  did not expose the item-based overload during package compilation.

### Remaining Phase 4 work

- Add targeted confirmation coverage for iOS swipe/context flows where the UI
  automation is stable enough to justify it.
- Wire list rename, notes, icon, and color editing through the existing
  identity editor.
- Make archive controls more visibly discoverable on macOS and iPad.
- Improve compact-width archive and inspector presentation.
- Preserve scroll and edit state when switching Edit/Check mode.
- Add platform-appropriate iPhone check haptics.
- Add VoiceOver labels, values, hints, and selected-state announcements for
  icon/color pickers and structural controls.

## Progress update — June 22, 2026, Phase 4 identity and discoverability slice

The second Phase 4 UX slice is complete.

### Implemented

- Reused the existing `ListIdentityEditor` for both new-list creation and
  editing existing lists.
- New-list creation now supports title, notes, icon, and color instead of title
  only.
- Added an Edit Details sheet for active lists from the library context menu.
- Added an Edit Details sheet for archived lists from the archive context menu.
- Added an Edit List toolbar action in the detail view so list metadata editing
  is discoverable without relying on sidebar context menus.
- Synchronized edited list metadata back into the open detail view so the
  navigation title and list inspector update after saving.
- Added a visible macOS sidebar Archive button below New List, using a distinct
  accessibility identifier to avoid ambiguous UI automation targets.
- Added accessibility labels, values, and identifiers for list icon and color
  choices.
- Preserved Return-to-create behavior in the new-list sheet.

### Verification

- `swift test`: 83 passed, 0 failed.
- Xcode iOS `test_sim`: 85 passed, 0 failed.
- Xcode macOS `test_macos`: 87 passed, 0 failed.

### Notes

- The first macOS UI run after adding the richer New List sheet exposed an
  ambiguous `library.newList` target between toolbar/sidebar actions. The
  sidebar-bottom action now uses `library.newList.sidebar`, leaving
  `library.newList` for the primary toolbar action.
- The editor intentionally remains a simple sheet-based flow. More advanced
  inline title editing and inspector-integrated list metadata editing can wait
  until command/undo grouping is tightened.

### Remaining Phase 4 work

- Add targeted confirmation coverage for iOS swipe/context flows where the UI
  automation is stable enough to justify it.
- Preserve scroll and edit state when switching Edit/Check mode.
- Add more complete VoiceOver hints and selected-state traits for structural
  controls beyond the list identity icon/color picker.

## Progress update — June 22, 2026, Phase 4 polish and Phase 5 model-hardening slice

Phase 4 polish continued, and the first Phase 5 Core Data hardening slice is
complete.

### Implemented

- Added a narrow `Platform` target dependency for platform-specific helpers.
- Added iPhone haptic feedback when check-mode items are toggled.
- Added VoiceOver labels and hints for check-mode disclosure controls.
- Added VoiceOver values and hints for check-state buttons, including mixed
  branch state.
- Added compact presentation detents for:
  - the New List sheet;
  - the Archive sheet;
  - list identity edit sheets;
  - compact inspector presentation.
- Added UUID uniqueness constraints for `ListEntity` and `OutlineItemEntity`.
- Added Core Data fetch indexes for active/archived list ordering and outline
  list/parent/position access patterns.
- Added a persistence model regression test proving the uniqueness constraints
  and index definitions exist.

### Verification

- `swift test`: 84 passed, 0 failed.
- Xcode macOS `test_macos`: 88 passed, 0 failed.
- Xcode iOS `test_sim`: 86 passed, 0 failed.
- Xcode iOS diagnostics: no warnings after marking the UIKit haptics helper
  `@MainActor`.

### Notes

- A sandboxed `swift test` run failed before compilation because the current
  Xcode/SwiftPM toolchain wanted to write compiler caches under `~/.cache` and
  `~/Library`. The verified `swift test` run used the approved escalated
  `swift test` prefix.
- This keeps the programmatic Core Data model for now. A versioned model or an
  equivalent explicit migration mechanism is still needed before CloudKit.

### Remaining Phase 4 work

- Add targeted confirmation coverage for iOS swipe/context flows where the UI
  automation is stable enough to justify it.
- Preserve scroll and edit state when switching Edit/Check mode.
- Add more complete VoiceOver hints and selected-state traits for structural
  controls beyond the list identity icon/color picker and check rows.

### Remaining Phase 5 work

- Add performance baselines for large edits, search, expansion, and bulk saves.

## Progress update — June 22, 2026, Phase 5 migration and bulk-repository slice

The second Phase 5 persistence-hardening slice is complete.

### Implemented

- Added explicit programmatic Core Data model versions:
  - `ListsurfModel.v1.initial`;
  - `ListsurfModel.v2.constraints-and-indexes`.
- Marked the current model version explicitly instead of leaving the model
  anonymous.
- Enabled automatic lightweight migration and inferred mapping on persistent
  store descriptions.
- Added a real migration fixture test:
  - creates a SQLite store with the v1 model;
  - inserts list and item data;
  - opens the store through the current stack;
  - verifies list/item data survives migration.
- Replaced remaining per-item outline `saveAll` fetch loops with a single
  set-based `id IN` fetch.
- Replaced outline `deleteAll` per-id fetch loops with a single set-based
  `id IN` fetch.
- Added regression coverage proving bulk save updates existing rows instead of
  duplicating them.
- Added regression coverage proving bulk delete removes only matching IDs.

### Verification

- `swift test`: 87 passed, 0 failed.
- Xcode iOS `test_sim`: 89 passed, 0 failed.
- Xcode macOS `test_macos`: 91 passed, 0 failed.

### Notes

- The project still uses a programmatic model, but it now has an explicit
  version identity and an old-store migration test. This is enough to catch
  accidental incompatible model changes while we decide whether to move to a
  committed `.xcdatamodeld` before CloudKit.

### Remaining Phase 5 work

- Add performance baselines for large edits, search, expansion, and bulk saves.
- Profile whether additional repository fetch optimizations matter in real
  large-list usage.
