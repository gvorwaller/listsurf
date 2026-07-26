import SwiftUI
import Domain
#if os(macOS)
import AppKit
#endif

struct InspectorView: View {
    @Bindable var store: ListStore
    let itemID: UUID?
    /// List metadata comes from AppStore (the single owner), not from a
    /// ListStore-cached copy that could go stale.
    let list: ListItem?
    /// Bumped by ListDetailView's Edit Notes action (td-2bc3a8, plan item 8)
    /// each time the user wants the cursor back in Notes — even if the
    /// inspector is already open, so ⌘O always refocuses.
    let focusNotesToken: Int
    @Environment(\.undoManager) private var undoManager
    @FocusState private var notesFocused: Bool

    var body: some View {
        Group {
            if let itemID, let item = store.items.first(where: { $0.id == itemID }) {
                itemInspector(item)
            } else {
                listInspector
            }
        }
        .onChange(of: focusNotesToken) { _, newValue in
            guard newValue > 0 else { return }
            requestNotesFocus()
        }
    }

    /// Deferred one runloop hop, mirroring the shape of
    /// `OutlineEditorView.assignFocus` (td-ff531e): the token can arrive
    /// while the inspector is still mid-mount (just-presented panel/sheet),
    /// so re-assert once if the first assignment didn't stick. This is the
    /// plain FocusState binding only — OutlineEditorView's full AppKit
    /// escalation (`focusAddFieldDirectly`/`findAddTextField`, needed there
    /// because arming an add field can race an outline restructure) isn't
    /// reused here; add it only if a test proves this plain binding
    /// unreliable for the Notes editor.
    private func requestNotesFocus() {
        Task { @MainActor in
            notesFocused = true
            await Task.yield()
            if !notesFocused {
                notesFocused = true
            }
        }
    }

    private func itemInspector(_ item: OutlineItem) -> some View {
        Form {
            Section("Title") {
                #if os(iOS)
                // iOS: the sheet sits in front of the row, so the inline
                // rename field behind it (armed by the old Rename button)
                // was invisible. Edit the title in place instead.
                ItemTitleField(item: item) { newTitle in
                    store.updateItemTitle(id: item.id, title: newTitle, undoManager: undoManager)
                }
                .id(item.id)
                #else
                LabeledContent("Title", value: item.title)
                Button("Rename") {
                    store.beginEditing(itemID: item.id)
                }
                .accessibilityIdentifier("inspector.renameItem")
                #endif
            }

            Section("Notes") {
                NotesEditor(item: item, focused: $notesFocused) { newValue in
                    store.updateItemNotes(id: item.id, notes: newValue.isEmpty ? nil : newValue, undoManager: undoManager)
                }
                // Reseed the draft when the selected item changes — same
                // shape as ItemTitleField's `.id(item.id)` above. Tearing
                // down the old instance also fires its `onDisappear`
                // commit, so switching items while the inspector stays
                // open (macOS) still commits the outgoing item's draft
                // before the new one mounts.
                .id(item.id)
                // Prototype parity: notes stay compact in both the macOS
                // inspector and iOS Details sheet, scrolling internally
                // instead of expanding the surrounding Form without bound.
                .frame(minHeight: 56, idealHeight: 88, maxHeight: 120)
            }

            Section("Quantity") {
                Stepper(
                    value: quantityBinding(item),
                    in: 1...999
                ) {
                    Text("\(item.quantity)")
                        .monospacedDigit()
                }
            }

            Section("Info") {
                LabeledContent("Created", value: item.createdAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Modified", value: item.updatedAt.formatted(date: .abbreviated, time: .shortened))
                if item.parentID != nil {
                    LabeledContent("Parent") {
                        if let parent = store.items.first(where: { $0.id == item.parentID }) {
                            Text(parent.title)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var listInspector: some View {
        Form {
            if let list {
                Section("List") {
                    LabeledContent("Title", value: list.title)
                    if let notes = list.notes, !notes.isEmpty {
                        LabeledContent("Notes", value: notes)
                    }
                }

                Section("Stats") {
                    let p = store.progress
                    LabeledContent("Items", value: "\(store.items.count)")
                    LabeledContent("Progress", value: "\(p.checked)/\(p.total)")
                }

                Section("Info") {
                    LabeledContent("Created", value: list.createdAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Modified", value: list.updatedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
        }
        .formStyle(.grouped)
    }

    private func quantityBinding(_ item: OutlineItem) -> Binding<Int> {
        Binding(
            get: { item.quantity },
            set: { newValue in
                store.updateItemQuantity(id: item.id, quantity: newValue, undoManager: undoManager)
            }
        )
    }
}

#if os(iOS)
/// Owns a local title draft so the Details sheet can rename an item without
/// per-keystroke store writes. Committed once per edit session (on submit,
/// and again defensively on disappear) — matches the editor's
/// trim-and-ignore-empty commit semantics (OutlineEditorView.commitEdit).
private struct ItemTitleField: View {
    let item: OutlineItem
    let onCommit: (String) -> Void

    @State private var draft: String
    @State private var lastCommitted: String

    init(item: OutlineItem, onCommit: @escaping (String) -> Void) {
        self.item = item
        self.onCommit = onCommit
        _draft = State(initialValue: item.title)
        _lastCommitted = State(initialValue: item.title)
    }

    var body: some View {
        TextField("Title", text: $draft)
            .accessibilityIdentifier("inspector.itemTitle")
            .onSubmit { commitIfNeeded() }
            .onDisappear { commitIfNeeded() }
    }

    private func commitIfNeeded() {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != lastCommitted else { return }
        lastCommitted = trimmed
        onCommit(trimmed)
    }
}
#endif

/// Owns a local notes draft so multi-line typing never round-trips through
/// the store per keystroke (td-204b17: `notesBinding`'s per-keystroke
/// `store.updateItemNotes` write raced the whole-view re-render this same
/// binding triggers, corrupting long/multi-line commits — the same race
/// class td-e7c609 fixed for rename/add via `EditorDraftText`, and that
/// `ItemTitleField` above already fixed for the title field). Committed
/// once per edit session: on focus loss (the multi-line equivalent of
/// `ItemTitleField`'s `onSubmit`, since `TextEditor` has no submit event)
/// and again defensively on disappear, which also covers inspector/sheet
/// dismissal and — combined with the caller's `.id(item.id)` — a same-
/// session item switch.
private struct NotesEditor: View {
    let item: OutlineItem
    var focused: FocusState<Bool>.Binding
    let onCommit: (String) -> Void

    @State private var draft: String
    @State private var lastCommitted: String

    init(item: OutlineItem, focused: FocusState<Bool>.Binding, onCommit: @escaping (String) -> Void) {
        self.item = item
        self.focused = focused
        self.onCommit = onCommit
        let initial = item.notes ?? ""
        _draft = State(initialValue: initial)
        _lastCommitted = State(initialValue: initial)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $draft)
                .scrollContentBackground(.hidden)
                .accessibilityIdentifier("inspector.itemNotes")
                .focused(focused)

            if draft.isEmpty {
                Text("Add notes...")
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: focused.wrappedValue) { _, isFocused in
            if !isFocused { commitIfNeeded() }
        }
        .onDisappear { commitIfNeeded() }
    }

    private func commitIfNeeded() {
        guard draft != lastCommitted else { return }
        lastCommitted = draft
        onCommit(draft)
    }
}

#if os(macOS)
/// Mirrors `KeyboardLegendFocus` (KeyboardLegendView.swift): the AppKit
/// responder chain is the ground truth for "what had focus before a
/// covering UI appeared," so capture/restore it directly rather than
/// guessing which of several on-screen `NSTableView`s (sidebar vs. outline)
/// is "the" one to refocus. Capture right before the inspector opens
/// (ListDetailView.handleInspectorPresentationChange); restore right after
/// it closes — this returns focus to whatever the outline's row selection
/// had claimed, not a heuristically-matched view.
@MainActor
enum InspectorFocusRestore {
    private static weak var window: NSWindow?
    private static weak var responder: NSResponder?

    static func capture() {
        window = NSApp.keyWindow
        responder = window?.firstResponder
    }

    static func restore() {
        defer {
            window = nil
            responder = nil
        }
        guard let window, let responder else { return }
        _ = window.makeFirstResponder(responder)
    }
}
#endif
