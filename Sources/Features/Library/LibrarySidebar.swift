import SwiftUI
import Domain

struct LibrarySidebar: View {
    @Environment(AppStore.self) private var appStore
    let onNewList: () -> Void
    @State private var searchText = ""
    @State private var showingArchive = false
    @State private var listPendingDeletion: ListDeletionConfirmation?
    @State private var listBeingEdited: ListItem?

    init(onNewList: @escaping () -> Void = {}) {
        self.onNewList = onNewList
    }

    var body: some View {
        @Bindable var store = appStore
        List(selection: $store.selectedListID) {
            if filteredLists.isEmpty && searchText.isEmpty {
                emptyLibrary
            } else {
                Section {
                    ForEach(filteredLists) { list in
                        LibraryRow(list: list)
                            .tag(list.id)
                            .contextMenu { listContextMenu(list) }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search Lists")
        .navigationTitle("Listsurf")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    onNewList()
                } label: {
                    Label("New List", systemImage: "plus")
                }
                .accessibilityIdentifier("library.newList")
                .help("Create a new list")

                Button {
                    showingArchive = true
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
                .help("View archived lists")
            }
        }
        .sheet(isPresented: $showingArchive) {
            ArchiveView()
        }
        .sheet(item: $listBeingEdited) { list in
            ListIdentityEditSheet(list: list) { updated in
                Task { await appStore.updateList(updated) }
            }
        }
        .confirmationDialog(
            "Delete List?",
            isPresented: isConfirmingListDeletion,
            titleVisibility: .visible
        ) {
            if let confirmation = listPendingDeletion {
                Button("Delete List", role: .destructive) {
                    Task { await appStore.deleteList(id: confirmation.id) }
                }
            }
        } message: {
            if let confirmation = listPendingDeletion {
                Text("“\(confirmation.title)” and all of its items will be permanently deleted. This cannot be undone.")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            #if os(macOS)
            Button {
                onNewList()
            } label: {
                Label("New List", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .accessibilityIdentifier("library.newList.sidebar")
            .help("Create a new list")

            Button {
                showingArchive = true
            } label: {
                Label("Archive", systemImage: "archivebox")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .accessibilityIdentifier("library.archive.sidebar")
            .help("View archived lists")
            #endif
        }
    }

    private var filteredLists: [ListItem] {
        if searchText.isEmpty { return appStore.lists }
        let query = searchText.lowercased()
        return appStore.lists.filter { $0.title.lowercased().contains(query) }
    }

    private var isConfirmingListDeletion: Binding<Bool> {
        Binding(
            get: { listPendingDeletion != nil },
            set: { if !$0 { listPendingDeletion = nil } }
        )
    }

    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label("No Lists Yet", systemImage: "list.bullet.indent")
        } description: {
            Text("Create your first list to get started.")
        } actions: {
            Button("Create List", action: onNewList)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("library.createFirstList")
        }
    }

    @ViewBuilder
    private func listContextMenu(_ list: ListItem) -> some View {
        Button(action: onNewList) {
            Label("New List", systemImage: "plus")
        }

        Divider()

        Button {
            listBeingEdited = list
        } label: {
            Label("Edit Details", systemImage: "pencil")
        }

        Button {
            Task { await appStore.duplicateList(id: list.id, clearChecks: false) }
        } label: {
            Label("Duplicate", systemImage: "doc.on.doc")
        }

        Button {
            Task { await appStore.duplicateList(id: list.id, clearChecks: true) }
        } label: {
            Label("Duplicate & Reset Checks", systemImage: "doc.on.doc.fill")
        }

        Divider()

        Button {
            Task { await appStore.archiveList(id: list.id) }
        } label: {
            Label("Archive", systemImage: "archivebox")
        }

        Divider()

        Button(role: .destructive) {
            listPendingDeletion = ListDeletionConfirmation(list)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

private struct ListDeletionConfirmation: Identifiable {
    let id: UUID
    let title: String

    init(_ list: ListItem) {
        id = list.id
        title = list.title
    }
}
