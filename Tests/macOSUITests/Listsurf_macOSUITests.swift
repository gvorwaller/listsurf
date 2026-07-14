import XCTest

final class Listsurf_macOSUITests: XCTestCase {
    @MainActor func testCommandNOpensNewListSheet() {
        continueAfterFailure = false
        let app = launchApp(store: "mac-command-new-list", reset: true)

        app.typeKey("n", modifierFlags: .command)
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
