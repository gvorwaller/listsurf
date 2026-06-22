import SwiftUI

public struct ListsurfCommands: Commands {
    @FocusedValue(\.listsurfAppCommands) private var appCommands
    @FocusedValue(\.listsurfListCommands) private var listCommands

    public init() {}

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New List") {
                appCommands?.newList()
            }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(appCommands == nil)
        }

        CommandMenu("Item") {
            Button("Add Item Below") {
                listCommands?.addBelow?()
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(listCommands?.addBelow == nil)

            Button("Add Item Above") {
                listCommands?.addAbove?()
            }
            .keyboardShortcut(.return, modifiers: [.shift])
            .disabled(listCommands?.addAbove == nil)

            Button("Add Child") {
                listCommands?.addChild?()
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(listCommands?.addChild == nil)

            Divider()

            Button("Indent") {
                listCommands?.indent?()
            }
            .keyboardShortcut(.tab, modifiers: [])
            .disabled(listCommands?.indent == nil)

            Button("Outdent") {
                listCommands?.outdent?()
            }
            .keyboardShortcut(.tab, modifiers: [.shift])
            .disabled(listCommands?.outdent == nil)

            Divider()

            Button("Move Up") {
                listCommands?.moveUp?()
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            .disabled(listCommands?.moveUp == nil)

            Button("Move Down") {
                listCommands?.moveDown?()
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            .disabled(listCommands?.moveDown == nil)

            Divider()

            Button("Delete") {
                listCommands?.delete?()
            }
            .keyboardShortcut(.delete, modifiers: [.command])
            .disabled(listCommands?.delete == nil)
        }

        CommandMenu("View") {
            Button("Toggle Check Mode") {
                listCommands?.toggleCheckMode?()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(listCommands?.toggleCheckMode == nil)

            Button("Toggle Inspector") {
                listCommands?.toggleInspector?()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(listCommands?.toggleInspector == nil)

            Divider()

            Button("Expand All") {
                listCommands?.expandAll?()
            }
            .disabled(listCommands?.expandAll == nil)

            Button("Collapse All") {
                listCommands?.collapseAll?()
            }
            .disabled(listCommands?.collapseAll == nil)
        }
    }
}
