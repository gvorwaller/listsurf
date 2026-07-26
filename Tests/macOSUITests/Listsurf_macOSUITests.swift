import XCTest

final class Listsurf_macOSUITests: XCTestCase {
    @MainActor func testCommandNOpensNewListSheet() {
        continueAfterFailure = false
        let app = launchApp(store: "mac-command-new-list", reset: true)

        app.typeKey("n", modifierFlags: [.command, .shift])
        fillNewListSheet(named: "Command Created List", in: app)

        XCTAssertTrue(app.staticTexts["Command Created List"].waitForExistence(timeout: 5))
    }

    @MainActor func testCreateListAndAddItem() {
        continueAfterFailure = false
        let app = launchApp(store: "mac-create-list", reset: true)
        createList(named: "Mac UI Packing List", in: app)

        addItem(named: "Passport", in: app)
        XCTAssertTrue(app.staticTexts["Passport"].waitForExistence(timeout: 5))
    }

    @MainActor func testVisibleDeleteRequiresConfirmation() {
        continueAfterFailure = false
        let app = launchApp(store: "mac-delete-confirmation", reset: true)
        createList(named: "Delete Confirmation List", in: app)
        addItem(named: "Temporary Item", in: app)

        let item = app.staticTexts["Temporary Item"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))

        let deleteItem = app.buttons["editor.deleteItem"].firstMatch
        XCTAssertTrue(deleteItem.waitForExistence(timeout: 5))
        deleteItem.click()

        let deleteButton = app.sheets.buttons["Delete Item"].firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        XCTAssertTrue(item.exists)

        deleteButton.click()
        XCTAssertFalse(item.waitForExistence(timeout: 2))
    }

    /// td-688730 (Gate M2, plan item 6): deleting the selected row used to
    /// drop focus to the sidebar list name instead of advancing selection
    /// within the editor. Proof: after ⌘⌫ + Return (confirm), selection must
    /// have already advanced to the row that took the deleted row's place,
    /// and Down must move that EDITOR selection to a DIFFERENT row — if
    /// focus had actually left for the sidebar, Down would never reach the
    /// outline's own selection.
    @MainActor func testDeleteAdvancesSelectionAndStaysInEditor() {
        continueAfterFailure = false
        let app = launchApp(store: "mac-delete-selection-advance", reset: true)
        createList(named: "Delete Selection Advance List", in: app)
        addItem(named: "Alpha", in: app)
        addItem(named: "Bravo", in: app)
        addItem(named: "Charlie", in: app)
        app.typeKey(.escape, modifierFlags: [])

        let alpha = app.staticTexts["Alpha"]
        XCTAssertTrue(alpha.waitForExistence(timeout: 5))
        alpha.click()
        let bravoRow = app.outlineRows.containing(.staticText, identifier: "Bravo").firstMatch
        let charlieRow = app.outlineRows.containing(.staticText, identifier: "Charlie").firstMatch

        app.typeKey(.delete, modifierFlags: [.command])
        let deleteButton = app.sheets.buttons["Delete Item"].firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        app.typeKey(.return, modifierFlags: [])

        XCTAssertFalse(alpha.waitForExistence(timeout: 2))
        XCTAssertTrue(
            waitUntil(timeout: 5) { bravoRow.isSelected },
            "Deleting Alpha must select the row that took its place, staying in the editor"
        )

        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(
            waitUntil(timeout: 5) { charlieRow.isSelected && !bravoRow.isSelected },
            "Down after the delete-confirm must move the EDITOR's selection to a different row — proves focus stayed in the editor, not the sidebar"
        )
    }

    @MainActor func testListPersistsAcrossRelaunch() {
        continueAfterFailure = false
        let app = launchApp(store: "mac-persistence", reset: true)
        createList(named: "Persistent Mac List", in: app)
        app.terminate()
        relaunch(app, reset: false)

        XCTAssertTrue(app.staticTexts["Persistent Mac List"].waitForExistence(timeout: 5))
        // td-03f6d1 part b (plan item 12b/E5): the list must not just be
        // visible in the sidebar — it must be the SELECTED/displayed list.
        // Without the restore, the detail pane shows "Select a List" and
        // neither add-item button exists.
        XCTAssertTrue(
            firstExisting(app.buttons["editor.addFirstItem"], app.buttons["editor.addItem"]).waitForExistence(timeout: 5),
            "The previously-selected list must be restored and shown after relaunch, not just listed in the sidebar"
        )
    }

    /// td-5d405a: per-list VIEW state (expandedIDs, checkFilter,
    /// selectedItemIDs) must survive switching between lists in-session —
    /// this was the reported bug (switching lists and back re-collapsed
    /// everything). Proof: expand a nested branch (via addChild, which
    /// auto-expands its parent), switch to a second list (hiding the
    /// child), switch back, and assert the child is visible WITHOUT any
    /// click on a disclosure control in between.
    @MainActor func testExpandedBranchSurvivesListSwitch() {
        continueAfterFailure = false
        let app = launchApp(store: "mac-viewstate-switch", reset: true)
        createList(named: "View State List A", in: app)
        addItem(named: "Anchor", in: app)
        app.typeKey(.escape, modifierFlags: [])

        let anchor = app.staticTexts["Anchor"]
        XCTAssertTrue(anchor.waitForExistence(timeout: 5))
        anchor.click()
        addChildItem(named: "Nested Child", in: app)
        app.typeKey(.escape, modifierFlags: [])

        let nestedChild = app.staticTexts["Nested Child"]
        XCTAssertTrue(nestedChild.waitForExistence(timeout: 5), "Precondition: addChild auto-expands its parent")

        // Switching creates a list — this also switches selection to it.
        createList(named: "View State List B", in: app)
        XCTAssertFalse(nestedChild.waitForExistence(timeout: 2), "Precondition: List B's editor must not show List A's rows")

        // Switch back by clicking List A's sidebar row (existing pattern —
        // rows are plain Text(list.title), no dedicated identifier).
        app.staticTexts["View State List A"].click()

        XCTAssertTrue(
            nestedChild.waitForExistence(timeout: 5),
            "The nested branch must still be expanded after switching lists and back — no re-expand click happened above"
        )
    }

    /// td-5d405a: extends the relaunch coverage above — an expanded branch
    /// AND the Remaining filter must both survive a full relaunch, not just
    /// list selection. Loose Item is checked then hidden by Remaining; if
    /// the filter didn't persist, it would reappear after relaunch since a
    /// fresh ListStore defaults to `.all`.
    @MainActor func testExpandedBranchAndRemainingFilterSurviveRelaunch() {
        continueAfterFailure = false
        let app = launchApp(store: "mac-viewstate-relaunch", reset: true)
        createList(named: "View State Relaunch List", in: app)
        addItem(named: "Anchor", in: app)
        app.typeKey(.escape, modifierFlags: [])

        let anchor = app.staticTexts["Anchor"]
        XCTAssertTrue(anchor.waitForExistence(timeout: 5))
        anchor.click()
        addChildItem(named: "Nested Child", in: app)
        app.typeKey(.escape, modifierFlags: [])

        let nestedChild = app.staticTexts["Nested Child"]
        XCTAssertTrue(nestedChild.waitForExistence(timeout: 5), "Precondition: addChild auto-expands its parent")

        addItem(named: "Loose Item", in: app)
        app.typeKey(.escape, modifierFlags: [])
        let checkLoose = app.buttons["Check Loose Item"]
        XCTAssertTrue(checkLoose.waitForExistence(timeout: 5))
        checkLoose.click()

        app.typeKey("2", modifierFlags: [.command, .option]) // Remaining filter
        let looseItem = app.staticTexts["Loose Item"]
        XCTAssertFalse(looseItem.waitForExistence(timeout: 2), "Precondition: Remaining hides the now-checked Loose Item")

        app.terminate()
        relaunch(app, reset: false)

        XCTAssertTrue(anchor.waitForExistence(timeout: 5), "The restored list must be selected and shown after relaunch")
        XCTAssertTrue(
            nestedChild.waitForExistence(timeout: 5),
            "The expanded branch must survive relaunch, not just an in-session list switch"
        )
        XCTAssertFalse(
            looseItem.waitForExistence(timeout: 2),
            "The Remaining filter must survive relaunch — a fresh ListStore defaulting to .all would show Loose Item again"
        )
    }

    @MainActor func testCoreActionsAreVisible() {
        continueAfterFailure = false
        let app = launchApp(store: "mac-visible-actions", reset: true)

        XCTAssertTrue(app.buttons["library.importBackup.visible"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["library.exportBackup.visible"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["library.archive.visible"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["library.help.visible"].waitForExistence(timeout: 5))

        createList(named: "Visible Mac Actions List", in: app)
        addItem(named: "Indentable Mac Item", in: app)

        let rowActions = firstExisting(
            app.buttons["editor.rowActions"].firstMatch,
            app.menuButtons["editor.rowActions"].firstMatch
        )
        XCTAssertTrue(rowActions.waitForExistence(timeout: 5))
    }

    @MainActor func testHelpOpensFromLibrary() {
        continueAfterFailure = false
        let app = launchApp(store: "mac-help", reset: true)

        let help = firstExisting(
            app.buttons["library.help.visible"],
            app.buttons["library.help.empty"]
        )
        XCTAssertTrue(help.waitForExistence(timeout: 15))
        help.click()

        XCTAssertTrue(app.staticTexts["Listsurf Help"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Start here"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Mac keyboard"].waitForExistence(timeout: 5))
        app.buttons["help.done"].click()
        XCTAssertFalse(app.staticTexts["Listsurf Help"].waitForExistence(timeout: 2))
    }

    @MainActor func testDragReordersSiblings() {
        continueAfterFailure = false
        let app = launchApp(store: "mac-drag-reorder", reset: true)
        createList(named: "Mac Drag Reorder List", in: app)

        addItem(named: "Alpha", in: app)
        addItem(named: "Bravo", in: app)
        addItem(named: "Charlie", in: app)

        // Committing with Return re-arms the add flow, and rows are
        // .moveDisabled while text entry is active — dismiss it first.
        app.typeKey(.escape, modifierFlags: [])

        let alpha = app.staticTexts["Alpha"]
        let bravo = app.staticTexts["Bravo"]
        let charlie = app.staticTexts["Charlie"]
        XCTAssertTrue(charlie.waitForExistence(timeout: 5))
        XCTAssertTrue(alpha.waitForExistence(timeout: 5))
        XCTAssertTrue(bravo.waitForExistence(timeout: 5))

        // Precondition: insertion order is Alpha, Bravo, Charlie top to bottom.
        XCTAssertLessThan(alpha.frame.minY, bravo.frame.minY)
        XCTAssertLessThan(bravo.frame.minY, charlie.frame.minY)

        // B1 fix: drag only arms while the row's content region is hovered
        // (macOS-only .moveDisabled predicate). XCUITest's click(forDuration:
        // thenDragTo:) doesn't hover first, so arm it explicitly — what a
        // human does anyway (spec §5 Phase 1 gate authorizes this).
        charlie.hover()
        // Let the hover state propagate through SwiftUI's onHover → @State
        // → .moveDisabled render cycle before the drag gesture captures it.
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        charlie.click(forDuration: 0.3, thenDragTo: alpha)

        XCTAssertTrue(waitUntil(timeout: 5) { charlie.frame.minY < bravo.frame.minY })
        XCTAssertLessThan(charlie.frame.minY, bravo.frame.minY, "Charlie should have moved above Bravo")

        app.typeKey("z", modifierFlags: .command)

        XCTAssertTrue(waitUntil(timeout: 5) {
            alpha.frame.minY < bravo.frame.minY && bravo.frame.minY < charlie.frame.minY
        })
        XCTAssertLessThan(alpha.frame.minY, bravo.frame.minY, "Undo should restore Alpha above Bravo")
        XCTAssertLessThan(bravo.frame.minY, charlie.frame.minY, "Undo should restore Bravo above Charlie")
    }

    /// B3 regression (spec §2, §5 Phase 1 item 5): `focusedCommandActions`
    /// closures must read selection LIVE at invocation. Before the fix,
    /// ⌘[/⌘] closed over the selection captured when the focused value was
    /// last published, so they could act on the last-added row instead of
    /// the row the user actually clicked.
    @MainActor func testCommandBracketIndentsSelectedRow() {
        continueAfterFailure = false
        let app = launchApp(store: "mac-command-bracket-indent", reset: true)
        createList(named: "Mac Command Bracket List", in: app)

        addItem(named: "Alpha", in: app)
        addItem(named: "Bravo", in: app)
        addItem(named: "Charlie", in: app)

        // Committing with Return re-arms the add flow — dismiss it before
        // selecting a row (same pattern as testDragReordersSiblings).
        app.typeKey(.escape, modifierFlags: [])

        let alpha = app.staticTexts["Alpha"]
        let bravo = app.staticTexts["Bravo"]
        let charlie = app.staticTexts["Charlie"]
        XCTAssertTrue(alpha.waitForExistence(timeout: 5))
        XCTAssertTrue(bravo.waitForExistence(timeout: 5))
        XCTAssertTrue(charlie.waitForExistence(timeout: 5))

        // Select the MIDDLE row, not the last-added one — Charlie (the last
        // row added) is the row the pre-fix bug would wrongly target.
        bravo.click()

        let originalMinX = bravo.frame.minX
        app.typeKey("]", modifierFlags: .command)

        XCTAssertTrue(waitUntil(timeout: 5) { bravo.frame.minX > originalMinX + 15 })
        XCTAssertGreaterThan(
            bravo.frame.minX, originalMinX + 15,
            "⌘] should indent the selected row (Bravo), not the last row"
        )
        // Charlie must be untouched by the indent.
        XCTAssertEqual(charlie.frame.minX, alpha.frame.minX, accuracy: 2)

        app.typeKey("z", modifierFlags: .command)

        XCTAssertTrue(waitUntil(timeout: 5) { abs(bravo.frame.minX - originalMinX) < 5 })
        XCTAssertEqual(
            bravo.frame.minX, originalMinX, accuracy: 5,
            "Undo should restore Bravo's original indent level"
        )
    }

    /// td-2735d9 (Gate E2, plan item 10): structure ops must act on the
    /// whole selection set, not just a single row. Proof: Shift-click
    /// selects Bravo AND Charlie, ⌘] indents BOTH under Alpha in one step,
    /// and ⌘Z restores both to root level in one undo.
    @MainActor func testCommandBracketIndentsMultiSelection() {
        continueAfterFailure = false
        let app = launchApp(store: "mac-command-bracket-multi-indent", reset: true)
        createList(named: "Mac Command Bracket Multi List", in: app)

        addItem(named: "Alpha", in: app)
        addItem(named: "Bravo", in: app)
        addItem(named: "Charlie", in: app)
        app.typeKey(.escape, modifierFlags: [])

        let alpha = app.staticTexts["Alpha"]
        let bravo = app.staticTexts["Bravo"]
        let charlie = app.staticTexts["Charlie"]
        XCTAssertTrue(charlie.waitForExistence(timeout: 5))

        let bravoOriginalMinX = bravo.frame.minX
        let charlieOriginalMinX = charlie.frame.minX

        bravo.click()
        XCUIElement.perform(withKeyModifiers: .shift) { charlie.click() }

        app.typeKey("]", modifierFlags: .command)

        XCTAssertTrue(waitUntil(timeout: 5) { bravo.frame.minX > bravoOriginalMinX + 15 })
        XCTAssertGreaterThan(bravo.frame.minX, bravoOriginalMinX + 15, "⌘] must indent Bravo")
        XCTAssertGreaterThan(charlie.frame.minX, charlieOriginalMinX + 15, "⌘] must indent Charlie too — the whole selection")
        XCTAssertEqual(bravo.frame.minX, charlie.frame.minX, accuracy: 2,
                       "Bravo and Charlie must land at the same depth (both children of Alpha)")
        XCTAssertEqual(alpha.frame.minX, bravoOriginalMinX, accuracy: 2, "Alpha must be untouched")

        app.typeKey("z", modifierFlags: .command)

        XCTAssertTrue(waitUntil(timeout: 5) { abs(bravo.frame.minX - bravoOriginalMinX) < 5 })
        XCTAssertEqual(bravo.frame.minX, bravoOriginalMinX, accuracy: 5,
                       "One undo must restore Bravo to root level")
        XCTAssertEqual(charlie.frame.minX, charlieOriginalMinX, accuracy: 5,
                       "The SAME undo must restore Charlie to root level too")
    }

    /// Gate M1 failure repro (2026-07-14): a multi-selected row must never
    /// lift into a drag — the pre-fix nested `.moveDisabled` was inert, so
    /// the drag lifted with a "2" badge and snapped back.
    @MainActor func testMultiSelectDragDoesNotReorder() {
        continueAfterFailure = false
        let app = launchApp(store: "mac-multidrag-refusal", reset: true)
        createList(named: "Multi Drag List", in: app)
        addItem(named: "Alpha", in: app)
        addItem(named: "Bravo", in: app)
        addItem(named: "Charlie", in: app)
        app.typeKey(.escape, modifierFlags: [])

        let alpha = app.staticTexts["Alpha"]
        let bravo = app.staticTexts["Bravo"]
        XCTAssertTrue(bravo.waitForExistence(timeout: 5))

        alpha.click()
        XCUIElement.perform(withKeyModifiers: .shift) { bravo.click() }

        // Hover arms single-drag; it must NOT arm a multi-selected row.
        bravo.hover()
        let alphaY = alpha.frame.minY
        bravo.click(forDuration: 0.3, thenDragTo: alpha)

        // Order unchanged: Alpha still above Bravo, at the same position.
        XCTAssertTrue(waitUntil(timeout: 3) { abs(alpha.frame.minY - alphaY) < 3 })
        XCTAssertLessThan(alpha.frame.minY, bravo.frame.minY,
                          "A multi-selected row must not drag-reorder")
    }

    /// Gate M1 failure repro (2026-07-14, note #4): Gaylon's flow has NO
    /// Escape — the armed add flow is dismissed by clicking a row directly
    /// (click-away). ⌘] must act on the clicked row, not the last-added one.
    @MainActor func testCommandBracketAfterClickAwayDismissal() {
        continueAfterFailure = false
        let app = launchApp(store: "mac-clickaway-bracket", reset: true)
        createList(named: "Click Away List", in: app)
        addItem(named: "Alpha", in: app)
        addItem(named: "Bravo", in: app)
        addItem(named: "Charlie", in: app)
        // NO Escape here — clicking Bravo IS the dismissal.

        let alpha = app.staticTexts["Alpha"]
        let bravo = app.staticTexts["Bravo"]
        let charlie = app.staticTexts["Charlie"]
        XCTAssertTrue(charlie.waitForExistence(timeout: 5))

        bravo.click()
        let bravoMinX = bravo.frame.minX
        let charlieMinX = charlie.frame.minX
        app.typeKey("]", modifierFlags: .command)

        XCTAssertTrue(waitUntil(timeout: 5) { bravo.frame.minX > bravoMinX + 15 })
        XCTAssertGreaterThan(bravo.frame.minX, bravoMinX + 15,
                             "⌘] after click-away must indent the clicked row (Bravo)")
        XCTAssertEqual(charlie.frame.minX, charlieMinX, accuracy: 2,
                       "⌘] must not touch the last-added row (Charlie)")
        XCTAssertEqual(alpha.frame.minX, charlieMinX, accuracy: 2)
    }

    /// Gate M1 failure repro (2026-07-14): ⇧Tab arrives as backtab (U+0019),
    /// which `.onKeyPress(.tab)` never matched — focus traversal dumped the
    /// user into the sidebar search field instead of outdenting.
    @MainActor func testShiftTabOutdentsSelectedRow() {
        continueAfterFailure = false
        let app = launchApp(store: "mac-shifttab-outdent", reset: true)
        createList(named: "Shift Tab List", in: app)
        addItem(named: "Alpha", in: app)
        addItem(named: "Bravo", in: app)
        app.typeKey(.escape, modifierFlags: [])

        let bravo = app.staticTexts["Bravo"]
        XCTAssertTrue(bravo.waitForExistence(timeout: 5))
        bravo.click()

        let rootMinX = bravo.frame.minX
        app.typeKey("]", modifierFlags: .command)
        if !waitUntil(timeout: 5, condition: { bravo.frame.minX > rootMinX + 15 }) {
            print("DIAG-SHIFTTAB-PREBRACKET \(app.debugDescription)")
        }
        XCTAssertTrue(bravo.frame.minX > rootMinX + 15, "⌘] indent precondition failed")

        app.typeKey(.tab, modifierFlags: .shift)

        XCTAssertTrue(waitUntil(timeout: 5) { abs(bravo.frame.minX - rootMinX) < 5 })
        XCTAssertEqual(bravo.frame.minX, rootMinX, accuracy: 5,
                       "⇧Tab must outdent the selected row, not move focus to search")
    }

    /// M5 Phase 2 (spec §5): the unified editor's checkbox and filter,
    /// replacing the old mode-switch UI test. Checkbox click toggles state
    /// and label (no mode switch needed to reach it); the Remaining filter
    /// hides checked rows; checking off everything remaining lands on the
    /// All Done state; Show All restores the full list.
    @MainActor func testCheckboxAndFilterFlow() {
        continueAfterFailure = false
        let app = launchApp(store: "mac-checkbox-filter", reset: true)
        createList(named: "Mac Checkbox Filter List", in: app)

        addItem(named: "Passport", in: app)
        addItem(named: "Sunscreen", in: app)
        app.typeKey(.escape, modifierFlags: [])

        let passport = app.staticTexts["Passport"]
        let sunscreen = app.staticTexts["Sunscreen"]
        XCTAssertTrue(passport.waitForExistence(timeout: 5))
        XCTAssertTrue(sunscreen.waitForExistence(timeout: 5))

        let checkPassport = app.buttons["Check Passport"]
        XCTAssertTrue(checkPassport.waitForExistence(timeout: 5))
        checkPassport.click()
        XCTAssertTrue(app.buttons["Uncheck Passport"].waitForExistence(timeout: 5))

        // Filter to Remaining: the now-checked Passport row must disappear,
        // Sunscreen (still unchecked) must stay. Use the Phase 3 command so
        // this remains stable when the toolbar collapses controls.
        app.typeKey("2", modifierFlags: [.command, .option])

        XCTAssertFalse(passport.waitForExistence(timeout: 2))
        XCTAssertTrue(sunscreen.waitForExistence(timeout: 5))

        // Check the last remaining row too — the list should empty out into
        // the All Done state.
        let checkSunscreen = app.buttons["Check Sunscreen"]
        XCTAssertTrue(checkSunscreen.waitForExistence(timeout: 5))
        checkSunscreen.click()

        XCTAssertTrue(app.staticTexts["All Done!"].waitForExistence(timeout: 5))

        let showAll = app.buttons["Show All"]
        XCTAssertTrue(showAll.waitForExistence(timeout: 5))
        showAll.click()

        XCTAssertTrue(passport.waitForExistence(timeout: 5))
        XCTAssertTrue(sunscreen.waitForExistence(timeout: 5))
    }

    /// Restored split-version binding (2026-07-20 plan): bare Return with a
    /// selected row arms an add field directly below it — editor-owned, no
    /// menu dispatch — and typing must land immediately.
    @MainActor func testReturnAddsItemBelowSelection() {
        continueAfterFailure = false
        let app = launchApp(store: "mac-return-add-below", reset: true)
        createList(named: "Return Add List", in: app)
        addItem(named: "Anchor", in: app)
        addItem(named: "Tail", in: app)
        app.typeKey(.escape, modifierFlags: [])

        let anchor = app.staticTexts["Anchor"]
        let tail = app.staticTexts["Tail"]
        XCTAssertTrue(tail.waitForExistence(timeout: 5))
        anchor.click()
        app.typeKey(.return, modifierFlags: [])

        let addField = app.textFields["editor.newItem"]
        XCTAssertTrue(addField.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(addField.frame.minY, anchor.frame.minY)
        XCTAssertLessThan(addField.frame.minY, tail.frame.minY,
                          "Return must arm the add field below the selection")
        app.typeText("Return Focus Proof")
        XCTAssertTrue(waitUntil(timeout: 5) { (addField.value as? String) == "Return Focus Proof" },
                      "Return's add field must own keyboard focus")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Return Focus Proof"].waitForExistence(timeout: 5))
    }

    /// Restored split-version binding: Shift-Return inserts a "New Item"
    /// above the selection and drops straight into a focused rename.
    @MainActor func testShiftReturnAddsRenameableItemAbove() {
        continueAfterFailure = false
        let app = launchApp(store: "mac-shift-return-above", reset: true)
        createList(named: "Shift Return List", in: app)
        addItem(named: "Anchor", in: app)
        app.typeKey(.escape, modifierFlags: [])

        let anchor = app.staticTexts["Anchor"]
        XCTAssertTrue(anchor.waitForExistence(timeout: 5))
        anchor.click()
        app.typeKey(.return, modifierFlags: .shift)

        let renameField = app.textFields["editor.renameField"]
        XCTAssertTrue(renameField.waitForExistence(timeout: 5))
        app.typeText("Above Proof")
        XCTAssertTrue(waitUntil(timeout: 5) { ((renameField.value as? String) ?? "").contains("Above Proof") },
                      "Shift-Return's rename field must own keyboard focus")
        app.typeKey(.escape, modifierFlags: [])

        let newItem = app.staticTexts["New Item"]
        XCTAssertTrue(newItem.waitForExistence(timeout: 5),
                      "Escape cancels the rename, leaving the placeholder title")
        XCTAssertLessThan(newItem.frame.minY, anchor.frame.minY,
                          "The inserted item must sit above the selection")
    }

    @MainActor func testCommandERenamesSelectedRow() {
        continueAfterFailure = false
        let app = launchApp(store: "mac-command-e-rename", reset: true)
        createList(named: "Rename List", in: app)
        addItem(named: "Original Title", in: app)
        app.typeKey(.escape, modifierFlags: [])

        let title = app.staticTexts["Original Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.click()
        app.typeKey("e", modifierFlags: .command)

        let renameField = app.textFields["editor.renameField"]
        XCTAssertTrue(renameField.waitForExistence(timeout: 5))
        app.typeText("Rename Focus Proof")
        XCTAssertTrue(waitUntil(timeout: 5) { ((renameField.value as? String) ?? "").contains("Rename Focus Proof") },
                      "Command-E's rename field must own keyboard focus")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(title.waitForExistence(timeout: 5), "Escape must cancel the rename without changing the title")
    }

    /// td-c85e4b (Gate M3, plan item 7): with the selection already empty,
    /// a second Esc used to fall through the editor's `.onKeyPress` (return
    /// `.ignored`) and let AppKit's responder chain carry it up to the
    /// sidebar. Proof: after two Escapes, Down must still move the
    /// EDITOR's selection — if focus had actually left for the sidebar,
    /// this outline row would never become selected.
    @MainActor func testSecondEscapeStaysInEditor() {
        continueAfterFailure = false
        let app = launchApp(store: "mac-second-escape", reset: true)
        createList(named: "Second Escape List", in: app)
        addItem(named: "Alpha", in: app)
        addItem(named: "Bravo", in: app)
        app.typeKey(.escape, modifierFlags: []) // dismiss the still-armed add flow

        let alpha = app.staticTexts["Alpha"]
        XCTAssertTrue(alpha.waitForExistence(timeout: 5))
        alpha.click()
        let alphaRow = app.outlineRows.containing(.staticText, identifier: "Alpha").firstMatch
        XCTAssertTrue(waitUntil(timeout: 5) { alphaRow.isSelected }, "Precondition: Alpha must be selected")

        app.typeKey(.escape, modifierFlags: []) // first Esc: clears the selection
        XCTAssertTrue(waitUntil(timeout: 5) { !alphaRow.isSelected }, "First Esc must clear the selection")

        app.typeKey(.escape, modifierFlags: []) // second Esc: selection already empty — must be consumed here

        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(
            waitUntil(timeout: 5) { alphaRow.isSelected },
            "Down arrow after the second Esc must move the editor's selection — proves focus stayed in the editor, not the sidebar"
        )
    }

    /// Also serves as the Phase 3 Space-delivery gate: bare Space reaches
    /// the focused native List and advances selection under Remaining.
    @MainActor func testSpaceTogglesCheckAndAdvances() {
        continueAfterFailure = false
        let app = launchApp(store: "mac-space-advance", reset: true)
        createList(named: "Space Advance List", in: app)
        for title in ["Alpha", "Bravo", "Charlie"] {
            addItem(named: title, in: app)
        }
        app.typeKey(.escape, modifierFlags: [])

        let alpha = app.staticTexts["Alpha"]
        let bravo = app.staticTexts["Bravo"]
        let charlie = app.staticTexts["Charlie"]
        XCTAssertTrue(charlie.waitForExistence(timeout: 5))
        app.typeKey("2", modifierFlags: [.command, .option])

        alpha.click()
        app.typeKey(.space, modifierFlags: [])
        XCTAssertFalse(alpha.waitForExistence(timeout: 2))
        let bravoRow = app.outlineRows.containing(.staticText, identifier: "Bravo").firstMatch
        XCTAssertTrue(waitUntil(timeout: 5) { bravoRow.isSelected }, "Selection must advance to Bravo")

        app.typeKey(.space, modifierFlags: [])
        XCTAssertFalse(bravo.waitForExistence(timeout: 2))
        let charlieRow = app.outlineRows.containing(.staticText, identifier: "Charlie").firstMatch
        XCTAssertTrue(waitUntil(timeout: 5) { charlieRow.isSelected }, "Selection must advance to Charlie")
    }

    @MainActor func testCommandNArmsAddFieldBelowSelection() {
        continueAfterFailure = false
        let app = launchApp(store: "mac-command-new-item", reset: true)
        createList(named: "Command New Item List", in: app)
        addItem(named: "Anchor", in: app)
        addItem(named: "Tail", in: app)
        app.typeKey(.escape, modifierFlags: [])

        let anchor = app.staticTexts["Anchor"]
        let tail = app.staticTexts["Tail"]
        XCTAssertTrue(tail.waitForExistence(timeout: 5))
        anchor.click()
        app.typeKey("n", modifierFlags: .command)

        let addField = app.textFields["editor.newItem"]
        XCTAssertTrue(addField.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(addField.frame.minY, anchor.frame.minY)
        XCTAssertLessThan(addField.frame.minY, tail.frame.minY,
                          "Command-N must arm the add field below the live selection")
        // td-ff531e: existence is not focus — typing must land in the field.
        app.typeText("Focus Proof")
        XCTAssertTrue(waitUntil(timeout: 5) { (addField.value as? String) == "Focus Proof" },
                      "Command-N's add field must own keyboard focus")
    }

    /// td-ff531e regression: the menu-equivalent path (menu-system key-focus
    /// churn on dismissal) stole the one-hop deferred focus assignment — the
    /// field armed but typing went nowhere.
    @MainActor func testCommandReturnArmsEditableChildField() {
        continueAfterFailure = false
        let app = launchApp(store: "mac-command-return-child", reset: true)
        createList(named: "Command Return List", in: app)
        addItem(named: "Parent", in: app)
        app.typeKey(.escape, modifierFlags: [])

        let parent = app.staticTexts["Parent"]
        XCTAssertTrue(parent.waitForExistence(timeout: 5))
        parent.click()
        app.typeKey(.return, modifierFlags: .command)

        let addField = app.textFields["editor.newItem"]
        XCTAssertTrue(addField.waitForExistence(timeout: 5))
        app.typeText("Child Via Menu")
        XCTAssertTrue(waitUntil(timeout: 5) { (addField.value as? String) == "Child Via Menu" },
                      "Command-Return's child add field must own keyboard focus")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Child Via Menu"].waitForExistence(timeout: 5))
    }

    @MainActor func testCommandKTogglesLiveMultiSelection() {
        continueAfterFailure = false
        let app = launchApp(store: "mac-command-k-multi", reset: true)
        createList(named: "Command K Multi List", in: app)
        for title in ["Alpha", "Bravo", "Charlie"] {
            addItem(named: title, in: app)
        }
        app.typeKey(.escape, modifierFlags: [])

        let alpha = app.staticTexts["Alpha"]
        let bravo = app.staticTexts["Bravo"]
        XCTAssertTrue(bravo.waitForExistence(timeout: 5))
        alpha.click()
        XCUIElement.perform(withKeyModifiers: .shift) { bravo.click() }

        app.typeKey("k", modifierFlags: .command)

        XCTAssertTrue(app.buttons["Uncheck Alpha"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Uncheck Bravo"].waitForExistence(timeout: 5),
                      "Command-K must read and toggle the Shift-extended selection at invocation")
    }

    /// td-0a4af9 (Gate M1, plan item 5): the second Opt-Cmd-L used to hide
    /// the whole app window instead of closing the legend (a parallel
    /// `@State` bool desynced from the legend's actual `NSWindow`
    /// visibility), Esc didn't close it, and focus never returned to the
    /// row that was selected when the legend opened. Proof: toggle
    /// open/close twice — once while the legend itself is key, via a direct
    /// click into it, which is the exact repro for the "hides the whole
    /// app" bug — then reopen and close with Esc, confirming the main
    /// window/editor never disappears and Down still moves the EDITOR's
    /// selection afterward.
    ///
    /// PENDING: cannot run tonight — the macOS UI test runner is
    /// auth-blocked (LocalAuthentication Code -4; Mac idle/locked) per the
    /// td-0a4af9 session log. Verified to compile via
    /// `xcodebuild build-for-testing` for `Listsurf_macOSUITests`; not yet
    /// executed.
    @MainActor func testKeyboardLegendToggleEscapeAndFocus() {
        continueAfterFailure = false
        let app = launchApp(store: "mac-keyboard-legend", reset: true)
        createList(named: "Keyboard Legend List", in: app)
        addItem(named: "Alpha", in: app)
        addItem(named: "Bravo", in: app)
        app.typeKey(.escape, modifierFlags: [])

        let alpha = app.staticTexts["Alpha"]
        XCTAssertTrue(alpha.waitForExistence(timeout: 5))
        alpha.click()

        let legendWindow = app.windows["Keyboard Legend"]

        // Open.
        app.typeKey("l", modifierFlags: [.command, .option])
        XCTAssertTrue(legendWindow.waitForExistence(timeout: 5))

        // Close — legend is NOT key here (opening never steals key status).
        app.typeKey("l", modifierFlags: [.command, .option])
        XCTAssertFalse(legendWindow.waitForExistence(timeout: 2))
        XCTAssertTrue(alpha.waitForExistence(timeout: 5),
                      "The main window/editor must still exist and be visible")

        // Reopen, then click INTO the legend to make it the key window.
        app.typeKey("l", modifierFlags: [.command, .option])
        XCTAssertTrue(legendWindow.waitForExistence(timeout: 5))
        var legendRow = legendWindow.staticTexts["New Item"]
        XCTAssertTrue(legendRow.waitForExistence(timeout: 5))
        legendRow.click()

        // Close while the legend IS key — the exact repro for the
        // "second Opt-Cmd-L hides the whole app" bug.
        app.typeKey("l", modifierFlags: [.command, .option])
        XCTAssertFalse(legendWindow.waitForExistence(timeout: 2))
        XCTAssertTrue(alpha.waitForExistence(timeout: 5),
                      "The app window must never hide when closing a key legend")

        // Reopen, make it key again, close via Esc this time.
        app.typeKey("l", modifierFlags: [.command, .option])
        XCTAssertTrue(legendWindow.waitForExistence(timeout: 5))
        legendRow = legendWindow.staticTexts["New Item"]
        XCTAssertTrue(legendRow.waitForExistence(timeout: 5))
        legendRow.click()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(legendWindow.waitForExistence(timeout: 2), "Esc must close the legend")

        // Focus restore: Down must move the EDITOR's selection, proving key
        // window/focus returned to the row selected before the legend
        // opened (Alpha) — not stranded on a closed window or the sidebar.
        let alphaRow = app.outlineRows.containing(.staticText, identifier: "Alpha").firstMatch
        XCTAssertTrue(waitUntil(timeout: 5) { alphaRow.isSelected },
                      "Precondition: Alpha must still be selected after the legend closes")
        app.typeKey(.downArrow, modifierFlags: [])
        let bravoRow = app.outlineRows.containing(.staticText, identifier: "Bravo").firstMatch
        XCTAssertTrue(
            waitUntil(timeout: 5) { bravoRow.isSelected && !alphaRow.isSelected },
            "Down after the legend closes must move the editor's selection — proves focus returned to the editor"
        )
    }

    @MainActor func testInspectorNotesEditorIsBounded() {
        continueAfterFailure = false
        let app = launchApp(store: "mac-bounded-notes", reset: true)
        createList(named: "Mac Bounded Notes", in: app)
        addItem(named: "Noted Item", in: app)
        app.typeKey(.escape, modifierFlags: [])

        let item = app.staticTexts["Noted Item"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.click()
        app.typeKey("i", modifierFlags: [.command, .option])

        let notes = app.textViews["inspector.itemNotes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
        let initialHeight = notes.frame.height
        XCTAssertGreaterThanOrEqual(initialHeight, 50)
        XCTAssertLessThanOrEqual(initialHeight, 130)
        notes.click()
        notes.typeText((1...12).map { "Line \($0)" }.joined(separator: "\n"))
        XCTAssertEqual(notes.frame.height, initialHeight, accuracy: 2,
                       "Long notes must scroll internally instead of expanding the inspector")
    }

    /// td-2bc3a8 (Gate M4/E3, plan item 8): ⌘O (Edit Notes) must open the
    /// inspector AND land keyboard focus in the Notes editor in one step —
    /// no manual click required — and closing the inspector via ⌥⌘I must
    /// return focus to the outline, not the sidebar. Proof for the close
    /// half uses the same idiom as `testDeleteAdvancesSelectionAndStaysInEditor`
    /// and `testSecondEscapeStaysInEditor`: Down must still move the
    /// EDITOR's selection afterward.
    ///
    /// PENDING: cannot run tonight — the macOS UI test runner is
    /// auth-blocked (LocalAuthentication Code -4; Mac idle/locked).
    /// Verified to compile via `xcodebuild build-for-testing` for
    /// `Listsurf_macOSUITests`; not yet executed.
    @MainActor func testEditNotesFocusesInspectorAndClosingRestoresEditorFocus() {
        continueAfterFailure = false
        let app = launchApp(store: "mac-edit-notes", reset: true)
        createList(named: "Edit Notes List", in: app)
        addItem(named: "Alpha", in: app)
        addItem(named: "Bravo", in: app)
        app.typeKey(.escape, modifierFlags: [])

        let alpha = app.staticTexts["Alpha"]
        XCTAssertTrue(alpha.waitForExistence(timeout: 5))
        alpha.click()

        app.typeKey("o", modifierFlags: .command)

        let notes = app.textViews["inspector.itemNotes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
        app.typeText("Edit Notes Focus Proof")
        XCTAssertTrue(
            waitUntil(timeout: 5) { ((notes.value as? String) ?? "").contains("Edit Notes Focus Proof") },
            "⌘O must land keyboard focus directly in the Notes editor — no manual click required"
        )

        app.typeKey("i", modifierFlags: [.command, .option])
        XCTAssertFalse(notes.waitForExistence(timeout: 2), "⌥⌘I must close the inspector")

        let alphaRow = app.outlineRows.containing(.staticText, identifier: "Alpha").firstMatch
        XCTAssertTrue(waitUntil(timeout: 5) { alphaRow.isSelected },
                      "Alpha must still be the selected row after the inspector closes")
        app.typeKey(.downArrow, modifierFlags: [])
        let bravoRow = app.outlineRows.containing(.staticText, identifier: "Bravo").firstMatch
        XCTAssertTrue(
            waitUntil(timeout: 5) { bravoRow.isSelected && !alphaRow.isSelected },
            "Down after the inspector closes must move the editor's selection — proves focus returned to the outline, not the sidebar"
        )
    }

    /// Polls `condition` until it's true or `timeout` elapses. Row-reorder
    /// geometry only settles after SwiftUI's drop/undo animation completes,
    /// so a single frame read right after the gesture can race the layout.
    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

    @MainActor private func launchApp(store: String, reset: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LISTSURF_UI_TEST_STORE"] = store
        app.launchArguments = reset ? ["--ui-testing-reset"] : []
        app.launch()
        app.activate()
        return app
    }

    @MainActor private func relaunch(_ app: XCUIApplication, reset: Bool) {
        app.launchArguments = reset ? ["--ui-testing-reset"] : []
        app.launch()
        app.activate()
    }

    @MainActor private func createList(named title: String, in app: XCUIApplication) {
        let newList = firstExisting(
            app.buttons["library.newList"],
            app.buttons["library.createFirstList"]
        )
        XCTAssertTrue(newList.waitForExistence(timeout: 15))
        app.activate()
        newList.click()
        fillNewListSheet(named: title, in: app)
        let editor = firstExisting(
            app.buttons["editor.addFirstItem"],
            app.buttons["editor.addItem"]
        )
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
    }

    @MainActor private func addItem(named title: String, in app: XCUIApplication) {
        let addItem = firstExisting(
            app.buttons["editor.addFirstItem"],
            app.buttons["editor.addItem"]
        )
        XCTAssertTrue(addItem.waitForExistence(timeout: 5))
        addItem.click()

        let itemField = firstExisting(
            app.textFields["editor.newItem"],
            app.textFields["New item"],
            app.textFields.firstMatch
        )
        XCTAssertTrue(itemField.waitForExistence(timeout: 5))
        itemField.click()
        itemField.typeText("\(title)\n")
    }

    /// No existing helper armed a child-add field (td-5d405a needed one):
    /// macOS has no dedicated "Add Child" button — ⌘Return (`CommandCatalog
    /// .addChild`) arms the field, mirroring `testCommandReturnArmsEditableChildField`.
    /// Requires the intended parent row to already be selected/clicked.
    @MainActor private func addChildItem(named title: String, in app: XCUIApplication) {
        app.typeKey(.return, modifierFlags: .command)
        let addField = app.textFields["editor.newItem"]
        XCTAssertTrue(addField.waitForExistence(timeout: 5))
        addField.typeText("\(title)\n")
    }

    @MainActor private func fillNewListSheet(named title: String, in app: XCUIApplication) {
        let titleField = firstExisting(
            app.textFields["newList.title"],
            app.textFields["List name"],
            app.alerts.textFields.firstMatch
        )
        if !titleField.waitForExistence(timeout: 5) {
            // macOS can drop the first toolbar click while the newly launched
            // window is still becoming key. Retry through the empty-state
            // action (or toolbar fallback) after reactivation.
            app.activate()
            let retry = firstExisting(
                app.buttons["library.createFirstList"],
                app.buttons["library.newList"]
            )
            if retry.exists { retry.click() }
        }
        if !titleField.waitForExistence(timeout: 5) {
            app.activate()
            app.typeKey("n", modifierFlags: [.command, .shift])
        }
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.click()
        titleField.typeText(title)

        let create = firstExisting(
            app.buttons["newList.create"].firstMatch,
            app.buttons["Create"].firstMatch
        )
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.click()
    }

    @MainActor private func firstExisting(_ elements: XCUIElement...) -> XCUIElement {
        elements.first(where: \.exists) ?? elements[0]
    }

    // MARK: - CODEX2 2026-07-26 review: stranded add/rename drafts (finding 1)

    /// Finding 1b: `store.beginEditing` (invoked here via the row-ellipsis
    /// menu's Rename action on a DIFFERENT row) nils `addPlacement` directly
    /// to enforce add/rename exclusivity, bypassing this view's own
    /// `cancelAdding`/`dismissPendingAdd` — the only paths that used to
    /// commit or discard the typed draft. Before the fix, the typed text
    /// was silently lost.
    @MainActor func testStrandedAddDraftCommitsWhenAnotherRowIsRenamedViaMenu() {
        continueAfterFailure = false
        let app = launchApp(store: "mac-stranded-add-draft", reset: true)
        createList(named: "Stranded Add List", in: app)
        addItem(named: "Alpha", in: app)
        addItem(named: "Bravo", in: app)
        app.typeKey(.escape, modifierFlags: [])

        let alpha = app.staticTexts["Alpha"]
        XCTAssertTrue(alpha.waitForExistence(timeout: 5))
        alpha.click()
        app.typeKey(.return, modifierFlags: [])

        let addField = app.textFields["editor.newItem"]
        XCTAssertTrue(addField.waitForExistence(timeout: 5))
        app.typeText("Draft Text")
        XCTAssertTrue(waitUntil(timeout: 5) { (addField.value as? String) == "Draft Text" },
                      "Precondition: the add field owns focus and has the typed draft")

        let bravoRow = app.outlineRows.containing(.staticText, identifier: "Bravo").firstMatch
        XCTAssertTrue(bravoRow.waitForExistence(timeout: 5))
        bravoRow.menuButtons["editor.rowActions"].firstMatch.click()
        // "Rename" by TITLE is ambiguous — the app's main menu bar exposes
        // the identically-titled Command-E command too (ListsurfCommands),
        // and XCUITest's click() traversal for a MenuItem it resolves to
        // the menu bar tries to open that top-level menu, colliding with
        // the popup already open ("open menu during menu traversal"
        // failure). The popup's item carries a distinct IDENTIFIER derived
        // from its systemImage ("pencil"; see CommandCatalog.rename) that
        // the menu-bar equivalent does not, so identifier lookup is
        // unambiguous.
        app.menuItems["pencil"].firstMatch.click()

        XCTAssertTrue(
            app.staticTexts["Draft Text"].waitForExistence(timeout: 5),
            "The typed add draft must be committed as a final item, not silently lost, when Rename (from another row's menu) ends the add flow externally"
        )
        let renameField = app.textFields["editor.renameField"]
        XCTAssertTrue(renameField.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitUntil(timeout: 5) { ((renameField.value as? String) ?? "").contains("Bravo") },
            "Bravo must now be the row being renamed"
        )
    }

    /// Finding 1a: the same `store.beginEditing` exclusivity switch also
    /// applies when a RENAME is already in progress and Rename is picked on
    /// another row — `editingItemID` transitions old-item→new-item directly,
    /// so the outgoing draft must be committed before the field reseeds for
    /// the new target, or it is silently overwritten.
    @MainActor func testOutgoingRenameDraftCommitsWhenAnotherRowIsRenamedViaMenu() {
        continueAfterFailure = false
        let app = launchApp(store: "mac-stranded-rename-draft", reset: true)
        createList(named: "Stranded Rename List", in: app)
        addItem(named: "Alpha", in: app)
        addItem(named: "Bravo", in: app)
        app.typeKey(.escape, modifierFlags: [])

        let alpha = app.staticTexts["Alpha"]
        XCTAssertTrue(alpha.waitForExistence(timeout: 5))
        alpha.click()
        app.typeKey("e", modifierFlags: .command)

        let renameFieldA = app.textFields["editor.renameField"]
        XCTAssertTrue(renameFieldA.waitForExistence(timeout: 5))
        // Replace the seeded "Alpha" rather than appending, so the resulting
        // title is deterministic regardless of default cursor placement.
        app.typeKey("a", modifierFlags: .command)
        app.typeText("Alpha Renamed")
        XCTAssertTrue(waitUntil(timeout: 5) { (renameFieldA.value as? String) == "Alpha Renamed" },
                      "Precondition: Alpha's rename field owns focus and has the typed draft")

        let bravoRow = app.outlineRows.containing(.staticText, identifier: "Bravo").firstMatch
        XCTAssertTrue(bravoRow.waitForExistence(timeout: 5))
        bravoRow.menuButtons["editor.rowActions"].firstMatch.click()
        // "Rename" by TITLE is ambiguous — the app's main menu bar exposes
        // the identically-titled Command-E command too (ListsurfCommands),
        // and XCUITest's click() traversal for a MenuItem it resolves to
        // the menu bar tries to open that top-level menu, colliding with
        // the popup already open ("open menu during menu traversal"
        // failure). The popup's item carries a distinct IDENTIFIER derived
        // from its systemImage ("pencil"; see CommandCatalog.rename) that
        // the menu-bar equivalent does not, so identifier lookup is
        // unambiguous.
        app.menuItems["pencil"].firstMatch.click()

        XCTAssertTrue(
            app.staticTexts["Alpha Renamed"].waitForExistence(timeout: 5),
            "The outgoing rename draft must be committed, not overwritten, when Rename starts on another row"
        )
        let renameFieldB = app.textFields["editor.renameField"]
        XCTAssertTrue(renameFieldB.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitUntil(timeout: 5) { ((renameFieldB.value as? String) ?? "").contains("Bravo") },
            "Bravo must now be the row being renamed"
        )
    }

    /// Finding 1c (mirror image of 1a/1b): starting an add elsewhere while a
    /// rename is in progress drives `editingItemID` old→nil directly via
    /// `store.beginAdding` — this lands in the PRE-EXISTING stranded-rename-
    /// commit branch (unchanged by the 1a/1b fix). Confirms that branch
    /// still fires correctly.
    @MainActor func testBeginningAddElsewhereCommitsStrandedRenameDraft() {
        continueAfterFailure = false
        let app = launchApp(store: "mac-mirror-stranded-rename", reset: true)
        createList(named: "Mirror Stranded Rename List", in: app)
        addItem(named: "Alpha", in: app)
        addItem(named: "Bravo", in: app)
        app.typeKey(.escape, modifierFlags: [])

        let alpha = app.staticTexts["Alpha"]
        XCTAssertTrue(alpha.waitForExistence(timeout: 5))
        alpha.click()
        app.typeKey("e", modifierFlags: .command)

        let renameFieldA = app.textFields["editor.renameField"]
        XCTAssertTrue(renameFieldA.waitForExistence(timeout: 5))
        app.typeKey("a", modifierFlags: .command)
        app.typeText("Alpha Renamed")
        XCTAssertTrue(waitUntil(timeout: 5) { (renameFieldA.value as? String) == "Alpha Renamed" },
                      "Precondition: Alpha's rename field owns focus and has the typed draft")

        let bravoRow = app.outlineRows.containing(.staticText, identifier: "Bravo").firstMatch
        XCTAssertTrue(bravoRow.waitForExistence(timeout: 5))
        bravoRow.menuButtons["editor.rowActions"].firstMatch.click()
        // Same menu-bar-collision reasoning as the Rename lookups above:
        // identifier "plus" (CommandCatalog.newItem's systemImage) is
        // unique to the popup's "New Item" entry.
        app.menuItems["plus"].firstMatch.click()

        XCTAssertTrue(
            app.staticTexts["Alpha Renamed"].waitForExistence(timeout: 5),
            "Starting an add elsewhere must still commit the stranded rename draft via the pre-existing branch"
        )
        XCTAssertTrue(
            app.textFields["editor.newItem"].waitForExistence(timeout: 5),
            "The add field must now be armed below Bravo"
        )
    }

    // MARK: - CODEX2 2026-07-26 review: inspector stale draft on external change (finding 3)

    /// Finding 3: `NotesEditor` only seeds `draft`/`lastCommitted` in
    /// `init`, which does not re-run for a same-item external change (the
    /// call site's `.id(item.id)` only tears the view down when the ITEM
    /// changes). An undo landing while the inspector is open on the SAME
    /// item used to leave the displayed notes stale, and the next commit
    /// would silently re-write the undone value right back.
    @MainActor func testInspectorNotesReseedsOnUndoAndDoesNotResurrectOverwrittenValue() {
        continueAfterFailure = false
        let app = launchApp(store: "mac-notes-undo-reseed", reset: true)
        createList(named: "Notes Undo Reseed List", in: app)
        addItem(named: "Alpha", in: app)
        app.typeKey(.escape, modifierFlags: [])

        // Scoped to the outline row: once the inspector is open it ALSO
        // shows "Alpha" as the Title LabeledContent's value, so an
        // unscoped `app.staticTexts["Alpha"]` becomes ambiguous.
        let alpha = app.outlineRows.staticTexts["Alpha"]
        XCTAssertTrue(alpha.waitForExistence(timeout: 5))
        alpha.click()
        app.typeKey("o", modifierFlags: .command)

        let notes = app.textViews["inspector.itemNotes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
        notes.typeText("Original Notes")
        XCTAssertTrue(waitUntil(timeout: 5) { ((notes.value as? String) ?? "").contains("Original Notes") },
                      "Precondition: the notes editor owns focus and has the typed draft")

        // Click away to commit (focus loss), Finder-style — mirrors
        // OutlineEditorView's click-away rename commit.
        alpha.click()
        XCTAssertTrue(
            waitUntil(timeout: 5) { (notes.value as? String) == "Original Notes" },
            "Precondition: the notes commit landed"
        )

        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(
            waitUntil(timeout: 5) { ((notes.value as? String) ?? "").isEmpty || (notes.value as? String) == "Add notes..." },
            "Undo (landing while the inspector is open, not focused) must refresh the stale draft — the field must show the undone (empty) value, not the stale committed text"
        )

        app.typeKey("o", modifierFlags: .command)
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
        notes.typeText("New Notes After Undo")
        alpha.click()

        XCTAssertTrue(
            waitUntil(timeout: 5) { (notes.value as? String) == "New Notes After Undo" },
            "Typing fresh notes after the undo-reseed must commit the NEW text"
        )
        XCTAssertFalse(
            (notes.value as? String)?.contains("Original Notes") ?? false,
            "The pre-undo overwritten value must never resurface"
        )
    }
}
