# M5 Gate RETEST — fixed items only (2026-07-26)

Focused re-verification of the 2026-07-25 gate findings after the fix pass
(commits `01e8c44`..`08d5e82`+). NOT the full 56-item gate — everything that
passed on 07-25 and wasn't touched stays passed. One clean run here (plus the
macOS UI suite unlock, below) closes the m5-gate-fixes issues and td-39e584.

**Before anything: unlock the Mac and let CC run the macOS UI suite once.**
The runner has been auth-blocked since the fixes landed (LocalAuthentication
dialog needs a human). Everything below assumes fresh builds of current main.

## Sitting 1 — macOS (~10 min)
1. ☐ **Legend (td-0a4af9)**: ⌥⌘L opens → ⌥⌘L closes. Reopen, CLICK the legend
   window (make it key) → ⌥⌘L again → legend closes, app window does NOT hide.
   Reopen → Esc closes. After every close: ↓ moves the editor selection
   (focus came back).
2. ☐ **Delete (td-688730)**: select a middle row → ⌘⌫ → Return → the row below
   is selected and ↓/↑ move in the editor (not the sidebar). Repeat on the
   LAST row → previous row selected. ⌘Z → deleted row AND selection restored.
3. ☐ **Second Esc (td-c85e4b)**: select row → Esc (selection clears) → Esc →
   nothing happens, sidebar untouched.
4. ☐ **Edit Notes (td-2bc3a8)**: select a row → ⌘O → inspector opens, TYPE
   IMMEDIATELY → text lands in Notes. ⌥⌘I closes → ↓ moves editor selection.
   Check ⌘O shows in View menu, Help, and the Legend.
5. ☐ **Multi-select ops (td-2735d9)**: ⇧-select 3 siblings → Tab indents all
   three, order preserved → ⇧Tab outdents, order preserved → ⌘⌥↑/↓ moves the
   block → ONE ⌘Z per op restores everything. Then include the FIRST sibling
   and Tab → nothing moves at all (all-or-nothing, no dead ⌘Z step).
6. ☐ **Note preview (td-50f035)**: item with a 5-line note, setting at 2
   lines → "more" chevron shows → tap → full note in the row, layout sane →
   collapse works. Settings picker now offers up to 10 lines.
7. ☐ **Restore last list (td-03f6d1b)**: select list B → quit → relaunch →
   list B is shown.
8. ☐ **Search notes (td-03f6d1e)**: in-list search for a word that appears
   only in a note → row (and its parents) appear.
9. ☐ **Rename lag spot-check (td-e7c609, macOS half)**: ⌘E, type a fast
   sentence — keystrokes land instantly (the old few-ms hiccup gone).

## Sitting 2 — iPhone, real device (~10 min)
1. ☐ **Rename lag (td-e7c609) — THE verdict**: rename, type a quick sentence.
   Record build type (cable-debug vs TestFlight/release) + verdict
   (none / noticeable / bad). This was "very noticeable, fix before ship."
2. ☐ **Details-sheet rename (td-9537dc)**: double-tap row → edit the Title
   field in the sheet → dismiss → row shows the new title. (The old dead
   "Rename" button is gone on iOS.)
3. ☐ **Filters (td-8982f7)**: filter icon visible top-right WITHOUT opening
   ••• → Remaining / Completed / All all work; icon fills when a filter is
   active.
4. ☐ **Keyboard occlusion (td-1ef423)**: long list → arm a child add on a
   bottom row → the field scrolls clear of the keyboard, cursor live. Same
   for renaming a bottom row. Then the chevron-dismiss flow: keyboard drops,
   NO giant blank strip at the bottom, add flow still armed.
5. ☐ **Large title (td-03f6d1c / td-ef3eec)**: scroll hard to top — no shake,
   title steady in the inline bar.
6. ☐ **Notes corruption (td-204b17)**: type a multi-line note (5+ lines, fast)
   in Details → close → reopen → text is EXACTLY what was typed.
7. ☐ **Action bar (td-03f6d1d)**: during normal use, note whether the bottom
   action bar ever floats mid-screen (instrumented in DEBUG — if it happens,
   note the time so the log signature can be pulled).
8. ☐ **Note preview expand (td-50f035)**: "more" chevron on a truncated note →
   expands in place → collapses.

## Wrap-up
- ☐ Hand CC the marked-up results (any form). All pass → td-39e584 closes;
  next stop TestFlight dogfood build.
