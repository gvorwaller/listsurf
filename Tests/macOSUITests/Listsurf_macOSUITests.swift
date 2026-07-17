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

    @MainActor func testListPersistsAcrossRelaunch() {
        continueAfterFailure = false
        let app = launchApp(store: "mac-persistence", reset: true)
        createList(named: "Persistent Mac List", in: app)
        app.terminate()
        relaunch(app, reset: false)

        XCTAssertTrue(app.staticTexts["Persistent Mac List"].waitForExistence(timeout: 5))
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

    @MainActor func testReturnRenamesSelectedRow() {
        continueAfterFailure = false
        let app = launchApp(store: "mac-return-rename", reset: true)
        createList(named: "Return Rename List", in: app)
        addItem(named: "Original Title", in: app)
        app.typeKey(.escape, modifierFlags: [])

        let title = app.staticTexts["Original Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.click()
        app.typeKey(.return, modifierFlags: [])

        let renameField = app.textFields["editor.renameField"]
        XCTAssertTrue(renameField.waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(title.waitForExistence(timeout: 5), "Escape must cancel Return rename without changing the title")

        title.click()
        app.typeKey("e", modifierFlags: .command)
        XCTAssertTrue(renameField.waitForExistence(timeout: 5), "Command-E must use the same inline rename path")
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
}
