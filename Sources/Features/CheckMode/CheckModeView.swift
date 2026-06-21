import SwiftUI
import Domain

struct CheckModeView: View {
    @Bindable var store: ListStore
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Group {
            if allCheckedAndFiltering {
                allDoneState
            } else if store.filteredRows.isEmpty {
                ContentUnavailableView(
                    "No Items",
                    systemImage: "checklist",
                    description: Text("This list has no items to check.")
                )
            } else {
                checkList
            }
        }
    }

    private var allCheckedAndFiltering: Bool {
        store.checkFilter == .unchecked && store.filteredRows.isEmpty && !store.items.isEmpty
    }

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

    private var checkList: some View {
        List {
            ForEach(store.filteredRows) { row in
                CheckRowView(
                    row: row,
                    onToggle: {
                        store.toggleCheck(itemID: row.id, undoManager: undoManager)
                    },
                    onToggleExpand: { store.toggleExpanded(row.id) }
                )
                .listRowInsets(EdgeInsets(
                    top: 6,
                    leading: 16 + Double(row.depth) * 20,
                    bottom: 6,
                    trailing: 16
                ))
                .contextMenu {
                    checkRowContextMenu(row)
                }
            }
        }
        .listStyle(.plain)
        .animation(.default, value: store.flatRows.map(\.id))
    }

    @ViewBuilder
    private func checkRowContextMenu(_ row: FlatRow) -> some View {
        Button {
            store.toggleCheck(itemID: row.id, undoManager: undoManager)
        } label: {
            Label(
                row.item.isChecked ? "Uncheck" : "Check",
                systemImage: row.item.isChecked ? "circle" : "checkmark.circle"
            )
        }

        if row.hasChildren {
            Button {
                store.resetSubtree(itemID: row.id, undoManager: undoManager)
            } label: {
                Label("Reset Branch", systemImage: "arrow.counterclockwise")
            }
        }
    }
}

#if DEBUG
#Preview("Check Mode") {
    NavigationStack {
        CheckModeView(store: PreviewFixtures.listStore(checkMode: true))
            .navigationTitle("Weekend Packing")
    }
}
#endif
