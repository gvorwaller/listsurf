# Restore split-version edit keys and revise the M5 gate checklist

## Context

Full code comparison of the last split-function commit (`2b73f6d`, the version whose edit mode Gaylon validated — it recorded the Gate M1 macOS pass) against HEAD (`ac45069`) showed the edit regressions are confined to the three "create a new item" entry points. Everything else (select, rename mechanics, commit/cancel, indent/outdent, delete, move, expand/collapse, the add-field's type-Return-next loop) is behaviorally identical or slightly improved.

Root cause: M5 rebound Return from "add below" to "rename" and moved ALL selection-relative adds (Cmd-N, Option-Cmd-N, Cmd-Return) onto menu-equivalent dispatch — a route that fails to put the cursor into the newly armed field (FocusState reports focused; AppKit first responder never moves). The old version's primary adds (Return, Shift-Return) were editor-owned key handlers and immune.

Decisions (Gaylon, 2026-07-19/20):
1. **Old bindings back**: Return = add item below, Shift-Return = add item above, Cmd-Return = add child. Rename stays on double-click and Cmd-E.
2. **Bare Space toggle STAYS.** Gaylon verified in his own testing that Space never fires while a text box is active (the field consumes it and the handler is guarded by `isTextInputActive`) and only toggles after Return/Escape ends text entry — he likes the convenience and it is a standard control. No change to Space, Cmd-K, or the checkbox.
3. Gaylon retested the current build (working tree, which includes the uncommitted td-ff531e focus fix) and reports functionality is GOOD. He will restart the full integrated gate checklist after this change, revised to match the new bindings.

## Step 1 — Commit the working-tree focus fix first

The uncommitted `OutlineEditorView.swift` diff (pendingFocus survives reach, NSMenu didEndTracking re-assert, first-typed-char clears guard, AppKit responder fallback) is what Gaylon just hands-on validated. Commit it as the td-ff531e fix BEFORE rebinding, so the validated state is a durable baseline. It also remains load-bearing for mouse-driven paths: clicking a menu item (menu bar or right-click "Add Child") still arms the field via menu dispatch, and the didEndTracking re-assert is what makes that work. Do not delete this machinery in this change.

## Step 2 — Rebind the editor-owned keys (macOS)

File: `Sources/Features/Editor/OutlineEditorView.swift`, `handleReturnKey` (~line 551).

Restore the `2b73f6d` semantics, plus make add-child editor-owned:
- Bare Return, single row selected → `store.beginAdding(.below(row.id))`. No selection → `beginAdding(.root)` (unchanged today).
- Shift-Return → `store.insertAbove(referenceID:…, title: "New Item")` then `store.beginEditing(newID)` (exactly the old code, `2b73f6d` OEV:453-457).
- Cmd-Return → handle DIRECTLY in the editor (`beginAdding(.child(row.id))`) instead of `.ignored`-falling-through to the menu. The menu item keeps its key equivalent for display; since menu equivalents are consumed by `performKeyEquivalent` before `.onKeyPress`, verify empirically which layer wins with the editor focused — if the menu still intercepts, the menu path now also works (Step 1 machinery), so both routes are acceptable; prefer whichever the probe shows, and record the finding.
- Multi-selection Return → `.ignored` (as today).
- Rename: Return no longer renames. Double-click, Cmd-E, and context-menu Rename remain (all existing code — Cmd-E's menu route plants a cursor and is covered by the Step 1 machinery, which Gaylon's testing just exercised).
- Cmd-N (New Item), Option-Cmd-N (Add Above) menu items and shortcuts stay as secondary paths — they work now per Gaylon's testing. Return/Shift-Return become the primary, guaranteed paths.
- Bare Space toggle: untouched (see Decision 2).
- Post the matching `CommandInvocation` IDs from the new handlers so the keyboard legend still highlights.

## Step 3 — Catalog / help / legend / docs consistency

- `Sources/Features/Commands/CommandCatalog.swift`: update `editorOwnedKey` entries — rename loses "Return"; newItem gains editor-owned "Return"; addAbove gains "⇧Return". toggleChecked keeps "Space" and Cmd-K unchanged. Keep the exact-inventory and ordered-editor-owned-keys unit tests in sync (they will fail until updated — that is the safety net working).
- Mac Help (`ListsurfHelpView`) and the Keyboard Legend render from the catalog — verify rows read correctly after the catalog edit. iOS Help still carries no keyboard content.
- `docs/m5-parity-matrix.md`: update the affected rows.
- Context-menu text hints (td-06fb0a mechanism): unchanged for Cmd-Return/Cmd-E; no hint additions for Return/Shift-Return in context menus (they are editor-owned keys, shown in Help/Legend as such).

## Step 4 — Tests

- Update the Gate M3-era UI tests that encode the M5 bindings: the Return-renames test becomes Return-adds-below (assert typing lands — the focus-proof pattern from `testCommandReturnArmsEditableChildField`); add a Shift-Return add-above + immediate-rename test.
- Space tests unchanged (Space-advance-under-Remaining stays as-is).
- Keep `testCommandReturnArmsEditableChildField` (menu path) — it now guards the Step 1 machinery.
- CommandCatalog unit tests updated per Step 3.

## Step 5 — Revise the integrated gate checklist

Files: `docs/` M5 integrated-gate checklist (commit 9e4b5aa) and its OPML twin (9ffd826). Replace: Return-rename steps → Return-add-below; add a Shift-Return step; keep the Space-toggle steps (including one that verifies Space types a space during text entry and toggles only after Return/Escape — Gaylon's observed behavior, now an explicit gate assertion); keep menu-click add steps (they exercise the Step 1 machinery). Gaylon restarts the full checklist from this revision.

## td bookkeeping

- td-ff531e: fixed by Step 1 commit (note Gaylon's hands-on validation as the evidence tier: local build, real hardware).
- td-06fb0a: already fixed in `ac45069`; close on gate evidence.
- New td issue for this rebinding change referencing this plan; the M5 spec gets a rev note (Rev 2.8): Return/Shift-Return bindings restored per Gaylon 2026-07-19/20 decision; Space toggle retained by explicit decision.

## Verification

- `swift test`, macOS xctestplan, iOS xctestplan all green.
- Live app: select mid-list row → Return → type immediately (characters must land) → Return → next item; Shift-Return → renameable "New Item" above; Cmd-Return → child field with cursor; Cmd-E and double-click rename; during a rename Space types a space; after Return/Escape Space toggles the selected rows; checkbox click completes.
- Then Gaylon runs the revised full gate checklist on macOS + real iPhone.
