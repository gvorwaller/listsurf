# 2026-06-23 — In-app help menu

## Problem

The app exposed core actions, but the meaning of the editor and library controls was still too implicit, especially on iPhone and iPad where the main workflow is touch-first.

## Changes

- Added an in-app `ListsurfHelpView` with short sections for:
  - getting started,
  - iPhone/iPad touch controls,
  - editor basics,
  - library/archive/backup actions,
  - check mode,
  - Mac bulk-entry shortcuts.
- Added Help entry points:
  - visible Help button in the Library action section,
  - Help item in the toolbar hamburger menu,
  - Help button in the empty-library state,
  - macOS Help menu command.
- Replaced the toolbar `Backups` menu with a broader hamburger `Menu` that includes Help, New List, Archive, Import Backup, and Export Backup.
- Kept the existing visible Import/Export/Archive actions in the Library instead of hiding them behind the hamburger.
- Put iPhone/iPad touch controls near the top of Help so the most important mobile explanation is visible immediately.

## Verification

- `swift test --quiet` — 95 passed.
- XcodeBuildMCP iOS simulator test suite — 99 passed.
- XcodeBuildMCP macOS test suite — 101 passed.

