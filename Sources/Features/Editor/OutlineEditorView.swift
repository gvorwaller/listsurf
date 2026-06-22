import SwiftUI
import Domain

struct OutlineEditorView: View {
    @Bindable var store: ListStore
    @Binding var inspectorItemID: UUID?
    @Binding var triggerAddItem: Bool
    @Environment(\.undoManager) private var undoManager
    @State private var editingItemID: UUID?
    @State private var editingText = ""
    @State private var showingAddField = false
    @State private var addingAfterID: UUID?
    @State private var newItemText = ""
    @FocusState private var addFieldFocused: Bool

    var body: some View {
        Group {
            if store.filteredRows.isEmpty && !showingAddField && store.searchText.isEmpty {
                emptyState
            } else if store.filteredRows.isEmpty && !showingAddField {
                ContentUnavailableView.search(text: store.searchText)
            } else {
                outlineList
            }
        }
        .outlineSearch(text: $store.searchText)
        .onChange(of: triggerAddItem) { _, newValue in
            if newValue {
                triggerAddItem = false
                beginAdding(afterID: nil)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Items", systemImage: "text.badge.plus")
        } description: {
            Text("Add your first item, or paste multiple lines.")
        } actions: {
            Button("Add Item") {
                beginAdding(afterID: nil)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("editor.addFirstItem")
        }
    }

    private var outlineList: some View {
        List(selection: $store.selectedItemIDs) {
            ForEach(store.filteredRows) { row in
                OutlineRowView(
                    row: row,
                    isEditing: editingItemID == row.id,
                    editingText: editingItemID == row.id ? $editingText : .constant(""),
                    onToggleExpand: { store.toggleExpanded(row.id) },
                    onCommitEdit: { commitEdit(row.id) },
                    onStartEdit: { startEdit(row) },
                    onSelect: { inspectorItemID = row.id }
                )
                .tag(row.id)
                .listRowInsets(EdgeInsets(
                    top: 4,
                    leading: 16 + Double(row.depth) * 20,
                    bottom: 4,
                    trailing: 16
                ))
                .contextMenu { rowContextMenu(row) }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        store.deleteItem(id: row.id, undoManager: undoManager)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }

            if showingAddField {
                addItemField
            }
        }
        .listStyle(.sidebar)
        .animation(.default, value: store.flatRows.map(\.id))
    }

    private var addItemField: some View {
        HStack {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.green)
            TextField("New item", text: $newItemText)
                .accessibilityIdentifier("editor.newItem")
                .focused($addFieldFocused)
                .onSubmit { commitNewItem() }
                .onKeyPress(.escape) {
                    cancelAdding()
                    return .handled
                }
        }
    }

    private func beginAdding(afterID: UUID?) {
        addingAfterID = afterID
        newItemText = ""
        showingAddField = true
        addFieldFocused = true
    }

    private func cancelAdding() {
        showingAddField = false
        addingAfterID = nil
        newItemText = ""
    }

    private func startEdit(_ row: FlatRow) {
        editingItemID = row.id
        editingText = row.item.title
    }

    private func commitEdit(_ id: UUID) {
        let text = editingText.trimmingCharacters(in: .whitespaces)
        editingItemID = nil
        guard !text.isEmpty else { return }
        store.updateItemTitle(id: id, title: text, undoManager: undoManager)
    }

    private func commitNewItem() {
        let text = newItemText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            cancelAdding()
            return
        }
        store.addItem(title: text, afterItemID: addingAfterID, undoManager: undoManager)
        newItemText = ""
        addFieldFocused = true
    }

    @ViewBuilder
    private func rowContextMenu(_ row: FlatRow) -> some View {
        Button {
            beginAdding(afterID: row.id)
        } label: {
            Label("Add Below", systemImage: "plus")
        }

        Button {
            store.insertAbove(referenceID: row.id, title: "New Item", undoManager: undoManager)
        } label: {
            Label("Add Above", systemImage: "arrow.up")
        }

        Button {
            store.addChild(parentID: row.id, title: "New Item", undoManager: undoManager)
        } label: {
            Label("Add Child", systemImage: "arrow.turn.down.right")
        }

        Divider()

        Button {
            store.indent(itemID: row.id, undoManager: undoManager)
        } label: {
            Label("Indent", systemImage: "increase.indent")
        }

        Button {
            store.outdent(itemID: row.id, undoManager: undoManager)
        } label: {
            Label("Outdent", systemImage: "decrease.indent")
        }

        Divider()

        Button {
            store.moveUp(itemID: row.id, undoManager: undoManager)
        } label: {
            Label("Move Up", systemImage: "arrow.up")
        }

        Button {
            store.moveDown(itemID: row.id, undoManager: undoManager)
        } label: {
            Label("Move Down", systemImage: "arrow.down")
        }

        Divider()

        Button { startEdit(row) } label: {
            Label("Rename", systemImage: "pencil")
        }

        Button { inspectorItemID = row.id } label: {
            Label("Details", systemImage: "info.circle")
        }

        Divider()

        Button(role: .destructive) {
            store.deleteItem(id: row.id, undoManager: undoManager)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

#if DEBUG
private struct OutlineEditorPreview: View {
    @State private var inspectorItemID: UUID?
    @State private var triggerAddItem = false
    @State private var store = PreviewFixtures.listStore()

    var body: some View {
        OutlineEditorView(
            store: store,
            inspectorItemID: $inspectorItemID,
            triggerAddItem: $triggerAddItem
        )
    }
}

#Preview("Outline Editor") {
    OutlineEditorPreview()
}
#endif


private extension View {
    @ViewBuilder
    func outlineSearch(text: Binding<String>) -> some View {
        #if os(macOS)
        self
        #else
        searchable(text: text, prompt: "Search Items")
        #endif
    }
}
