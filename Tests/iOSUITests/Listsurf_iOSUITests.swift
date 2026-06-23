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

    @MainActor func testCoreActionsAreVisible() {
        continueAfterFailure = false
        let app = launchApp(store: "ios-visible-actions", reset: true)

        XCTAssertTrue(app.buttons["library.importBackup.visible"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["library.exportBackup.visible"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["library.archive.visible"].waitForExistence(timeout: 5))

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
        titleField.typeText(title)

        let create = firstExisting(
            app.buttons["newList.create"].firstMatch,
            app.buttons["Create"].firstMatch
        )
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()
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
        addItem.tap()

        let itemField = app.textFields["editor.newItem"]
        XCTAssertTrue(itemField.waitForExistence(timeout: 5))
        itemField.typeText("\(title)\n")
    }

    @MainActor private func firstExisting(_ elements: XCUIElement...) -> XCUIElement {
        elements.first(where: \.exists) ?? elements[0]
    }
}
