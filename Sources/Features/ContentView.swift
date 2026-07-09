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

    public init() {}

    public var body: some View {
        Group {
            if let presentation = appStore.errorStore.current,
               case .storeCorrupted = presentation.error {
                StoreRecoveryView(presentation: presentation)
            } else {
                NavigationSplitView {
                    LibrarySidebar(
                        onNewList: beginNewList,
                        onImportBackup: beginImportBackup,
                        onExportBackup: beginExportBackup,
                        onShowSettings: showSettings,
                        onShowHelp: showHelp
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
            }
        }
        .focusedSceneValue(
            \.listsurfAppCommands,
            ListsurfAppCommandActions(
                newList: beginNewList,
                importBackup: beginImportBackup,
                exportBackup: beginExportBackup,
                showHelp: showHelp
            )
        )
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json],
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
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportFilename,
            onCompletion: handleExportCompletion
        )
        .sheet(isPresented: $showingHelp) {
            ListsurfHelpView {
                showingHelp = false
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                ListsurfSettingsView()
                    .navigationTitle("Settings")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showingSettings = false
                            }
                        }
                    }
            }
        }
        .task {
            if case .storeCorrupted = appStore.errorStore.current?.error {
                return
            }
            await appStore.loadLists()
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
        showingImporter = true
    }

    private func beginExportBackup() {
        Task {
            do {
                exportDocument = ListsurfBackupDocument(
                    data: try await appStore.exportLibrary(appVersion: appVersion)
                )
                exportFilename = backupFilename()
                showingExporter = true
            } catch {
                // AppStore already presents the export failure through the shared error store.
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

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.1.0"
    }

    private func backupFilename(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "Listsurf Backup \(formatter.string(from: date)).json"
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
            pendingImport = PendingLibraryImport(
                filename: url.lastPathComponent,
                data: try Data(contentsOf: url)
            )
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
            try await appStore.importLibrary(from: pendingImport.data)
        }
    }

    private func handleExportCompletion(_ result: Result<URL, Error>) {
        if case .failure(let error) = result {
            appStore.errorStore.present(
                .backupExportFailed(message: error.localizedDescription)
            )
        }
    }
}

private struct PendingLibraryImport: Identifiable {
    let id = UUID()
    let filename: String
    let data: Data
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
