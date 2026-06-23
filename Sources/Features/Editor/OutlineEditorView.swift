import SwiftUI
import Domain

enum OutlineAddPlacement: Equatable {
    case root
    case below(UUID)
    case child(UUID)
}

struct OutlineAddRequest: Equatable {
    let id = UUID()
    let placement: OutlineAddPlacement

    init(afterID: UUID?) {
        placement = afterID.map(OutlineAddPlacement.below) ?? .root
    }

    init(childOfID: UUID) {
        placement = .child(childOfID)
    }
}

struct OutlineEditorView: View {
    @Bindable var store: ListStore
    @Binding var inspectorItemID: UUID?
    @Binding var addRequest: OutlineAddRequest?
    @Environment(\.undoManager) private var undoManager
    @State private var editingItemID: UUID?
    @State private var editingText = ""
    @State private var showingAddField = false
    @State private var addPlacement: OutlineAddPlacement = .root
    @State private var newItemText = ""
    @State private var itemPendingDeletion: ItemDeletionConfirmation?
    @FocusState private var addFieldFocused: Bool

    var body: some View {
        #if os(iOS)
        editorContent
            .safeAreaInset(edge: .bottom, spacing: 0) {
                selectedItemActionBar
            }
            .modifier(KeyboardAccessoryModifier(
                isVisible: showingAddField || editingItemID != nil,
                onCancel: cancelTextEntry,
                onDone: commitTextEntry,
                onAddBelow: { selectedRow.map { beginAdding(.below($0.id)) } },
                onAddChild: { selectedRow.map { beginAdding(.child($0.id)) } },
                onIndent: { selectedRow.map { store.indent(itemID: $0.id, undoManager: undoManager) } },
                onOutdent: { selectedRow.map { store.outdent(itemID: $0.id, undoManager: undoManager) } },
                hasSelectedItem: selectedRow != nil
            ))
        #else
        editorContent
        #endif
    }

    private var editorContent: some View {
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
        .onChange(of: addRequest) { _, newValue in
            if let newValue {
                addRequest = nil
                beginAdding(newValue.placement)
            }
        }
        .confirmationDialog(
            "Delete Item?",
            isPresented: isConfirmingItemDeletion,
            titleVisibility: .visible
        ) {
            if let confirmation = itemPendingDeletion {
                Button("Delete Item", role: .destructive) {
                    store.deleteItem(id: confirmation.id, undoManager: undoManager)
                }
            }
        } message: {
            if let confirmation = itemPendingDeletion {
                Text("“\(confirmation.title)” and all of its child items will be deleted.")
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
                beginAdding(.root)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("editor.addFirstItem")
        }
    }

    private var outlineList: some View {
        List(selection: $store.selectedItemIDs) {
            ForEach(store.filteredRows) { row in
                HStack(spacing: 8) {
                    OutlineRowView(
                        row: row,
                        isSelected: store.selectedItemIDs.contains(row.id),
                        isEditing: editingItemID == row.id,
                        editingText: editingItemID == row.id ? $editingText : .constant(""),
                        onToggleExpand: { store.toggleExpanded(row.id) },
                        onCommitEdit: { commitEdit(row.id) },
                        onStartEdit: { startEdit(row) },
                        onSelect: { select(row) }
                    )

                    Menu {
                        rowContextMenu(row)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .imageScale(.large)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Actions for \(row.item.title)")
                    .accessibilityIdentifier("editor.rowActions")

                    Button(role: .destructive) {
                        requestDelete(row)
                    } label: {
                        Image(systemName: "trash")
                            .imageScale(.large)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Delete \(row.item.title)")
                    .accessibilityIdentifier("editor.deleteItem")
                }
                .contentShape(Rectangle())
                .onTapGesture { select(row) }
                .tag(row.id)
                .listRowInsets(EdgeInsets(
                    top: 4,
                    leading: 16 + Double(row.depth) * 20,
                    bottom: 4,
                    trailing: 16
                ))
                .contextMenu { rowContextMenu(row) }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        requestDelete(row)
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

    #if os(iOS)
    @ViewBuilder
    private var selectedItemActionBar: some View {
        if let row = selectedRow, !showingAddField {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Button {
                        beginAdding(.below(row.id))
                    } label: {
                        Label("Below", systemImage: "plus")
                    }
                    .accessibilityIdentifier("editor.ios.addBelow")

                    Button {
                        beginAdding(.child(row.id))
                    } label: {
                        Label("Child", systemImage: "arrow.turn.down.right")
                    }
                    .accessibilityIdentifier("editor.ios.addChild")

                    Button {
                        store.indent(itemID: row.id, undoManager: undoManager)
                    } label: {
                        Label("Indent", systemImage: "increase.indent")
                    }
                    .accessibilityIdentifier("editor.ios.indent")

                    Button {
                        store.outdent(itemID: row.id, undoManager: undoManager)
                    } label: {
                        Label("Outdent", systemImage: "decrease.indent")
                    }
                    .accessibilityIdentifier("editor.ios.outdent")

                    Button {
                        store.moveUp(itemID: row.id, undoManager: undoManager)
                    } label: {
                        Label("Up", systemImage: "arrow.up")
                    }
                    .accessibilityIdentifier("editor.ios.moveUp")

                    Button {
                        store.moveDown(itemID: row.id, undoManager: undoManager)
                    } label: {
                        Label("Down", systemImage: "arrow.down")
                    }
                    .accessibilityIdentifier("editor.ios.moveDown")

                    Button {
                        inspectorItemID = row.id
                    } label: {
                        Label("Details", systemImage: "info.circle")
                    }
                    .accessibilityIdentifier("editor.ios.details")

                    Button(role: .destructive) {
                        requestDelete(row)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .accessibilityIdentifier("editor.ios.delete")
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(.regularMaterial)
            .overlay(alignment: .top) { Divider() }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("editor.ios.actionBar")
        }
    }
    #endif

    private var addItemField: some View {
        HStack {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.green)
            TextField(addPlaceholder, text: $newItemText)
                .accessibilityIdentifier("editor.newItem")
                .focused($addFieldFocused)
                .onSubmit { commitNewItem() }
                .onKeyPress(.escape) {
                    cancelAdding()
                    return .handled
                }
        }
    }

    private func select(_ row: FlatRow) {
        addFieldFocused = false
        if showingAddField && newItemText.isEmpty {
            cancelAdding()
        }
        store.selectedItemIDs = [row.id]
        inspectorItemID = row.id
    }

    private func beginAdding(_ placement: OutlineAddPlacement) {
        addPlacement = placement
        newItemText = ""
        showingAddField = true
        addFieldFocused = true
    }

    private func cancelAdding() {
        showingAddField = false
        addPlacement = .root
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
        switch addPlacement {
        case .root:
            store.addItem(title: text, undoManager: undoManager)
        case .below(let itemID):
            store.addItem(title: text, afterItemID: itemID, undoManager: undoManager)
        case .child(let itemID):
            store.addChild(parentID: itemID, title: text, undoManager: undoManager)
        }
        newItemText = ""
        addFieldFocused = true
    }

    @ViewBuilder
    private func rowContextMenu(_ row: FlatRow) -> some View {
        Button {
            beginAdding(.below(row.id))
        } label: {
            Label("Add Below", systemImage: "plus")
        }

        Button {
            store.insertAbove(referenceID: row.id, title: "New Item", undoManager: undoManager)
        } label: {
            Label("Add Above", systemImage: "arrow.up")
        }

        Button {
            beginAdding(.child(row.id))
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
            requestDelete(row)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func requestDelete(_ row: FlatRow) {
        itemPendingDeletion = ItemDeletionConfirmation(row)
    }

    private var isConfirmingItemDeletion: Binding<Bool> {
        Binding(
            get: { itemPendingDeletion != nil },
            set: { if !$0 { itemPendingDeletion = nil } }
        )
    }

    private var selectedRow: FlatRow? {
        guard store.selectedItemIDs.count == 1,
              let selectedID = store.selectedItemIDs.first else {
            return nil
        }
        return store.flatRows.first { $0.id == selectedID }
    }

    private var addPlaceholder: String {
        switch addPlacement {
        case .root:
            "New item"
        case .below:
            "New item below"
        case .child:
            "New child item"
        }
    }

    private func cancelTextEntry() {
        if showingAddField {
            cancelAdding()
        }
        if editingItemID != nil {
            editingItemID = nil
            editingText = ""
        }
    }

    private func commitTextEntry() {
        if let editingItemID {
            commitEdit(editingItemID)
        } else if showingAddField {
            commitNewItem()
        }
    }
}

private struct KeyboardAccessoryModifier: ViewModifier {
    let isVisible: Bool
    let onCancel: () -> Void
    let onDone: () -> Void
    let onAddBelow: () -> Void
    let onAddChild: () -> Void
    let onIndent: () -> Void
    let onOutdent: () -> Void
    let hasSelectedItem: Bool

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    if isVisible {
                        Button("Cancel", action: onCancel)
                            .accessibilityIdentifier("editor.keyboard.cancel")

                        Spacer()

                        Button("Below", action: onAddBelow)
                            .disabled(!hasSelectedItem)
                            .accessibilityIdentifier("editor.keyboard.addBelow")

                        Button("Child", action: onAddChild)
                            .disabled(!hasSelectedItem)
                            .accessibilityIdentifier("editor.keyboard.addChild")

                        Button {
                            onIndent()
                        } label: {
                            Image(systemName: "increase.indent")
                        }
                        .disabled(!hasSelectedItem)
                        .accessibilityIdentifier("editor.keyboard.indent")

                        Button {
                            onOutdent()
                        } label: {
                            Image(systemName: "decrease.indent")
                        }
                        .disabled(!hasSelectedItem)
                        .accessibilityIdentifier("editor.keyboard.outdent")

                        Button("Done", action: onDone)
                            .bold()
                            .accessibilityIdentifier("editor.keyboard.done")
                    }
                }
            }
        #else
        content
        #endif
    }
}

private struct ItemDeletionConfirmation: Identifiable {
    let id: UUID
    let title: String

    init(_ row: FlatRow) {
        id = row.id
        title = row.item.title
    }
}

#if DEBUG
private struct OutlineEditorPreview: View {
    @State private var inspectorItemID: UUID?
    @State private var addRequest: OutlineAddRequest?
    @State private var store = PreviewFixtures.listStore()

    var body: some View {
        OutlineEditorView(
            store: store,
            inspectorItemID: $inspectorItemID,
            addRequest: $addRequest
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
