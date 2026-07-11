import SwiftUI
import Domain

struct LibrarySidebar: View {
    @Environment(AppStore.self) private var appStore
    let onNewList: () -> Void
    let onImportBackup: () -> Void
    let onExportBackup: () -> Void
    let onShowSettings: () -> Void
    let onShowHelp: () -> Void
    let onImportList: () -> Void
    let onExportList: (ListItem, ListExportFileFormat) -> Void
    let onShareListMarkdown: (ListItem) -> Void
    @State private var searchText = ""
    @State private var showingArchive = false
    @State private var listPendingDeletion: ListDeletionConfirmation?
    @State private var listBeingEdited: ListItem?

    init(
        onNewList: @escaping () -> Void = {},
        onImportBackup: @escaping () -> Void = {},
        onExportBackup: @escaping () -> Void = {},
        onShowSettings: @escaping () -> Void = {},
        onShowHelp: @escaping () -> Void = {},
        onImportList: @escaping () -> Void = {},
        onExportList: @escaping (ListItem, ListExportFileFormat) -> Void = { _, _ in },
        onShareListMarkdown: @escaping (ListItem) -> Void = { _ in }
    ) {
        self.onNewList = onNewList
        self.onImportBackup = onImportBackup
        self.onExportBackup = onExportBackup
        self.onShowSettings = onShowSettings
        self.onShowHelp = onShowHelp
        self.onImportList = onImportList
        self.onExportList = onExportList
        self.onShareListMarkdown = onShareListMarkdown
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
                    onImportList()
                } label: {
                    Label("Import List…", systemImage: "square.and.arrow.down.on.square")
                }
                .accessibilityIdentifier("library.importList.visible")

                Button {
                    onExportBackup()
                } label: {
                    Label("Export Backup…", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("library.exportBackup.visible")

                Button {
                    showingArchive = true
                } label: {
                    Label("Archived Lists", systemImage: "archivebox")
                }
                .badge(appStore.archivedLists.count)
                .accessibilityIdentifier("library.archive.visible")

                Button {
                    onShowHelp()
                } label: {
                    Label("Help", systemImage: "questionmark.circle")
                }
                .accessibilityIdentifier("library.help.visible")

                settingsButton
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
                            .contextMenu { listActionMenu(list) }
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
                    // No .badge here: it renders on list rows and menu items,
                    // not on toolbar buttons.
                    Label("Archived Lists", systemImage: "archivebox")
                }
                .help(archiveHelpText)

                settingsButton

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
                        Label("Archived Lists", systemImage: "archivebox")
                    }
                    .badge(appStore.archivedLists.count)
                    .accessibilityIdentifier("library.menu.archive")

                    Divider()

                    settingsButton

                    Divider()

                    Button {
                        onImportBackup()
                    } label: {
                        Label("Import Backup…", systemImage: "square.and.arrow.down")
                    }
                    .accessibilityIdentifier("library.importBackup")

                    Button {
                        onImportList()
                    } label: {
                        Label("Import List…", systemImage: "square.and.arrow.down.on.square")
                    }
                    .accessibilityIdentifier("library.importList")

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
                Label(archiveButtonTitle, systemImage: "archivebox")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .accessibilityIdentifier("library.archive.sidebar")
            .help(archiveHelpText)
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

                Button("Import List…", action: onImportList)
                    .accessibilityIdentifier("library.importFirstList")

                Button("Help", action: onShowHelp)
                    .accessibilityIdentifier("library.help.empty")
            }
        }
    }

    private var archiveButtonTitle: String {
        let count = appStore.archivedLists.count
        return count > 0 ? "Archived Lists (\(count))" : "Archived Lists"
    }

    private var archiveHelpText: String {
        let count = appStore.archivedLists.count
        return count > 0 ? "View \(count) archived lists" : "View archived lists"
    }

    @ViewBuilder
    private var settingsButton: some View {
        #if os(macOS)
        SettingsLink {
            Label("Settings…", systemImage: "gearshape")
        }
        .accessibilityIdentifier("library.settings")
        #else
        Button {
            onShowSettings()
        } label: {
            Label("Settings", systemImage: "gearshape")
        }
        .accessibilityIdentifier("library.settings")
        #endif
    }

    @ViewBuilder
    private func listActionMenu(_ list: ListItem) -> some View {
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

        Button { onExportList(list, .json) } label: { Label("Export List (JSON)…", systemImage: "square.and.arrow.up") }
            .accessibilityIdentifier("library.list.exportJSON")
        Button { onExportList(list, .opml) } label: { Label("Export List (OPML)…", systemImage: "square.and.arrow.up") }
            .accessibilityIdentifier("library.list.exportOPML")
        Button { onShareListMarkdown(list) } label: { Label("Share as Markdown…", systemImage: "square.and.arrow.up.on.square") }
            .accessibilityIdentifier("library.list.shareMarkdown")

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
