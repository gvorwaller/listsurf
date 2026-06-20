import SwiftUI
import Domain

struct InspectorView: View {
    @Bindable var store: ListStore
    let itemID: UUID?
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
                TextField("Title", text: titleBinding(item), axis: .vertical)
                    .lineLimit(1...3)
            }

            Section("Notes") {
                TextField("Add notes…", text: notesBinding(item), axis: .vertical)
                    .lineLimit(3...10)
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
        .navigationTitle("Item Details")
    }

    private var listInspector: some View {
        Form {
            if let list = store.list {
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
        .navigationTitle("List Info")
    }

    private func titleBinding(_ item: OutlineItem) -> Binding<String> {
        Binding(
            get: { item.title },
            set: { newValue in
                Task { await store.updateItemTitle(id: item.id, title: newValue, undoManager: undoManager) }
            }
        )
    }

    private func notesBinding(_ item: OutlineItem) -> Binding<String> {
        Binding(
            get: { item.notes ?? "" },
            set: { newValue in
                Task { await store.updateItemNotes(id: item.id, notes: newValue.isEmpty ? nil : newValue, undoManager: undoManager) }
            }
        )
    }

    private func quantityBinding(_ item: OutlineItem) -> Binding<Int> {
        Binding(
            get: { item.quantity },
            set: { newValue in
                Task { await store.updateItemQuantity(id: item.id, quantity: newValue, undoManager: undoManager) }
            }
        )
    }
}
