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

        CommandGroup(after: .newItem) {
            Button("Import Library Backup…") {
                appCommands?.importBackup()
            }
            .disabled(appCommands == nil)

            // No keyboard shortcut — bare-key/menu-equivalent trap (spec §11).
            Button("Import List…") {
                appCommands?.importList()
            }
            .disabled(appCommands == nil)

            Button("Export Library Backup…") {
                appCommands?.exportBackup()
            }
            .disabled(appCommands == nil)
        }

        CommandGroup(replacing: .help) {
            Button("Listsurf Help") {
                appCommands?.showHelp()
            }
            .keyboardShortcut("?", modifiers: [.command])
            .disabled(appCommands == nil)
        }

        CommandMenu("Item") {
            // Note: Add Below/Above deliberately carry no key equivalents.
            // Bare Return/Tab menu equivalents intercept typing in every
            // text field in the window; the editor owns those keys directly
            // (Return = add below, Shift-Return = add above, Tab = indent,
            // Shift-Tab = outdent) and only while the outline has focus.
            Button("Add Item Below") {
                listCommands?.addBelow?()
            }
            .disabled(listCommands?.addBelow == nil)

            Button("Add Item Above") {
                listCommands?.addAbove?()
            }
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
            .keyboardShortcut("]", modifiers: [.command])
            .disabled(listCommands?.indent == nil)

            Button("Outdent") {
                listCommands?.outdent?()
            }
            .keyboardShortcut("[", modifiers: [.command])
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
