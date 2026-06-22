import SwiftUI
import Domain
import Platform

struct CheckModeView: View {
    @Bindable var store: ListStore
    @Environment(\.undoManager) private var undoManager
    @State private var branchPendingReset: BranchResetConfirmation?

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
        .confirmationDialog(
            "Reset Branch?",
            isPresented: isConfirmingBranchReset,
            titleVisibility: .visible
        ) {
            if let confirmation = branchPendingReset {
                Button("Reset Branch", role: .destructive) {
                    store.resetSubtree(itemID: confirmation.id, undoManager: undoManager)
                }
            }
        } message: {
            if let confirmation = branchPendingReset {
                Text("“\(confirmation.title)” and all of its child items will be unchecked.")
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
                        Haptics.checkToggle()
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
            Haptics.checkToggle()
        } label: {
            Label(
                row.checkState == .checked ? "Uncheck" : "Check",
                systemImage: row.checkState == .checked ? "circle" : "checkmark.circle"
            )
        }

        if row.hasChildren {
            Button {
                branchPendingReset = BranchResetConfirmation(row)
            } label: {
                Label("Reset Branch", systemImage: "arrow.counterclockwise")
            }
            .disabled(row.checkState == .unchecked)
        }
    }

    private var isConfirmingBranchReset: Binding<Bool> {
        Binding(
            get: { branchPendingReset != nil },
            set: { if !$0 { branchPendingReset = nil } }
        )
    }
}

private struct BranchResetConfirmation: Identifiable {
    let id: UUID
    let title: String

    init(_ row: FlatRow) {
        id = row.id
        title = row.item.title
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
