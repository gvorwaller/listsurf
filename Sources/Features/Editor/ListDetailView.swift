import SwiftUI
import Domain

struct ListDetailView: View {
    let listID: UUID
    @Environment(AppStore.self) private var appStore
    @State private var listStore: ListStore?
    @State private var showInspector = false
    @State private var showingResetAllChecksConfirmation = false
    @State private var listBeingEdited: ListItem?
    @AppStorage(ListsurfSettingsKey.notesPreviewLineLimit) private var notePreviewLineCount = 1
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Group {
            if let store = listStore {
                if store.isCheckMode {
                    CheckModeView(
                        store: store,
                        notePreviewLineCount: max(0, notePreviewLineCount)
                    )
                } else {
                    OutlineEditorView(
                        store: store,
                        showInspector: $showInspector,
                        notePreviewLineCount: max(0, notePreviewLineCount)
                    )
                }
            } else {
                ProgressView()
            }
        }
        .inspector(isPresented: $showInspector) {
            if let store = listStore {
                InspectorView(
                    store: store,
                    itemID: singleSelectedItemID(in: store),
                    list: currentList
                )
                .inspectorColumnWidth(min: 250, ideal: 300, max: 400)
                .presentationDetents([.medium, .large])
            }
        }
        .navigationTitle(currentList?.title ?? "")
        .toolbar { toolbarContent }
        .focusedSceneValue(\.listsurfListCommands, focusedCommandActions)
        .sheet(item: $listBeingEdited) { list in
            ListIdentityEditSheet(list: list) { updated in
                Task { await appStore.updateList(updated) }
            }
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            "Reset All Checks?",
            isPresented: $showingResetAllChecksConfirmation,
            titleVisibility: .visible
        ) {
            if let store = listStore {
                Button("Reset All Checks", role: .destructive) {
                    store.resetAllChecks(undoManager: undoManager)
                }
            }
        } message: {
            Text("Every checked item in this list will be unchecked.")
        }
        .confirmationDialog(
            deletionDialogTitle,
            isPresented: isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            if let store = listStore, let ids = store.pendingDeletionIDs {
                Button(ids.count == 1 ? "Delete Item" : "Delete Items", role: .destructive) {
                    store.deleteItems(ids: ids, undoManager: undoManager)
                    store.pendingDeletionIDs = nil
                }
                .keyboardShortcut(.defaultAction)

                Button("Cancel", role: .cancel) {
                    store.pendingDeletionIDs = nil
                }
                .keyboardShortcut(.cancelAction)
            }
        } message: {
            Text(deletionDialogMessage)
        }
        .task(id: listID) {
            // Replacing the store must retire its undo actions, or the Undo
            // menu could mutate and persist a list that's no longer shown.
            listStore?.teardownUndo(undoManager)
            let store = appStore.makeListStore(for: listID)
            listStore = store
            await store.load()
        }
        .onDisappear {
            listStore?.teardownUndo(undoManager)
        }
    }

    /// AppStore owns list metadata; this view reads it fresh on every render
    /// instead of keeping a second copy synchronized by hand.
    private var currentList: ListItem? {
        appStore.lists.first { $0.id == listID }
            ?? appStore.archivedLists.first { $0.id == listID }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if let store = listStore {
                Button {
                    store.isCheckMode.toggle()
                } label: {
                    Label(
                        store.isCheckMode ? "Edit Mode" : "Check Mode",
                        systemImage: store.isCheckMode ? "list.bullet.indent" : "checklist"
                    )
                }
                .accessibilityIdentifier("detail.toggleMode")
                .help(store.isCheckMode ? "Switch to Edit Mode" : "Switch to Check Mode")

                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "info.circle")
                }
                .help("Toggle Inspector")

                Button {
                    listBeingEdited = currentList
                } label: {
                    Label("Edit List", systemImage: "pencil")
                }
                .disabled(currentList == nil)
                .help("Edit list title, notes, icon, and color")
            }
        }

        ToolbarItemGroup(placement: .secondaryAction) {
            if let store = listStore {
                if store.isCheckMode {
                    checkModeToolbar(store)
                } else {
                    editModeToolbar(store)
                }
            }
        }
    }

    @ViewBuilder
    private func editModeToolbar(_ store: ListStore) -> some View {
        Button {
            store.beginAdding(.root)
        } label: {
            Label("Add Item", systemImage: "plus")
        }
        .accessibilityIdentifier("editor.addItem")
        .help("Add a new item")

        Menu {
            if store.selectedItemIDs.isEmpty {
                Text("Select an item first")
            } else {
                ItemActionsMenu(
                    store: store,
                    itemIDs: store.selectedItemIDs,
                    showsShortcutHints: true,
                    onShowDetails: { id in
                        store.selectedItemIDs = [id]
                        showInspector = true
                    }
                )
            }
        } label: {
            Label("Item Actions", systemImage: "ellipsis.circle")
        }
        .disabled(store.selectedItemIDs.isEmpty)
        .accessibilityIdentifier("editor.itemActions")
        .help("Add, indent, move, rename, or delete the selected items")

        Button {
            store.expandAll()
        } label: {
            Label("Expand All", systemImage: "arrow.up.left.and.arrow.down.right")
        }
        .help("Expand all branches")

        Button {
            store.collapseAll()
        } label: {
            Label("Collapse All", systemImage: "arrow.down.right.and.arrow.up.left")
        }
        .help("Collapse all branches")
    }

    @ViewBuilder
    private func checkModeToolbar(_ store: ListStore) -> some View {
        let progress = store.progress
        Text("\(progress.checked)/\(progress.total)")
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .help("Items checked / total")

        Picker("Filter", selection: filterBinding(store)) {
            ForEach(ListStore.CheckFilter.allCases, id: \.self) { filter in
                Text(filter.rawValue).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .help("Filter items by check state")

        Button {
            store.expandAll()
        } label: {
            Label("Expand All", systemImage: "arrow.up.left.and.arrow.down.right")
        }
        .help("Expand all branches")

        Button {
            store.collapseAll()
        } label: {
            Label("Collapse All", systemImage: "arrow.down.right.and.arrow.up.left")
        }
        .help("Collapse all branches")

        Button {
            showingResetAllChecksConfirmation = true
        } label: {
            Label("Reset All", systemImage: "arrow.counterclockwise")
        }
        .disabled(progress.checked == 0)
        .help("Uncheck all items")
    }

    private func filterBinding(_ store: ListStore) -> Binding<ListStore.CheckFilter> {
        Binding(
            get: { store.checkFilter },
            set: { store.checkFilter = $0 }
        )
    }

    private var focusedCommandActions: ListsurfListCommandActions {
        guard let store = listStore else { return ListsurfListCommandActions() }
        var actions = ListsurfListCommandActions()

        actions.toggleCheckMode = { store.isCheckMode.toggle() }
        actions.toggleInspector = { showInspector.toggle() }
        actions.expandAll = { store.expandAll() }
        actions.collapseAll = { store.collapseAll() }

        // While the user is typing (rename or add field), structural
        // commands must be disabled: an enabled menu equivalent would fire
        // instead of, or on top of, the text field's own handling.
        guard !store.isCheckMode, !store.isTextInputActive else { return actions }

        let selectedID = singleSelectedItemID(in: store)

        actions.addBelow = {
            store.beginAdding(selectedID.map(OutlineAddPlacement.below) ?? .root)
        }
        if let selectedID {
            actions.addAbove = {
                let newID = store.insertAbove(referenceID: selectedID, title: "New Item", undoManager: undoManager)
                store.beginEditing(itemID: newID)
            }
            actions.addChild = {
                store.beginAdding(.child(selectedID))
            }
            actions.indent = {
                store.indent(itemID: selectedID, undoManager: undoManager)
            }
            actions.outdent = {
                store.outdent(itemID: selectedID, undoManager: undoManager)
            }
            actions.moveUp = {
                store.moveUp(itemID: selectedID, undoManager: undoManager)
            }
            actions.moveDown = {
                store.moveDown(itemID: selectedID, undoManager: undoManager)
            }
        }
        if !store.selectedItemIDs.isEmpty {
            actions.delete = {
                store.pendingDeletionIDs = store.selectedItemIDs
            }
        }

        return actions
    }

    private func singleSelectedItemID(in store: ListStore) -> UUID? {
        guard store.selectedItemIDs.count == 1 else { return nil }
        return store.selectedItemIDs.first
    }

    private var deletionDialogTitle: String {
        guard let ids = listStore?.pendingDeletionIDs, ids.count > 1 else {
            return "Delete Item?"
        }
        return "Delete \(ids.count) Items?"
    }

    private var deletionDialogMessage: String {
        guard let store = listStore, let ids = store.pendingDeletionIDs else { return "" }
        if ids.count == 1, let id = ids.first,
           let item = store.items.first(where: { $0.id == id }) {
            return "“\(item.title)” and all of its child items will be deleted."
        }
        return "\(ids.count) selected items and any child items will be deleted."
    }

    private var isConfirmingDeletion: Binding<Bool> {
        Binding(
            get: { listStore?.pendingDeletionIDs != nil },
            set: { if !$0 { listStore?.pendingDeletionIDs = nil } }
        )
    }
}
