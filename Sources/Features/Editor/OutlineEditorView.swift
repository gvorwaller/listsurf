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
    @Binding var showInspector: Bool
    @Binding var addRequest: OutlineAddRequest?
    let notePreviewLineCount: Int
    @Environment(\.undoManager) private var undoManager
    @State private var editingItemID: UUID?
    @State private var editingText = ""
    @State private var showingAddField = false
    @State private var addPlacement: OutlineAddPlacement = .root
    @State private var newItemText = ""
    @State private var itemPendingDeletion: ItemDeletionConfirmation?
    @FocusState private var addFieldFocused: Bool
    @FocusState private var editorFocused: Bool

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
            .focusable()
            .focused($editorFocused)
            .background {
                MacOutlineTabKeyMonitor(
                    isOutlineActive: editorFocused && editingItemID == nil && !showingAddField,
                    isAddFieldActive: showingAddField && addFieldFocused,
                    onTab: { isShiftPressed in
                        handleTabKey(isShiftPressed: isShiftPressed)
                    },
                    onCommitAddField: {
                        commitNewItem()
                    }
                )
                .frame(width: 0, height: 0)
            }
            .onAppear { editorFocused = true }
            .onChange(of: store.selectedItemIDs) { _, _ in
                if editingItemID == nil && !showingAddField {
                    editorFocused = true
                }
            }
            .onKeyPress(.upArrow) {
                moveSelection(delta: -1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                moveSelection(delta: 1)
                return .handled
            }
            .onKeyPress(.return, phases: .down) { keyPress in
                handleReturnKey(modifiers: keyPress.modifiers)
                return .handled
            }
            .onKeyPress(.tab, phases: .down) { keyPress in
                handleTabKey(isShiftPressed: keyPress.modifiers.contains(.shift))
                return .handled
            }
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
                .keyboardShortcut(.defaultAction)

                Button("Cancel", role: .cancel) {
                    itemPendingDeletion = nil
                }
                .keyboardShortcut(.cancelAction)
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
                        notePreviewLineCount: notePreviewLineCount,
                        editingText: editingItemID == row.id ? $editingText : .constant(""),
                        onToggleExpand: { store.toggleExpanded(row.id) },
                        onCommitEdit: { commitEdit(row.id) },
                        onShowDetails: { showDetails(for: row) },
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

                if let addFieldDepth = addFieldPlacement(after: row) {
                    addItemField(depth: addFieldDepth)
                }
            }

            if showingAddField, addPlacement == .root {
                addItemField(depth: 0)
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
                        showDetails(for: row)
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

    private func addItemField(depth: Int) -> some View {
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
        .listRowInsets(EdgeInsets(
            top: 4,
            leading: 16 + Double(depth) * 20,
            bottom: 4,
            trailing: 16
        ))
    }

    private func addFieldPlacement(after row: FlatRow) -> Int? {
        guard showingAddField else { return nil }
        switch addPlacement {
        case .root:
            return nil
        case .below(let itemID):
            return row.id == itemID ? row.depth : nil
        case .child(let itemID):
            return row.id == itemID ? row.depth + 1 : nil
        }
    }

    private func select(_ row: FlatRow) {
        addFieldFocused = false
        if showingAddField && newItemText.isEmpty {
            cancelAdding()
        }
        store.selectedItemIDs = [row.id]
        inspectorItemID = row.id
        editorFocused = true
    }

    private func beginAdding(_ placement: OutlineAddPlacement) {
        addPlacement = placement
        newItemText = ""
        showingAddField = true
        if case .child(let itemID) = placement {
            store.expandedIDs.insert(itemID)
        }
        addFieldFocused = true
    }

    private func beginAddingAndFocus(_ placement: OutlineAddPlacement) {
        beginAdding(placement)
        Task { @MainActor in
            addFieldFocused = true
        }
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
        let newID: UUID
        switch addPlacement {
        case .root:
            newID = store.addItem(title: text, undoManager: undoManager)
        case .below(let itemID):
            newID = store.addItem(title: text, afterItemID: itemID, undoManager: undoManager)
        case .child(let itemID):
            newID = store.addChild(parentID: itemID, title: text, undoManager: undoManager)
        }
        store.selectedItemIDs = [newID]
        inspectorItemID = newID
        addPlacement = .below(newID)
        newItemText = ""
        Task { @MainActor in
            addFieldFocused = true
        }
    }

    @ViewBuilder
    private func rowContextMenu(_ row: FlatRow) -> some View {
        Button {
            beginAddingAndFocus(.below(row.id))
        } label: {
            Label("Add Below", systemImage: "plus")
        }
        .keyboardShortcut(.return, modifiers: [])

        Button {
            store.insertAbove(referenceID: row.id, title: "New Item", undoManager: undoManager)
        } label: {
            Label("Add Above", systemImage: "arrow.up")
        }
        .keyboardShortcut(.return, modifiers: [.shift])

        Button {
            beginAddingAndFocus(.child(row.id))
        } label: {
            Label("Add Child", systemImage: "arrow.turn.down.right")
        }
        .keyboardShortcut(.return, modifiers: [.command])

        Divider()

        Button {
            store.indent(itemID: row.id, undoManager: undoManager)
        } label: {
            Label("Indent", systemImage: "increase.indent")
        }
        .keyboardShortcut(.tab, modifiers: [])

        Button {
            store.outdent(itemID: row.id, undoManager: undoManager)
        } label: {
            Label("Outdent", systemImage: "decrease.indent")
        }
        .keyboardShortcut(.tab, modifiers: [.shift])

        Divider()

        Button {
            store.moveUp(itemID: row.id, undoManager: undoManager)
        } label: {
            Label("Move Up", systemImage: "arrow.up")
        }
        .keyboardShortcut(.upArrow, modifiers: [.command, .option])

        Button {
            store.moveDown(itemID: row.id, undoManager: undoManager)
        } label: {
            Label("Move Down", systemImage: "arrow.down")
        }
        .keyboardShortcut(.downArrow, modifiers: [.command, .option])

        Divider()

        Button { startEdit(row) } label: {
            Label("Rename", systemImage: "pencil")
        }

        Button { showDetails(for: row) } label: {
            Label("Details", systemImage: "info.circle")
        }

        Divider()

        Button(role: .destructive) {
            requestDelete(row)
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .keyboardShortcut(.delete, modifiers: [.command])
    }

    private func showDetails(for row: FlatRow) {
        select(row)
        inspectorItemID = row.id
        showInspector = true
    }

    private func moveSelection(delta: Int) {
        let rows = store.filteredRows
        guard !rows.isEmpty else { return }

        if store.selectedItemIDs.count == 1,
           let selectedID = store.selectedItemIDs.first,
           let index = rows.firstIndex(where: { $0.id == selectedID }) {
            let nextIndex = min(max(index + delta, rows.startIndex), rows.index(before: rows.endIndex))
            select(rows[nextIndex])
        } else {
            select(delta < 0 ? rows[rows.index(before: rows.endIndex)] : rows[rows.startIndex])
        }
    }

    private func handleReturnKey(modifiers: EventModifiers) {
        guard editingItemID == nil else { return }
        if showingAddField {
            commitNewItem()
            return
        }
        if modifiers.contains(.command), let row = selectedRow {
            beginAddingAndFocus(.child(row.id))
        } else if modifiers.contains(.shift), let row = selectedRow {
            let newID = store.insertAbove(referenceID: row.id, title: "New Item", undoManager: undoManager)
            startEditingNewItem(id: newID)
        } else {
            beginAddingAndFocus(selectedRow.map { .below($0.id) } ?? .root)
        }
    }

    private func handleTabKey(isShiftPressed: Bool) {
        if showingAddField {
            commitNewItem()
            return
        }
        guard editingItemID == nil, let row = selectedRow else { return }
        if isShiftPressed {
            store.outdent(itemID: row.id, undoManager: undoManager)
        } else {
            store.indent(itemID: row.id, undoManager: undoManager)
        }
        store.selectedItemIDs = [row.id]
        inspectorItemID = row.id
        editorFocused = true
    }

    private func startEditingNewItem(id: UUID) {
        guard let row = store.filteredRows.first(where: { $0.id == id }) else { return }
        select(row)
        startEdit(row)
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
            showInspector: .constant(false),
            addRequest: $addRequest,
            notePreviewLineCount: 1
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
