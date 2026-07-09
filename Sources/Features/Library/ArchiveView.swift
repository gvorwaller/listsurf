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
                        description: Text("Archive moves lists out of the main library without deleting them. Restore brings a list back.")
                    )
                } else {
                    List {
                        ForEach(appStore.archivedLists) { list in
                            HStack(spacing: 8) {
                                LibraryRow(list: list)
                                Spacer(minLength: 8)
                                Button {
                                    Task { await appStore.restoreList(id: list.id) }
                                } label: {
                                    Label("Restore", systemImage: "arrow.uturn.backward")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .accessibilityIdentifier("archive.restoreList")

                                Menu {
                                    archivedListActionMenu(list)
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .imageScale(.large)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Actions for \(list.title)")
                                .accessibilityIdentifier("archive.listActions")
                            }
                                .contextMenu {
                                    archivedListActionMenu(list)
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
            .navigationTitle("Archived Lists")
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
            .presentationDetents([.medium, .large])
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

    @ViewBuilder
    private func archivedListActionMenu(_ list: ListItem) -> some View {
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
}

private struct ArchivedListDeletionConfirmation: Identifiable {
    let id: UUID
    let title: String

    init(_ list: ListItem) {
        id = list.id
        title = list.title
    }
}
