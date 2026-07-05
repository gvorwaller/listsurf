import SwiftUI
import Domain
import os

@MainActor
@Observable
public final class AppStore {
    public var lists: [ListItem] = []
    public var archivedLists: [ListItem] = []
    public var selectedListID: UUID?

    public let errorStore: AppErrorStore

    private let listRepo: any ListRepository
    private let outlineRepo: any OutlineRepository
    private let logger = Logger(subsystem: "net.vorwaller.listsurf", category: "ui")
    private let exportService = ExportService()

    public init(
        listRepository: any ListRepository,
        outlineRepository: any OutlineRepository,
        errorStore: AppErrorStore = AppErrorStore()
    ) {
        self.listRepo = listRepository
        self.outlineRepo = outlineRepository
        self.errorStore = errorStore
    }

    public func loadLists() async {
        do {
            lists = try await listRepo.fetchActive()
                .sorted { $0.position < $1.position }
            archivedLists = try await listRepo.fetchArchived()
        } catch {
            presentLoadError(error, operation: "load lists")
        }
    }

    public func createList(
        title: String,
        notes: String? = nil,
        icon: String? = nil,
        colorName: String? = nil
    ) async {
        let position = (lists.map(\.position).max() ?? 0) + 1.0
        let list = ListItem(
            title: title,
            notes: notes,
            icon: icon,
            colorName: colorName,
            position: position
        )
        do {
            try await listRepo.save(list)
            await loadLists()
            selectedListID = list.id
        } catch {
            presentSaveError(error, operation: "create list")
        }
    }

    public func updateList(_ list: ListItem) async {
        do {
            try await listRepo.save(list)
            await loadLists()
        } catch {
            presentSaveError(error, operation: "update list")
        }
    }

    public func deleteList(id: UUID) async {
        do {
            try await listRepo.deleteListAndItems(id: id)
            if selectedListID == id { selectedListID = nil }
            await loadLists()
        } catch {
            presentSaveError(error, operation: "delete list")
        }
    }

    public func archiveList(id: UUID) async {
        guard var list = lists.first(where: { $0.id == id }) else { return }
        list.archivedAt = Date()
        list.updatedAt = Date()
        await updateList(list)
        if selectedListID == id { selectedListID = nil }
    }

    public func restoreList(id: UUID) async {
        guard var list = archivedLists.first(where: { $0.id == id }) else { return }
        list.archivedAt = nil
        list.updatedAt = Date()
        await updateList(list)
    }

    public func duplicateList(id: UUID, clearChecks: Bool) async {
        do {
            guard let list = lists.first(where: { $0.id == id }) else { return }
            let items = try await outlineRepo.fetchItems(forList: id)
            let engine = TreeEngine()
            let (newList, newItems) = engine.duplicateList(
                list,
                items: items,
                clearChecks: clearChecks
            )
            var positioned = newList
            positioned.position = (lists.map(\.position).max() ?? 0) + 1.0
            try await listRepo.saveListAndItems(positioned, items: newItems)
            await loadLists()
            selectedListID = positioned.id
        } catch {
            presentSaveError(error, operation: "duplicate list")
        }
    }

    public func exportLibrary(appVersion: String = "0.1.0") async throws -> Data {
        do {
            let lists = try await listRepo.fetchAll()
                .sorted { $0.position < $1.position }
            var archivedLists: [ArchivedList] = []
            for list in lists {
                let items = try await outlineRepo.fetchItems(forList: list.id)
                archivedLists.append(
                    ArchivedList(
                        list: list,
                        items: items.sorted { $0.position < $1.position }
                    )
                )
            }
            let export = exportService.export(
                archive: LibraryArchive(lists: archivedLists),
                appVersion: appVersion
            )
            return try exportService.encode(export)
        } catch {
            presentLoadError(error, operation: "export library")
            throw error
        }
    }

    public func importLibrary(from data: Data) async throws {
        do {
            let decoded = try exportService.decode(from: data)
            let archive = try exportService.archive(from: decoded)
            try await listRepo.replaceAllListsAndItems(with: archive)
            await loadLists()
            selectedListID = lists.first?.id
        } catch let error as ExportValidationError {
            errorStore.present(.importValidation(message: error.localizedDescription))
            throw error
        } catch let error as DecodingError {
            errorStore.present(.importValidation(message: error.localizedDescription))
            throw error
        } catch {
            presentSaveError(error, operation: "import library")
            throw error
        }
    }

    public func makeListStore(for listID: UUID) -> ListStore {
        ListStore(
            listID: listID,
            outlineRepo: outlineRepo,
            listRepo: listRepo,
            errorStore: errorStore
        )
    }

    private func presentLoadError(_ error: Error, operation: String) {
        logger.error("Failed to \(operation): \(error.localizedDescription)")
        errorStore.present(
            .persistenceLoad(underlying: error.localizedDescription),
            retryTitle: "Retry Load"
        ) { [weak self] in
            Task { await self?.loadLists() }
        }
    }

    private func presentSaveError(_ error: Error, operation: String) {
        logger.error("Failed to \(operation): \(error.localizedDescription)")
        errorStore.present(
            .persistenceSave(underlying: error.localizedDescription),
            retryTitle: "Reload Lists"
        ) { [weak self] in
            Task { await self?.loadLists() }
        }
    }
}
