import SwiftUI
import Domain

struct OutlineEditorView: View {
    @Bindable var store: ListStore
    @Binding var inspectorItemID: UUID?
    @Environment(\.undoManager) private var undoManager
    @State private var editingItemID: UUID?
    @State private var editingText = ""
    @State private var addingAfterID: UUID?
    @State private var newItemText = ""
    @FocusState private var addFieldFocused: Bool

    var body: some View {
        Group {
            if store.filteredRows.isEmpty && store.searchText.isEmpty {
                emptyState
            } else if store.filteredRows.isEmpty {
                ContentUnavailableView.search(text: store.searchText)
            } else {
                outlineList
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
                addingAfterID = nil
                newItemText = ""
                addFieldFocused = true
            }
            .buttonStyle(.borderedProminent)
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
                        Task { await store.deleteItem(id: row.id, undoManager: undoManager) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }

            if addingAfterID != nil || (store.filteredRows.isEmpty && store.searchText.isEmpty) {
                addItemField
            }
        }
        .listStyle(.sidebar)
        .animation(.default, value: store.flatRows.map(\.id))
    }

    private var addItemField: some View {
        HStack {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.secondary)
            TextField("New item", text: $newItemText)
                .focused($addFieldFocused)
                .onSubmit { commitNewItem() }
        }
        .padding(.leading, addingAfterID != nil ? 16 : 0)
    }

    private func startEdit(_ row: FlatRow) {
        editingItemID = row.id
        editingText = row.item.title
    }

    private func commitEdit(_ id: UUID) {
        let text = editingText.trimmingCharacters(in: .whitespaces)
        editingItemID = nil
        guard !text.isEmpty else { return }
        Task { await store.updateItemTitle(id: id, title: text, undoManager: undoManager) }
    }

    private func commitNewItem() {
        let text = newItemText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            addingAfterID = nil
            return
        }
        let afterID = addingAfterID
        newItemText = ""

        Task {
            await store.addItem(title: text, afterItemID: afterID, undoManager: undoManager)
            addFieldFocused = true
        }
    }

    @ViewBuilder
    private func rowContextMenu(_ row: FlatRow) -> some View {
        Button {
            addingAfterID = row.id
            newItemText = ""
            addFieldFocused = true
        } label: {
            Label("Add Below", systemImage: "plus")
        }

        Button {
            Task { await store.insertAbove(referenceID: row.id, title: "", undoManager: undoManager) }
        } label: {
            Label("Add Above", systemImage: "arrow.up")
        }

        Button {
            Task { await store.addChild(parentID: row.id, title: "", undoManager: undoManager) }
        } label: {
            Label("Add Child", systemImage: "arrow.turn.down.right")
        }

        Divider()

        Button {
            Task { await store.indent(itemID: row.id, undoManager: undoManager) }
        } label: {
            Label("Indent", systemImage: "increase.indent")
        }
        .keyboardShortcut(.tab, modifiers: [])

        Button {
            Task { await store.outdent(itemID: row.id, undoManager: undoManager) }
        } label: {
            Label("Outdent", systemImage: "decrease.indent")
        }

        Divider()

        Button {
            Task { await store.moveUp(itemID: row.id, undoManager: undoManager) }
        } label: {
            Label("Move Up", systemImage: "arrow.up")
        }

        Button {
            Task { await store.moveDown(itemID: row.id, undoManager: undoManager) }
        } label: {
            Label("Move Down", systemImage: "arrow.down")
        }

        Divider()

        Button {
            startEdit(row)
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Button {
            inspectorItemID = row.id
        } label: {
            Label("Details", systemImage: "info.circle")
        }

        Divider()

        Button(role: .destructive) {
            Task { await store.deleteItem(id: row.id, undoManager: undoManager) }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}
