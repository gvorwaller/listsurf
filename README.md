# Listsurf

Listsurf is a native Apple app for durable, structured personal lists. It is built for reusable outlines such as packing lists, travel planning, inventories, procedures, event prep, and reference lists.

It is intentionally not a daily task manager. Dates, alerts, recurring reminders, and task inbox workflows belong in Apple Reminders. Listsurf focuses on long-lived hierarchical lists that are easy to refine, reuse, check off, archive, and back up.

## Status

Listsurf is in active V1 development. The repo currently contains a working SwiftUI app target for iOS and macOS, local Core Data persistence, domain and persistence tests, UI test targets, backup import/export, archive support, check mode, and in-app help.

CloudKit sync is not enabled yet. V1 is local-first; V1.1 is expected to add personal iCloud sync over the same Core Data model.

## Features

- Native SwiftUI app for iPhone, iPad, and Mac
- Library sidebar for active and archived lists
- Hierarchical outline items with nesting, reordering, indent, outdent, and deletion
- Check mode for using an outline as a checklist
- List duplication with new UUIDs and optional check reset
- Per-list metadata such as notes, icon, and color
- Item details including title, notes, quantity, timestamps, and check state
- Full-library JSON backup export and import
- Store-load error presentation and recovery affordances
- In-app help for touch controls, editor basics, library actions, check mode, and Mac shortcuts

## Core Concepts

- **Lists** are long-lived containers for structured information.
- **Items** are nestable, checkable rows. Any item can parent other items.
- **Check mode** is a presentation over the same outline data, not a separate run state.
- **Duplication** is the reuse mechanism for V1. A duplicate receives new list and item UUIDs and can optionally clear checks.
- **Archive** keeps completed or inactive lists out of the main library without deleting them.

Templates, runs, and dedicated section entities are intentionally deferred.

## Architecture

The project is split into small Swift Package Manager targets plus a thin app target:

- `App/` - app entry point, Info.plist, privacy manifest, and assets
- `Sources/Domain/` - pure Swift models, tree commands, validation, and JSON export/import types
- `Sources/Persistence/` - Core Data model, persistent stack, managed objects, and repository implementations
- `Sources/Features/` - SwiftUI views, stores, commands, library, editor, check mode, inspector, archive, backup UI, and help
- `Sources/Platform/` - narrow UIKit/AppKit integrations
- `Tests/` - unit, persistence, feature, and UI test sources
- `docs/` - product plans, mockups, and development notes

The domain layer does not depend on SwiftUI or Core Data. SwiftUI talks to observable stores, and persistence is accessed through repository protocols.

## Requirements

- macOS with Xcode installed
- Swift 6 toolchain
- XcodeGen if regenerating `Listsurf.xcodeproj` from `project.yml`

The package manifest uses iOS 18 and macOS 15 so command-line SwiftPM builds work. The Xcode project carries the app target settings used by the Apple-platform app.

## Getting Started

Clone the repo and open the project:

```sh
open Listsurf.xcodeproj
```

Choose the iOS or macOS Listsurf scheme in Xcode and run it on a simulator or on the Mac.

If `project.yml` changes, regenerate the Xcode project:

```sh
xcodegen generate
```

## Command-Line Checks

Run package tests:

```sh
swift test
```

Build the package:

```sh
swift build
```

The Xcode project also defines iOS and macOS test plans:

- `Listsurf_iOS.xctestplan`
- `Listsurf_macOS.xctestplan`

Run those from Xcode, or use `xcodebuild test` with a destination that exists on your machine.

## Data and Backups

Listsurf stores data locally using Core Data with a SQLite-backed persistent store. The app treats that store as private Core Data implementation detail.

Use the built-in backup actions for portable data:

- **Export Library Backup** writes a JSON backup with format `listsurf` and schema version `1`.
- **Import Library Backup** validates a backup and replaces the current local library after confirmation.

Backups are intended to be inspectable and versioned. They are also the migration path for manual recovery while sync is deferred.

## Development Notes

- Keep app behavior native to Apple platforms.
- Keep tree behavior testable in `Domain`.
- Do not add server dependencies for V1.
- Do not directly manipulate the Core Data SQLite file.
- Run tests before committing changes.
- Use `td` for task tracking in this repo.

Useful docs:

- [docs/codex-listsurf-V1-plan.md](docs/codex-listsurf-V1-plan.md)
- [docs/devlog/](docs/devlog/)

## License

Personal project. All rights reserved for now.
