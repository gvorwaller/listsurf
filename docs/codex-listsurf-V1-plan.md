# Listsurf — Native Structured Lists App Plan

**Project**: Listsurf  
**Date**: 2026-06-20  
**Status**: Refined V1 product and technical direction  
**Platforms**: iPhone, iPad, and Mac  
**Minimum OS**: iOS 26, iPadOS 26, macOS 26

---

## Executive Recommendation

Build Listsurf as a standalone, local-first SwiftUI app for iPhone, iPad, and Mac. Use a local Core Data persistent store, design its model for CloudKit from the beginning, and add personal iCloud synchronization after the single-device app is stable.

The first release should be a focused native outliner, not a generalized task manager and not a miniature collaboration platform. Its job is to make durable, deeply structured lists fast to create, easy to reorganize, and pleasant to check while moving around.

The strongest parts of the original proposal are the CarbonFin-inspired hierarchy, native Apple direction, local-first posture, and emphasis on packing/checking ergonomics. The main changes recommended here are:

- Choose one persistence direction instead of leaving GRDB, SwiftData, and Core Data unresolved.
- Do not synchronize a live SQLite file through iCloud Drive.
- Replace the early templates/runs/run-state subsystem with one simpler list model plus duplicate, reset, and archive.
- Reduce V1 import/export formats and defer features that do not strengthen the core outliner.
- Treat Mac/iPad authoring and iPhone checking as distinct presentations of the same data and commands.
- Define tree integrity, undo, migrations, recovery, and eventual sync behavior before implementation.

## Product Definition

Listsurf is a personal app for long-lived, reusable structured lists:

- Packing lists
- Event and trip preparation
- Procedures and recurring checklists
- Inventories
- Reference outlines
- Research and planning lists

It deliberately does not compete with Apple Reminders for dates, alerts, recurring tasks, or daily to-dos. It also does not attempt to replace a document editor, project manager, or team workspace.

The defining interaction is a native outline whose rows can be nested, folded, reordered, checked, annotated, duplicated, and reset without friction.

## Why a Standalone Apple App Is the Right Choice

For this project, remaining standalone is a feature rather than a limitation.

### Advantages

- Immediate startup and complete offline operation.
- No accounts, authentication, hosting, deployment, or server maintenance.
- Native keyboard, pointer, drag-and-drop, menu, share-sheet, and accessibility behavior.
- Private data remains on the user's devices and in their private iCloud database when sync is enabled.
- The project provides meaningful experience with Swift, SwiftUI, Core Data, CloudKit, and Apple platform design.
- A small product surface makes the app realistic to maintain as a personal project.

### Costs

- No browser or non-Apple client.
- Cross-user collaboration is substantially harder than personal sync.
- CloudKit synchronization is asynchronous and less observable than operating a custom service.
- Distribution, iCloud capabilities, and production CloudKit schema management require an Apple Developer account.
- A native app needs platform-specific interaction work even when most source code is shared.

### Recommendation

Do not introduce a server abstraction merely to preserve a hypothetical web future. Instead, preserve data portability with documented, versioned exports and keep domain logic independent of SwiftUI and Core Data where practical. That leaves room for a future migration without burdening V1.

## Persistence and Sync Architecture

### Recommendation: Core Data, then CloudKit

Use Core Data with a local SQLite-backed persistent store. Treat the SQLite file as Core Data's private implementation detail; the app must never directly edit it or place the live store in iCloud Drive.

Core Data is the best fit for the chosen priorities:

- It is an Apple-native stack and materially different from the project's existing web technology.
- `NSPersistentCloudKitContainer` provides the established path for record-level personal sync.
- It supports local transactions, background contexts, undo integration, migrations, validation, and change tracking.
- It avoids building a custom bidirectional CloudKit synchronization engine.
- It is mature enough that the project can focus on outliner behavior instead of persistence infrastructure.

### Why not GRDB for V1

GRDB is excellent when direct SQL, explicit relational control, and database portability dominate. It would also make the local tree model straightforward. Its drawback here is decisive: GRDB does not provide automatic CloudKit synchronization. Adding sync later would require designing record serialization, change tracking, zones, tokens, deletes, retries, conflicts, and recovery.

That is a reasonable project in its own right, but it is not the fun structured-list app described here.

### Why not SwiftData for V1

SwiftData offers less boilerplate and close SwiftUI integration, but Core Data is preferable for this project because sync behavior, migrations, persistent history, store configuration, and diagnostics are more explicit. SwiftData can be reconsidered later if its tooling and migration controls become clearly advantageous, but changing persistence frameworks should not be an early milestone.

### Sync sequence

**V1** uses the production data model locally with CloudKit mirroring disabled. The schema must still obey CloudKit-compatible design constraints so enabling sync does not require a redesign.

**V1.1** enables private-database CloudKit mirroring and adds:

- iCloud account and sync-status presentation.
- Remote-change handling and UI refresh.
- Two-device conflict and convergence tests.
- Retry and recovery guidance for persistent failures.
- Export-before-reset and safe local-store recovery.

Sync must never block local editing. The local store is always the source used by the UI; CloudKit transfers changes asynchronously.

## Core Data Model

V1 needs two synchronized entities and no template/run subsystem.

### `ListEntity`

- `id: UUID`
- `title: String`
- `notes: String?`
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

CloudKit cannot enforce all of the same constraints as a conventional relational database. The application layer must therefore enforce:

- Every item belongs to an existing list.
- A parent belongs to the same list as its child.
- An item cannot parent itself or any ancestor.
- Missing parents are repaired by moving affected items to the list root and reporting the repair.
- Sibling order is deterministic even if two items temporarily share a position.
- All subtree mutations occur in one Core Data transaction.

Use midpoint `Double` positions for ordinary insertions and moves. Rebalance only the affected sibling group when adjacent positions become too close. Break temporary ties by UUID so rendering remains deterministic during sync convergence.

### Device-local presentation state

Do not synchronize presentation state. Keep the following per device:

- Expanded/collapsed item IDs
- Selected list and row
- Current search and filter
- Edit versus Check mode
- Sidebar visibility and split-view position
- Window-specific navigation state

Use scene-owned state and `@SceneStorage` for window/session state, and a small local preferences store for durable per-device expansion and display preferences.

## Domain Architecture

Keep tree behavior in pure Swift types that do not import SwiftUI or Core Data. This is the most valuable architectural lesson to carry over from the `trips` implementation.

The domain layer should provide commands for:

- Flattening a hierarchy for display.
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

Wrap persistence behind repository interfaces so commands can be tested with value fixtures. SwiftUI views should issue domain commands through a scene-scoped store rather than contain tree mutation logic.

Suggested project boundaries:

- `App`: application entry point, scenes, dependency installation, commands.
- `Domain`: value models, tree engine, validation, import/export structures.
- `Persistence`: Core Data stack, repositories, migrations, CloudKit configuration.
- `Features`: library, outline editor, check mode, search, archive, settings.
- `Platform`: narrow iOS/macOS integrations that cannot be shared cleanly.

Use Swift 6 concurrency checking. Keep UI-observed state on `@MainActor`; perform import/export and larger persistence work in explicit background tasks or contexts.

## V1 User Experience

### Library

The library is the app's home screen and contains active and archived lists.

- Create, rename, duplicate, archive, restore, and delete lists.
- Search list titles and item content.
- Show compact progress based on checked leaf items.
- Sort manually by default, with optional title or recently modified views.
- Include a small set of sample lists that users may keep or delete.

Duplication is the V1 reuse mechanism. A duplicate receives new list and item UUIDs and can optionally begin with all checks cleared. This covers most template use cases without maintaining two kinds of editable outline.

### Outline editor

The editor is optimized for structural work:

- Unlimited practical nesting, with an implementation-tested depth target of at least 20 levels.
- Inline add and rename.
- Insert above, insert below, and add child.
- Drag-and-drop reorder and reparent.
- Keyboard move, indent, outdent, add sibling, and add child commands.
- Multi-selection for move, check, uncheck, and delete where platform controls support it reliably.
- Fold/unfold branch and collapse/expand all.
- Multiline paste using indentation to infer hierarchy; unindented text creates siblings.
- Notes and quantity in an inspector or detail sheet rather than crowding every row.
- Search with matching rows revealed inside enough ancestor context to remain understandable.
- Undo and redo for all destructive and structural edits in the current scene.

### Check mode

Check mode is a separate presentation, not a separate data model.

- Large checkbox and row targets.
- Minimal editing controls.
- Checked, unchecked, and all-items filters.
- Visible list and branch progress.
- Parent rows display checked, unchecked, or mixed state derived from leaf descendants.
- Checking a parent applies the chosen state to all descendants in one transaction.
- Reset is available for a branch or entire list and requires confirmation plus undo.
- Optional automatic hiding of newly checked rows is off by default to avoid disorienting movement.

### Platform composition

**Mac** uses a `WindowGroup` with `NavigationSplitView`: a native source-list sidebar, outline editor, and optional inspector. Important operations appear in menus, toolbars, context menus, and keyboard shortcuts. Multiple windows may open the same or different lists; scene selection and undo remain window-scoped.

**iPad** uses the same split-view concept with touch-appropriate toolbars, drag/drop, hardware keyboard commands, and an inspector sheet when space is constrained.

**iPhone** uses `NavigationStack`. The library opens either Check mode or Edit mode for a list. Structural commands live in context menus and focused sheets rather than dense inline buttons.

The app should use semantic system colors, Dynamic Type, VoiceOver labels, reduced-motion behavior, and current system materials. A distinctive visual identity can be added after interaction density and hierarchy readability are correct.

## Proven Behaviors to Carry Forward from `trips`

The `trips` packing-list implementation provides useful product evidence and domain behavior, but its web UI and server architecture should not be copied.

Carry forward:

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

## Import, Export, and Data Ownership

V1 supports a deliberately small set of formats.

### Versioned JSON

JSON is the canonical lossless backup and transfer format. Define an export envelope with:

- `format: "listsurf"`
- `schemaVersion: Int`
- `exportedAt: Date`
- `appVersion: String`
- Complete list and item records

Imports validate the entire payload before writing. UUID collisions create new UUIDs unless the user explicitly chooses a future restore/replace workflow. A failed import writes nothing.

### OPML

Support OPML import/export for interoperability with outliners. Preserve title, nesting, notes, quantity, and checked state where attributes are available. Unknown attributes are ignored but must not invalidate the document.

### Markdown and plain text

Export nested Markdown lists with checkbox syntax. Import Markdown bullets, checkbox markers, and indentation. Multiline plain text paste uses indentation but does not attempt AI interpretation.

Defer CSV because it represents hierarchy and notes poorly. Defer natural-language or AI parsing until deterministic import behavior is excellent; an AI requirement would also complicate the standalone and offline product promise.

Use native file import/export and share sheets. Provide an explicit full-library backup command before CloudKit is enabled.

## V1 Scope

### Included

- Native iPhone, iPad, and Mac app.
- List library and archive.
- Nested outline editing.
- Check mode and reset.
- Notes and quantity.
- Reorder, indent, outdent, folding, and multiline paste.
- Duplicate as reusable list.
- Search and unchecked filtering.
- Undo/redo.
- JSON, OPML, and Markdown import/export.
- Device-local presentation preferences.
- Accessibility and keyboard support.
- Local Core Data persistence with a CloudKit-compatible schema.

### Explicitly deferred

- CloudKit activation and production sync support, targeted for V1.1.
- Cross-user sharing and collaboration.
- Dedicated template and run entities.
- Attachments, photos, and rich media.
- Due dates, reminders, calendar integration, and notifications.
- Tags, smart folders, inventory catalogs, and cross-list references.
- AI-assisted parsing or generation.
- Widgets, App Intents, and Shortcuts.
- Web clients, accounts, APIs, and servers.
- CSV and custom styling systems.

## Implementation Sequence

### Phase 0 — Project and persistence foundation

- Create the multiplatform Xcode project and shared module boundaries.
- Configure Core Data locally with CloudKit disabled.
- Define the sync-compatible model and migration policy.
- Add deterministic fixtures, previews, and an in-memory test store.
- Add versioned JSON export early enough to recover development data.

### Phase 1 — Tree engine

- Implement and exhaustively test hierarchy traversal and mutation commands.
- Enforce same-list parenting and cycle prevention.
- Implement midpoint ordering and sibling rebalance.
- Implement leaf-only progress, tri-state checks, reset, duplicate, and delete.

### Phase 2 — Mac and iPad authoring

- Build the library, split-view editor, inspector, menus, commands, and drag/drop.
- Add inline editing, multiline paste, folding, search, multi-selection, and undo.
- Use this phase to make long-form list construction efficient before polishing mobile checking.

### Phase 3 — iPhone and Check mode

- Build the compact library and focused Check/Edit flows.
- Validate target sizes, one-handed use, filtering, progress, reset, and context menus.
- Test with realistic packing and procedure lists on a physical phone.

### Phase 4 — Interchange and hardening

- Add JSON, OPML, and Markdown round trips.
- Add archive/restore, recovery messaging, accessibility, performance tests, and migration fixtures.
- Exercise the app on real lists until the model and commands stop changing frequently.

### Phase 5 — V1.1 personal sync

- Enable the private CloudKit database in development.
- Initialize and inspect the CloudKit schema before production promotion.
- Add remote-change handling, sync status, diagnostics, and recovery.
- Test two-device offline edits, deletes, moves, duplicate positions, and convergence.
- Promote the CloudKit schema only after destructive model changes are unlikely.

## Testing and Acceptance Criteria

### Domain tests

- Flattening always emits parents before descendants in visible order.
- Move, indent, outdent, and reparent preserve every subtree.
- Self-parenting, descendant-parenting, missing parents, and cross-list parenting are rejected or repaired as specified.
- Duplicate produces an equivalent tree with entirely new UUIDs.
- Parent check state is derived correctly for empty, mixed, checked, and unchecked branches.
- Progress counts only leaves.
- Reset and subtree deletion are atomic and undoable.
- Position rebalance preserves displayed order.

### Persistence and interchange tests

- Store creation and every model migration succeed from committed fixtures.
- Failed multi-row operations roll back completely.
- JSON round trips without loss.
- OPML and Markdown preserve hierarchy and supported metadata.
- Malformed imports produce actionable errors and no partial records.
- Orphan repair is deterministic and reported.

### UI tests

- Create and edit a nested list using touch, pointer, and keyboard paths.
- Drag within a sibling group and into/out of a parent.
- Paste an indented outline and immediately undo it.
- Search reveals matches with ancestor context.
- Check mode supports parent cascade, mixed state, filtering, reset, and undo.
- Archive and restore preserve content and order.
- VoiceOver identifies hierarchy level, expansion state, check state, quantity, and available actions.
- Dynamic Type does not hide primary checking controls.

### V1 acceptance

V1 is complete when a deeply nested real-world list can be efficiently authored on Mac or iPad, checked comfortably on iPhone, reset or duplicated safely, searched, archived, exported, restored, and used completely offline without data loss.

### V1.1 acceptance

V1.1 is complete when edits, checks, moves, duplicates, archives, and deletes made on either of two devices converge without corrupting hierarchy; offline changes recover when connectivity returns; and persistent sync failures are visible and recoverable without deleting the user's only copy.

## Risks and Guardrails

### Scope creep

The largest product risk is becoming a task manager, note system, or collaboration service. New features should be accepted only when they improve creating, structuring, reusing, or executing durable lists.

### Tree interaction complexity

Native hierarchical editing is the hardest part of the app. Build and test the domain commands before committing to a highly customized row UI. Every gesture must have a discoverable menu or keyboard equivalent where appropriate.

### CloudKit constraints

CloudKit schema changes become restrictive after production promotion, and sync is eventually consistent. Keep the synchronized model small, avoid unnecessary entities, use stable UUIDs, and defer production schema deployment until V1 usage validates the model.

### SwiftUI platform gaps

Shared SwiftUI views should not force identical interaction on all platforms. Use narrow AppKit or UIKit interoperability only when native SwiftUI cannot provide reliable focus, command, drag/drop, or outline behavior.

### Data safety

Undo, atomic commands, migration tests, and lossless exports are V1 requirements. Confirmation dialogs alone are not an adequate recovery strategy.

## Post-V1 Possibilities

Consider these only after V1 and V1.1 are reliable:

- Promote selected lists to reusable templates if duplication proves insufficient.
- App Intents and Shortcuts for opening a list or starting Check mode.
- Widgets showing progress or the next unchecked items.
- Photos and attachments using CloudKit assets.
- Saved filters or smart collections.
- Cross-list reusable inventory items.
- Version history beyond scene undo.
- Opt-in list sharing through CloudKit shared databases.

Cross-user sharing should be treated as a separate product phase. It introduces permissions, ownership, invitation flows, conflict expectations, and support burdens that personal multi-device sync does not.

## Final Direction

Listsurf should begin as a small, high-quality native outliner with unusually good checking ergonomics. The project should favor directness over abstraction: two persisted entities, one pure Swift tree engine, one local store, native platform presentations, and portable exports.

The original proposal correctly identified the opportunity. The refined plan removes the parts most likely to bury that opportunity under infrastructure: custom database sync, parallel template/run models, too many interchange formats, and speculative collaboration.

Build the local experience first. Make it trustworthy enough to hold real lists. Then add personal CloudKit sync without changing what the app fundamentally is.
