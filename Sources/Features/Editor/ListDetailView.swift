import SwiftUI
import Domain
import Combine

struct ListDetailView: View {
    let listID: UUID
    @Environment(AppStore.self) private var appStore
    @State private var listStore: ListStore?
    @State private var showInspector = false
    @State private var showingResetAllChecksConfirmation = false
    @State private var listBeingEdited: ListItem?
    @State private var canUndo = false
    @State private var canRedo = false
    @State private var undoAvailabilityRefreshGate = UndoAvailabilityRefreshGate()
    @AppStorage(ListsurfSettingsKey.notesPreviewLineLimit) private var notePreviewLineCount = 1
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Group {
            if let store = listStore {
                OutlineEditorView(
                    store: store,
                    showInspector: $showInspector,
                    notePreviewLineCount: max(0, notePreviewLineCount)
                )
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
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerCheckpoint)) { notification in
            refreshUndoAvailability(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidUndoChange)) { notification in
            refreshUndoAvailability(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidRedoChange)) { notification in
            refreshUndoAvailability(from: notification)
        }
        #endif
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
            "Reset Branch?",
            isPresented: isConfirmingBranchReset,
            titleVisibility: .visible
        ) {
            if let store = listStore, let id = store.pendingBranchResetID {
                Button("Reset Branch", role: .destructive) {
                    store.resetSubtree(itemID: id, undoManager: undoManager)
                    store.pendingBranchResetID = nil
                }
            }
        } message: {
            if let store = listStore, let id = store.pendingBranchResetID,
               let item = store.items.first(where: { $0.id == id }) {
                Text("“\(item.title)” and all of its child items will be unchecked.")
            }
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
            refreshUndoAvailability()
            let store = appStore.makeListStore(for: listID)
            listStore = store
            await store.load()
            refreshUndoAvailability()
        }
        .onDisappear {
            listStore?.teardownUndo(undoManager)
            refreshUndoAvailability()
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
            if listStore != nil {
                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "info.circle")
                }
                .accessibilityIdentifier("editor.inspector")
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
                #if os(iOS)
                Button {
                    undoManager?.undo()
                    refreshUndoAvailability()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!canUndo)
                .accessibilityIdentifier("editor.undo")

                Button {
                    undoManager?.redo()
                    refreshUndoAvailability()
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(!canRedo)
                .accessibilityIdentifier("editor.redo")
                #endif

                editorToolbar(store)
            }
        }
    }

    @ViewBuilder
    private func editorToolbar(_ store: ListStore) -> some View {
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

        Picker("Filter", selection: filterBinding(store)) {
            ForEach(ListStore.CheckFilter.allCases, id: \.self) { filter in
                Text(filter.rawValue).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("editor.filter")
        .help("Filter items by check state")

        let progress = store.progress
        Text("\(progress.checked)/\(progress.total)")
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("editor.progress")
            .help("Items checked / total")

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
            Label("Reset All Checks", systemImage: "arrow.counterclockwise")
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

    private func refreshUndoAvailability(from notification: Notification? = nil) {
        if let notification,
           let notificationManager = notification.object as? UndoManager,
           notificationManager !== undoManager {
            return
        }
        if notification?.name == .NSUndoManagerCheckpoint,
           undoAvailabilityRefreshGate.ignoresNextCheckpoint {
            undoAvailabilityRefreshGate.ignoresNextCheckpoint = false
            return
        }

        guard let undoManager else {
            if canUndo { canUndo = false }
            if canRedo { canRedo = false }
            return
        }

        // Accessing availability emits NSUndoManagerCheckpoint. Mark that
        // notification as self-generated so the observer does not spin.
        undoAvailabilityRefreshGate.ignoresNextCheckpoint = true
        let nextCanUndo = undoManager.canUndo
        let nextCanRedo = undoManager.canRedo
        if canUndo != nextCanUndo { canUndo = nextCanUndo }
        if canRedo != nextCanRedo { canRedo = nextCanRedo }
    }

    private var focusedCommandActions: ListsurfListCommandActions {
        guard let store = listStore else { return ListsurfListCommandActions() }
        var actions = ListsurfListCommandActions()

        actions.toggleInspector = { showInspector.toggle() }
        actions.expandAll = { store.expandAll() }
        actions.collapseAll = { store.collapseAll() }

        // While the user is typing (rename or add field), structural
        // commands must be disabled: an enabled menu equivalent would fire
        // instead of, or on top of, the text field's own handling.
        guard !store.isTextInputActive else { return actions }

        // Presence (nil vs non-nil) still gates menu enablement at publish
        // time — a republication lag can only mis-gray a menu item
        // momentarily, never mis-target an action.
        let selectedID = singleSelectedItemID(in: store)

        // B3 fix (spec §2): every closure below reads selection LIVE at
        // invocation instead of closing over a value captured at publish
        // time — `focusedSceneValue` republication lags, so a by-value
        // capture of `selectedID` could act on a stale selection (⌘[/⌘]
        // acting on the last-added row instead of the clicked one).
        actions.addBelow = {
            guard !store.isTextInputActive else { return }
            let liveID = singleSelectedItemID(in: store)
            store.beginAdding(liveID.map(OutlineAddPlacement.below) ?? .root)
        }
        if selectedID != nil {
            actions.addAbove = {
                guard !store.isTextInputActive, let liveID = singleSelectedItemID(in: store) else { return }
                let newID = store.insertAbove(referenceID: liveID, title: "New Item", undoManager: undoManager)
                store.beginEditing(itemID: newID)
            }
            actions.addChild = {
                guard !store.isTextInputActive, let liveID = singleSelectedItemID(in: store) else { return }
                store.beginAdding(.child(liveID))
            }
            actions.indent = {
                guard !store.isTextInputActive, let liveID = singleSelectedItemID(in: store) else { return }
                store.indent(itemID: liveID, undoManager: undoManager)
            }
            actions.outdent = {
                guard !store.isTextInputActive, let liveID = singleSelectedItemID(in: store) else { return }
                store.outdent(itemID: liveID, undoManager: undoManager)
            }
            actions.moveUp = {
                guard !store.isTextInputActive, let liveID = singleSelectedItemID(in: store) else { return }
                store.moveUp(itemID: liveID, undoManager: undoManager)
            }
            actions.moveDown = {
                guard !store.isTextInputActive, let liveID = singleSelectedItemID(in: store) else { return }
                store.moveDown(itemID: liveID, undoManager: undoManager)
            }
        }
        if !store.selectedItemIDs.isEmpty {
            actions.delete = {
                guard !store.isTextInputActive, !store.selectedItemIDs.isEmpty else { return }
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

    private var isConfirmingBranchReset: Binding<Bool> {
        Binding(
            get: { listStore?.pendingBranchResetID != nil },
            set: { if !$0 { listStore?.pendingBranchResetID = nil } }
        )
    }
}

private final class UndoAvailabilityRefreshGate {
    var ignoresNextCheckpoint = false
}
