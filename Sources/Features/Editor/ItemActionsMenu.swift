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
                Label(hinted(CommandCatalog.newItem.title, CommandCatalog.newItem.binding), systemImage: CommandCatalog.newItem.systemImage)
            }

            Button {
                selectTargetIfNeeded()
                let newID = store.insertAbove(referenceID: id, title: "New Item", undoManager: undoManager)
                store.beginEditing(itemID: newID)
            } label: {
                Label(hinted(CommandCatalog.addAbove.title, CommandCatalog.addAbove.binding), systemImage: CommandCatalog.addAbove.systemImage)
            }

            Button {
                selectTargetIfNeeded()
                store.beginAdding(.child(id))
            } label: {
                Label(hinted(CommandCatalog.addChild.title, CommandCatalog.addChild.binding), systemImage: CommandCatalog.addChild.systemImage)
            }

            Divider()

            Button {
                selectTargetIfNeeded()
                store.indent(itemID: id, undoManager: undoManager)
            } label: {
                Label(hinted(CommandCatalog.indent.title, CommandCatalog.indent.binding), systemImage: CommandCatalog.indent.systemImage)
            }

            Button {
                selectTargetIfNeeded()
                store.outdent(itemID: id, undoManager: undoManager)
            } label: {
                Label(hinted(CommandCatalog.outdent.title, CommandCatalog.outdent.binding), systemImage: CommandCatalog.outdent.systemImage)
            }

            Divider()

            Button {
                selectTargetIfNeeded()
                store.moveUp(itemID: id, undoManager: undoManager)
            } label: {
                Label(hinted(CommandCatalog.moveUp.title, CommandCatalog.moveUp.binding), systemImage: CommandCatalog.moveUp.systemImage)
            }

            Button {
                selectTargetIfNeeded()
                store.moveDown(itemID: id, undoManager: undoManager)
            } label: {
                Label(hinted(CommandCatalog.moveDown.title, CommandCatalog.moveDown.binding), systemImage: CommandCatalog.moveDown.systemImage)
            }

            Divider()

            Button {
                selectTargetIfNeeded()
                store.beginEditing(itemID: id)
            } label: {
                Label(hinted(CommandCatalog.rename.title, CommandCatalog.rename.binding), systemImage: CommandCatalog.rename.systemImage)
            }

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
                    hinted(store.wouldCheck(ids: [id]) ? "Check" : "Uncheck", CommandCatalog.toggleChecked.binding),
                    systemImage: store.wouldCheck(ids: [id]) ? "checkmark.circle" : "circle"
                )
            }

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
            // Structure ops act on the whole selection set (plan item 10 —
            // parity with Check/Uncheck, which already does).
            Button {
                selectTargetIfNeeded()
                store.indent(itemIDs: itemIDs, undoManager: undoManager)
            } label: {
                Label(hinted(CommandCatalog.indent.title, CommandCatalog.indent.binding), systemImage: CommandCatalog.indent.systemImage)
            }

            Button {
                selectTargetIfNeeded()
                store.outdent(itemIDs: itemIDs, undoManager: undoManager)
            } label: {
                Label(hinted(CommandCatalog.outdent.title, CommandCatalog.outdent.binding), systemImage: CommandCatalog.outdent.systemImage)
            }

            Button {
                selectTargetIfNeeded()
                store.moveUp(itemIDs: itemIDs, undoManager: undoManager)
            } label: {
                Label(hinted(CommandCatalog.moveUp.title, CommandCatalog.moveUp.binding), systemImage: CommandCatalog.moveUp.systemImage)
            }

            Button {
                selectTargetIfNeeded()
                store.moveDown(itemIDs: itemIDs, undoManager: undoManager)
            } label: {
                Label(hinted(CommandCatalog.moveDown.title, CommandCatalog.moveDown.binding), systemImage: CommandCatalog.moveDown.systemImage)
            }

            Divider()

            Button {
                selectTargetIfNeeded()
                store.toggleChecked(ids: itemIDs, undoManager: undoManager)
            } label: {
                Label(
                    hinted(store.wouldCheck(ids: itemIDs) ? "Check" : "Uncheck", CommandCatalog.toggleChecked.binding),
                    systemImage: store.wouldCheck(ids: itemIDs) ? "checkmark.circle" : "circle"
                )
            }

            Divider()
        }

        if !itemIDs.isEmpty {
            Button(role: .destructive) {
                selectTargetIfNeeded()
                store.pendingDeletionIDs = itemIDs
            } label: {
                Label(hinted(itemIDs.count == 1 ? "Delete" : "Delete \(itemIDs.count) Items", CommandCatalog.delete.binding), systemImage: "trash")
            }
        }
    }

    private func selectTargetIfNeeded() {
        if selectsTargetOnAct {
            store.selectedItemIDs = itemIDs
        }
    }

    /// macOS suppresses key equivalents in context menus by platform design
    /// (Finder, Notes, and every system context menu show none), so the
    /// `.keyboardShortcut` modifier renders nothing there (td-06fb0a). The
    /// hint is appended to the title text instead — only on surfaces whose
    /// target is the selection (see `showsShortcutHints` doc above).
    private func hinted(_ title: String, _ binding: CommandCatalog.Binding?) -> String {
        guard showsShortcutHints, let binding else { return title }
        return "\(title)   \(binding.display)"
    }
}
