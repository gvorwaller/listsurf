# Listsurf — V1 Implementation Plan

**Project**: Listsurf
**Date**: 2026-06-20
**Status**: Implementation-ready V1 plan
**Platforms**: iPhone, iPad, and Mac
**Minimum OS**: iOS 26, iPadOS 26, macOS 26
**Lineage**: Refines `codex-listsurf-V1-plan.md` (June 20) with UI/UX interaction design, architecture specifics, and document coherence fixes. Supersedes `grok-listsurf-V1-plan.md` (June 18).

---

## Executive Summary

Build Listsurf as a standalone, local-first SwiftUI app for iPhone, iPad, and Mac. Use Core Data with a local SQLite-backed persistent store, design the model for CloudKit from the beginning, and add personal iCloud synchronization after the single-device app is stable (V1.1).

The first release is a focused native outliner — not a task manager, not a collaboration platform. Its job is to make durable, deeply structured lists fast to create, easy to reorganize, and pleasant to check while moving around.

### Key Decisions

1. **Core Data** for persistence. CloudKit mirroring deferred to V1.1.
2. **Two entities** — `ListEntity` and `OutlineItemEntity`. No template/run/section entities.
3. **Duplicate + reset** replaces templates. Template-like lists stay in the library with icon/color identity; used copies get archived.
4. **Check mode is a presentation** over the same data, not separate entities.
5. **iPhone defaults to Check mode** (last-used mode per list, Check on first open). iPad/Mac default to Edit mode.

---

## Product Definition

Listsurf is a personal app for long-lived, reusable structured lists:

- Packing lists
- Event and trip preparation
- Procedures and recurring checklists
- Inventories
- Reference outlines
- Research and planning lists

It deliberately does not compete with Apple Reminders for dates, alerts, recurring tasks, or daily to-dos. It does not attempt to replace a document editor, project manager, or team workspace.

### Core Concepts

- **Lists** — long-lived containers for structured information
- **Items** — nestable, checkable rows; any item can parent other items (no separate Section entity)
- **Check mode** — a presentation layer over the same data, not separate run/state entities
- **Duplication** — copies a list with new UUIDs and optionally clears checks; replaces templates
- **Archive** — completed or inactive lists

The defining interaction is a native outline whose rows can be nested, folded, reordered, checked, annotated, duplicated, and reset without friction.

---

## Why a Standalone Apple App

For this project, remaining standalone is a feature rather than a limitation.

### Advantages

- Immediate startup and complete offline operation.
- No accounts, authentication, hosting, deployment, or server maintenance.
- Native keyboard, pointer, drag-and-drop, menu, share-sheet, and accessibility behavior.
- Private data remains on the user's devices and in their private iCloud database when sync is enabled.
- Meaningful experience with Swift, SwiftUI, Core Data, CloudKit, and Apple platform design.
- A small product surface makes the app realistic to maintain as a personal project.

### Costs

- No browser or non-Apple client.
- Cross-user collaboration is substantially harder than personal sync.
- CloudKit synchronization is asynchronous and less observable than a custom service.
- Distribution, iCloud capabilities, and production CloudKit schema management require an Apple Developer account.

### Recommendation

Do not introduce a server abstraction for a hypothetical web future. Preserve data portability with documented, versioned exports and keep domain logic independent of SwiftUI and Core Data where practical.

---

## Persistence and Sync Architecture

### Core Data, then CloudKit

Use Core Data with a local SQLite-backed persistent store. The SQLite file is Core Data's private implementation detail; the app must never directly edit it or place the live store in iCloud Drive.

Core Data is the best fit because:

- `NSPersistentCloudKitContainer` provides the established path for record-level personal sync.
- It supports local transactions, background contexts, undo integration, migrations, validation, and change tracking.
- It avoids building a custom bidirectional CloudKit synchronization engine.
- It is mature enough that the project can focus on outliner behavior instead of persistence infrastructure.

### Sync Sequence

**V1** uses the production data model locally with CloudKit mirroring disabled. The schema must obey CloudKit-compatible design constraints so enabling sync does not require a redesign.

**V1.1** enables private-database CloudKit mirroring and adds:

- iCloud account and sync-status presentation.
- Remote-change handling and UI refresh.
- Two-device conflict and convergence tests.
- Retry and recovery guidance for persistent failures.
- Export-before-reset and safe local-store recovery.

Sync must never block local editing. The local store is always the source used by the UI; CloudKit transfers changes asynchronously.

### Background Context Policy

- **Main context**: UI-driven reads (`@FetchRequest`, observation) and small writes (single item add/edit, check toggle, single move).
- **Background context**: Bulk operations — import, full-list duplication, full-list reset, export data preparation, orphan repair, position rebalancing.
- **Threshold**: Operations affecting more than ~50 items should use a background context.
- **Merge**: Background context saves; main context merges via `NSManagedObjectContextDidSave` notification. SwiftUI observation picks up merged changes.
- **V1.1**: CloudKit's `NSPersistentCloudKitContainer` manages its own background contexts for sync. The app should not interfere.

---

## Core Data Model

V1 needs two synchronized entities.

### `ListEntity`

- `id: UUID`
- `title: String`
- `notes: String?`
- `icon: String?` — SF Symbol name (app defaults to `"list.bullet"`)
- `colorName: String?` — system color name (app defaults to accent color)
- `position: Double`
- `createdAt: Date`
- `updatedAt: Date`
- `archivedAt: Date?`

### `OutlineItemEntity`

- `id: UUID`
- `listID: UUID`
- `parentID: UUID?`
- `title: String`
- `notes: String?`
- `quantity: Int64` with an effective minimum of 1
- `isChecked: Bool`
- `position: Double`
- `createdAt: Date`
- `updatedAt: Date`

Stable UUID references are intentional. They keep hierarchy operations easy to test, export, import, duplicate, and repair without relying on Core Data object identifiers or CloudKit relationship ordering.

### Application-Layer Invariants

CloudKit cannot enforce all relational constraints. The application layer must enforce:

- Every item belongs to an existing list.
- A parent belongs to the same list as its child.
- An item cannot parent itself or any ancestor.
- Missing parents are repaired by moving affected items to the list root and reporting the repair.
- Sibling order is deterministic even if two items temporarily share a position.
- All subtree mutations occur in one Core Data transaction.

### Position Ordering

Use midpoint `Double` positions for ordinary insertions and moves:

- New items inserted between positions `a` and `b` get `(a + b) / 2`.
- Items appended to the end get `lastPosition + 1.0` (or `1.0` if no siblings).
- **Rebalance trigger**: When `abs(a - b) < 1e-10` (~33 bisections before precision loss).
- **Rebalance operation**: Reassign all siblings of the affected parent, spaced by 1.0, in current sort order. Single Core Data save.
- **Tie-breaking**: Secondary sort by UUID string for deterministic rendering during sync convergence.
- Rebalancing is invisible to the user — a persistence housekeeping operation.

### Device-Local Presentation State

Do not synchronize presentation state. Keep the following per device:

- Expanded/collapsed item IDs
- Selected list and row
- Current search and filter
- Edit versus Check mode (per-list last-used mode on iPhone)
- Sidebar visibility and split-view position
- Window-specific navigation state

Use scene-owned state and `@SceneStorage` for window/session state, and a small local preferences store for durable per-device expansion and display preferences.

---

## Domain Architecture

Keep tree behavior in pure Swift types that do not import SwiftUI or Core Data.

### Tree Engine Commands

- Flattening a hierarchy for display (lazy — only expanded branches).
- Finding descendants and leaf descendants.
- Moving among siblings.
- Indenting under the previous sibling.
- Outdenting immediately after the current parent.
- Reparenting at a requested child position.
- Rejecting cycles and cross-list parenting.
- Inserting above or below a row.
- Duplicating a complete list with new UUIDs.
- Deleting a subtree.
- Checking or unchecking a subtree.
- Resetting all checks in a list or subtree.
- Calculating tri-state parent status and leaf-only progress.

Wrap persistence behind repository interfaces so commands can be tested with value fixtures. SwiftUI views should issue domain commands through a scene-scoped store.

### Module Boundaries

```
App -> Features -> Domain
App -> Persistence -> Domain
App -> Platform
Features -> Domain (directly)
Features -> Persistence (via Domain protocol implementations only)
Persistence -> Domain
Platform -> (UIKit/AppKit only, no Domain import)
Domain -> (Foundation only, nothing from project)
```

- **App**: Composition root — scenes, dependency wiring, commands.
- **Domain**: Value models, tree engine, validation, import/export structures. Imports Foundation only.
- **Persistence**: Core Data stack, repositories, migrations, CloudKit configuration. Implements Domain protocols.
- **Features**: Library, outline editor, check mode, search, archive, settings, inspector.
- **Platform**: Narrow iOS/macOS integrations that cannot be shared cleanly (e.g., AppKit `NSOutlineView` wrapper if needed).

Use Swift 6 concurrency checking. Keep UI-observed state on `@MainActor`; perform import/export and larger persistence work in background contexts.

### Error Handling Strategy

- **Persistence errors** (save failures, migration failures): Non-modal banner at the top of the active view (like Apple's connectivity banners). Persists until resolved or dismissed. Catastrophic failures (store cannot be opened): modal alert with "Export Data" and "Reset Store" options.
- **Validation errors** (cycle detection, cross-list parenting): Should never reach the user under normal operation. If they occur (corrupted import), log and show brief toast.
- **Import errors**: Summary sheet — "Imported 47 of 50 items. 3 items had invalid parent references and were placed at the root level." User chooses to accept or discard entire import.
- **Orphan repair**: One-time dismissible notification — "Some items were reorganized because their parent items were missing."
- **Implementation**: `AppError` enum in Domain with associated context. `@MainActor` error-presentation service in Features that views observe. No scattered `try/catch` + alert logic in views.

### Logging and Diagnostics

- Apple's `os.Logger` with subsystem `com.listsurf.app` and categories: `persistence`, `tree`, `import-export`, `ui`, `sync` (V1.1).
- No third-party logging frameworks.
- **Diagnostics screen** (Settings): store location, store size, item count, last export date. Invaluable for debugging before CloudKit adds opacity.
- **V1.1**: Add sync status, last sync timestamp, pending changes count, CloudKit account status.

### Undo Architecture

- **Scope**: Per-scene (per-window on Mac, per-navigation-context on iOS).
- **Undoable**: All structural mutations (add, delete, move, indent, outdent, reparent), all check mutations (check, uncheck, cascade, reset), title/notes edits, paste, import (grouped as single operation).
- **Not undoable**: Archive/restore (confirmation dialog), list deletion (confirmation dialog), export (read-only).
- **Mode-agnostic**: Undo stack spans Edit and Check mode. Checking items in Check mode and pressing undo in Edit mode undoes the check.
- **Implementation**: Register undo actions at the domain command level, not in views. Each domain command accepts `UndoManager?` and registers its inverse.
- **Grouping**: Multi-item operations (cascade check, paste, multi-select delete) register as a single undo group.

---

## V1 User Experience

### Library

The library is the app's home screen and contains active and archived lists.

- Create, rename, duplicate, archive, restore, and delete lists.
- Search list titles and item content.
- Show compact progress based on checked leaf items.
- Sort manually by default, with optional title or recently modified views.
- **List visual identity**: Each list shows an SF Symbol icon (default `list.bullet`, user-selectable from ~30 curated symbols) tinted with a user-selected accent color (~10 system colors). Helps distinguish template-like lists at a glance.

Duplication is the V1 reuse mechanism. A duplicate receives new list and item UUIDs and can optionally begin with all checks cleared.

### First-Run and Discoverability

- **One curated sample list** (e.g., "Weekend Trip Packing") demonstrating nesting, notes, quantity, and a folded branch. Titled to read as a tutorial, not placeholder data.
- **TipKit coaching tips** (3 key moments, dismiss permanently after interaction):
  1. First time in a list: "Swipe or long-press a row for more options"
  2. First time on Mac/iPad with keyboard: "Use Tab/Shift-Tab to indent and outdent"
  3. First time viewing progress: "Tap to enter Check mode"
- **Mac menu bar**: All structural commands (indent, outdent, move, add child/sibling) in the Edit or Item menu with keyboard shortcut labels. This is the Mac's built-in discoverability mechanism.
- No onboarding wizard, no tour, no overlay.

### Empty States

Every screen needs a designed empty state using `ContentUnavailableView`:

- **Empty library**: SF Symbol (`list.bullet.indent`) + "No lists yet" + prominent "Create List" button.
- **Empty list**: "Add your first item" with a tap target and hint about multiline paste.
- **No search results**: "No items match [query]" + clear button.
- **Empty archive**: "No archived lists" — simple text.
- **All items checked** (unchecked filter active): "All done!" with progress count (e.g., "24/24") and "Show All" button.

### Outline Editor

The editor is optimized for structural work:

- Unlimited practical nesting, with a tested depth target of at least 20 levels.
- Inline add and rename.
- Insert above, insert below, and add child.
- Drag-and-drop reorder and reparent.
- Keyboard move, indent, outdent, add sibling, and add child commands.
- Multi-selection for move, check, uncheck, and delete where platform controls support it.
- Fold/unfold branch and collapse/expand all.
- Multiline paste using indentation to infer hierarchy; unindented text creates siblings.
- Notes and quantity in an inspector or detail sheet (see Inspector section).
- Search with matching rows revealed inside enough ancestor context to remain understandable.
- Undo and redo for all destructive and structural edits in the current scene.

#### Drag-and-Drop Feedback

- **Insertion indicator**: A horizontal line at the proposed drop position. Indented to child level for nesting, sibling level for sibling placement.
- **Nesting intent**: Horizontal drag position determines sibling vs. child. Dragging right proposes nesting under the row above; dragging left proposes sibling.
- **Invalid drops**: Dragging onto own descendant (cycle) shows prohibition indicator.
- **Multi-row drag**: Selected rows stack visually during drag.

### Check Mode

Check mode is a separate presentation, not a separate data model.

- Large checkbox and row targets.
- Minimal editing controls.
- Checked, unchecked, and all-items filters.
- Visible list and branch progress.
- Parent rows display checked, unchecked, or mixed state derived from leaf descendants.
- Checking a parent applies the chosen state to all descendants in one transaction.
- Reset is available for a branch or entire list and requires confirmation plus undo.
- Optional automatic hiding of newly checked rows is off by default.

#### Entry and Exit

- **iPhone**: Last-used mode per list (stored locally by list UUID), defaulting to Check mode on first open. Edit accessible via toolbar toggle. Rationale: phone use is mostly checking, but lists being actively built shouldn't force Check mode.
- **iPad/Mac**: Opens Edit mode by default. Toolbar toggle switches between modes (SF Symbols: `checklist` for Check, `list.bullet.indent` for Edit). Toggle persists per-list per-device via `@SceneStorage`.
- **Mac**: Additionally, "View > Check Mode" menu item with keyboard shortcut.
- Switching preserves scroll position and commits any in-progress edit.

#### Haptic Feedback (iPhone)

- Single item check/uncheck: light impact.
- Parent cascade: medium impact on tap, soft notification on completion.
- Reset confirmation: warning notification feedback.
- Drag pickup: medium impact.
- All haptics guarded behind `#if os(iOS)`.

### Inspector / Detail Sheet

- **Mac**: Trailing `.inspector()` panel. Shows details for selected row: title (editable), notes (multiline editor), quantity stepper, creation/modification dates. Collapsible, visibility persisted via `@SceneStorage`. No row selected: shows list-level info (title, notes, item count, progress).
- **iPad**: Same inspector in regular horizontal size class. Compact size class: half-height sheet (`.presentationDetents([.medium, .large])`).
- **iPhone**: Sheet from context menu ("Details") or "i" button. Uses `.presentationDetents([.medium, .large])`.
- **Design constraint**: The inspector is never required for basic operations. Users who never open it can still create, check, nest, and reorder items.

### Search

- **Library search**: `.searchable()` on sidebar/library. Filters list titles and optionally item content (scope toggle). Results show list titles with match context subtitle.
- **In-list search**: Filters the current outline. Non-matching rows hidden except ancestors of matches (hierarchy context). Matching text highlighted. Cmd-F activates on Mac/iPad.
- **Dismiss behavior**: Clearing search restores previous expansion state. Tapping a result then dismissing search keeps focus on that row in the full outline.

### Toolbar Adaptation

- **Edit mode** (Mac/iPad): Add Item, Add Child, Indent, Outdent, Move Up/Down, Fold/Unfold, Search, Inspector toggle, Check Mode toggle.
- **Check mode** (Mac/iPad): Filter selector (All/Unchecked/Checked), Reset, Progress display, Edit Mode toggle.
- **iPhone**: Minimal in both modes. Check: filter, progress, reset. Edit: add, paste, search.
- **Selection-sensitive**: Multi-selection shows batch operations (Check All, Uncheck All, Delete).
- **Context menu parity**: Every toolbar action also available in long-press/right-click context menu.

### Animation and Transitions

- **Row insert/delete**: Slide animations via stable `id` in `ForEach`.
- **Fold/unfold**: Children slide vertically; disclosure triangle rotates.
- **Check mode switch**: Cross-fade toolbar and row layout as a unit.
- **Check cascade**: Short stagger (50ms/child, 300ms max) for visual confirmation.
- **Respect `UIAccessibility.isReduceMotionEnabled`**: All transitions fall back to dissolve or instant swap.

### Platform Composition

**Mac** uses a `WindowGroup` with `NavigationSplitView`: native source-list sidebar, outline editor, and optional inspector. Important operations appear in menus, toolbars, context menus, and keyboard shortcuts. Multiple windows may open the same or different lists; undo, selection, and scroll position are per-window. Simultaneous edits to the same field use last-write-wins (acceptable for single-user V1).

**iPad** uses the same split-view concept with touch-appropriate toolbars, drag/drop, hardware keyboard commands, and inspector (panel or sheet depending on size class).

**iPhone** uses `NavigationStack`. Library opens the list in last-used mode (Check or Edit). Structural commands live in context menus and focused sheets.

The app should use semantic system colors, Dynamic Type, VoiceOver labels, reduced-motion behavior, and current system materials. A distinctive visual identity can be added after interaction density and hierarchy readability are correct.

### Keyboard Shortcut Discoverability

- **Mac**: All shortcuts appear in menu items (standard Mac discoverability). App should have an "Item" menu with all structural commands.
- **iPad**: `UIKeyCommand` / SwiftUI `.keyboardShortcut()` integration so the Command-hold overlay shows available commands.
- No dedicated keyboard shortcuts settings screen for V1.

---

## Proven Behaviors from `trips`

The `trips` packing-list implementation provides useful product evidence. Carry forward:

- Parent/child hierarchy with sibling ordering.
- Pure, unit-testable tree operations.
- Transactional reparenting and reorder.
- Cycle and cross-container rejection.
- Parent-first tree copying.
- Fast multiline item entry.
- Insert above and below.
- Subtree checkbox cascade.
- Tri-state parent checkboxes.
- Progress based on leaves rather than category rows.
- Per-device folding.
- Clear subtree-aware delete warnings.

Improve in the native app:

- Replace rows full of tiny buttons with drag/drop, menus, keyboard commands, and focused editing surfaces.
- Make undo a primary safety mechanism instead of relying only on confirmations.
- Give checking its own ergonomic mode.
- Preserve expansion and selection naturally per scene.
- Use native accessibility semantics and focus management.

---

## Import, Export, and Data Ownership

V1 supports a deliberately small set of formats.

### Versioned JSON

JSON is the canonical lossless backup format. Define an export envelope with:

- `format: "listsurf"`
- `schemaVersion: Int`
- `exportedAt: Date`
- `appVersion: String`
- Complete list and item records

Imports validate the entire payload before writing. UUID collisions create new UUIDs. A failed import writes nothing.

### OPML

Support OPML import/export for outliner interoperability. Preserve title, nesting, notes, quantity, and checked state where attributes are available. Unknown attributes are ignored but must not invalidate the document.

### Markdown and Plain Text

Export nested Markdown lists with checkbox syntax. Import Markdown bullets, checkbox markers, and indentation. Multiline plain text paste uses indentation but does not attempt AI interpretation.

Defer CSV and natural-language/AI parsing.

Use native file import/export and share sheets. Provide an explicit full-library backup command before CloudKit is enabled.

---

## V1 Scope

### Included

- Native iPhone, iPad, and Mac app.
- List library and archive.
- List visual identity (icon + accent color).
- Nested outline editing.
- Check mode with platform-appropriate entry/exit.
- Notes, quantity, and inspector/detail sheet.
- Reorder, indent, outdent, folding, and multiline paste.
- Duplicate as reusable list.
- Search (library and in-list).
- Undo/redo.
- JSON, OPML, and Markdown import/export.
- Device-local presentation preferences.
- Accessibility and keyboard support.
- Local Core Data persistence with a CloudKit-compatible schema.
- Empty states, TipKit discoverability, haptic feedback.
- Diagnostics screen.
- Error handling (banners, import summary, orphan repair notification).

### Explicitly Deferred

- CloudKit activation and production sync support (V1.1).
- Cross-user sharing and collaboration.
- Dedicated template and run entities.
- Attachments, photos, and rich media.
- Due dates, reminders, calendar integration, and notifications.
- Tags, smart folders, inventory catalogs, and cross-list references.
- AI-assisted parsing or generation.
- Widgets, App Intents, and Shortcuts.
- Web clients, accounts, APIs, and servers.
- CSV and custom styling systems.

---

## Implementation Sequence

### Phase 0 — Project and Persistence Foundation

- Create the multiplatform Xcode project and shared module boundaries (App, Domain, Persistence, Features, Platform).
- Configure Core Data locally with CloudKit disabled.
- Define the sync-compatible model and migration policy.
- Add deterministic fixtures, previews, and an in-memory test store.
- Add versioned JSON export early enough to recover development data.
- Set up `os.Logger` with subsystem and categories.

### Phase 1 — Tree Engine

- Implement and exhaustively test hierarchy traversal and mutation commands.
- Enforce same-list parenting and cycle prevention.
- Implement midpoint ordering and sibling rebalance.
- Implement leaf-only progress, tri-state checks, reset, duplicate, and delete.
- Implement undo registration at the domain command level.
- Add performance test fixture (1,000 items / 10 levels).

### Phase 2 — Mac and iPad Authoring

- Build the library with icon/color identity, split-view editor, inspector, menus, commands, and drag/drop.
- Add inline editing, multiline paste, folding, search, multi-selection, and undo.
- Implement toolbar adaptation (Edit vs. Check mode, selection-sensitive).
- Add empty states, TipKit tips, and keyboard shortcut discoverability.
- Implement drag-and-drop insertion indicators and nesting feedback.
- Build error presentation (banners, import summary sheet).

### Phase 3 — iPhone and Check Mode

- Build the compact library and last-used-mode list opening (Check default).
- Validate target sizes, one-handed use, filtering, progress, reset, and context menus.
- Add haptic feedback for check interactions.
- Test with realistic packing and procedure lists on a physical phone.

### Phase 4 — Interchange and Hardening

- Add JSON, OPML, and Markdown round trips.
- Add archive/restore, recovery messaging, accessibility, performance tests, and migration fixtures.
- Build diagnostics screen.
- Exercise the app on real lists until the model and commands stop changing frequently.

### Phase 5 — V1.1 Personal Sync

- Enable the private CloudKit database in development.
- Initialize and inspect the CloudKit schema before production promotion.
- Add remote-change handling, sync status, diagnostics, and recovery.
- Test two-device offline edits, deletes, moves, duplicate positions, and convergence.
- Promote the CloudKit schema only after destructive model changes are unlikely.

---

## Testing and Acceptance Criteria

### Domain Tests

- Flattening always emits parents before descendants in visible order.
- Move, indent, outdent, and reparent preserve every subtree.
- Self-parenting, descendant-parenting, missing parents, and cross-list parenting are rejected or repaired.
- Duplicate produces an equivalent tree with entirely new UUIDs.
- Parent check state is derived correctly for empty, mixed, checked, and unchecked branches.
- Progress counts only leaves.
- Reset and subtree deletion are atomic and undoable.
- Position rebalance preserves displayed order.
- Undo reverses every undoable command correctly.

### Persistence and Interchange Tests

- Store creation and every model migration succeed from committed fixtures.
- Failed multi-row operations roll back completely.
- JSON round trips without loss.
- OPML and Markdown preserve hierarchy and supported metadata.
- Malformed imports produce actionable errors and no partial records.
- Orphan repair is deterministic and reported.
- Background context operations merge correctly to main context.

### UI Tests

- Create and edit a nested list using touch, pointer, and keyboard paths.
- Drag within a sibling group and into/out of a parent with correct insertion indicators.
- Paste an indented outline and immediately undo it.
- Search reveals matches with ancestor context; dismiss preserves focus.
- Check mode supports parent cascade, mixed state, filtering, reset, and undo.
- Mode switching preserves scroll position and commits edits.
- Archive and restore preserve content and order.
- VoiceOver identifies hierarchy level, expansion state, check state, quantity, and available actions.
- Dynamic Type does not hide primary checking controls.
- Empty states display correctly for all five screens.
- Inspector shows/hides correctly on all platforms and size classes.
- Haptic feedback fires on iPhone check interactions (manual verification).
- TipKit tips appear at correct moments and dismiss permanently.

### V1 Acceptance

V1 is complete when a deeply nested real-world list can be efficiently authored on Mac or iPad, checked comfortably on iPhone (with haptic feedback and large targets), reset or duplicated safely, searched, archived, exported, restored, and used completely offline without data loss. Template-like lists are visually distinguishable in the library via icon and color.

### V1.1 Acceptance

V1.1 is complete when edits, checks, moves, duplicates, archives, and deletes made on either of two devices converge without corrupting hierarchy; offline changes recover when connectivity returns; and persistent sync failures are visible and recoverable without deleting the user's only copy.

---

## Risks and Guardrails

### Scope Creep

The largest product risk is becoming a task manager, note system, or collaboration service. New features should be accepted only when they improve creating, structuring, reusing, or executing durable lists.

### Tree Interaction Complexity

Native hierarchical editing is the hardest part of the app. Build and test the domain commands before committing to a highly customized row UI. Every gesture must have a discoverable menu or keyboard equivalent.

### CloudKit Constraints

CloudKit schema changes become restrictive after production promotion, and sync is eventually consistent. Keep the synchronized model small, avoid unnecessary entities, use stable UUIDs, and defer production schema deployment until V1 usage validates the model.

### SwiftUI Platform Gaps

Shared SwiftUI views should not force identical interaction on all platforms. Use narrow AppKit or UIKit interoperability only when native SwiftUI cannot provide reliable focus, command, drag/drop, or outline behavior.

### Data Safety

Undo, atomic commands, migration tests, and lossless exports are V1 requirements. Confirmation dialogs alone are not an adequate recovery strategy.

---

## Performance Guidance

- **Lazy flattening**: Only expand visible branches. Incremental recompute on expansion change, not full re-flatten on every mutation.
- **Performance test fixture**: 1,000 items / 10 levels deep. Targets: <100ms flatten, <500ms duplicate on a reasonable device.
- **Don't over-engineer**: Typical V1 personal use is 50-200 items per list. Don't build pagination or virtual scrolling until profiling shows a need.

---

## Post-V1 Possibilities

Consider only after V1 and V1.1 are reliable:

- Promote selected lists to reusable templates if duplication proves insufficient.
- App Intents and Shortcuts for opening a list or starting Check mode.
- Widgets showing progress or next unchecked items.
- Photos and attachments using CloudKit assets.
- Saved filters or smart collections.
- Cross-list reusable inventory items.
- Version history beyond scene undo.
- Opt-in list sharing through CloudKit shared databases.

Cross-user sharing should be treated as a separate product phase with its own permissions, invitation flows, and conflict expectations.

---

## Final Direction

Listsurf should begin as a small, high-quality native outliner with unusually good checking ergonomics. Two persisted entities, one pure Swift tree engine, one local store, native platform presentations, portable exports, and enough visual identity (icon + color) to make a library of lists scannable.

Build the local experience first. Make it trustworthy enough to hold real lists. Then add personal CloudKit sync without changing what the app fundamentally is.
