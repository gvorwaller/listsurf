import SwiftUI
import Domain

struct InspectorView: View {
    @Bindable var store: ListStore
    let itemID: UUID?
    /// List metadata comes from AppStore (the single owner), not from a
    /// ListStore-cached copy that could go stale.
    let list: ListItem?
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Group {
            if let itemID, let item = store.items.first(where: { $0.id == itemID }) {
                itemInspector(item)
            } else {
                listInspector
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
                NotesEditor(text: notesBinding(item))
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

    private func notesBinding(_ item: OutlineItem) -> Binding<String> {
        Binding(
            get: { item.notes ?? "" },
            set: { newValue in
                store.updateItemNotes(id: item.id, notes: newValue.isEmpty ? nil : newValue, undoManager: undoManager)
            }
        )
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

private struct NotesEditor: View {
    @Binding var text: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .accessibilityIdentifier("inspector.itemNotes")

            if text.isEmpty {
                Text("Add notes...")
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
        }
    }
}
