import XCTest
@testable import Features

final class CommandCatalogTests: XCTestCase {
    func testBindingsAreUnique() {
        let bound = CommandCatalog.allCommands.compactMap { command in
            command.binding.map { (command, $0) }
        }
        for (index, lhs) in bound.enumerated() {
            for rhs in bound.dropFirst(index + 1) {
                XCTAssertFalse(
                    lhs.1.key == rhs.1.key && lhs.1.modifiers == rhs.1.modifiers,
                    "Duplicate binding: \(lhs.0.id) and \(rhs.0.id)"
                )
            }
        }
    }

    func testEveryKeyboardCommandHasHelp() {
        for command in CommandCatalog.allCommands
            where command.binding != nil || command.editorOwnedKey != nil {
            XCTAssertFalse(command.helpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           "Missing help for \(command.id)")
        }
    }

    func testEveryBoundCommandAppearsInMacKeyboardHelp() {
        let helpIDs = Set(CommandCatalog.macKeyboardHelp.map(\.id))
        let boundIDs = Set(CommandCatalog.allCommands.filter { $0.binding != nil }.map(\.id))
        XCTAssertTrue(boundIDs.isSubset(of: helpIDs), "Missing from Help: \(boundIDs.subtracting(helpIDs))")
    }

    func testDeclaredIDsExactlyMatchExpectedInventory() {
        XCTAssertEqual(Set(CommandCatalog.allCommands.map(\.id)), CommandCatalog.expectedIDs)
        XCTAssertEqual(CommandCatalog.allCommands.count, CommandCatalog.expectedIDs.count,
                       "Duplicate command IDs")
    }

    func testEditorOwnedKeysAreRepresentedInOrderedHelp() {
        let displays = CommandCatalog.macKeyboardHelp.map(\.keyDisplay)
        XCTAssertTrue(displays.contains { $0.contains("Return") })
        XCTAssertTrue(displays.contains { $0.contains("Tab") })
        XCTAssertTrue(displays.contains { $0.contains("Space") })
        XCTAssertTrue(displays.contains { $0.contains("Esc") })
    }

    func testKeyboardHelpSurfacesMatchGeneratedRows() {
        let helpIDs = Set(CommandCatalog.macKeyboardHelp.map(\.id))
        let declaredHelpIDs = Set(CommandCatalog.allCommands.filter { $0.surfaces.contains(.help) }.map(\.id))
        let legendIDs = Set(CommandCatalog.allCommands.filter { $0.surfaces.contains(.keyboardLegend) }.map(\.id))
        XCTAssertEqual(helpIDs, declaredHelpIDs)
        XCTAssertEqual(helpIDs, legendIDs)
    }

    func testActionToSurfaceMemberships() {
        typealias S = CommandCatalog.Surface
        let expected: [String: Set<S>] = [
            "newItem": [.itemMenu, .rowContextMenu, .rowEllipsis, .toolbarActions, .emptyAreaContextMenu, .help, .keyboardLegend],
            "addAbove": [.itemMenu, .rowContextMenu, .rowEllipsis, .toolbarActions, .help, .keyboardLegend],
            "addChild": [.itemMenu, .rowContextMenu, .rowEllipsis, .toolbarActions, .help, .keyboardLegend],
            "rename": [.itemMenu, .rowContextMenu, .rowEllipsis, .toolbarActions, .help, .keyboardLegend],
            "toggleChecked": [.itemMenu, .rowContextMenu, .rowEllipsis, .toolbarActions, .help, .keyboardLegend],
            "indent": [.itemMenu, .rowContextMenu, .rowEllipsis, .toolbarActions, .help, .keyboardLegend],
            "outdent": [.itemMenu, .rowContextMenu, .rowEllipsis, .toolbarActions, .help, .keyboardLegend],
            "moveUp": [.itemMenu, .rowContextMenu, .rowEllipsis, .toolbarActions, .help, .keyboardLegend],
            "moveDown": [.itemMenu, .rowContextMenu, .rowEllipsis, .toolbarActions, .help, .keyboardLegend],
            "delete": [.itemMenu, .rowContextMenu, .rowEllipsis, .toolbarActions, .help, .keyboardLegend],
            "resetAllChecks": [.itemMenu, .toolbarActions],
            "resetBranch": [.rowContextMenu, .rowEllipsis, .toolbarActions],
            "filterAll": [.viewMenu, .toolbarActions, .help, .keyboardLegend],
            "filterRemaining": [.viewMenu, .toolbarActions, .help, .keyboardLegend],
            "filterCompleted": [.viewMenu, .toolbarActions, .help, .keyboardLegend],
            "toggleInspector": [.viewMenu, .toolbarActions, .help, .keyboardLegend],
            "expandAll": [.viewMenu, .toolbarActions, .emptyAreaContextMenu],
            "collapseAll": [.viewMenu, .toolbarActions, .emptyAreaContextMenu],
            "newList": [.help, .keyboardLegend],
            "help": [.help, .keyboardLegend],
            "navigate": [.help, .keyboardLegend],
            "escape": [.help, .keyboardLegend],
            "settings": [.help, .keyboardLegend],
            "keyboardLegend": [.viewMenu, .help, .keyboardLegend]
        ]
        XCTAssertEqual(Set(expected.keys), CommandCatalog.expectedIDs)
        for command in CommandCatalog.allCommands {
            XCTAssertEqual(command.surfaces, expected[command.id], "Surface drift for \(command.id)")
        }
    }
}
