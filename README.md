# Listsurf

**Listsurf** is a native Apple app for durable, structured personal lists.

It is a focused tool for flexible, long-lived checklists — a modern, personal successor to the CarbonFin Outliner style of working. Think packing lists, travel and event planning, inventories, recurring procedures, and reference lists that you actually want to keep and refine over time.

Listsurf deliberately stays out of the "daily task manager" space (that's what Apple Reminders is for) and focuses on rich, hierarchical, reusable structures.

## Core Concepts

- **Lists** — long-lived containers for structured information
- **Items** — nestable, checkable rows; any item can parent other items
- **Check mode** — a presentation layer for checking items off, not separate data
- **Duplication** — copies a list with new UUIDs and optionally clears checks; replaces templates
- **Archive** — completed or inactive lists

Durable structure stays in the library; duplicate-and-reset handles reuse without mutating the original.

## Goals

- Fast, delightful native experience on iPhone, iPad, and Mac
- Local-first (works perfectly offline)
- Simple enough to maintain for personal use
- Excellent ergonomics for "pack mode" checking while on the move
- Strong import/export and data ownership from day one

## Status

Early exploration / V1 planning.

See the current implementation plan and earlier exploration:

- [docs/CC-listsurf-V1-plan.md](docs/CC-listsurf-V1-plan.md) — current V1 plan
- [docs/grok-listsurf-V1-plan.md](docs/grok-listsurf-V1-plan.md) — initial exploration (historical)

## Tech (V1)

- SwiftUI (universal macOS + iOS app)
- Local persistence (Core Data with local SQLite-backed store)
- No server dependency in the first version
- CloudKit personal sync planned for V1.1

## Getting Started

(Coming soon — this is currently a planning stub.)

## License

Personal project. All rights reserved for now.

---

Built with ❤️ for structured lists that actually last.