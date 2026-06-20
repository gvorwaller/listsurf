import SwiftUI

public struct ListsurfCommands: Commands {
    public init() {}

    public var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New List") {
                NotificationCenter.default.post(name: .listsurfNewList, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command])
        }

        CommandMenu("Item") {
            Button("Add Item Below") {
                NotificationCenter.default.post(name: .listsurfAddBelow, object: nil)
            }
            .keyboardShortcut(.return, modifiers: [])

            Button("Add Item Above") {
                NotificationCenter.default.post(name: .listsurfAddAbove, object: nil)
            }
            .keyboardShortcut(.return, modifiers: [.shift])

            Button("Add Child") {
                NotificationCenter.default.post(name: .listsurfAddChild, object: nil)
            }
            .keyboardShortcut(.return, modifiers: [.command])

            Divider()

            Button("Indent") {
                NotificationCenter.default.post(name: .listsurfIndent, object: nil)
            }
            .keyboardShortcut(.tab, modifiers: [])

            Button("Outdent") {
                NotificationCenter.default.post(name: .listsurfOutdent, object: nil)
            }
            .keyboardShortcut(.tab, modifiers: [.shift])

            Divider()

            Button("Move Up") {
                NotificationCenter.default.post(name: .listsurfMoveUp, object: nil)
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])

            Button("Move Down") {
                NotificationCenter.default.post(name: .listsurfMoveDown, object: nil)
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])

            Divider()

            Button("Delete") {
                NotificationCenter.default.post(name: .listsurfDelete, object: nil)
            }
            .keyboardShortcut(.delete, modifiers: [.command])
        }

        CommandMenu("View") {
            Button("Toggle Check Mode") {
                NotificationCenter.default.post(name: .listsurfToggleCheckMode, object: nil)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button("Toggle Inspector") {
                NotificationCenter.default.post(name: .listsurfToggleInspector, object: nil)
            }
            .keyboardShortcut("i", modifiers: [.command, .option])

            Divider()

            Button("Expand All") {
                NotificationCenter.default.post(name: .listsurfExpandAll, object: nil)
            }

            Button("Collapse All") {
                NotificationCenter.default.post(name: .listsurfCollapseAll, object: nil)
            }
        }
    }
}

extension Notification.Name {
    static let listsurfNewList = Notification.Name("listsurfNewList")
    static let listsurfAddBelow = Notification.Name("listsurfAddBelow")
    static let listsurfAddAbove = Notification.Name("listsurfAddAbove")
    static let listsurfAddChild = Notification.Name("listsurfAddChild")
    static let listsurfIndent = Notification.Name("listsurfIndent")
    static let listsurfOutdent = Notification.Name("listsurfOutdent")
    static let listsurfMoveUp = Notification.Name("listsurfMoveUp")
    static let listsurfMoveDown = Notification.Name("listsurfMoveDown")
    static let listsurfDelete = Notification.Name("listsurfDelete")
    static let listsurfToggleCheckMode = Notification.Name("listsurfToggleCheckMode")
    static let listsurfToggleInspector = Notification.Name("listsurfToggleInspector")
    static let listsurfExpandAll = Notification.Name("listsurfExpandAll")
    static let listsurfCollapseAll = Notification.Name("listsurfCollapseAll")
}
