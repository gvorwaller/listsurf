# Listsurf — Native Structured Lists App Plan

**Project**: Listsurf  
**Date**: 2026-06-18  
**Status**: V1 exploration and direction. This document supersedes earlier notes on a dedicated lists tool.  
**Name**: Listsurf (chosen for its surfer energy and the idea of casually "surfing" through your structured lists).

---

## Context

A web-based checklist tool for travel packing and event planning has proven the value of durable, sectioned, nestable lists. The UX patterns that emerged — fast check/uncheck, templates for recurring structures, hierarchical items, notes, bulk entry, and clean reset behavior — feel worth extracting into their own dedicated app.

The goal is not another general task manager. Listsurf should be a modern, personal successor to CarbonFin-style flexible lists: durable structured checklists for recurring events, long-term reference, packing, planning, inventories, and shared procedures.

The motivating distinction is clear:

- Apple Reminders remains the daily-driver for dated tasks, reminders, and ordinary to-dos.
- Listsurf focuses on the flexible, long-lived, structured checklist category without competing directly with Reminders, Todoist, Notion, or full project-management tools.

## Direction

- Build Listsurf as a **native Apple app** (SwiftUI for macOS and iOS) from the start.
- Favor **local-first** storage over a server-required model.
- Consider iCloud/CloudKit sync later, after the local app feels excellent.
- Keep any web or server components out of V1.

This architecture matches the use case perfectly: instant launch, offline by default, excellent native drag/reorder and ergonomics, local files and exports, and the ability to work while packing or moving around without network dependency.

## Product Shape

The app is designed around **durable structured lists** rather than transient tasks.

Core concepts:

- **Lists**: long-lived containers for structured information.
- **Sections**: grouping within a list (categories, phases, etc.).
- **Items**: checkable rows with optional notes, quantity, metadata, and richer detail.
- **Templates**: reusable list structures (e.g., "Beach Trip", "Work Travel", "Home Inventory Base").
- **Runs**: event-specific checked-state sessions derived from a list or template. A "Travel Packing" template can spawn a "June 2026 Italy Trip" run without mutating the source.
- **Archive**: completed or historical runs.
- **Sharing** (future): optional, not required for local-first v1.

The key model distinction is between the **durable structure** (templates and master lists) and **temporary checked state** (runs). This prevents the common frustration of having your master checklist permanently altered after every use.

## Native App Advantages

A native Apple version delivers several advantages for this product:

- Instant launch.
- Offline by default.
- Native drag/reorder behavior (with excellent support for nesting).
- Native context menus, keyboard shortcuts, and multi-select.
- Superior iPhone ergonomics for checking items while moving.
- Superior Mac ergonomics for long-form list editing and organization.
- Local files and exports without server round-trips.
- iCloud sync path without needing to operate a public service.

This is a much stronger fit than a web app for the personal utility nature of the tool.

## Storage Options

Three main native persistence paths were considered:

### SwiftData
Modern Apple framework that pairs cleanly with SwiftUI.

**Strengths**: Low boilerplate, native integration, fast to build with.  
**Weaknesses**: More framework magic, less explicit control over schema/migrations, long-term portability less clear.

### Core Data + CloudKit
Mature path with built-in sync.

**Strengths**: Battle-tested, direct CloudKit integration.  
**Weaknesses**: More complexity and Apple-specific knowledge.

### SQLite + GRDB (or similar)
Direct SQLite via a mature wrapper.

**Strengths**:
- Data remains inspectable and understandable.
- Explicit migrations.
- Straightforward export/import.
- Strong long-term durability and portability.
- Model can stay close to proven relational designs (parent/child + sort order trees).

**Weaknesses**:
- More manual integration with SwiftUI.
- Sync is not automatic (but CloudKit can be layered on later).

**Current recommendation**: SQLite + GRDB if transparent, durable data and explicit control are priorities. SwiftData if maximum development speed and pure Apple-native convenience matter most for the initial version. GRDB aligns well with a desire for understandable, long-lived personal data.

## Strong V1 Scope

Stay narrow for the first version:

- Universal SwiftUI app (macOS + iOS).
- Local-first data (SQLite-backed).
- Lists with sections and nestable items.
- Item notes, quantity, category/metadata.
- Check, uncheck, and reset (per list, section, or run).
- Templates (save structure, apply to create fresh runs).
- Runs / instances for event-specific checked state.
- Search.
- Reorder (sections and items, with full nesting support).
- Import and export (text, Markdown outlines, JSON, CSV, OPML).
- Mobile-first "pack/check mode" with large tap targets.
- Mac-friendly editing and organization mode.
- Client-side folding/collapse state (remembered per device).

Sharing, CloudKit sync, attachments/files, advanced collaboration, public accounts, calendar integration, due dates, and notifications should wait until the local experience is already excellent and daily-useful.

## Data Model Sketch (V1)

A simple starting relational model (easily adapted to SwiftData or GRDB):

- `list`
- `section` (or treat as special items)
- `item` (with parent_id + sort_order for nesting)
- `item_note` (or richer metadata fields)
- `template` (and `template_item`)
- `run` (instance derived from a list or template)
- `run_item_state` (captures checked state and any overrides for a specific run)

The `run_item_state` separation is important: the same durable template or list can generate many independent executions without side effects.

## Validated UX Patterns to Carry Forward

Prior work on structured checklists (especially for travel packing and planning) has validated several interaction patterns worth replicating or improving in native:

- Sectioned, hierarchical outliner layout.
- Fast check/uncheck with subtree cascade (checking a category checks its children).
- Templates with full hierarchy preservation.
- Bulk multi-line paste into items.
- Insert-at-position (add a new item directly above or below an existing one).
- Per-item notes and lightweight metadata.
- Client-only folding/collapse (device-local, no server write).
- Clear reset behavior for checked state.
- Progress indicators at list and section level.
- Natural flow between overview editing and focused checking mode.

A native implementation can make many of these feel even better (true native gestures, better ergonomics on each platform, instant feedback).

## Differentiators

Areas where Listsurf can improve on existing tools like CarbonFin:

- Fast "pack mode" with large mobile tap targets and minimal UI.
- Clean reset of checked items per list, section, or run.
- Templates with variants (short trip, long trip, beach, work, etc.).
- Richer item content (notes, URLs, photos later, reference details).
- Smart filtered views (unchecked only, recently changed, by category).
- Strong import/export from day one.
- Natural-language entry: paste rough text and intelligently split into sections and items.
- Future inventory mode for items that persist and are referenced across many lists.
- Version history or easy undo for clearing mistakes.
- Native share sheet and local backup files.
- Excellent keyboard and multi-select support on Mac.

## Multi-Device, Sync, and Sharing

Multi-device and sharing should not drive V1.

Recommended sequence:

1. Excellent single-device local app.
2. iCloud/CloudKit for personal multi-device sync (when it becomes important).
3. Shared records or other models only if real collaboration proves worth the complexity.
4. Server-backed accounts only with a deliberate decision to run a service.

Suggested future roles (if sharing is added later):
- Owner: full control.
- Editor: modify structure and state.
- Viewer: read + limited check-off (when explicitly allowed).

## Scope Risks and Maintenance Posture

The primary risk is scope creep into crowded task-management territory.

Features to avoid early:
- Calendar integration and due dates.
- Recurring reminders and complex notifications.
- Kanban or full project views.
- Billing or public accounts.
- Advanced real-time collaboration.
- Server infrastructure before the local app proves daily value.

Recommended posture:
- Build first for personal use.
- Keep any external access invite-only.
- Provide robust export/import from the beginning.
- Set "as-is" expectations if the app is ever shared.
- Keep the feature surface small enough that maintenance remains pleasant.

This can still be useful to others without becoming an accidental support obligation or public CarbonFin successor.

## Possible Next Steps After V1

- iCloud/CloudKit sync.
- Attachments or rich media on items.
- Lightweight sharing model.
- Widgets, Shortcuts, and App Intents for quick access.
- Inventory-style reusable item catalog.
- Better history/undo.
- Cross-list smart views.

## Name

**Listsurf** was selected. It carries a light, active surfer connotation — "surfing your lists" evokes quick, fluid navigation and checking while in motion (perfect for packing or on-the-go use). For a primarily personal, single-user tool, the name is distinctive, memorable, and enjoyable without needing to optimize for discoverability or marketing.

(Other names considered included ListBreak, ListSwell, ListTide, Listwell, KeptList, and ListAnchor. Listsurf won for personality and fit.)

## Current Recommendation

Proceed with Listsurf as a native SwiftUI app (macOS + iOS), local-first, using SQLite (via GRDB or SwiftData) for persistence.

Focus first on delivering a delightful core outliner experience with templates, runs, notes, search, reorder, and excellent mobile + desktop ergonomics.

Continue refining checklist workflows in any related tools as living product research, but treat Listsurf as a clean-slate native implementation that borrows only the best UX patterns — not code or server assumptions.

Do not introduce sync, sharing, or server requirements until the local app has proven its value in real daily use.

---

**End of plan.** Ready for implementation when desired. The emphasis remains on a focused, personal, high-quality tool that feels immediate and durable.