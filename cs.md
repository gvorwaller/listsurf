# AI Assistant Session Guide

## Session Startup (Required)
1. Read `cs.md` (this file) — hard rules that override defaults
2. Read design docs in `docs/` — current V1 plans and direction
3. Check recent devlog entries in `docs/devlog/`
4. Run `td usage --new-session` to see current tasks

---

## Core Principles

### No Assumptions
- **Never guess** when you can verify — read source code, check config files, test directly
- **Never assume the user's environment** — don't guess what device, OS version, or Xcode version they're using
- **State uncertainty explicitly** — if you must hypothesize, say so and ask for confirmation
- **Ask when uncertain** — one question is cheaper than one wrong assumption

### No Quick Fixes
- Find root causes, not band-aids
- Implement maintainable solutions
- If a fix requires multiple rounds, slow down and trace the data flow

### Evidence-Based Debugging (MANDATORY)
When diagnosing errors, follow this methodology instead of guessing:

1. **Read the relevant source code** before forming any hypothesis
2. **Trace the data flow** — view -> view model -> model -> persistence -> response
3. **Test each layer independently** — use previews, unit tests, or debug logging
4. **Compare expected vs actual** at each boundary
5. **Never assume a cause** — verify with evidence first, then propose a fix

> "No guesses, only solid evidence, tracing the code carefully."

---

## Project Overview

**Listsurf** is a 100% native Apple standalone app — SwiftUI on iPhone, iPad, and Mac. No server, no web stack, no backend. Local-first, personal use.

### What It Is
A focused tool for durable, structured personal lists — packing lists, travel planning, inventories, recurring procedures, reference lists. Not a daily task manager (that's Apple Reminders).

### Core Concepts
- **Lists** — long-lived containers for structured information
- **Items** — nestable, checkable rows; any item can parent other items (no separate Section entity)
- **Check mode** — a presentation layer over the same data, not separate run/state entities
- **Duplication** — copies a list with new UUIDs and optionally clears checks; replaces templates
- **Archive** — completed or inactive lists

> Templates, Runs, and dedicated Section entities are intentionally deferred. Duplication + reset covers the core reuse workflow for V1.

---

## Tech Stack (V1)

- **Language**: Swift
- **UI**: SwiftUI (universal macOS + iOS app)
- **Persistence**: Core Data (local SQLite-backed store), CloudKit mirroring deferred to V1.1
- **No server dependency** — everything runs on-device
- **Future possibility**: iCloud/CloudKit for personal multi-device sync
- **Build**: Xcode, Swift Package Manager for dependencies

---

## Project-Specific Rules

### Swift & SwiftUI
- Target latest stable iOS + macOS SDKs
- Use Swift concurrency (async/await, actors) — not Combine for new code
- `@MainActor` for all UI-touching code
- Prefer value types (structs) over reference types (classes) unless identity semantics are needed
- Use SwiftUI's built-in navigation (NavigationStack/NavigationSplitView), not UIKit bridges

### Persistence (Core Data)
- All persistence operations must be transactional where multi-step
- Never fabricate synthetic IDs, timestamps, or placeholder data
- Schema migrations go in dedicated migration code, not inline
- Use `NSPersistentContainer` for V1; `NSPersistentCloudKitContainer` for V1.1
- Never access the SQLite file directly — it is Core Data's private implementation detail
- Use the main context for UI reads and small writes; background contexts for bulk operations (import, duplication, reset, export)
- Merge background context saves via `NSManagedObjectContextDidSave` notifications

### Data Integrity
**NEVER:**
- Create synthetic or placeholder data (IDs, timestamps, dummy items)
- Use fallback data to mask broken code
- Add schema columns/fields that don't exist
- Modify user data without explicit confirmation

**ALWAYS:**
- Use actual unique constraints from the schema
- Fix root causes when data is missing — never paper over with defaults
- Handle missing data as explicit errors with user notification
- Validate at system boundaries, trust internal code

### UI Conventions
- Native Apple design language — no custom design systems that fight the platform
- Support Dynamic Type
- VoiceOver accessibility on all interactive elements
- Adapt layout for iPhone, iPad, and Mac (size classes)
- Dark mode support from day one

---

## Development Workflow

- **Always `cd` back** to project root after operations
- **Use absolute paths** when possible to avoid directory confusion
- **Commits**: Only commit when explicitly asked
- **Build verification**: `swift build` or Xcode build must succeed before committing
- **Tests**: Run tests before committing if test targets exist

---

## State Tracking Tools
- `td` — task management CLI (run `td usage --new-session` at session start)
- `/nn` — append timestamped entry to today's devlog (`docs/devlog/YYYY-MM-DD.md`)
- `/review` — adversarial review loop before commits

---

## Historical Failures (Learn From These)
*(Inherited from sibling projects — same developer, same mistakes to avoid)*

- **Synthetic data**: Synthetic IDs/timestamps added to mask broken inserts — broke uniqueness invariants. Never fabricate data to make code "work."
- **Missing import causing CPU spike**: A missing import threw errors in a hot loop, pegging CPU at 100%. Always run a smoke test after refactors.
- **Assumptions are the enemy**: Read the code. Read the config. Test the layer. Only then diagnose.

### Key Principle
> Assumptions are the enemy. Read the code. Read the config. Test the layer. Only then diagnose.
