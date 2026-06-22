import SwiftUI
import Domain

struct ListDetailView: View {
    let listID: UUID
    @Environment(AppStore.self) private var appStore
    @State private var listStore: ListStore?
    @State private var showInspector = false
    @State private var inspectorItemID: UUID?
    @State private var addRequest: OutlineAddRequest?
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Group {
            if let store = listStore {
                if store.isCheckMode {
                    CheckModeView(store: store)
                } else {
                    OutlineEditorView(
                        store: store,
                        inspectorItemID: $inspectorItemID,
                        addRequest: $addRequest
                    )
                }
            } else {
                ProgressView()
            }
        }
        .inspector(isPresented: $showInspector) {
            if let store = listStore {
                InspectorView(store: store, itemID: inspectorItemID)
                    .inspectorColumnWidth(min: 250, ideal: 300, max: 400)
            }
        }
        .navigationTitle(listStore?.list?.title ?? "")
        .toolbar { toolbarContent }
        .focusedSceneValue(\.listsurfListCommands, focusedCommandActions)
        .task(id: listID) {
            let store = appStore.makeListStore(for: listID)
            listStore = store
            await store.load()
        }
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
            requestAdd(afterID: nil)
        } label: {
            Label("Add Item", systemImage: "plus")
        }
        .accessibilityIdentifier("editor.addItem")
        .help("Add a new item")

        Button {
            store.expandAll()
        } label: {
            Label("Expand All", systemImage: "arrow.down.right.and.arrow.up.left")
        }
        .help("Expand all branches")

        Button {
            store.collapseAll()
        } label: {
            Label("Collapse All", systemImage: "arrow.up.left.and.arrow.down.right")
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
            store.resetAllChecks(undoManager: undoManager)
        } label: {
            Label("Reset All", systemImage: "arrow.counterclockwise")
        }
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
        let selectedID = singleSelectedItemID(in: store)
        let hasSelection = !store.selectedItemIDs.isEmpty
        var actions = ListsurfListCommandActions()

        actions.toggleCheckMode = { store.isCheckMode.toggle() }
        actions.toggleInspector = { showInspector.toggle() }
        actions.expandAll = { store.expandAll() }
        actions.collapseAll = { store.collapseAll() }

        guard !store.isCheckMode else { return actions }

        actions.addBelow = { requestAdd(afterID: selectedID) }
        if let selectedID {
            actions.addAbove = {
                store.insertAbove(referenceID: selectedID, title: "New Item", undoManager: undoManager)
            }
            actions.addChild = {
                store.addChild(parentID: selectedID, title: "New Item", undoManager: undoManager)
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
        if hasSelection {
            actions.delete = {
                store.deleteSelected(undoManager: undoManager)
            }
        }

        return actions
    }

    private func singleSelectedItemID(in store: ListStore) -> UUID? {
        guard store.selectedItemIDs.count == 1 else { return nil }
        return store.selectedItemIDs.first
    }

    private func requestAdd(afterID: UUID?) {
        addRequest = OutlineAddRequest(afterID: afterID)
    }
}
