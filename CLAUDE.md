# CLAUDE.md

Guidance for AI coding agents (Claude Code et al.) working in this repo.

**Authoritative project rules live in [`cs.md`](./cs.md) — read it first.** It covers
the app architecture (100% native Apple, SwiftUI, local-first), persistence approach,
data integrity rules, UI conventions, and the evidence-based debugging mandate.
`AGENTS.md` and this file both defer to `cs.md` as the single source of truth.

## Session startup (required)
- Run `td usage --new-session` at conversation start (or after `/clear`) to see
  current work; `td usage -q` for subsequent reads. `td` is the task tracker.
- Skim the latest `docs/devlog/` entry for recent context.

## Where things are
- **Design docs:** `docs/` — V1 planning documents.
- **Devlog:** `docs/devlog/YYYY-MM-DD.md`.

## Tech stack
- **Swift + SwiftUI** — universal app (iOS + macOS)
- **Persistence**: Core Data (local SQLite-backed store), CloudKit mirroring deferred to V1.1
- **No server, no backend** — everything on-device
- **Dependencies**: Swift Package Manager

## Before you commit
- Build must succeed (`swift build` or Xcode build).
- Debug from evidence (previews/logs), never assumption — see `cs.md` → Evidence-Based Debugging.
