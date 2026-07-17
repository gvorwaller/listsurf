import SwiftUI

enum CommandCatalog {
    struct Binding {
        let key: KeyEquivalent
        let modifiers: EventModifiers
        let display: String
    }

    enum Surface: String, CaseIterable, Hashable {
        case itemMenu
        case viewMenu
        case rowContextMenu
        case rowEllipsis
        case toolbarActions
        case emptyAreaContextMenu
        case help
        case keyboardLegend
    }

    struct Command: Identifiable {
        let id: String
        let title: String
        let systemImage: String
        let binding: Binding?
        let editorOwnedKey: String?
        let helpText: String
        let surfaces: Set<Surface>

        var keyDisplay: String {
            [editorOwnedKey, binding?.display].compactMap { $0 }.joined(separator: " / ")
        }
    }

    private static func command(
        _ id: String,
        _ title: String,
        _ systemImage: String,
        binding: Binding? = nil,
        editorOwnedKey: String? = nil,
        helpText: String,
        surfaces: Set<Surface>
    ) -> Command {
        Command(id: id, title: title, systemImage: systemImage, binding: binding,
                editorOwnedKey: editorOwnedKey, helpText: helpText, surfaces: surfaces)
    }

    private static let itemSurfaces: Set<Surface> = [.itemMenu, .rowContextMenu, .rowEllipsis, .toolbarActions]
    private static let keyboardSurfaces: Set<Surface> = [.help, .keyboardLegend]

    static let newItem = command("newItem", "New Item", "plus", binding: .init(key: "n", modifiers: [.command], display: "⌘N"), helpText: "Starts a new item below the selection, or at the root when nothing is selected; with nothing selected, Return also starts a new item.", surfaces: [.itemMenu, .rowContextMenu, .rowEllipsis, .toolbarActions, .emptyAreaContextMenu, .help, .keyboardLegend])
    static let addAbove = command("addAbove", "Add Above", "arrow.up", binding: .init(key: "n", modifiers: [.command, .option], display: "⌥⌘N"), helpText: "Adds a new item above the selected item.", surfaces: itemSurfaces.union(keyboardSurfaces))
    static let addChild = command("addChild", "Add Child", "arrow.turn.down.right", binding: .init(key: .return, modifiers: [.command], display: "⌘↩"), helpText: "Starts a child item inside the selection.", surfaces: itemSurfaces.union(keyboardSurfaces))
    static let rename = command("rename", "Rename", "pencil", binding: .init(key: "e", modifiers: [.command], display: "⌘E"), editorOwnedKey: "Return", helpText: "Renames the selected item in place.", surfaces: itemSurfaces.union(keyboardSurfaces))
    static let toggleChecked = command("toggleChecked", "Toggle Checked", "checkmark.circle", binding: .init(key: "k", modifiers: [.command], display: "⌘K"), editorOwnedKey: "Space", helpText: "Checks or unchecks the selected items; under a filter, selection advances to the next visible item.", surfaces: itemSurfaces.union(keyboardSurfaces))
    static let indent = command("indent", "Indent", "increase.indent", binding: .init(key: "]", modifiers: [.command], display: "⌘]"), editorOwnedKey: "Tab", helpText: "Moves the selected item one level deeper.", surfaces: itemSurfaces.union(keyboardSurfaces))
    static let outdent = command("outdent", "Outdent", "decrease.indent", binding: .init(key: "[", modifiers: [.command], display: "⌘["), editorOwnedKey: "⇧Tab", helpText: "Moves the selected item one level higher.", surfaces: itemSurfaces.union(keyboardSurfaces))
    static let moveUp = command("moveUp", "Move Up", "arrow.up", binding: .init(key: .upArrow, modifiers: [.command, .option], display: "⌥⌘↑"), helpText: "Moves the selected item up among its siblings.", surfaces: itemSurfaces.union(keyboardSurfaces))
    static let moveDown = command("moveDown", "Move Down", "arrow.down", binding: .init(key: .downArrow, modifiers: [.command, .option], display: "⌥⌘↓"), helpText: "Moves the selected item down among its siblings.", surfaces: itemSurfaces.union(keyboardSurfaces))
    static let delete = command("delete", "Delete", "trash", binding: .init(key: .delete, modifiers: [.command], display: "⌘⌫"), helpText: "Deletes the selected items after confirmation.", surfaces: itemSurfaces.union(keyboardSurfaces))
    static let resetAllChecks = command("resetAllChecks", "Reset All Checks…", "arrow.counterclockwise", helpText: "Unchecks every item in the list after confirmation.", surfaces: [.itemMenu, .toolbarActions])
    static let resetBranch = command("resetBranch", "Reset Branch…", "arrow.counterclockwise", helpText: "Unchecks the selected item and all of its children after confirmation.", surfaces: [.rowContextMenu, .rowEllipsis, .toolbarActions])
    static let filterAll = command("filterAll", "All", "line.3.horizontal.decrease.circle", binding: .init(key: "1", modifiers: [.command, .option], display: "⌥⌘1"), helpText: "Shows all items.", surfaces: [.viewMenu, .toolbarActions, .help, .keyboardLegend])
    static let filterRemaining = command("filterRemaining", "Remaining", "circle", binding: .init(key: "2", modifiers: [.command, .option], display: "⌥⌘2"), helpText: "Shows unchecked items.", surfaces: [.viewMenu, .toolbarActions, .help, .keyboardLegend])
    static let filterCompleted = command("filterCompleted", "Completed", "checkmark.circle", binding: .init(key: "3", modifiers: [.command, .option], display: "⌥⌘3"), helpText: "Shows checked items.", surfaces: [.viewMenu, .toolbarActions, .help, .keyboardLegend])
    static let toggleInspector = command("toggleInspector", "Toggle Inspector", "info.circle", binding: .init(key: "i", modifiers: [.command, .option], display: "⌥⌘I"), helpText: "Shows or hides the inspector.", surfaces: [.viewMenu, .toolbarActions, .help, .keyboardLegend])
    static let expandAll = command("expandAll", "Expand All", "arrow.up.left.and.arrow.down.right", helpText: "Expands every branch.", surfaces: [.viewMenu, .toolbarActions, .emptyAreaContextMenu])
    static let collapseAll = command("collapseAll", "Collapse All", "arrow.down.right.and.arrow.up.left", helpText: "Collapses every branch.", surfaces: [.viewMenu, .toolbarActions, .emptyAreaContextMenu])
    static let newList = command("newList", "New List", "plus.rectangle.on.folder", binding: .init(key: "n", modifiers: [.command, .shift], display: "⇧⌘N"), helpText: "Creates a new list.", surfaces: keyboardSurfaces)
    static let help = command("help", "Listsurf Help", "questionmark.circle", binding: .init(key: "?", modifiers: [.command], display: "⌘?"), helpText: "Opens Listsurf Help.", surfaces: keyboardSurfaces)
    static let navigate = command("navigate", "Navigate Selection", "arrow.up.arrow.down", editorOwnedKey: "↑ / ↓", helpText: "Moves the selection through the outline; Command-click or Shift-click selects multiple items.", surfaces: keyboardSurfaces)
    static let escape = command("escape", "Cancel or Clear Selection", "escape", editorOwnedKey: "Esc", helpText: "Cancels text entry, or clears the current selection.", surfaces: keyboardSurfaces)
    static let settings = command("settings", "Settings", "gearshape", binding: .init(key: ",", modifiers: [.command], display: "⌘,"), helpText: "Opens Settings.", surfaces: keyboardSurfaces)
    static let keyboardLegend = command("keyboardLegend", "Keyboard Legend", "keyboard", binding: .init(key: "l", modifiers: [.command, .option], display: "⌥⌘L"), helpText: "Shows or hides the Keyboard Legend window.", surfaces: [.viewMenu, .help, .keyboardLegend])

    static let allCommands: [Command] = [
        newItem, addAbove, addChild, rename, toggleChecked, indent, outdent,
        moveUp, moveDown, delete, resetAllChecks, resetBranch,
        filterAll, filterRemaining, filterCompleted, toggleInspector,
        expandAll, collapseAll, newList, help, navigate, escape, settings,
        keyboardLegend
    ]

    static let macKeyboardHelp: [Command] = [
        navigate, rename, newItem, addAbove, newList, addChild, toggleChecked,
        indent, outdent, moveUp, moveDown, filterAll, filterRemaining,
        filterCompleted, escape, delete, toggleInspector, keyboardLegend,
        help, settings
    ]

    static let expectedIDs: Set<String> = [
        "newItem", "addAbove", "addChild", "rename", "toggleChecked",
        "indent", "outdent", "moveUp", "moveDown", "delete",
        "resetAllChecks", "resetBranch", "filterAll", "filterRemaining",
        "filterCompleted", "toggleInspector", "expandAll", "collapseAll",
        "newList", "help", "navigate", "escape", "settings", "keyboardLegend"
    ]
}

extension Notification.Name {
    static let listsurfCommandDidInvoke = Notification.Name("ListsurfCommandDidInvoke")
}

@MainActor
enum CommandInvocation {
    static func post(_ command: CommandCatalog.Command) {
        NotificationCenter.default.post(
            name: .listsurfCommandDidInvoke,
            object: nil,
            userInfo: ["commandID": command.id]
        )
    }
}
