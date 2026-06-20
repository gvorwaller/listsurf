import SwiftUI
import Domain

struct ListDetailView: View {
    let listID: UUID
    @Environment(AppStore.self) private var appStore
    @State private var listStore: ListStore?
    @State private var showInspector = false
    @State private var inspectorItemID: UUID?
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Group {
            if let store = listStore {
                if store.isCheckMode {
                    CheckModeView(store: store)
                } else {
                    OutlineEditorView(store: store, inspectorItemID: $inspectorItemID)
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
        .task(id: listID) {
            let store = appStore.makeListStore(for: listID)
            listStore = store
            await store.load()
        }
        .searchable(text: searchBinding, prompt: "Search Items")
    }

    private var searchBinding: Binding<String> {
        Binding(
            get: { listStore?.searchText ?? "" },
            set: { listStore?.searchText = $0 }
        )
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

                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "info.circle")
                }
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
            Task { await store.addItem(title: "", undoManager: undoManager) }
        } label: {
            Label("Add Item", systemImage: "plus")
        }

        Button {
            store.expandAll()
        } label: {
            Label("Expand All", systemImage: "arrow.down.right.and.arrow.up.left")
        }

        Button {
            store.collapseAll()
        } label: {
            Label("Collapse All", systemImage: "arrow.up.left.and.arrow.down.right")
        }
    }

    @ViewBuilder
    private func checkModeToolbar(_ store: ListStore) -> some View {
        let progress = store.progress
        Text("\(progress.checked)/\(progress.total)")
            .monospacedDigit()
            .foregroundStyle(.secondary)

        Picker("Filter", selection: filterBinding(store)) {
            ForEach(ListStore.CheckFilter.allCases, id: \.self) { filter in
                Text(filter.rawValue).tag(filter)
            }
        }
        .pickerStyle(.segmented)

        Button {
            Task { await store.resetAllChecks(undoManager: undoManager) }
        } label: {
            Label("Reset All", systemImage: "arrow.counterclockwise")
        }
    }

    private func filterBinding(_ store: ListStore) -> Binding<ListStore.CheckFilter> {
        Binding(
            get: { store.checkFilter },
            set: { store.checkFilter = $0 }
        )
    }
}
