# M5 action-to-surface parity matrix

This is the manual Gate M4 source of truth. A check means the action must be
present; a dash means it must not be present. Labels and shortcuts must match
`CommandCatalog`. Row right-click acts on the current selection. Row ellipsis
acts on its row, selects that row immediately before every action, and shows no
shortcut hints.

| Command | Canonical label | Key | Item menu | View menu | Row right-click | Row ellipsis | Toolbar actions | Empty-area right-click |
|---|---|---:|:---:|:---:|:---:|:---:|:---:|:---:|
| newItem | New Item | ⌘N / Return with no selection | ✓ | — | ✓ (below) | ✓ (below) | ✓ | ✓ |
| addAbove | Add Above | ⌥⌘N | ✓ | — | ✓ | ✓ | ✓ | — |
| addChild | Add Child | ⌘↩ | ✓ | — | ✓ | ✓ | ✓ | — |
| rename | Rename | Return / ⌘E | ✓ | — | ✓ | ✓ | ✓ | — |
| toggleChecked | Toggle Checked | Space / ⌘K | ✓ | — | ✓ | ✓ | ✓ | — |
| indent | Indent | Tab / ⌘] | ✓ | — | ✓ | ✓ | ✓ | — |
| outdent | Outdent | ⇧Tab / ⌘[ | ✓ | — | ✓ | ✓ | ✓ | — |
| moveUp | Move Up | ⌥⌘↑ | ✓ | — | ✓ | ✓ | ✓ | — |
| moveDown | Move Down | ⌥⌘↓ | ✓ | — | ✓ | ✓ | ✓ | — |
| delete | Delete | ⌘⌫ | ✓ | — | ✓ | ✓ | ✓ | — |
| resetAllChecks | Reset All Checks… | — | ✓ | — | — | — | ✓ | — |
| resetBranch | Reset Branch… | — | — | — | parent only | parent only | parent only | — |
| filterAll | All | ⌥⌘1 | — | ✓ | — | — | ✓ | — |
| filterRemaining | Remaining | ⌥⌘2 | — | ✓ | — | — | ✓ | — |
| filterCompleted | Completed | ⌥⌘3 | — | ✓ | — | — | ✓ | — |
| toggleInspector | Toggle Inspector | ⌥⌘I | — | ✓ | — | — | ✓ | — |
| expandAll | Expand All | — | — | ✓ | — | — | ✓ | ✓ |
| collapseAll | Collapse All | — | — | ✓ | — | — | ✓ | ✓ |
| keyboardLegend | Keyboard Legend | ⌥⌘L | — | ✓ | — | — | — | — |

Commands outside the six item/action surfaces are audited independently:

| Command | Required surface | Key / native gesture | Must not appear on |
|---|---|---|---|
| newList | File/New command group and generated Mac Help/legend | ⇧⌘N | Item/View and item-action surfaces |
| help | Help menu and generated Mac Help/legend | ⌘? | Item/View and item-action surfaces |
| navigate | Native outline selection and generated Mac Help/legend | ↑ / ↓, modifier-click | Menus and item-action surfaces |
| escape | Editor handler and generated Mac Help/legend | Esc | Menus and item-action surfaces |
| settings | Native app Settings scene and generated Mac Help/legend | ⌘, | Item/View and item-action surfaces |

## Integrated manual audit

1. On macOS, open each surface in the table and compare both presences and
   absences. Confirm the row ellipsis has no shortcut glyphs and each action
   changes selection to that row before acting.
2. Right-click empty outline space and verify exactly New Item, Expand All,
   and Collapse All from this matrix.
3. Open Help and Keyboard Legend side by side. Confirm they have the same
   ordered key rows, including Return, Tab, Space, Esc, ⌘?, ⌘,, and ⌥⌘L.
4. Invoke every advertised shortcut once. With the legend open, verify the
   matching row highlights for about 0.9 seconds without moving editor focus.
5. On iOS, verify Help contains the touch Keyboard accessory explanation and
   no hardware-keyboard shortcut section or shortcut copy.
