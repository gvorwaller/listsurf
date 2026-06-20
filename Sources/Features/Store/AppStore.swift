import SwiftUI
import Domain
import os

@MainActor
@Observable
public final class AppStore {
    public var lists: [ListItem] = []
    public var archivedLists: [ListItem] = []
    public var selectedListID: UUID?
    public var error: AppError?
    public var showingError = false

    private let listRepo: any ListRepository
    private let outlineRepo: any OutlineRepository
    private let logger = Logger(subsystem: "com.listsurf.app", category: "ui")

    public init(listRepository: any ListRepository, outlineRepository: any OutlineRepository) {
        self.listRepo = listRepository
        self.outlineRepo = outlineRepository
    }

    public func loadLists() async {
        do {
            lists = try await listRepo.fetchActive()
                .sorted { $0.position < $1.position }
            archivedLists = try await listRepo.fetchArchived()
                .sorted { $0.position < $1.position }
        } catch {
            logger.error("Failed to load lists: \(error.localizedDescription)")
            self.error = .persistenceLoad(underlying: error.localizedDescription)
            showingError = true
        }
    }

    public func createList(title: String, icon: String? = nil, colorName: String? = nil) async {
        let position = (lists.map(\.position).max() ?? 0) + 1.0
        let list = ListItem(title: title, icon: icon, colorName: colorName, position: position)
        do {
            try await listRepo.save(list)
            await loadLists()
            selectedListID = list.id
        } catch {
            logger.error("Failed to create list: \(error.localizedDescription)")
            self.error = .persistenceSave(underlying: error.localizedDescription)
            showingError = true
        }
    }

    public func updateList(_ list: ListItem) async {
        do {
            try await listRepo.save(list)
            await loadLists()
        } catch {
            logger.error("Failed to update list: \(error.localizedDescription)")
            self.error = .persistenceSave(underlying: error.localizedDescription)
            showingError = true
        }
    }

    public func deleteList(id: UUID) async {
        do {
            let items = try await outlineRepo.fetchItems(forList: id)
            try await outlineRepo.deleteAll(ids: items.map(\.id))
            try await listRepo.delete(id: id)
            if selectedListID == id { selectedListID = nil }
            await loadLists()
        } catch {
            logger.error("Failed to delete list: \(error.localizedDescription)")
            self.error = .persistenceSave(underlying: error.localizedDescription)
            showingError = true
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
            let (newList, newItems) = engine.duplicateList(list, items: items, clearChecks: clearChecks)
            var positioned = newList
            positioned.position = (lists.map(\.position).max() ?? 0) + 1.0
            try await listRepo.save(positioned)
            try await outlineRepo.saveAll(newItems)
            await loadLists()
            selectedListID = newList.id
        } catch {
            logger.error("Failed to duplicate list: \(error.localizedDescription)")
            self.error = .persistenceSave(underlying: error.localizedDescription)
            showingError = true
        }
    }

    public func makeListStore(for listID: UUID) -> ListStore {
        ListStore(listID: listID, outlineRepo: outlineRepo, listRepo: listRepo)
    }
}
