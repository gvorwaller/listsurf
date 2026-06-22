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
    private let logger = Logger(subsystem: "com.listsurf.app", category: "ui")

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
