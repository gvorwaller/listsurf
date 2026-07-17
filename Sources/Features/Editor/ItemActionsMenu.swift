import SwiftUI
import Domain

/// The single definition of the item action set. Every surface that offers
/// item actions (row context menu, toolbar menu, per-row ellipsis menu)
/// renders this view, so the actions cannot drift between surfaces.
///
/// `showsShortcutHints` must be true only on surfaces whose target is the
/// current selection — the displayed shortcuts act on the selection, and a
/// hint on a menu that targets something else would advertise a shortcut
/// that does a different thing.
struct ItemActionsMenu: View {
    @Bindable var store: ListStore
    let itemIDs: Set<UUID>
    let showsShortcutHints: Bool
    let onShowDetails: (UUID) -> Void
    @Environment(\.undoManager) private var undoManager

    private var singleID: UUID? {
        itemIDs.count == 1 ? itemIDs.first : nil
    }

    var body: some View {
        if let id = singleID {
            Button {
                store.beginAdding(.below(id))
            } label: {
                Label("Add Below", systemImage: "plus")
            }

            Button {
                let newID = store.insertAbove(referenceID: id, title: "New Item", undoManager: undoManager)
                store.beginEditing(itemID: newID)
            } label: {
                Label("Add Above", systemImage: "arrow.up")
            }

            Button {
                store.beginAdding(.child(id))
            } label: {
                Label("Add Child", systemImage: "arrow.turn.down.right")
            }
            .shortcutHint(.return, modifiers: [.command], enabled: showsShortcutHints)

            Divider()

            Button {
                store.indent(itemID: id, undoManager: undoManager)
            } label: {
                Label("Indent", systemImage: "increase.indent")
            }
            .shortcutHint("]", modifiers: [.command], enabled: showsShortcutHints)

            Button {
                store.outdent(itemID: id, undoManager: undoManager)
            } label: {
                Label("Outdent", systemImage: "decrease.indent")
            }
            .shortcutHint("[", modifiers: [.command], enabled: showsShortcutHints)

            Divider()

            Button {
                store.moveUp(itemID: id, undoManager: undoManager)
            } label: {
                Label("Move Up", systemImage: "arrow.up")
            }
            .shortcutHint(.upArrow, modifiers: [.command, .option], enabled: showsShortcutHints)

            Button {
                store.moveDown(itemID: id, undoManager: undoManager)
            } label: {
                Label("Move Down", systemImage: "arrow.down")
            }
            .shortcutHint(.downArrow, modifiers: [.command, .option], enabled: showsShortcutHints)

            Divider()

            Button {
                store.beginEditing(itemID: id)
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .shortcutHint("e", modifiers: [.command], enabled: showsShortcutHints)

            Button {
                onShowDetails(id)
            } label: {
                Label("Details", systemImage: "info.circle")
            }

            Divider()

            Button {
                store.toggleChecked(ids: [id], undoManager: undoManager)
            } label: {
                Label(
                    store.wouldCheck(ids: [id]) ? "Check" : "Uncheck",
                    systemImage: store.wouldCheck(ids: [id]) ? "checkmark.circle" : "circle"
                )
            }
            .shortcutHint("k", modifiers: [.command], enabled: showsShortcutHints)

            if store.resolvedRow(for: id)?.hasChildren == true {
                Button {
                    store.pendingBranchResetID = id
                } label: {
                    Label("Reset Branch…", systemImage: "arrow.counterclockwise")
                }
                .disabled(store.resolvedRow(for: id)?.checkState == .unchecked)
            }

            Divider()
        } else if itemIDs.count > 1 {
            Button {
                store.toggleChecked(ids: itemIDs, undoManager: undoManager)
            } label: {
                Label(
                    store.wouldCheck(ids: itemIDs) ? "Check" : "Uncheck",
                    systemImage: store.wouldCheck(ids: itemIDs) ? "checkmark.circle" : "circle"
                )
            }
            .shortcutHint("k", modifiers: [.command], enabled: showsShortcutHints)

            Divider()
        }

        if !itemIDs.isEmpty {
            Button(role: .destructive) {
                store.pendingDeletionIDs = itemIDs
            } label: {
                Label(itemIDs.count == 1 ? "Delete" : "Delete \(itemIDs.count) Items", systemImage: "trash")
            }
            .shortcutHint(.delete, modifiers: [.command], enabled: showsShortcutHints)
        }
    }
}

private extension View {
    @ViewBuilder
    func shortcutHint(_ key: KeyEquivalent, modifiers: EventModifiers, enabled: Bool) -> some View {
        if enabled {
            keyboardShortcut(key, modifiers: modifiers)
        } else {
            self
        }
    }
}
