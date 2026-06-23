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

        createList(named: "Visible Mac Actions List", in: app)
        addItem(named: "Indentable Mac Item", in: app)

        let rowActions = firstExisting(
            app.buttons["editor.rowActions"].firstMatch,
            app.menuButtons["editor.rowActions"].firstMatch
        )
        XCTAssertTrue(rowActions.waitForExistence(timeout: 5))
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
        XCTAssertTrue(newList.waitForExistence(timeout: 15))
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
