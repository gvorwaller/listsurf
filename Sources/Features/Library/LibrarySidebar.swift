import SwiftUI
import Domain

struct LibrarySidebar: View {
    @Environment(AppStore.self) private var appStore
    let onNewList: () -> Void
    let onImportBackup: () -> Void
    let onExportBackup: () -> Void
    let onShowHelp: () -> Void
    @State private var searchText = ""
    @State private var showingArchive = false
    @State private var listPendingDeletion: ListDeletionConfirmation?
    @State private var listBeingEdited: ListItem?

    init(
        onNewList: @escaping () -> Void = {},
        onImportBackup: @escaping () -> Void = {},
        onExportBackup: @escaping () -> Void = {},
        onShowHelp: @escaping () -> Void = {}
    ) {
        self.onNewList = onNewList
        self.onImportBackup = onImportBackup
        self.onExportBackup = onExportBackup
        self.onShowHelp = onShowHelp
    }

    var body: some View {
        @Bindable var store = appStore
        List(selection: $store.selectedListID) {
            Section {
                Button {
                    onImportBackup()
                } label: {
                    Label("Import Backup…", systemImage: "square.and.arrow.down")
                }
                .accessibilityIdentifier("library.importBackup.visible")

                Button {
                    onExportBackup()
                } label: {
                    Label("Export Backup…", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("library.exportBackup.visible")

                Button {
                    showingArchive = true
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
                .accessibilityIdentifier("library.archive.visible")

                Button {
                    onShowHelp()
                } label: {
                    Label("Help", systemImage: "questionmark.circle")
                }
                .accessibilityIdentifier("library.help.visible")
            }

            if filteredLists.isEmpty && searchText.isEmpty {
                emptyLibrary
            } else {
                Section {
                    ForEach(filteredLists) { list in
                        HStack(spacing: 8) {
                            LibraryRow(list: list)
                            Spacer(minLength: 8)
                            Menu {
                                listActionMenu(list)
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .imageScale(.large)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Actions for \(list.title)")
                            .accessibilityIdentifier("library.listActions")
                        }
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

                Menu {
                    Button(action: onShowHelp) {
                        Label("Help", systemImage: "questionmark.circle")
                    }
                    .accessibilityIdentifier("library.help")

                    Divider()

                    Button(action: onNewList) {
                        Label("New List", systemImage: "plus")
                    }
                    .accessibilityIdentifier("library.menu.newList")

                    Button {
                        showingArchive = true
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    .accessibilityIdentifier("library.menu.archive")

                    Divider()

                    Button {
                        onImportBackup()
                    } label: {
                        Label("Import Backup…", systemImage: "square.and.arrow.down")
                    }
                    .accessibilityIdentifier("library.importBackup")

                    Button {
                        onExportBackup()
                    } label: {
                        Label("Export Backup…", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("library.exportBackup")
                } label: {
                    Label("Menu", systemImage: "line.3.horizontal")
                }
                .accessibilityIdentifier("library.appMenu")
                .help("Open Listsurf actions and help")
            }
        }
        .sheet(isPresented: $showingArchive) {
            ArchiveView()
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $listBeingEdited) { list in
            ListIdentityEditSheet(list: list) { updated in
                Task { await appStore.updateList(updated) }
            }
            .presentationDetents([.medium, .large])
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
            VStack {
                Button("Create List", action: onNewList)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("library.createFirstList")

                Button("Import Backup…", action: onImportBackup)
                    .accessibilityIdentifier("library.importFirstBackup")

                Button("Help", action: onShowHelp)
                    .accessibilityIdentifier("library.help.empty")
            }
        }
    }

    @ViewBuilder
    private func listContextMenu(_ list: ListItem) -> some View {
        listActionMenu(list)
    }

    @ViewBuilder
    private func listActionMenu(_ list: ListItem) -> some View {
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
