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
        .sheet(isPresented: $showingNewList) {
            NewListSheet(
                title: $newListTitle,
                onCreate: createList,
                onCancel: cancelNewList
            )
        }
        .sheet(isPresented: $showingArchive) {
            ArchiveView()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            #if os(macOS)
            Button {
                showingNewList = true
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

    private func createList() {
        let title = newListTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        Task {
            await appStore.createList(title: title)
            newListTitle = ""
            showingNewList = false
        }
    }

    private func cancelNewList() {
        newListTitle = ""
        showingNewList = false
    }
}

private struct NewListSheet: View {
    @Binding var title: String
    let onCreate: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New List")
                .font(.title2.bold())

            TextField("List name", text: $title)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("newList.title")
                .onSubmit(onCreate)

            HStack {
                Spacer()

                Button("Cancel", role: .cancel, action: onCancel)

                Button("Create", action: onCreate)
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("newList.create")
            }
        }
        .padding(20)
        .frame(minWidth: 320)
        #if os(macOS)
        .frame(idealWidth: 360)
        #endif
    }
}
