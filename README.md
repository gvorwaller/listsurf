# Listsurf

**Listsurf** is a native Apple app for durable, structured personal lists.

It is a focused tool for flexible, long-lived checklists — a modern, personal successor to the CarbonFin Outliner style of working. Think packing lists, travel and event planning, inventories, recurring procedures, and reference lists that you actually want to keep and refine over time.

Listsurf deliberately stays out of the "daily task manager" space (that's what Apple Reminders is for) and focuses on rich, hierarchical, reusable structures.

## Core Concepts

- **Lists** — long-lived containers for structured information
- **Sections** — grouping within a list
- **Items** — checkable rows with notes, quantity, categories, and metadata
- **Templates** — reusable master structures
- **Runs** — event-specific instances (so using a template for a trip doesn't mutate the original)
- **Archive** — historical runs

The key idea is separating durable structure from temporary checked state.

## Goals

- Fast, delightful native experience on iPhone, iPad, and Mac
- Local-first (works perfectly offline)
- Simple enough to maintain for personal use
- Excellent ergonomics for "pack mode" checking while on the move
- Strong import/export and data ownership from day one

## Status

Early exploration / V1 planning.

See the current direction and detailed thinking in:

- [docs/grok-listsurf-V1-plan.md](docs/grok-listsurf-V1-plan.md)

## Tech (V1)

- SwiftUI (universal macOS + iOS app)
- Local persistence (SQLite via GRDB or SwiftData)
- No server dependency in the first version
- Future possibility: iCloud/CloudKit for personal multi-device sync

## Getting Started

(Coming soon — this is currently a planning stub.)

## License

Personal project. All rights reserved for now.

---

Built with ❤️ for structured lists that actually last.