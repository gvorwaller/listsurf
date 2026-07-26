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
        let passport = app.staticTexts["Passport"]
        XCTAssertTrue(passport.waitForExistence(timeout: 5))

        // Committing with Return re-arms the add flow; tapping the row is
        // the click-away dismissal (same pattern as the drag tests) before
        // the checkbox button can be reached directly.
        passport.tap()

        let checkButton = app.buttons["Check Passport"]
        XCTAssertTrue(checkButton.waitForExistence(timeout: 5))
        checkButton.tap()
        XCTAssertTrue(app.buttons["Uncheck Passport"].waitForExistence(timeout: 5))
    }

    /// Rev 2.5 (td-ee5174): double-tap a row opens Details without delaying
    /// single-tap selection. Verifies both halves of that contract in one
    /// pass — a lone tap must show the action bar promptly, and a fast
    /// second tap must open the inspector sheet.
    @MainActor func testDoubleTapOpensDetails() {
        continueAfterFailure = false
        let app = launchApp(store: "ios-double-tap-details", reset: true)
        createList(named: "Double Tap List", in: app)
        addItem(named: "Passport", in: app)

        let passport = app.staticTexts["Passport"]
        XCTAssertTrue(passport.waitForExistence(timeout: 5))

        // Single tap: selection (and the action bar it drives) must appear
        // promptly — not gated behind a double-tap-failure timeout.
        passport.tap()
        XCTAssertTrue(app.buttons["editor.ios.details"].waitForExistence(timeout: 1.5))

        // Double tap: opens Details directly. iOS shows an editable title
        // field in place of macOS's Rename button (td-9537dc).
        passport.doubleTap()
        XCTAssertTrue(app.textFields["inspector.itemTitle"].waitForExistence(timeout: 5))
    }

    /// td-9537dc (Gate I1a, plan item 4): the old Rename button armed the
    /// inline row rename BEHIND the Details sheet, so nothing visibly
    /// happened. The sheet's title field must rename the row directly.
    @MainActor func testDetailsSheetTitleFieldRenamesRow() {
        continueAfterFailure = false
        let app = launchApp(store: "ios-details-rename", reset: true)
        createList(named: "Details Rename List", in: app)
        addItem(named: "Passport", in: app)

        let passport = app.staticTexts["Passport"]
        XCTAssertTrue(passport.waitForExistence(timeout: 5))
        passport.doubleTap()

        let titleField = app.textFields["inspector.itemTitle"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()

        // Clear the existing text, then type the new title.
        if let currentValue = titleField.value as? String, !currentValue.isEmpty {
            let deleteAll = String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count)
            titleField.typeText(deleteAll)
        }
        titleField.typeText("Boarding Pass")

        // The sheet auto-expands to its large detent while the keyboard is
        // up (no dimmed backdrop remains to tap), so dismiss it with a drag
        // from the grabber instead — this exercises the onDisappear commit
        // path (as opposed to onSubmit).
        let grabber = app.buttons["Sheet Grabber"]
        XCTAssertTrue(grabber.waitForExistence(timeout: 5))
        let grabberStart = grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let dismissTarget = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        grabberStart.press(forDuration: 0.05, thenDragTo: dismissTarget)

        XCTAssertFalse(app.staticTexts["Passport"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Boarding Pass"].waitForExistence(timeout: 5))
    }

    /// td-8982f7 (Gate I2, plan item 2): the Remaining/Completed/All filter
    /// must be reachable directly on iPhone, NOT behind the ••• overflow
    /// menu that .secondaryAction collapses into.
    @MainActor func testFilterMenuReachableWithoutOverflow() {
        continueAfterFailure = false
        let app = launchApp(store: "ios-filter-menu", reset: true)
        createList(named: "Filter Menu List", in: app)
        addItem(named: "Passport", in: app)

        let passport = app.staticTexts["Passport"]
        XCTAssertTrue(passport.waitForExistence(timeout: 5))
        passport.tap() // dismiss the continuation field, select the row

        let checkButton = app.buttons["Check Passport"]
        XCTAssertTrue(checkButton.waitForExistence(timeout: 5))
        checkButton.tap()
        XCTAssertTrue(app.buttons["Uncheck Passport"].waitForExistence(timeout: 5))

        // Reachable directly — no "More"/overflow tap in this path.
        let filterMenu = app.buttons["editor.filterMenu"]
        XCTAssertTrue(filterMenu.waitForExistence(timeout: 5))
        filterMenu.tap()

        let remaining = app.buttons["Remaining"]
        XCTAssertTrue(remaining.waitForExistence(timeout: 5))
        remaining.tap()
        XCTAssertFalse(passport.waitForExistence(timeout: 2), "Checked item must hide under the Remaining filter")

        filterMenu.tap()
        let all = app.buttons["All"]
        XCTAssertTrue(all.waitForExistence(timeout: 5))
        all.tap()
        XCTAssertTrue(passport.waitForExistence(timeout: 5), "All filter must bring the item back")
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

    /// M4 Stage 1 contract (spec D2): a drag can NEVER re-parent — a drop
    /// across a parent boundary clamps to the item's own sibling group.
    /// Gaylon reported an apparent re-parent via drag on hardware
    /// (2026-07-14); this asserts the clamp holds under the same gesture.
    @MainActor func testDragAcrossParentBoundaryDoesNotReparent() {
        continueAfterFailure = false
        let app = launchApp(store: "ios-drag-clamp", reset: true)
        createList(named: "Clamp List", in: app)

        let addItem = firstExisting(
            app.buttons["editor.addFirstItem"],
            app.buttons["editor.addItem"]
        )
        XCTAssertTrue(addItem.waitForExistence(timeout: 5))
        addItem.tap()
        for title in ["Parent", "Bravo"] {
            let itemField = app.textFields["editor.newItem"]
            XCTAssertTrue(itemField.waitForExistence(timeout: 5))
            itemField.tap()
            itemField.typeText("\(title)\n")
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5))
        }
        // Dismiss the armed add flow, then give Parent a child.
        app.staticTexts["Parent"].tap()
        XCTAssertTrue(app.buttons["editor.ios.addChild"].waitForExistence(timeout: 5))
        app.buttons["editor.ios.addChild"].tap()
        let childField = app.textFields["editor.newItem"]
        XCTAssertTrue(childField.waitForExistence(timeout: 5))
        childField.tap()
        childField.typeText("Kid\n")
        XCTAssertTrue(app.staticTexts["Kid"].waitForExistence(timeout: 5))
        app.staticTexts["Parent"].tap() // dismiss add flow

        let bravo = app.staticTexts["Bravo"]
        let kid = app.staticTexts["Kid"]
        XCTAssertTrue(bravo.waitForExistence(timeout: 5))
        let bravoRootX = bravo.frame.minX
        XCTAssertGreaterThan(kid.frame.minX, bravoRootX + 10, "Kid must render indented")

        // Drag root-level Bravo ONTO the child row inside Parent.
        bravo.press(
            forDuration: 0.6,
            thenDragTo: kid,
            withVelocity: .slow,
            thenHoldForDuration: 0.5
        )

        // Clamp contract: Bravo may reorder among roots but must stay a
        // root — same indent, never adopted by Parent.
        XCTAssertTrue(waitUntil(timeout: 5) { abs(bravo.frame.minX - bravoRootX) < 5 })
        XCTAssertEqual(bravo.frame.minX, bravoRootX, accuracy: 5,
                       "Drag across a parent boundary must NOT re-parent (D2 clamp)")
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

    /// M5 Rev 2.6: the add field is load-bearing UI at the requested outline
    /// slot, and dismissing the software keyboard must not end that add flow
    /// or discard its draft.
    @MainActor func testAddFieldPlacementAndKeyboardDismissal() {
        continueAfterFailure = false
        let app = launchApp(store: "ios-add-placement-dismiss", reset: true)
        createList(named: "Placement List", in: app)

        let addItem = firstExisting(
            app.buttons["editor.addFirstItem"],
            app.buttons["editor.addItem"]
        )
        XCTAssertTrue(addItem.waitForExistence(timeout: 5))
        addItem.tap()
        for title in ["Anchor", "Tail"] {
            let field = app.textFields["editor.newItem"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.typeText("\(title)\n")
        }

        let anchor = app.staticTexts["Anchor"]
        let tail = app.staticTexts["Tail"]
        XCTAssertTrue(anchor.waitForExistence(timeout: 5))
        XCTAssertTrue(tail.waitForExistence(timeout: 5))
        anchor.tap() // dismiss the continuation field and select Anchor

        XCTAssertTrue(app.buttons["editor.ios.addBelow"].waitForExistence(timeout: 5))
        app.buttons["editor.ios.addBelow"].tap()
        let belowField = app.textFields["editor.newItem"]
        XCTAssertTrue(belowField.waitForExistence(timeout: 5))
        let belowFrame = belowField.frame
        XCTAssertGreaterThan(belowFrame.minY, anchor.frame.minY)
        XCTAssertLessThan(belowFrame.minY, tail.frame.minY,
                          "Below field must render between its anchor and next sibling")

        belowField.typeText("Preserved draft")
        let dismissKeyboard = app.buttons["editor.keyboard.dismiss"]
        XCTAssertTrue(dismissKeyboard.waitForExistence(timeout: 5))
        dismissKeyboard.tap()
        XCTAssertFalse(app.keyboards.element.waitForExistence(timeout: 2))
        XCTAssertTrue(belowField.exists, "Dismissing the keyboard must keep the add field armed")
        XCTAssertEqual(belowField.value as? String, "Preserved draft")

        belowField.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["editor.keyboard.cancel"].waitForExistence(timeout: 5))
        app.buttons["editor.keyboard.cancel"].tap()
        XCTAssertFalse(app.textFields["editor.newItem"].waitForExistence(timeout: 2))

        anchor.tap()
        XCTAssertTrue(app.buttons["editor.ios.addChild"].waitForExistence(timeout: 5))
        app.buttons["editor.ios.addChild"].tap()
        let childField = app.textFields["editor.newItem"]
        XCTAssertTrue(childField.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(childField.frame.minY, anchor.frame.minY)
        XCTAssertLessThan(childField.frame.minY, tail.frame.minY,
                          "Child field must render immediately below its parent")
        XCTAssertGreaterThan(childField.frame.minX, belowFrame.minX + 10,
                             "Child field must be visibly indented from a sibling add field")
    }

    /// M5 §1.6(b): iOS exposes stable Undo/Redo rows whose enablement follows
    /// the scene UndoManager and is cleared when ListDetailView switches stores.
    @MainActor func testUndoRedoAvailabilityAcrossMutationAndListSwitch() {
        continueAfterFailure = false
        let app = launchApp(store: "ios-undo-redo", reset: true)
        createList(named: "First Undo List", in: app)
        addItem(named: "Undoable", in: app)
        let undoable = app.staticTexts["Undoable"]
        XCTAssertTrue(undoable.waitForExistence(timeout: 5))
        undoable.tap() // dismiss the continuation field

        openEditorOverflowIfNeeded(in: app)
        var undo = undoButton(in: app)
        var redo = redoButton(in: app)
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertTrue(redo.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) { undo.isEnabled })
        XCTAssertFalse(redo.isEnabled)
        undo.tap()
        XCTAssertFalse(undoable.waitForExistence(timeout: 2))

        openEditorOverflowIfNeeded(in: app)
        redo = redoButton(in: app)
        XCTAssertTrue(waitUntil(timeout: 5) { redo.isEnabled })
        redo.tap()
        XCTAssertTrue(undoable.waitForExistence(timeout: 5))

        let back = firstExisting(
            app.navigationBars.buttons["Listsurf"],
            app.navigationBars.buttons["Back"],
            app.navigationBars.buttons.firstMatch
        )
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        createList(named: "Second Undo List", in: app)

        openEditorOverflowIfNeeded(in: app)
        undo = undoButton(in: app)
        redo = redoButton(in: app)
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertTrue(redo.waitForExistence(timeout: 5))
        XCTAssertFalse(undo.isEnabled, "Switching lists must retire the old store's undo actions")
        XCTAssertFalse(redo.isEnabled, "Switching lists must retire the old store's redo actions")
    }

    @MainActor func testDetailsNotesEditorIsBounded() {
        continueAfterFailure = false
        let app = launchApp(store: "ios-bounded-notes", reset: true)
        createList(named: "Bounded Notes List", in: app)
        addItem(named: "Noted Item", in: app)

        let item = app.staticTexts["Noted Item"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.doubleTap()

        let notes = app.textViews["inspector.itemNotes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
        let initialHeight = notes.frame.height
        XCTAssertGreaterThanOrEqual(initialHeight, 50)
        XCTAssertLessThanOrEqual(initialHeight, 130)
        notes.tap()
        notes.typeText((1...12).map { "Line \($0)" }.joined(separator: "\n"))
        XCTAssertGreaterThanOrEqual(notes.frame.height, 50)
        XCTAssertLessThanOrEqual(notes.frame.height, 130,
                                 "Long notes must scroll internally instead of expanding Details")
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

    /// td-1ef423 (Gate I3+I1b, plan item 3): with a long list, the armed
    /// child-add field and the inline rename field for the LAST row land at
    /// the very bottom of the outline — exactly where the software keyboard
    /// would otherwise occlude them without the new ScrollViewReader
    /// scrollTo triggers. `isHittable` fails if a field exists in the
    /// hierarchy but is actually covered by the keyboard.
    @MainActor func testKeyboardOcclusionScrollsFieldsIntoView() {
        continueAfterFailure = false
        let app = launchApp(store: "ios-keyboard-occlusion", reset: true)
        createList(named: "Long Occlusion List", in: app)

        let addItem = firstExisting(
            app.buttons["editor.addFirstItem"],
            app.buttons["editor.addItem"]
        )
        XCTAssertTrue(addItem.waitForExistence(timeout: 5))
        addItem.tap()

        var lastTitle = ""
        for index in 1...25 {
            lastTitle = "Item \(index)"
            let itemField = app.textFields["editor.newItem"]
            XCTAssertTrue(itemField.waitForExistence(timeout: 5))
            itemField.typeText("\(lastTitle)\n")
        }

        let lastRow = app.staticTexts[lastTitle]
        XCTAssertTrue(lastRow.waitForExistence(timeout: 5))
        lastRow.tap() // dismiss the still-armed continuation field, select the last row

        // Arm a child add on the selected (last) row via the bottom action
        // bar — the same path testCoreActionsAreVisible and
        // testDragAcrossParentBoundaryDoesNotReparent already use.
        XCTAssertTrue(app.buttons["editor.ios.addChild"].waitForExistence(timeout: 5))
        app.buttons["editor.ios.addChild"].tap()

        let childField = app.textFields["editor.newItem"]
        XCTAssertTrue(childField.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitUntil(timeout: 5) { childField.isHittable },
            "Armed child-add field on the last row must scroll clear of the keyboard"
        )

        // Cancel cleanly (existing keyboard-accessory path) rather than
        // committing, so the last row is still Item 25 for the rename step.
        let cancel = app.buttons["editor.keyboard.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertFalse(app.textFields["editor.newItem"].waitForExistence(timeout: 2))

        // Rename the last row via its row-actions menu (same menu content
        // as the context menu; identifier "editor.rowActions" is shared
        // across rows, so the row's accessibility LABEL disambiguates).
        let rowActions = app.buttons["Actions for \(lastTitle)"]
        XCTAssertTrue(rowActions.waitForExistence(timeout: 5))
        rowActions.tap()
        let renameButton = app.buttons["Rename"]
        XCTAssertTrue(renameButton.waitForExistence(timeout: 5))
        renameButton.tap()

        let renameField = app.textFields["editor.renameField"]
        XCTAssertTrue(renameField.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitUntil(timeout: 5) { renameField.isHittable },
            "Inline rename field on the last row must scroll clear of the keyboard"
        )
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

    @MainActor private func openEditorOverflowIfNeeded(in app: XCUIApplication) {
        if undoButton(in: app).exists { return }

        let more = firstExisting(
            app.buttons["More"].firstMatch,
            app.buttons["Toolbar overflow"].firstMatch
        )
        XCTAssertTrue(more.waitForExistence(timeout: 5), "Expected the iOS toolbar overflow button")
        more.tap()
        XCTAssertTrue(waitUntil(timeout: 5) { undoButton(in: app).exists })
    }

    @MainActor private func undoButton(in app: XCUIApplication) -> XCUIElement {
        firstExisting(app.buttons["editor.undo"].firstMatch, app.buttons["Undo"].firstMatch)
    }

    @MainActor private func redoButton(in app: XCUIApplication) -> XCUIElement {
        firstExisting(app.buttons["editor.redo"].firstMatch, app.buttons["Redo"].firstMatch)
    }

    @MainActor private func firstExisting(_ elements: XCUIElement...) -> XCUIElement {
        elements.first(where: \.exists) ?? elements[0]
    }
}
