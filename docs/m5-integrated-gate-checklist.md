# M5 Integrated Gate — Consolidated Checklist

One pass closes epic td-39e584. Consolidates Gates M2 + M3 + M4 (spec Rev 2.7) plus the
Phase 2/4 additions. Two sittings: **macOS (~25 min)**, then **iPhone (~15 min)**.
Mark each ☐ pass/fail; jot a note on anything that feels wrong even if it "passes."
Failures don't need diagnosis — a one-line symptom is enough; CC2 turns them into td issues.

**Build prerequisites**
- ☐ macOS: current main (`7772057` or later), fresh build.
- ☐ iPhone: real device — cable build is fine for everything EXCEPT step P5 (rename lag),
  which should ideally also be tried on a TestFlight/release build before calling it real.

---

## Sitting 1 — macOS

### A. Checkbox & filter flow (Gate M2)
1. ☐ Create a list; add 5 items with some nesting (2–3 levels).
2. ☐ Check a leaf → strikethrough appears; parent shows progress (e.g. 1/3).
3. ☐ Click a parent's checkbox → whole branch checks (branch check).
4. ☐ Make a mixed parent (some children checked) → orange minus tri-state.
5. ☐ Filter Remaining → checked rows gone. Completed → only checked. All → everything.
6. ☐ Under Remaining, check a visible row → it animates out, selection advances.
7. ☐ Check everything under Remaining → "All Done!" 🎉 → Show All returns.
8. ☐ Right-click a parent → Reset Branch… → confirm → branch unchecked.
9. ☐ Toolbar ↺ Reset All… → confirm → all unchecked.
10. ☐ ⌘Z back through every mutation above — each one undoes cleanly.
11. ☐ Quit and relaunch → everything persisted; legend window did NOT auto-reopen.
12. ☐ Remnant sweep: no "Check Mode" wording anywhere — toolbar, menus, Help, **Settings**.

### B. Keyboard-only session (Gate M3 — mouse untouched)
1. ☐ ⇧⌘N → create a list from the keyboard.
2. ☐ ⌘N → type → Return → type → Return (continuation ×3) → Esc ends the flow.
3. ☐ Arrows move selection; ⇧-arrows extend it.
4. ☐ Return on a selected row → renames in place. Do it ~10× on different rows — every time.
5. ☐ While renaming: Esc cancels (title unchanged); Return commits.
6. ☐ Filter Remaining (⌥⌘2) → select top row → Space, Space, Space → rows vanish,
   selection advances each time.
7. ☐ ⇧-extend a multi-selection → ⌘K immediately → ALL selected rows toggle
   (this is the old "acts on the last row" bug — it must hit the highlighted rows).
8. ☐ Tab / ⇧Tab indent/outdent the selected row; ⌘] / ⌘[ same; ⌘⌥↑/↓ moves it.
9. ☐ ⌘⌫ → confirmation dialog → **Return activates Delete (the default), never rename**.
10. ☐ ⌘Z back through everything.
11. Edge cases:
    - ☐ Return with nothing selected on an empty list → arms root add.
    - ☐ Return with a multi-selection → does nothing.
    - ☐ Space while renaming/adding → types a space, never toggles.
    - ☐ Click into sidebar search, press Space → types a space; editor untouched.
    - ☐ Space with no selection → list scrolls (native default).
12. ☐ Esc with no text entry active → clears selection; Esc again → nothing.

### C. Consistency audit (Gate M4)
1. ☐ Open Help (⌘?) → read the "Mac keyboard" section **line by line, performing each
   entry as you read it**. Any line that doesn't match reality = fail.
2. ☐ Open `docs/m5-parity-matrix.md` next to the app. For each surface, check contents
   against the matrix (present where required, absent where forbidden):
   - ☐ Menu bar → Item menu
   - ☐ Menu bar → View menu (incl. Filter submenu ⌥⌘1/2/3, Keyboard Legend)
   - ☐ Right-click on a row (hints shown)
   - ☐ Row ⋯ ellipsis menu (hints ABSENT — deliberate)
   - ☐ Toolbar ⋯ Actions button
   - ☐ Right-click on empty outline area (Add Item, Expand All, Collapse All)
3. ☐ Press every shortcut Help advertises, once each: ⌘N ⇧⌘N ⌥⌘N ⌘⏎ ⌘E ⌘K ⌘] ⌘[
   ⌘⌥↑ ⌘⌥↓ ⌘⌫ ⌥⌘1 ⌥⌘2 ⌥⌘3 ⌥⌘I ⌥⌘L ⌘? ⌘, ⌘Z ⇧⌘Z.

### D. New features (Phase 2 batch + Phase 4)
1. ☐ Inspector notes (⌥⌘I): paste ~15 lines into Notes → the field stays compact
   (~3–6 lines tall) and scrolls internally; inspector layout doesn't blow out.
2. ☐ Keyboard Legend: ⌥⌘L opens it; press keys in the editor (Return, Space, Tab,
   ⌘K, arrows…) → the matching legend row lights up ~1s. ⌥⌘L again (or close) hides it.
3. ☐ With the legend open, keep typing in the editor → focus stays in the editor
   (the legend never steals keystrokes).

### E. Judgment calls (feel, not pass/fail — note your verdict)
1. ☐ Row context/ellipsis menus now say "New Item" where they used to say "Add Below."
   Keep, or revert to contextual wording?
2. ☐ Strikethrough on checked rows — keep?
3. ☐ Instant hide under Remaining (vs a Things-style grace delay) — keep?
4. ☐ Overall: does it feel like the prototype? Anything missing goes on a list, not in your head.

---

## Sitting 2 — iPhone (real device)

### P. Core flow (Gate M2)
1. ☐ Create list → add 5 nested items — **the add field appears AT the insertion point**
   (below its anchor, indented for a child), never at the bottom of the list.
2. ☐ While adding: tap ⌄ → keyboard drops but the add flow stays armed (field + draft
   remain) → tap the field → keyboard returns → Done ends the flow.
3. ☐ Checkbox flow: leaf, branch (parent), mixed tri-state, filters, All Done → Show All,
   Reset via toolbar. Fat-finger check: checkbox vs chevron never mis-tap.
4. ☐ Undo/Redo in the toolbar ⋯ overflow: mutate → Undo enabled / Redo disabled →
   Undo → Redo enabled → Redo → switch lists → both disabled.
5. ☐ **Rename lag measurement (td-e7c609)**: rename an item, type a quick sentence.
   Note build type (cable-debug vs TestFlight) and verdict: no lag / noticeable / bad.
   Non-blocking today; fix-before-ship regardless.
6. ☐ Double-tap a row → Details sheet opens; single-tap select is not delayed.
7. ☐ Details notes: paste long text → bounded field, scrolls internally.
8. ☐ Scroll the list hard to the top — **no shake, and the large title renders**
   (td-ef3eec: if it still shakes, that's a fail with a known td — just note it).

### Q. Gestures never verified on hardware (Gate M2 Rev 2.6)
1. ☐ Drag a row among its siblings (same parent) → clean reorder.
2. ☐ Try to drag past the first/last sibling → clamps sanely, no crash/jump.
3. ☐ Long-press a row: menu appears. Note the drag-vs-menu arbitration behavior
   (td-3960b2 said drag only works if you slide out of the menu — record what happens now).
4. ☐ Swipe-to-delete → confirmation → delete → Undo from overflow restores it.
5. ☐ Kill and relaunch the app → everything persisted.

---

## Wrap-up
- Hand CC2 the marked-up list (photo of paper, notes file, whatever).
- Every fail → a td issue with your one-line symptom. Judgment calls → decisions recorded in spec/td.
- All pass (or fails signed off as deferrals) → td-39e584 closes and M5 is done;
  next stop TestFlight dogfood build.
