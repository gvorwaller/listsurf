import SwiftUI
import Domain

struct LibrarySidebar: View {
    @Environment(AppStore.self) private var appStore
    @State private var searchText = ""
    @State private var showingNewList = false
    @State private var showingArchive = false
    @State private var newListTitle = ""

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
                    showingNewList = true
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
        .alert("New List", isPresented: $showingNewList) {
            TextField("List name", text: $newListTitle)
                .accessibilityIdentifier("newList.title")
            Button("Create") {
                guard !newListTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                Task {
                    await appStore.createList(title: newListTitle)
                    newListTitle = ""
                }
            }
            .accessibilityIdentifier("newList.create")
            Button("Cancel", role: .cancel) { newListTitle = "" }
        }
        .sheet(isPresented: $showingArchive) {
            ArchiveView()
        }
    }

    private var filteredLists: [ListItem] {
        if searchText.isEmpty { return appStore.lists }
        let query = searchText.lowercased()
        return appStore.lists.filter { $0.title.lowercased().contains(query) }
    }

    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label("No Lists Yet", systemImage: "list.bullet.indent")
        } description: {
            Text("Create your first list to get started.")
        } actions: {
            Button("Create List") { showingNewList = true }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("library.createFirstList")
        }
    }

    @ViewBuilder
    private func listContextMenu(_ list: ListItem) -> some View {
        Button { showingNewList = true } label: {
            Label("New List", systemImage: "plus")
        }

        Divider()

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
            Task { await appStore.deleteList(id: list.id) }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}
