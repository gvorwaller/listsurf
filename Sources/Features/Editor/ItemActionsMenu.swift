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
    let selectsTargetOnAct: Bool
    let onShowDetails: (UUID) -> Void
    @Environment(\.undoManager) private var undoManager

    private var singleID: UUID? {
        itemIDs.count == 1 ? itemIDs.first : nil
    }

    var body: some View {
        if let id = singleID {
            Button {
                selectTargetIfNeeded()
                store.beginAdding(.below(id))
            } label: {
                Label(CommandCatalog.newItem.title, systemImage: CommandCatalog.newItem.systemImage)
            }

            Button {
                selectTargetIfNeeded()
                let newID = store.insertAbove(referenceID: id, title: "New Item", undoManager: undoManager)
                store.beginEditing(itemID: newID)
            } label: {
                Label(CommandCatalog.addAbove.title, systemImage: CommandCatalog.addAbove.systemImage)
            }

            Button {
                selectTargetIfNeeded()
                store.beginAdding(.child(id))
            } label: {
                Label(CommandCatalog.addChild.title, systemImage: CommandCatalog.addChild.systemImage)
            }
            .shortcutHint(CommandCatalog.addChild.binding, enabled: showsShortcutHints)

            Divider()

            Button {
                selectTargetIfNeeded()
                store.indent(itemID: id, undoManager: undoManager)
            } label: {
                Label(CommandCatalog.indent.title, systemImage: CommandCatalog.indent.systemImage)
            }
            .shortcutHint(CommandCatalog.indent.binding, enabled: showsShortcutHints)

            Button {
                selectTargetIfNeeded()
                store.outdent(itemID: id, undoManager: undoManager)
            } label: {
                Label(CommandCatalog.outdent.title, systemImage: CommandCatalog.outdent.systemImage)
            }
            .shortcutHint(CommandCatalog.outdent.binding, enabled: showsShortcutHints)

            Divider()

            Button {
                selectTargetIfNeeded()
                store.moveUp(itemID: id, undoManager: undoManager)
            } label: {
                Label(CommandCatalog.moveUp.title, systemImage: CommandCatalog.moveUp.systemImage)
            }
            .shortcutHint(CommandCatalog.moveUp.binding, enabled: showsShortcutHints)

            Button {
                selectTargetIfNeeded()
                store.moveDown(itemID: id, undoManager: undoManager)
            } label: {
                Label(CommandCatalog.moveDown.title, systemImage: CommandCatalog.moveDown.systemImage)
            }
            .shortcutHint(CommandCatalog.moveDown.binding, enabled: showsShortcutHints)

            Divider()

            Button {
                selectTargetIfNeeded()
                store.beginEditing(itemID: id)
            } label: {
                Label(CommandCatalog.rename.title, systemImage: CommandCatalog.rename.systemImage)
            }
            .shortcutHint(CommandCatalog.rename.binding, enabled: showsShortcutHints)

            Button {
                selectTargetIfNeeded()
                onShowDetails(id)
            } label: {
                Label("Details", systemImage: "info.circle")
            }

            Divider()

            Button {
                selectTargetIfNeeded()
                store.toggleChecked(ids: [id], undoManager: undoManager)
            } label: {
                Label(
                    store.wouldCheck(ids: [id]) ? "Check" : "Uncheck",
                    systemImage: store.wouldCheck(ids: [id]) ? "checkmark.circle" : "circle"
                )
            }
            .shortcutHint(CommandCatalog.toggleChecked.binding, enabled: showsShortcutHints)

            if store.resolvedRow(for: id)?.hasChildren == true {
                Button {
                    selectTargetIfNeeded()
                    store.pendingBranchResetID = id
                } label: {
                    Label(CommandCatalog.resetBranch.title, systemImage: CommandCatalog.resetBranch.systemImage)
                }
                .disabled(store.resolvedRow(for: id)?.checkState == .unchecked)
            }

            Divider()
        } else if itemIDs.count > 1 {
            Button {
                selectTargetIfNeeded()
                store.toggleChecked(ids: itemIDs, undoManager: undoManager)
            } label: {
                Label(
                    store.wouldCheck(ids: itemIDs) ? "Check" : "Uncheck",
                    systemImage: store.wouldCheck(ids: itemIDs) ? "checkmark.circle" : "circle"
                )
            }
            .shortcutHint(CommandCatalog.toggleChecked.binding, enabled: showsShortcutHints)

            Divider()
        }

        if !itemIDs.isEmpty {
            Button(role: .destructive) {
                selectTargetIfNeeded()
                store.pendingDeletionIDs = itemIDs
            } label: {
                Label(itemIDs.count == 1 ? "Delete" : "Delete \(itemIDs.count) Items", systemImage: "trash")
            }
            .shortcutHint(CommandCatalog.delete.binding, enabled: showsShortcutHints)
        }
    }

    private func selectTargetIfNeeded() {
        if selectsTargetOnAct {
            store.selectedItemIDs = itemIDs
        }
    }
}

private extension View {
    @ViewBuilder
    func shortcutHint(_ binding: CommandCatalog.Binding?, enabled: Bool) -> some View {
        if enabled, let binding {
            keyboardShortcut(binding.key, modifiers: binding.modifiers)
        } else {
            self
        }
    }
}
