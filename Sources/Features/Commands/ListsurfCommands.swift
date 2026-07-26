import SwiftUI
#if os(macOS)
import AppKit
#endif

// Shortcut titles and bindings belong in CommandCatalog. Do not hand-code a
// keyboard shortcut here: generated Help, the legend, and parity tests all
// depend on that catalog remaining the single source of truth.
public struct ListsurfCommands: Commands {
    @FocusedValue(\.listsurfAppCommands) private var appCommands
    @FocusedValue(\.listsurfListCommands) private var listCommands
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    #endif

    public init() {}

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            catalogButton(CommandCatalog.newItem, action: listCommands?.addBelow)
                .disabled(listCommands?.addBelow == nil)
            catalogButton(CommandCatalog.newList, action: appCommands?.newList)
                .disabled(appCommands == nil)
        }

        CommandGroup(after: .newItem) {
            Button("Import Library Backup…") { appCommands?.importBackup() }
                .disabled(appCommands == nil)
            Button("Import List…") { appCommands?.importList() }
                .disabled(appCommands == nil)
            Button("Export Library Backup…") { appCommands?.exportBackup() }
                .disabled(appCommands == nil)
        }

        CommandGroup(replacing: .help) {
            catalogButton(CommandCatalog.help, action: appCommands?.showHelp)
                .disabled(appCommands == nil)
        }

        CommandMenu("Item") {
            // The editor owns bare Return/Tab/Space. Making them menu
            // equivalents would intercept typing in every text field.
            Button(CommandCatalog.newItem.title) { listCommands?.addBelow?() }
                .disabled(listCommands?.addBelow == nil)
            catalogButton(CommandCatalog.addAbove, action: listCommands?.addAbove)
                .disabled(listCommands?.addAbove == nil)
            catalogButton(CommandCatalog.addChild, action: listCommands?.addChild)
                .disabled(listCommands?.addChild == nil)
            Divider()
            catalogButton(CommandCatalog.rename, action: listCommands?.rename)
                .disabled(listCommands?.rename == nil)
            catalogButton(CommandCatalog.toggleChecked, action: listCommands?.toggleChecked)
                .disabled(listCommands?.toggleChecked == nil)
            Divider()
            catalogButton(CommandCatalog.indent, action: listCommands?.indent)
                .disabled(listCommands?.indent == nil)
            catalogButton(CommandCatalog.outdent, action: listCommands?.outdent)
                .disabled(listCommands?.outdent == nil)
            Divider()
            catalogButton(CommandCatalog.moveUp, action: listCommands?.moveUp)
                .disabled(listCommands?.moveUp == nil)
            catalogButton(CommandCatalog.moveDown, action: listCommands?.moveDown)
                .disabled(listCommands?.moveDown == nil)
            Divider()
            catalogButton(CommandCatalog.delete, action: listCommands?.delete)
                .disabled(listCommands?.delete == nil)
            Divider()
            Button(CommandCatalog.resetAllChecks.title) { listCommands?.resetAllChecks?() }
                .disabled(listCommands?.resetAllChecks == nil)
        }

        CommandMenu("View") {
            catalogButton(CommandCatalog.toggleInspector, action: listCommands?.toggleInspector)
                .disabled(listCommands?.toggleInspector == nil)
            Divider()
            Menu("Filter") {
                filterButton(CommandCatalog.filterAll, filter: .all)
                filterButton(CommandCatalog.filterRemaining, filter: .remaining)
                filterButton(CommandCatalog.filterCompleted, filter: .completed)
            }
            Divider()
            Button(CommandCatalog.expandAll.title) { listCommands?.expandAll?() }
                .disabled(listCommands?.expandAll == nil)
            Button(CommandCatalog.collapseAll.title) { listCommands?.collapseAll?() }
                .disabled(listCommands?.collapseAll == nil)
            #if os(macOS)
            Divider()
            catalogButton(CommandCatalog.keyboardLegend) {
                if let window = legendWindow(), window.isVisible {
                    dismissWindow(id: "keyboard-legend")
                } else {
                    KeyboardLegendFocus.capture()
                    openWindow(id: "keyboard-legend")
                }
                CommandInvocation.post(CommandCatalog.keyboardLegend)
            }
            #endif
        }
    }

    private func catalogButton(
        _ command: CommandCatalog.Command,
        action: (@MainActor () -> Void)?
    ) -> some View {
        catalogButton(command) {
            action?()
        }
    }

    private func catalogButton(
        _ command: CommandCatalog.Command,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(command.title, action: action)
            .catalogShortcut(command.binding)
    }

    private func filterButton(_ command: CommandCatalog.Command, filter: ListStore.CheckFilter) -> some View {
        catalogButton(command) { listCommands?.setFilter?(filter) }
            .disabled(listCommands?.setFilter == nil)
    }

    #if os(macOS)
    /// Finds the live Keyboard Legend `NSWindow`, if one exists, so the
    /// toggle can read actual window state instead of a parallel `@State`
    /// bool (which desynced from `dismissWindow`/close-button dismissal and
    /// caused the second Opt-Cmd-L to hide the whole app — td-0a4af9).
    /// SwiftUI derives `NSWindow.identifier` from the `Window(id:)` scene
    /// identifier, but may suffix it (extra windows, restoration); match by
    /// prefix with a title-match fallback.
    private func legendWindow() -> NSWindow? {
        NSApp.windows.first { window in
            if let identifier = window.identifier?.rawValue,
               identifier.hasPrefix("keyboard-legend") {
                return true
            }
            return window.title == "Keyboard Legend"
        }
    }
    #endif
}

private extension View {
    @ViewBuilder
    func catalogShortcut(_ binding: CommandCatalog.Binding?) -> some View {
        if let binding {
            keyboardShortcut(binding.key, modifiers: binding.modifiers)
        } else {
            self
        }
    }
}
