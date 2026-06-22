import SwiftUI
import Domain

struct ArchiveView: View {
    @Environment(AppStore.self) private var appStore
    @Environment(\.dismiss) private var dismiss
    @State private var listPendingDeletion: ArchivedListDeletionConfirmation?
    @State private var listBeingEdited: ListItem?

    var body: some View {
        NavigationStack {
            Group {
                if appStore.archivedLists.isEmpty {
                    ContentUnavailableView(
                        "No Archived Lists",
                        systemImage: "archivebox",
                        description: Text("Archived lists will appear here.")
                    )
                } else {
                    List {
                        ForEach(appStore.archivedLists) { list in
                            LibraryRow(list: list)
                                .contextMenu {
                                    Button {
                                        listBeingEdited = list
                                    } label: {
                                        Label("Edit Details", systemImage: "pencil")
                                    }

                                    Divider()

                                    Button {
                                        Task { await appStore.restoreList(id: list.id) }
                                    } label: {
                                        Label("Restore", systemImage: "arrow.uturn.backward")
                                    }

                                    Button(role: .destructive) {
                                        listPendingDeletion = ArchivedListDeletionConfirmation(list)
                                    } label: {
                                        Label("Delete Permanently", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        listPendingDeletion = ArchivedListDeletionConfirmation(list)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        Task { await appStore.restoreList(id: list.id) }
                                    } label: {
                                        Label("Restore", systemImage: "arrow.uturn.backward")
                                    }
                                    .tint(.blue)
                                }
                        }
                    }
                }
            }
            .navigationTitle("Archive")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .sheet(item: $listBeingEdited) { list in
            ListIdentityEditSheet(list: list) { updated in
                Task { await appStore.updateList(updated) }
            }
        }
        .confirmationDialog(
            "Delete Archived List?",
            isPresented: isConfirmingListDeletion,
            titleVisibility: .visible
        ) {
            if let confirmation = listPendingDeletion {
                Button("Delete Permanently", role: .destructive) {
                    Task { await appStore.deleteList(id: confirmation.id) }
                }
            }
        } message: {
            if let confirmation = listPendingDeletion {
                Text("“\(confirmation.title)” and all of its items will be permanently deleted. This cannot be undone.")
            }
        }
    }

    private var isConfirmingListDeletion: Binding<Bool> {
        Binding(
            get: { listPendingDeletion != nil },
            set: { if !$0 { listPendingDeletion = nil } }
        )
    }
}

private struct ArchivedListDeletionConfirmation: Identifiable {
    let id: UUID
    let title: String

    init(_ list: ListItem) {
        id = list.id
        title = list.title
    }
}
