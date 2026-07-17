import SwiftUI
import Domain
import UniformTypeIdentifiers

public struct ContentView: View {
    @Environment(AppStore.self) private var appStore
    @State private var showingNewList = false
    @State private var newListTitle = ""
    @State private var newListNotes = ""
    @State private var newListIcon = "list.bullet"
    @State private var newListColorName = ListColor.blue.rawValue
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var showingHelp = false
    @State private var showingSettings = false
    @State private var exportDocument = ListsurfBackupDocument()
    @State private var exportFilename = "Listsurf Backup.json"
    @State private var pendingImport: PendingLibraryImport?
    @State private var importMode: LibraryImportMode = .replaceLibrary
    @State private var exportContentType: UTType = .json
    @State private var pendingAdditiveImport: PendingAdditiveImport?
    @State private var markdownShare: MarkdownShareItem?

    public init() {}

    public var body: some View {
        Group {
            if let presentation = appStore.errorStore.current,
               case .storeCorrupted = presentation.error {
                // Recovery mode gets NO app commands and no presentation
                // hosts: an enabled ⌘N here would arm a sheet with nowhere
                // to present, which then pops unprompted after recovery.
                StoreRecoveryView(presentation: presentation)
            } else {
                libraryView
            }
        }
        .task {
            if case .storeCorrupted = appStore.errorStore.current?.error {
                return
            }
            await appStore.loadLists()
        }
    }

    private var libraryView: some View {
        NavigationSplitView {
            LibrarySidebar(
                onNewList: beginNewList,
                onImportBackup: beginImportBackup,
                onExportBackup: beginExportBackup,
                onShowSettings: showSettings,
                onShowHelp: showHelp,
                onImportList: beginImportList,
                onExportList: beginExportList,
                onShareListMarkdown: beginShareListMarkdown
            )
        } detail: {
            if let selectedID = appStore.selectedListID {
                ListDetailView(listID: selectedID)
            } else {
                ContentUnavailableView(
                    "Select a List",
                    systemImage: "list.bullet.indent",
                    description: Text("Choose a list from the sidebar, or create a new one.")
                )
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let presentation = appStore.errorStore.current {
                ErrorBannerView(presentation: presentation) {
                    appStore.errorStore.retryCurrent()
                } onDismiss: {
                    appStore.errorStore.dismiss()
                }
            }
        }
        .focusedSceneValue(
            \.listsurfAppCommands,
            ListsurfAppCommandActions(
                newList: {
                    beginNewList()
                    CommandInvocation.post(CommandCatalog.newList)
                },
                importBackup: beginImportBackup,
                exportBackup: beginExportBackup,
                showHelp: {
                    showHelp()
                    CommandInvocation.post(CommandCatalog.help)
                },
                importList: beginImportList
            )
        )
        .sheet(isPresented: $showingNewList) {
            NewListSheet(
                title: $newListTitle,
                notes: $newListNotes,
                icon: $newListIcon,
                colorName: $newListColorName,
                onCreate: createList,
                onCancel: cancelNewList
            )
            .presentationDetents([.medium, .large])
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: importMode == .replaceLibrary ? [.json] : [.json, .opml, .xml],
            allowsMultipleSelection: false,
            onCompletion: handleImportSelection
        )
        .confirmationDialog(
            "Replace Library?",
            isPresented: isConfirmingImport,
            titleVisibility: .visible
        ) {
            Button("Replace Library", role: .destructive) {
                importPendingBackup()
            }
            Button("Cancel", role: .cancel) {
                pendingImport = nil
            }
        } message: {
            if let pendingImport {
                Text("Importing “\(pendingImport.filename)” will replace every current list and item. Export a backup first if you need to preserve the current library.")
            }
        }
        .sheet(item: $pendingAdditiveImport) { pending in
            ImportSummaryView(
                filename: pending.filename,
                listTitle: pending.plan.archive.lists.first?.list.title ?? pending.filename,
                summary: pending.plan.summary,
                onAccept: acceptPendingAdditiveImport,
                onDiscard: {
                    pendingAdditiveImport = nil
                }
            )
            .presentationDetents([.medium])
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: exportContentType,
            defaultFilename: exportFilename,
            onCompletion: handleExportCompletion
        )
        .sheet(isPresented: $showingHelp) {
            ListsurfHelpView {
                showingHelp = false
            }
        }
        .sheet(isPresented: $showingSettings) {
            ListsurfSettingsSheet {
                showingSettings = false
            }
        }
        .sheet(item: $markdownShare) { item in
            MarkdownShareView(listTitle: item.listTitle, text: item.text) {
                markdownShare = nil
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func beginNewList() {
        newListTitle = ""
        newListNotes = ""
        newListIcon = "list.bullet"
        newListColorName = ListColor.blue.rawValue
        showingNewList = true
    }

    private func beginImportBackup() {
        importMode = .replaceLibrary
        showingImporter = true
    }

    /// One-shot by construction: the plan is consumed from @State (not from
    /// the sheet's captured item), so a second tap on "Add to Library" before
    /// the sheet dismisses finds nil and does nothing. Without this, two
    /// commits of the same minted UUIDs can race the repository's collision
    /// preflight in separate background contexts — the silent-upsert class of
    /// failure the preflight cannot see across transactions.
    private func acceptPendingAdditiveImport() {
        guard let pending = pendingAdditiveImport else { return }
        pendingAdditiveImport = nil
        Task { await appStore.commitAdditiveImport(pending.plan) }
    }

    private func beginImportList() {
        importMode = .additiveList
        showingImporter = true
    }

    private func beginExportBackup() {
        Task {
            guard let data = await appStore.exportLibrary() else { return }
            exportDocument = ListsurfBackupDocument(data: data)
            exportFilename = backupFilename()
            exportContentType = .json
            showingExporter = true
        }
    }

    private func beginExportList(_ list: ListItem, format: ListExportFileFormat) {
        Task {
            let data: Data?
            switch format {
            case .json:
                data = await appStore.exportListJSON(id: list.id)
            case .opml:
                data = await appStore.exportListOPML(id: list.id)
            }
            guard let data else { return }
            exportDocument = ListsurfBackupDocument(data: data)
            exportFilename = exportFilename(for: list.title, ext: format == .json ? "json" : "opml")
            exportContentType = format == .json ? .json : .opml
            showingExporter = true
        }
    }

    private func beginShareListMarkdown(_ list: ListItem) {
        Task {
            if let text = await appStore.exportListMarkdown(id: list.id) {
                markdownShare = MarkdownShareItem(listTitle: list.title, text: text)
            }
        }
    }

    private func showHelp() {
        showingHelp = true
    }

    private func showSettings() {
        showingSettings = true
    }

    private func createList() {
        let title = newListTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        Task {
            await appStore.createList(
                title: title,
                notes: newListNotes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                icon: newListIcon.nilIfEmpty,
                colorName: newListColorName.nilIfEmpty
            )
            resetNewListDraft()
            showingNewList = false
        }
    }

    private func cancelNewList() {
        resetNewListDraft()
        showingNewList = false
    }

    private func resetNewListDraft() {
        newListTitle = ""
        newListNotes = ""
        newListIcon = "list.bullet"
        newListColorName = ListColor.blue.rawValue
    }

    private var isConfirmingImport: Binding<Bool> {
        Binding(
            get: { pendingImport != nil },
            set: { if !$0 { pendingImport = nil } }
        )
    }

    private func backupFilename(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "Listsurf Backup \(formatter.string(from: date)).json"
    }

    /// D10 file naming: sanitize a list title into a filename by replacing
    /// "/" and ":" (both illegal or awkward in filenames) with "-", trimming
    /// whitespace, and falling back to "List" if that leaves nothing usable.
    /// Non-private so it is independently unit-testable (@testable import Features).
    func exportFilename(for title: String, ext: String) -> String {
        var sanitized = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.isEmpty {
            sanitized = "List"
        }
        return "\(sanitized).\(ext)"
    }

    private func handleImportSelection(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let data = try Data(contentsOf: url)
            switch importMode {
            case .replaceLibrary:
                pendingImport = PendingLibraryImport(
                    filename: url.lastPathComponent,
                    data: data
                )
            case .additiveList:
                // View is @MainActor-annotated, so this plain Task inherits
                // MainActor — matches every existing async flow in this file
                // (e.g. importPendingBackup).
                Task {
                    guard let plan = await appStore.prepareAdditiveImport(from: data, filename: url.lastPathComponent) else { return }
                    if plan.summary.repairedParentCount > 0 {
                        pendingAdditiveImport = PendingAdditiveImport(filename: url.lastPathComponent, plan: plan)
                    } else {
                        await appStore.commitAdditiveImport(plan)
                    }
                }
            }
        } catch {
            appStore.errorStore.present(
                .importValidation(message: error.localizedDescription)
            )
        }
    }

    private func importPendingBackup() {
        guard let pendingImport else { return }
        self.pendingImport = nil
        Task {
            await appStore.importLibrary(from: pendingImport.data)
        }
    }

    private func handleExportCompletion(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            UserDefaults.standard.set(
                Date().timeIntervalSinceReferenceDate,
                forKey: ListsurfSettingsKey.lastExportAt
            )
        case .failure(let error):
            appStore.errorStore.present(
                .backupExportFailed(message: error.localizedDescription)
            )
        }
    }
}

private enum LibraryImportMode {
    case replaceLibrary
    case additiveList
}

private struct PendingLibraryImport: Identifiable {
    let id = UUID()
    let filename: String
    let data: Data
}

private struct PendingAdditiveImport: Identifiable {
    let id = UUID()
    let filename: String
    let plan: AdditiveImportPlan
}

private struct MarkdownShareItem: Identifiable {
    let id = UUID()
    let listTitle: String
    let text: String
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private struct StoreRecoveryView: View {
    @Environment(AppStore.self) private var appStore
    let presentation: AppErrorPresentation

    var body: some View {
        ContentUnavailableView {
            Label(
                presentation.error.errorDescription ?? "The Database Could Not Be Opened",
                systemImage: "externaldrive.badge.exclamationmark"
            )
        } description: {
            Text(presentation.error.failureReason ?? "Listsurf could not open its local database.")
        } actions: {
            if presentation.canRetry {
                Button(presentation.retryTitle ?? "Retry") {
                    appStore.errorStore.retryCurrent()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

#if DEBUG
#Preview("Library") {
    ContentView()
        .environment(PreviewFixtures.appStore())
}

#Preview("Selected List") {
    ContentView()
        .environment(PreviewFixtures.appStore(selected: true))
}
#endif
