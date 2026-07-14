import XCTest

final class Listsurf_iOSUITests: XCTestCase {
    @MainActor func testCreateListAddItemAndCheckIt() {
        continueAfterFailure = false
        let app = launchApp(store: "ios-create-list", reset: true)
        createList(named: "UI Packing List", in: app)

        let addItem = firstExisting(
            app.buttons["editor.addFirstItem"],
            app.buttons["editor.addItem"]
        )
        XCTAssertTrue(addItem.waitForExistence(timeout: 5))
        addItem.tap()

        let itemField = app.textFields["editor.newItem"]
        XCTAssertTrue(itemField.waitForExistence(timeout: 5))
        itemField.typeText("Passport\n")
        XCTAssertTrue(app.staticTexts["Passport"].waitForExistence(timeout: 5))

        let modeButton = app.buttons["detail.toggleMode"]
        XCTAssertTrue(modeButton.waitForExistence(timeout: 5))
        modeButton.tap()

        let checkButton = app.buttons["Check Passport"]
        XCTAssertTrue(checkButton.waitForExistence(timeout: 5))
        checkButton.tap()
        XCTAssertTrue(app.buttons["Uncheck Passport"].waitForExistence(timeout: 5))
    }

    @MainActor func testListPersistsAcrossRelaunch() {
        continueAfterFailure = false
        let app = launchApp(store: "ios-persistence", reset: true)
        createList(named: "Persistent UI List", in: app)
        app.terminate()
        relaunch(app, reset: false)

        XCTAssertTrue(app.staticTexts["Persistent UI List"].waitForExistence(timeout: 5))
    }

    @MainActor func testDragReordersSiblings() {
        continueAfterFailure = false
        let app = launchApp(store: "ios-drag-reorder", reset: true)
        createList(named: "Drag Reorder List", in: app)

        // One tap arms the add flow; each "\n" commits and keeps the field
        // armed below the new item, so three items need no further buttons.
        let addItem = firstExisting(
            app.buttons["editor.addFirstItem"],
            app.buttons["editor.addItem"]
        )
        XCTAssertTrue(addItem.waitForExistence(timeout: 5))
        addItem.tap()
        // Each "\n" commits and RECREATES the field below the new item, so
        // the element reference must be re-resolved per line.
        for title in ["Alpha", "Bravo", "Charlie"] {
            let itemField = app.textFields["editor.newItem"]
            XCTAssertTrue(itemField.waitForExistence(timeout: 5))
            itemField.tap()   // the recreated field's focus re-grab can race the test
            itemField.typeText("\(title)\n")
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5))
        }
        // Dismiss the continuing add field so drag isn't disabled by the
        // text-entry guard (.moveDisabled while isTextInputActive). Tapping a
        // row is the click-away dismissal and doesn't depend on the keyboard
        // accessory being visible.
        app.staticTexts["Alpha"].tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))

        let alpha = app.staticTexts["Alpha"]
        let bravo = app.staticTexts["Bravo"]
        let charlie = app.staticTexts["Charlie"]
        XCTAssertTrue(charlie.waitForExistence(timeout: 5))
        XCTAssertLessThan(alpha.frame.minY, bravo.frame.minY)
        XCTAssertLessThan(bravo.frame.minY, charlie.frame.minY)

        // Short press: rows also carry a context menu, and a stationary hold
        // ≥0.5s opens it instead of lifting the row for reorder. Slow drag +
        // destination hold lets the reorder interaction track the move.
        charlie.press(
            forDuration: 0.6,
            thenDragTo: alpha,
            withVelocity: .slow,
            thenHoldForDuration: 0.5
        )

        XCTAssertTrue(waitUntil(timeout: 5) { charlie.frame.minY < bravo.frame.minY })
        XCTAssertLessThan(charlie.frame.minY, bravo.frame.minY, "Charlie should have moved above Bravo")
    }

    /// Polls `condition` until true or timeout — reorder geometry settles
    /// only after the drop animation completes.
    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

    /// Phase 1 focus promise (Gate M1 iOS finding, 2026-07-14: on hardware
    /// the add field appeared WITHOUT the keyboard). The store-driven
    /// EditorFocus must focus the add field on its own — this test types
    /// immediately with NO tap-the-field workaround. If this fails, the
    /// task-deferred focus is losing and the spec's escalation rule applies.
    @MainActor func testAddFieldReceivesFocusWithoutTap() {
        continueAfterFailure = false
        let app = launchApp(store: "ios-addfocus", reset: true)
        createList(named: "Focus List", in: app)

        let addItem = firstExisting(
            app.buttons["editor.addFirstItem"],
            app.buttons["editor.addItem"]
        )
        XCTAssertTrue(addItem.waitForExistence(timeout: 5))
        addItem.tap()

        let itemField = app.textFields["editor.newItem"]
        XCTAssertTrue(itemField.waitForExistence(timeout: 5))
        // Deliberately NO itemField.tap() — typeText requires keyboard
        // focus, so this fails loudly if the focus architecture loses.
        itemField.typeText("Untapped\n")
        XCTAssertTrue(app.staticTexts["Untapped"].waitForExistence(timeout: 5))
    }

    @MainActor func testCoreActionsAreVisible() {
        continueAfterFailure = false
        let app = launchApp(store: "ios-visible-actions", reset: true)

        XCTAssertTrue(app.buttons["library.importBackup.visible"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["library.exportBackup.visible"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["library.archive.visible"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["library.help.visible"].waitForExistence(timeout: 5))

        createList(named: "Visible Actions List", in: app)
        addItem(named: "Indentable Item", in: app)

        XCTAssertTrue(app.buttons["editor.rowActions"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["editor.deleteItem"].firstMatch.waitForExistence(timeout: 5))

        let item = app.staticTexts["Indentable Item"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()

        XCTAssertTrue(app.buttons["editor.ios.addChild"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["editor.ios.indent"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["editor.ios.outdent"].waitForExistence(timeout: 5))

        app.buttons["editor.ios.addChild"].tap()
        let childField = app.textFields["editor.newItem"]
        XCTAssertTrue(childField.waitForExistence(timeout: 5))
        childField.typeText("Child Item\n")
        XCTAssertTrue(app.staticTexts["Child Item"].waitForExistence(timeout: 5))
    }

    @MainActor func testHelpOpensFromLibrary() {
        continueAfterFailure = false
        let app = launchApp(store: "ios-help", reset: true)

        let help = firstExisting(
            app.buttons["library.help.visible"],
            app.buttons["library.help.empty"]
        )
        XCTAssertTrue(help.waitForExistence(timeout: 5))
        help.tap()

        XCTAssertTrue(app.staticTexts["Listsurf Help"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Start here"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["iPhone and iPad touch controls"].waitForExistence(timeout: 5))
        app.buttons["help.done"].tap()
        XCTAssertFalse(app.staticTexts["Listsurf Help"].waitForExistence(timeout: 2))
    }

    @MainActor private func launchApp(store: String, reset: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LISTSURF_UI_TEST_STORE"] = store
        app.launchArguments = reset ? ["--ui-testing-reset"] : []
        app.launch()
        return app
    }

    @MainActor private func relaunch(_ app: XCUIApplication, reset: Bool) {
        app.launchArguments = reset ? ["--ui-testing-reset"] : []
        app.launch()
    }

    @MainActor private func createList(named title: String, in app: XCUIApplication) {
        let newList = firstExisting(
            app.buttons["library.newList"],
            app.buttons["library.createFirstList"]
        )
        XCTAssertTrue(newList.waitForExistence(timeout: 5))
        newList.tap()

        let titleField = firstExisting(
            app.textFields["newList.title"],
            app.textFields["List name"],
            app.alerts.textFields.firstMatch
        )
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("\(title)\n")

        let editor = firstExisting(
            app.buttons["editor.addFirstItem"],
            app.buttons["editor.addItem"]
        )
        if !editor.waitForExistence(timeout: 2) {
            let create = firstExisting(
                app.buttons["newList.create"].firstMatch,
                app.buttons["Create"].firstMatch
            )
            XCTAssertTrue(create.waitForExistence(timeout: 5))
            create.tap()
        }
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
    }

    @MainActor private func addItem(named title: String, in app: XCUIApplication) {
        let addItem = firstExisting(
            app.buttons["editor.addFirstItem"],
            app.buttons["editor.addItem"]
        )
        XCTAssertTrue(addItem.waitForExistence(timeout: 5))
        addItem.tap()

        let itemField = app.textFields["editor.newItem"]
        XCTAssertTrue(itemField.waitForExistence(timeout: 5))
        itemField.typeText("\(title)\n")
    }

    @MainActor private func firstExisting(_ elements: XCUIElement...) -> XCUIElement {
        elements.first(where: \.exists) ?? elements[0]
    }
}
