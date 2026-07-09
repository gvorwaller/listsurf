# Listsurf — Independent Plan: Fixes, Usability, and Edge

**Date**: 2026-07-08
**Author**: Claude (independent review — docs, commit history, td tracker, and code exploration)
**Inputs**: `docs/devlog/2026-07-07-gbv-testing-notes.txt`, `docs/CC-listsurf-V1-plan.md`, all devlog entries, `td` state as of 2026-07-07
**Context**: iOS and macOS 1.0.0 both submitted to App Review (Waiting for Review, manual release). App's original purpose was Apple-ecosystem learning; goal now shifting toward genuine usefulness and a unique identity.

---

## Part 1 — Remedying the testing notes

Every item in the 2026-07-07 testing notes was confirmed against source. They fall into three groups with very different costs.

### Group A: Quick fixes (each is hours, not days — a natural "1.0.1" batch)

| # | Issue | Root cause & fix |
|---|-------|------------------|
| A1 | Duplicate keeps same name | `TreeEngine.duplicateList` copies `title` verbatim (`Sources/Domain/Tree/TreeEngine.swift:341`). Fix in `AppStore.duplicateList` (`AppStore.swift:96-114`): append "Copy" / "Copy 2" after checking existing titles. Naming policy belongs in the store, not the pure tree engine. |
| A2 | Expand/collapse symbols reversed | Literally swapped in `Sources/Features/Editor/ListDetailView.swift:144,151` — Expand All uses the inward-pointing glyph (`arrow.down.right.and.arrow.up.left`) and Collapse All the outward one. Swap them. |
| A3 | "New list from existing list" | A proper standalone `+` toolbar button already exists (`LibrarySidebar.swift:88-94`); the confusion is that the **per-list ellipsis/context menu also contains "New List"** (`LibrarySidebar.swift:239-241`), making it look derived from that list. Remove it from that menu. |
| A4 | Details context menu does nothing | `OutlineEditorView.swift:364` sets `inspectorItemID` but never sets `showInspector = true`, which lives in `ListDetailView` (`ListDetailView.swift:8`). On Mac the inspector never opens. Wire an `onChange`/callback so Details opens the inspector. |
| A5 | Check mode lacks expand/collapse all | The focused commands are already wired even in check mode (`ListDetailView.swift:272-273`); only the toolbar buttons are missing from `checkModeToolbar` (`ListDetailView.swift:232-255`). Add them. |
| A6 | Archive confusion ("where does archive go?") | Archive + restore are fully implemented (`ArchiveView.swift`, swipe-to-restore + menu Restore; `AppStore.archiveList/restoreList`) — this is discoverability, not function. Rename the sidebar entry to "Archived Lists", add a count badge, and make Restore a visible button rather than swipe-only. |
| A7 | Context menus should show keystrokes | No context-menu button carries `.keyboardShortcut`, so macOS renders no hint (`OutlineEditorView.rowContextMenu`, `ListDetailView.itemActionMenu`, `LibrarySidebar.listActionMenu`, `CheckModeView.checkRowContextMenu`). Add the modifier to menu buttons that mirror `ListsurfCommands`. |
| A8 | Help sections collapsible | Help is static `Section`s (`Sources/Features/Help/ListsurfHelpView.swift:106-137`). Convert `HelpSection` rendering to `Section(isExpanded:)`/`DisclosureGroup`. |

### Group B: The Mac interaction cluster — one root cause, four symptoms

Testing notes "cursor keys don't move selection (Mac)", "edit in place doesn't work (Mac)", and "command keys as spec'd in help don't work" are **one problem, not three**. The editor uses custom `.onTapGesture` selection on rows (`OutlineRowView.swift:44`) layered on top of, and fighting with, native `List(selection:)` (`OutlineEditorView.swift:106`). Consequences:

- Native list selection never gets keyboard focus → **arrow keys do nothing**. There is no `onMoveCommand`, `.focusable`, or selection-follows-keyboard wiring anywhere.
- Edit-in-place is a double-tap gesture stacked with single-tap and parent-tap gestures (`OutlineRowView.swift:28,45`; parent tap at `OutlineEditorView.swift:141`) → **AppKit swallows the double-click**, and `.onAppear { isFocused = true }` focus is fragile inside Mac list rows.
- All Item-menu commands (Return, ⇧Return, ⌘Return, Tab, ⇧Tab, ⌘⌥↑/↓, ⌘⌫ in `ListsurfCommands.swift`) are disabled unless exactly one item is selected via `store.selectedItemIDs` (`ListDetailView.swift:277-297`) — which keyboard/click selection often doesn't populate → **the shortcuts documented in Help genuinely don't work**; they're permanently greyed out.

**The fix is one refactor, not four patches:**

1. Make native `List(selection:)` the single source of truth for selection; remove custom tap-gesture selection. This gives arrow-key navigation on Mac for free.
2. Make edit-in-place an explicit action — Return-to-rename like Finder, plus double-click — with properly sequenced `FocusState` instead of `.onAppear` focus.
3. With selection reliable, the focused commands enable themselves and the Help doc becomes true.
4. Update Help's Mac section to list all twelve shortcuts in `ListsurfCommands.swift` (it currently documents only four).

This is the highest-leverage fix in the whole list; treat it as its own milestone. Do it **before** drag-and-drop — drag and selection interact, and drag shouldn't be built on the broken gesture stack.

### Group C: Features

- **Drag-and-drop reorder** ("want drag-n-drop to move items, at least up/down"): Nothing exists today — no `.onMove` anywhere; reordering is Move Up/Down buttons only. The V1 plan (§Drag-and-Drop Feedback) specs full insertion-indicator drag with reparenting; that's the hardest UI work in the app. Stage it: first `.onMove` on the flattened visible rows mapped to existing `TreeEngine` move commands (covers the "at least up/down" ask cheaply), then indicator-based reparenting drag as a separate later task. After Group B.
- **Per-list import/export + OPML**: Currently only whole-library JSON with destructive replace-all import (`AppStore.swift:116-158`; `Sources/Domain/Export/ListsurfExport.swift`, JSON-only). Extend the existing envelope for single-list scope — export from the list's action menu via `fileExporter`/share sheet; import as *additive* (new UUIDs, appended to library), never replace. OPML is already tracked (`td-e95f67`) and matters for the CarbonFin Outliner migration; it fits the same per-list pipeline, so build per-list JSON and OPML together.
- **Inspecting the database** ("connect to the local sqlite db"): Possible today without code. The store is at `~/Library/Containers/net.vorwaller.listsurf/Data/Library/Application Support/Listsurf.sqlite` on Mac (model is code-defined in `Sources/Persistence/CoreDataModel.swift`; entities `ListEntity`, `OutlineItemEntity`). Open **read-only** with `sqlite3` or DB Browser — never write (cs.md rule; Core Data uses WAL). The durable answer is the **Diagnostics screen already in the V1 plan** (Phase 4): store path with "Reveal in Finder", store size, list/item counts, last export date. Build that instead of any live DB-viewer feature.
- **Common storage Mac/iOS** (user's P3): This is exactly CloudKit mirroring (`td-aad4ca`, V1.1). The schema was deliberately designed CloudKit-compatible from day one, so it's a switch-flip plus sync-status/recovery work — not a refactor. P3 is right: do it only after Groups A–C stabilize the model, because CloudKit schema becomes rigid after production promotion.

### Tracker gap

Of the testing notes, only OPML (`td-e95f67`) and loosely the Phase 3/4 tasks (`td-93efb7`, `td-a8cd2e`) are tracked. Groups A and B are not in `td` at all and should be added as tasks.

---

## Part 2 — Usability & utility, keeping it simple

Beyond the testing notes, ranked by leverage-per-complexity:

1. **The Group B refactor** — also the top usability item. A Mac outliner where keyboard navigation and inline rename work is the difference between "demo" and "daily tool."
2. **Markdown export via share sheet, per list.** Cheap (the tree engine already flattens), and the single most useful everyday feature: paste a packing list into Messages/Mail/Notes as `- [ ]` checkboxes. The V1 plan already scopes Markdown; per-list share is the killer delivery vehicle for it.
3. **Progress in library rows.** The plan specs leaf-based progress per list in the library; showing "12/24" or a small ring makes the library scannable and makes check mode feel consequential.
4. **First-run sample list + empty states.** One curated "Weekend Trip Packing" list demonstrating nesting, notes, quantity, and a folded branch (V1 plan §First-Run). For a public App Store app, the first 60 seconds currently show an empty library — cheapest retention fix available.
5. **Duplicate flow polish as a unit**: new name (A1) + the existing "clear checks" option + land the user *in* the new list afterward. Duplication is the template mechanism; it should feel first-class.
6. **Multiline paste with indentation** (V1 plan §Outline Editor) if not already implemented — it's how real lists get into the app in bulk, and pairs with OPML import as the "get your data in" story.

**Explicitly not doing**, to protect simplicity: tags, due dates/reminders, smart folders, attachments, AI parsing *(revised 2026-07-08: on-device Apple Intelligence changes this calculus — see Milestone 6 below; the guardrail still applies, chatbot-shaped features remain out)*. The V1 plan's scope-creep guardrail — features accepted only if they improve *creating, structuring, reusing, or executing durable lists* — is the right filter; keep it.

---

## Part 3 — The edge

The broad lists ecosystem splits into daily task managers (Reminders, Things, Todoist — dates, urgency, disposable items) and heavy outliners (Workflowy, OmniOutliner, Logseq — documents, sync, complexity). Almost nobody serves the thing Listsurf is already architected around: **lists you keep forever and run many times.** Three candidate edges, in recommended order:

### 1. "Checklists you run" — the recurring-procedure identity (recommended)

Lean into the aviation-checklist metaphor: a Listsurf list is a durable asset — packing list, opening/closing procedure, pre-trip routine — that you *run*, complete, reset, and run again. The machinery is ~80% built (duplicate+reset, check mode as presentation, archive). The missing 20% is tiny:

- Track `lastCompletedAt` and a run count per list.
- Show "Last completed June 12" in the library.
- When a run hits 100%, offer: "Done — reset for next time / archive this run (dated)".

No new entities — metadata plus framing. No mainstream app owns "the packing list you've refined over ten trips," and it's a story App Store copy can tell in one sentence. It also makes duplicate-vs-reset finally legible to users.

### 2. "Author on the Mac, execute on the phone"

Once CloudKit lands: the only app with a real keyboard-driven outliner on Mac *and* best-in-class one-handed check mode on iPhone for the same list. Outliners have bad phones; task apps have bad outlining. Less a feature than a bar to hit — requires Group B (Mac editing must be excellent) and V1.1 sync, so it's the *second-wave* edge that compounds with #1.

### 3. Quantity-native lists

`quantity` is already modeled — most list apps don't have it. Pushed slightly further (quantity shown in check mode, "4×" targets, progress counting units), it uniquely serves packing/inventory/provisioning. Cheapest of the three but narrowest; treat as a supporting feature of #1 rather than the headline.

**Common thread**: don't add a category of feature — sharpen the identity the architecture already has. *"Durable, deeply structured lists you run"* is defensible, simple, and honest to the codebase.

---

## Suggested sequencing

1. **Milestone 1 — 1.0.1 fix batch** (Group A, all eight): safe now while both App Review submissions sit in "Waiting for Review" (manual release controls timing; a rejection could absorb these into a resubmission).
2. **Milestone 2 — Mac selection/focus/editing refactor** (Group B): one coherent piece of work; fixes four reported issues.
3. **Milestone 3 — Interchange**: per-list JSON export/import, OPML (`td-e95f67`), Markdown share, Diagnostics screen.
4. **Milestone 4 — Drag-and-drop**, staged (`.onMove` first, reparenting drag later).
5. **Milestone 5 — Run lifecycle** (the edge): `lastCompletedAt`, run count, completion flow, library "last completed" display.
6. **Milestone 6 — Apple Intelligence integration** (see dedicated section below): on-device text→outline structuring, photo→outline capture, Siri/App Intents voice-add. After Milestone 3 — it shares the additive-import + validation plumbing.
7. **V1.1 — CloudKit** stays where planned: after the model stops moving. (Can interleave with Milestone 6; they touch different subsystems.)

---

## Addendum (2026-07-08, after discussion)

### AI parsing: manual-LLM workflow, not an app feature

Decision: "AI parsing" is served by a manual workflow — paste a list into any LLM app, ask for OPML/JSON, import the file. The app stays 100% local-first with zero API keys, network code, or privacy-manifest complications. This reframes Milestone 3: **import quality is the AI feature.**

- Import must be **additive** (append with new UUIDs), never replace-all.
- Validation errors must be **actionable** — good enough to paste back into the LLM chat to get a corrected file.
- **OPML is the preferred target format** for this workflow: simpler than the JSON envelope (no `schemaVersion`/UUID fields to fumble); any LLM produces clean OPML.
- Cheap win: ship a ready-made prompt in the help doc or README ("paste this prompt, then your list") — zero-cost feature, closes the AI-parsing loop.

### Database inspection: personal-edification path (not an app feature)

The current live store (sandboxed App Store/TestFlight build, post-`beffced`) is:

```
~/Library/Containers/net.vorwaller.listsurf/Data/Library/Application Support/Listsurf/Listsurf.sqlite
```

A **stale orphan** from pre-sandbox dev builds exists at `~/Library/Application Support/Listsurf/Listsurf.sqlite` (last written 2026-06-30) — old data, not what the current app uses. The `Listsurf-UITests` folders alongside both are throwaway test fixtures.

TablePlus notes:
- Tables: `ZLISTENTITY`, `ZOUTLINEITEMENTITY`; all columns Z-prefixed; `Z_PRIMARYKEY`/`Z_METADATA` are Core Data bookkeeping.
- Dates are seconds since **2001-01-01** (Core Data epoch): `datetime(ZCREATEDAT + 978307200, 'unixepoch')`.
- WAL mode — freshest rows may be in the `-wal` sidecar. Connect **read-only** (or with the app quit); an external write can corrupt a Core Data store.
- The Diagnostics screen (Milestone 3) still earns its keep by surfacing this path in-app with "Reveal in Finder."

---

## Milestone 6 — Apple Intelligence integration (added 2026-07-08)

**Status**: Researched 2026-07-08 (post-WWDC26 sources below). Sequenced after Milestone 3 because every feature here feeds the same additive-import + validation pipeline.

### Why this is the right AI path for Listsurf

The **Foundation Models framework** (iOS 26 / macOS 26+, which is already Listsurf's minimum OS) gives third-party apps direct Swift access to the on-device model behind Apple Intelligence: **no API keys, no network, no server, no user account, no cost.** It is the only AI integration that preserves the app's local-first identity, and it dissolves the original objections that motivated the manual-LLM workflow (which remains valuable for heavy lifts — the two coexist). Strategically: CarbonFin (web-based, maintenance mode) structurally cannot follow the app here.

This milestone **revises** the earlier "no AI parsing" exclusion. The V1 scope guardrail still governs: features must improve *creating, structuring, reusing, or executing durable lists*. Structuring-shaped features pass; chatbot-shaped features stay out.

### Framework essentials (enough to start without re-research)

- `import FoundationModels`. Core types: `SystemLanguageModel` and `LanguageModelSession` (methods `respond(to:)` / `streamResponse(to:)`), accepting a plain string or a `Prompt` builder.
- **Guided generation — the killer feature for Listsurf.** Annotate a Swift struct/enum with `@Generable` (property hints via `@Guide`); pass it as the response type and the model is *constrained* to emit that exact type — populated, type-checked, no JSON parsing, no malformed-output retry loop. Requirement: all properties must themselves be Generable types. Define a `GenerableOutline` mirror of the domain model (title, children, notes, quantity) and generated lists drop straight into the tree engine — **through the same validation invariants (cycle checks, same-list parenting) and additive-insert path as file import.** Never trust generated structure past the schema; validate like any import.
- **Tool calling**: conform to the `Tool` protocol; `call(arguments:)` implements the tool; arguments must be `@Generable` (or `GeneratedContent`). Lets the model query app state mid-generation if ever needed.
- **Availability handling (mandatory)**: check `SystemLanguageModel.default.availability` — `.available` or `.unavailable(reason:)` with reasons including `deviceNotEligible`, `appleIntelligenceNotEnabled`, `modelNotReady`. Hardware floor: iPhone 15 Pro or later, M-series iPad/Mac, Apple Intelligence enabled. **All Milestone 6 features must hide/degrade gracefully when unavailable** (also an App Review expectation).

### WWDC26 additions (June 2026) that matter here

- **New on-device model**, rebuilt with better logic and tool calling.
- **Multimodal image input**: prompts can include images, and Vision framework tools (OCR, barcode reading) are callable by the model directly, all on-device → enables photo→outline.
- **Context-size inspection and token-counting APIs** (instructions/prompts/transcripts) — use to chunk long pasted text.
- **Free Private Cloud Compute (PCC) access** for apps with < 2M first-time App Store downloads: Apple's larger server-side model, privacy-preserving, no user account, no developer cost. Relevant split: the on-device model (~3B-class) is strong at *structuring* given text but thin on *world knowledge*; generation-from-nothing wants PCC.
- Framework can also route to third-party models (Claude, Gemini) through the same API — **explicitly skipped** for Listsurf: it reintroduces the provider dependency this plan avoids.
- Apple announced the framework goes open source later in summer 2026.

### Feature candidates, ranked

| # | Feature | Stack | Notes |
|---|---------|-------|-------|
| F1 | **Structure pasted/selected text → outline** ("make this a list") | On-device FM + `@Generable` | The everyday 80% of the manual-LLM workflow, in-app, offline. First to build. |
| F2 | **Photo → outline** (handwritten packing list, whiteboard, recipe card) | On-device FM multimodal + Vision OCR tools | The signature "trick CarbonFin will never get." |
| F3 | **Generate starter list from a description** ("weekend camping in Patagonia") | PCC (needs world knowledge) | Present results as a *draft to edit*, never auto-commit. |
| F4 | **Siri/App Intents voice-add + start check mode** ("add sunscreen to Packing") | App Intents (not FM, but surfaced by Apple Intelligence) | Perfect fit with check-mode identity — hands are full when checking. Also unlocks Shortcuts/Spotlight. |
| F5 | **Writing Tools** in notes/title fields | Automatic on standard SwiftUI text views on supported hardware | Approximately free; verify it works in the editor's fields. |

**Non-goals**: chat UI, third-party model routing, anything requiring a Listsurf server or key.

### References

- [What's new in the Foundation Models framework — WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/)
- [WWDC26 Apple Intelligence developer guide](https://developer.apple.com/wwdc26/guides/apple-intelligence/)
- [Foundation Models framework documentation](https://developer.apple.com/documentation/FoundationModels)
- [Deep dive into the Foundation Models framework — WWDC25 session 301](https://developer.apple.com/videos/play/wwdc2025/301/) (guided generation, tool calling fundamentals)
- [MacRumors — Platforms State of the Union 2026 summary](https://www.macrumors.com/2026/06/09/apple-outlines-major-ai-and-developer-tool-updates/) (PCC free tier, multimodal, third-party routing, open-source plan)
- Community guides on `@Generable`/`@Guide` and `LanguageModelSession`: [createwithswift.com](https://www.createwithswift.com/exploring-the-foundation-models-framework/), [azamsharp.com](https://azamsharp.com/2025/06/18/the-ultimate-guide-to-the-foundation-models-framework.html), [appcoda.com](https://www.appcoda.com/generable/)

---

## Addendum 2 (2026-07-09) — Settings architecture

Context: the app has no settings surface. The first setting (notes displayed under items, configurable 1–n scrollable lines) is being added; it should land in a centralized Settings home rather than as a one-off toggle, to avoid a later migration.

### Platform surfaces (native-correct, one shared view)

- **macOS**: add a SwiftUI `Settings { SettingsView() }` scene to the app declaration. This provides the standard app-menu "Settings…" item with **⌘,** and the standard settings window for free. Do not hand-roll a settings window.
- **iOS/iPadOS**: gear icon in the library toolbar presenting the same `SettingsView` (a plain `Form`) as a sheet. No iOS Settings-app bundle — in-app is correct for presentation preferences.
- One `SettingsView`, two presentation wrappers. No forked settings logic.

### Storage

`@AppStorage` / `UserDefaults` — **not Core Data**. Per the V1 plan's Device-Local Presentation State rule, presentation preferences are device-local and must stay out of the Core Data model so they don't enter CloudKit's sync scope in V1.1 (device A's display prefs must not overwrite device B's). The notes setting is exactly this kind, e.g. `@AppStorage("notesPreviewLineLimit")` with `0 = off`, `1–n = visible lines`.

### Sections (grow into this; keep the bar for new settings high)

| Section | Now | Later |
|---------|-----|-------|
| **Display** | Notes preview line limit (0/1–n) | Auto-hide checked rows |
| **Check Mode** | — | Haptics toggle, default filter |
| **Data** | — | Diagnostics screen (Milestone 3): store path + Reveal in Finder, store size, list/item counts, last export date; backup entry points |
| **About** | Version, help/privacy links | — |

Guardrail: every setting is a declined design decision — prefer good defaults over toggles. The settings *surface* is infrastructure (Diagnostics alone justifies it), but each added toggle needs to pass the same scope filter as any feature.
