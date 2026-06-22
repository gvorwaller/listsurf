import SwiftUI
import Domain

struct LibrarySidebar: View {
    @Environment(AppStore.self) private var appStore
    let onNewList: () -> Void
    @State private var searchText = ""
    @State private var showingArchive = false

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
            .accessibilityIdentifier("library.newList")
            .help("Create a new list")
            #endif
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
