import SwiftUI
import Domain
import Platform

struct OutlineEditorView: View {
    @Bindable var store: ListStore
    @Binding var showInspector: Bool
    let notePreviewLineCount: Int
    @Environment(\.undoManager) private var undoManager
    @State private var editingText = ""
    @State private var newItemText = ""
    @State private var selectionFromAddFlow: Set<UUID> = []
    @FocusState private var focus: EditorFocus?

    var body: some View {
        #if os(iOS)
        editorContent
            .safeAreaInset(edge: .bottom, spacing: 0) {
                selectedItemActionBar
            }
            .modifier(KeyboardAccessoryModifier(
                isVisible: store.isTextInputActive,
                onCancel: cancelTextEntry,
                onDone: commitTextEntry,
                // Below/Child commit the current draft first (as Help
                // documents), then continue relative to the fresh selection —
                // never silently relocate typed text to another placement.
                onAddBelow: {
                    commitTextEntry()
                    selectedRow.map { store.beginAdding(.below($0.id)) }
                },
                onAddChild: {
                    commitTextEntry()
                    selectedRow.map { store.beginAdding(.child($0.id)) }
                },
                onIndent: { selectedRow.map { store.indent(itemID: $0.id, undoManager: undoManager) } },
                onOutdent: { selectedRow.map { store.outdent(itemID: $0.id, undoManager: undoManager) } },
                onDismissKeyboard: { focus = nil },
                hasSelectedItem: selectedRow != nil
            ))
        #else
        // macOS keyboard ownership: the List (via native selection) handles
        // ↑/↓/⌘-click/⇧-click itself. The editor owns bare Return = rename
        // (or root-add with no selection), Tab/⇧Tab = indent/outdent, and
        // Space = toggle check. They must never be bare menu equivalents,
        // which would intercept typing in every text field in the window.
        editorContent
            .onKeyPress(.return, phases: .down) { keyPress in
                handleReturnKey(modifiers: keyPress.modifiers)
            }
            .onKeyPress(.space, phases: .down) { keyPress in
                handleSpaceKey(modifiers: keyPress.modifiers)
            }
            // Escape fallback: the add/rename fields own Escape while they
            // have focus, but focus assignment is task-deferred (Phase 1) —
            // an Escape landing in the deferral window used to vanish,
            // leaving the add flow armed and every menu command disabled
            // (Gate M1 diagnostic, 2026-07-14). This editor-level handler
            // catches what the fields don't.
            .onKeyPress(.escape, phases: .down) { _ in
                if store.addPlacement != nil {
                    cancelAdding()
                    return .handled
                }
                if store.editingItemID != nil {
                    editingText = ""
                    store.cancelEditing()
                    return .handled
                }
                if !store.selectedItemIDs.isEmpty {
                    store.selectedItemIDs = []
                    return .handled
                }
                return .ignored
            }
            // ⇧Tab arrives as a DIFFERENT key (backtab, U+0019) on macOS —
            // `.onKeyPress(.tab)` never fires for it, so focus traversal used
            // to win and dump the user in the sidebar search field (Gate M1
            // finding, 2026-07-14). Match both keys explicitly.
            .onKeyPress(phases: .down) { keyPress in
                let isBacktab = keyPress.characters == "\u{19}"
                guard keyPress.key == .tab || isBacktab else { return .ignored }
                return handleTabKey(isShiftPressed: isBacktab || keyPress.modifiers.contains(.shift))
            }
        #endif
    }

    private var editorContent: some View {
        Group {
            if store.filteredRows.isEmpty && store.addPlacement == nil && store.searchText.isEmpty {
                filteredEmptyState
            } else if store.filteredRows.isEmpty && store.addPlacement == nil {
                ContentUnavailableView.search(text: store.searchText)
            } else {
                outlineList
            }
        }
        .outlineSearch(text: $store.searchText)
        .onAppear {
            // If this view was recreated while a rename was already active
            // (the onChange below won't fire for an unchanged value), seed
            // the draft buffer from the item.
            if let editingID = store.editingItemID,
               let item = store.items.first(where: { $0.id == editingID }) {
                editingText = item.title
            }
        }
        .onChange(of: store.editingItemID) { oldValue, newValue in
            if let newValue, let item = store.items.first(where: { $0.id == newValue }) {
                editingText = item.title
                // Task-deferred: the assignment must land after the rename
                // field mounts (one runloop hop), not inside the transaction
                // that flips editingItemID (spec §2, B2/B4 fix).
                Task { @MainActor in focus = .rename(newValue) }
            } else if let oldValue, newValue == nil {
                // Editing was ended by something other than this view's own
                // commit/cancel (both consume the draft first) — e.g. the
                // store enforcing add/rename exclusivity. Commit the
                // stranded draft rather than silently discarding it.
                let text = editingText.trimmingCharacters(in: .whitespaces)
                editingText = ""
                if !text.isEmpty {
                    store.updateItemTitle(id: oldValue, title: text, undoManager: undoManager)
                }
            }
        }
        .onChange(of: store.addPlacement) { _, newValue in
            // Task-deferred for the same reason as above: nil→value always
            // fires (cancelAdding/dismissPendingAdd nil the placement before
            // any re-add), and the continuation flow's .below(a)→.below(b)
            // is a value change that also fires.
            if newValue != nil {
                Task { @MainActor in focus = .addField }
            }
        }
        .onChange(of: store.selectedItemIDs) { _, newValue in
            // Click-away commits an in-progress rename, Finder-style.
            if let editingID = store.editingItemID, !newValue.contains(editingID) {
                commitEdit(editingID)
            }
            // Any selection change — including deselecting by clicking empty
            // space — dismisses a pending add, except when the change is the
            // add flow itself selecting the item it just created.
            if store.addPlacement != nil, newValue != selectionFromAddFlow {
                dismissPendingAdd()
            }
        }
    }

    /// Filter-aware replacement for the mode-switch (spec §1.4): with items
    /// on the list but none visible under the active filter, the empty state
    /// explains why and offers a way back to All rather than looking like an
    /// empty list.
    @ViewBuilder
    private var filteredEmptyState: some View {
        if store.checkFilter == .remaining, !store.items.isEmpty {
            allDoneState
        } else if store.checkFilter == .completed, !store.items.isEmpty {
            noCompletedState
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Items", systemImage: "text.badge.plus")
        } description: {
            Text("Add your first item to start building this list.")
        } actions: {
            Button("Add Item") {
                store.beginAdding(.root)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("editor.addFirstItem")
        }
    }

    /// Carried from `CheckModeView.swift:46-58` (M5 unification).
    private var allDoneState: some View {
        let p = store.progress
        return ContentUnavailableView {
            Label("All Done!", systemImage: "checkmark.circle.fill")
        } description: {
            Text("\(p.checked)/\(p.total) items checked")
        } actions: {
            Button("Show All") {
                store.checkFilter = .all
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var noCompletedState: some View {
        ContentUnavailableView {
            Label("No Completed Items", systemImage: "circle")
        } actions: {
            Button("Show All") {
                store.checkFilter = .all
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var outlineList: some View {
        List(selection: $store.selectedItemIDs) {
            ForEach(store.filteredRows) { row in
                outlineRow(row)
                    // D5/D9/B6: the move trait MUST be applied here, on the
                    // ForEach's direct content — a `.moveDisabled` inside
                    // OutlineRowView (a nested child) is silently ignored by
                    // List (proven at Gate M1: multi-drags lifted). Hover
                    // gating is retired — see RowMoveDisabled's doc comment.
                    .modifier(RowMoveDisabled(blocked: dragBlocked(row)))
                    .tag(row.id)
                    .listRowInsets(EdgeInsets(
                        top: 4,
                        leading: 16 + Double(row.depth) * 20,
                        bottom: 4,
                        trailing: 16
                    ))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            store.pendingDeletionIDs = [row.id]
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }

                if let addFieldDepth = addFieldPlacement(after: row) {
                    addItemField(depth: addFieldDepth)
                }
            }
            .onMove { source, destination in
                store.moveRows(from: source, to: destination, undoManager: undoManager)
            }

            if shouldShowRootAddField {
                addItemField(depth: 0)
            }
        }
        .listStyle(.sidebar)
        .animation(.default, value: store.filteredRows.map(\.id))
        .modifier(OutlineContextMenuModifier(
            store: store,
            onShowDetails: showDetails(itemID:)
        ))
    }

    /// B6 fix (spec §2): the drag gate terms, all editor-computed so trait
    /// changes re-diff correctly (Rev 2.4). Phase 2 adds the filter term
    /// (`checkFilter != .all`): filtered rows are a non-contiguous excerpt
    /// of true sibling order, same rationale as the search guard.
    private func dragBlocked(_ row: FlatRow) -> Bool {
        if store.isTextInputActive || !store.searchText.isEmpty { return true }
        if store.checkFilter != .all { return true }
        if rowInMultiSelection(row) { return true }
        return false
    }

    private func rowInMultiSelection(_ row: FlatRow) -> Bool {
        store.selectedItemIDs.count > 1 && store.selectedItemIDs.contains(row.id)
    }

    private func outlineRow(_ row: FlatRow) -> some View {
        HStack(spacing: 8) {
            OutlineRowView(
                row: row,
                isEditing: store.editingItemID == row.id,
                notePreviewLineCount: notePreviewLineCount,
                editingText: store.editingItemID == row.id ? $editingText : .constant(""),
                focus: $focus,
                onToggleExpand: { store.toggleExpanded(row.id) },
                onToggleCheck: {
                    store.toggleCheck(itemID: row.id, undoManager: undoManager)
                    Haptics.checkToggle()
                },
                onCommitEdit: { commitEdit(row.id) },
                onCancelEdit: {
                    editingText = ""
                    store.cancelEditing()
                }
            )

            Menu {
                // Hints off: this menu targets the row, while the displayed
                // shortcuts act on the selection — they may differ.
                ItemActionsMenu(
                    store: store,
                    itemIDs: [row.id],
                    showsShortcutHints: false,
                    onShowDetails: showDetails(itemID:)
                )
            } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.large)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Actions for \(row.item.title)")
            .accessibilityIdentifier("editor.rowActions")

            Button(role: .destructive) {
                store.pendingDeletionIDs = [row.id]
            } label: {
                Image(systemName: "trash")
                    .imageScale(.large)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete \(row.item.title)")
            .accessibilityIdentifier("editor.deleteItem")
        }
        .contentShape(Rectangle())
        .modifier(RowSelectionTapModifier(
            rowID: row.id,
            onSelect: selectRow(_:),
            onDoubleTap: showDetails(itemID:)
        ))
    }

    #if os(iOS)
    @ViewBuilder
    private var selectedItemActionBar: some View {
        if let row = selectedRow, store.addPlacement == nil {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Button {
                        store.beginAdding(.below(row.id))
                    } label: {
                        Label("Below", systemImage: "plus")
                    }
                    .accessibilityIdentifier("editor.ios.addBelow")

                    Button {
                        store.beginAdding(.child(row.id))
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
                        showDetails(itemID: row.id)
                    } label: {
                        Label("Details", systemImage: "info.circle")
                    }
                    .accessibilityIdentifier("editor.ios.details")

                    Button(role: .destructive) {
                        store.pendingDeletionIDs = [row.id]
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
                .focused($focus, equals: .addField)
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
        switch store.addPlacement {
        case nil, .root:
            return nil
        case .below(let itemID):
            return row.id == itemID ? row.depth : nil
        case .child(let itemID):
            return row.id == itemID ? row.depth + 1 : nil
        }
    }

    /// The add field must always be reachable while adding is active. If its
    /// anchor row is hidden (search filter, collapsed ancestor), fall back to
    /// the root slot rather than leaving an active entry with no field.
    private var shouldShowRootAddField: Bool {
        switch store.addPlacement {
        case nil:
            return false
        case .root:
            return true
        case .below(let itemID), .child(let itemID):
            return !store.filteredRows.contains { $0.id == itemID }
        }
    }

    private func cancelAdding() {
        store.cancelAdding()
        newItemText = ""
    }

    private func commitEdit(_ id: UUID) {
        let text = editingText.trimmingCharacters(in: .whitespaces)
        editingText = ""
        store.cancelEditing()
        guard !text.isEmpty else { return }
        store.updateItemTitle(id: id, title: text, undoManager: undoManager)
    }

    private func commitNewItem() {
        guard let placement = store.addPlacement else { return }
        let text = newItemText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            cancelAdding()
            return
        }
        let newID = insertPendingItem(text, at: placement)
        // Keep the flow going: the next entry lands below the item just added.
        selectionFromAddFlow = [newID]
        store.beginAdding(.below(newID))
        newItemText = ""
    }

    /// Dismiss the add flow on click-away: commit typed text as a final
    /// item, or cancel an empty field — never leave a dangling entry field.
    private func dismissPendingAdd() {
        guard let placement = store.addPlacement else { return }
        let text = newItemText.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty {
            _ = insertPendingItem(text, at: placement)
        }
        cancelAdding()
    }

    private func insertPendingItem(_ text: String, at placement: OutlineAddPlacement) -> UUID {
        switch placement {
        case .root:
            store.addItem(title: text, undoManager: undoManager)
        case .below(let itemID):
            store.addItem(title: text, afterItemID: itemID, undoManager: undoManager)
        case .child(let itemID):
            store.addChild(parentID: itemID, title: text, undoManager: undoManager)
        }
    }

    /// A user tap always dismisses a pending add (commit-or-cancel), even if
    /// the tapped row is the item the add flow just created — the intent is
    /// "done entering, work with this row".
    private func selectRow(_ id: UUID) {
        if store.addPlacement != nil {
            dismissPendingAdd()
        }
        store.selectedItemIDs = [id]
    }

    private func showDetails(itemID: UUID) {
        store.selectedItemIDs = [itemID]
        showInspector = true
    }

    #if os(macOS)
    private func handleReturnKey(modifiers: EventModifiers) -> KeyPress.Result {
        guard store.editingItemID == nil, store.addPlacement == nil else { return .ignored }
        guard modifiers.isEmpty else { return .ignored }
        switch store.selectedItemIDs.count {
        case 0:
            store.beginAdding(.root)
        case 1:
            guard let selectedID = store.selectedItemIDs.first else { return .ignored }
            store.beginEditing(itemID: selectedID)
        default:
            return .ignored
        }
        return .handled
    }

    private func handleTabKey(isShiftPressed: Bool) -> KeyPress.Result {
        guard store.editingItemID == nil, store.addPlacement == nil,
              let row = selectedRow else {
            return .ignored
        }
        if isShiftPressed {
            store.outdent(itemID: row.id, undoManager: undoManager)
        } else {
            store.indent(itemID: row.id, undoManager: undoManager)
        }
        return .handled
    }

    private func handleSpaceKey(modifiers: EventModifiers) -> KeyPress.Result {
        guard modifiers.isEmpty,
              !store.isTextInputActive,
              !store.selectedItemIDs.isEmpty else {
            return .ignored
        }
        store.toggleChecked(ids: store.selectedItemIDs, undoManager: undoManager)
        return .handled
    }
    #endif

    private var selectedRow: FlatRow? {
        guard store.selectedItemIDs.count == 1,
              let selectedID = store.selectedItemIDs.first else {
            return nil
        }
        return store.flatRows.first { $0.id == selectedID }
    }

    private var addPlaceholder: String {
        switch store.addPlacement {
        case nil, .root:
            "New item"
        case .below:
            "New item below"
        case .child:
            "New child item"
        }
    }

    private func cancelTextEntry() {
        if store.addPlacement != nil {
            cancelAdding()
        }
        if store.editingItemID != nil {
            editingText = ""
            store.cancelEditing()
        }
    }

    private func commitTextEntry() {
        if let editingItemID = store.editingItemID {
            commitEdit(editingItemID)
        } else if store.addPlacement != nil {
            commitNewItem()
        }
    }
}

/// Selection-driven context menu. On macOS the double-click primary action
/// starts a rename, Finder-style. Shortcut hints are on: this menu's target
/// IS the selection, so the hints tell the truth.
private struct OutlineContextMenuModifier: ViewModifier {
    @Bindable var store: ListStore
    let onShowDetails: (UUID) -> Void
    @Environment(\.undoManager) private var undoManager

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .contextMenu(forSelectionType: UUID.self) { ids in
                menuContent(ids)
            } primaryAction: { ids in
                if ids.count == 1, let id = ids.first {
                    store.beginEditing(itemID: id)
                }
            }
        #else
        content
            .contextMenu(forSelectionType: UUID.self) { ids in
                menuContent(ids)
            }
        #endif
    }

    @ViewBuilder
    private func menuContent(_ ids: Set<UUID>) -> some View {
        if ids.isEmpty {
            Button {
                store.beginAdding(.root)
            } label: {
                Label("Add Item", systemImage: "plus")
            }
        } else {
            ItemActionsMenu(
                store: store,
                itemIDs: ids,
                showsShortcutHints: true,
                onShowDetails: onShowDetails
            )
        }
    }
}

/// iOS selects by row tap (List selection outside edit mode is a macOS
/// affordance); macOS relies on native List selection and adds nothing.
///
/// Double-tap opens Details (Rev 2.5, spec §1.6, td-ee5174). The double-tap
/// gesture is attached with `.simultaneousGesture` rather than a second
/// `.onTapGesture(count: 2)` — two competing `.gesture` recognizers of
/// different counts force SwiftUI to wait for the higher count to fail
/// before firing the lower one, delaying every single tap. Simultaneous
/// gestures recognize independently: the single-tap handler still fires the
/// instant one tap completes, and a fast second tap additionally fires the
/// double-tap handler.
private struct RowSelectionTapModifier: ViewModifier {
    let rowID: UUID
    let onSelect: (UUID) -> Void
    let onDoubleTap: (UUID) -> Void

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .onTapGesture {
                onSelect(rowID)
            }
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    onDoubleTap(rowID)
                }
            )
        #else
        content
        #endif
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
    let onDismissKeyboard: () -> Void
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

                        Button(action: onDismissKeyboard) {
                            Image(systemName: "keyboard.chevron.compact.down")
                        }
                        .accessibilityLabel("Dismiss Keyboard")
                        .accessibilityIdentifier("editor.keyboard.dismiss")

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

#if DEBUG
private struct OutlineEditorPreview: View {
    @State private var showInspector = false
    @State private var store = PreviewFixtures.listStore()

    var body: some View {
        OutlineEditorView(
            store: store,
            showInspector: $showInspector,
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
        // Deliberately NOT .searchable here: the sidebar already owns this
        // window's search toolbar item, and a second .searchable in the same
        // NavigationSplitView crashes NSToolbar (duplicate item insertion).
        // In-list search on macOS needs its own affordance (e.g. a filter
        // field above the outline) — tracked as a known gap.
        self
        #else
        searchable(text: text, prompt: "Search Items")
        #endif
    }
}
