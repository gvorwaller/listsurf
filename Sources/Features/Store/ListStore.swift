import SwiftUI
import Domain
import os

@MainActor
@Observable
public final class ListStore {
    public var list: ListItem?
    public var items: [OutlineItem] = []
    public var flatRows: [FlatRow] = []
    public var expandedIDs: Set<UUID> = []
    public var selectedItemIDs: Set<UUID> = []
    public var isCheckMode = false
    public var checkFilter: CheckFilter = .all
    public var searchText = ""

    let listID: UUID
    private let outlineRepo: any OutlineRepository
    private let listRepo: any ListRepository
    private let errorStore: AppErrorStore
    private let engine = TreeEngine()
    private let logger = Logger(subsystem: "com.listsurf.app", category: "tree")
    @ObservationIgnored private var persistenceTail: Task<Void, Never>?

    public enum CheckFilter: String, CaseIterable {
        case all = "All"
        case unchecked = "Unchecked"
        case checked = "Checked"
    }

    init(
        listID: UUID,
        outlineRepo: any OutlineRepository,
        listRepo: any ListRepository,
        errorStore: AppErrorStore = AppErrorStore()
    ) {
        self.listID = listID
        self.outlineRepo = outlineRepo
        self.listRepo = listRepo
        self.errorStore = errorStore
    }

    public var progress: (checked: Int, total: Int) {
        engine.listProgress(items: items)
    }

    public var filteredRows: [FlatRow] {
        var rows = flatRows

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            let matchingIDs = Set(items.filter { $0.title.lowercased().contains(query) }.map(\.id))
            var visibleIDs = matchingIDs
            for id in matchingIDs {
                let ancestors = engine.ancestorIDs(of: id, in: items)
                visibleIDs.formUnion(ancestors)
            }
            rows = engine
                .flatten(items: items, expandedIDs: expandedIDs.union(visibleIDs))
                .filter { visibleIDs.contains($0.id) }
        }

        if isCheckMode {
            switch checkFilter {
            case .all: break
            case .unchecked:
                rows = rows.filter { $0.checkState != .checked }
            case .checked:
                rows = rows.filter { $0.checkState == .checked }
            }
        }

        return rows
    }

    public func load() async {
        do {
            list = try await listRepo.fetch(id: listID)
            let fetchedItems = try await outlineRepo.fetchItems(forList: listID)
            let repair = engine.repairInvalidParents(in: fetchedItems)
            let repairedCount = repair.orphanCount + repair.cycleCount
            items = repair.repaired
            rebuildRows()
            if repairedCount > 0 {
                try await persistRepair(originalItems: fetchedItems, repairedItems: repair.repaired)
                errorStore.present(.orphanRepair(
                    repairedCount: repairedCount,
                    listTitle: list?.title ?? "List"
                ))
            }
        } catch {
            logger.error("Failed to load items: \(error.localizedDescription)")
            errorStore.present(
                .persistenceLoad(underlying: error.localizedDescription),
                retryTitle: "Retry Load"
            ) { [weak self] in
                Task { await self?.load() }
            }
        }
    }

    private func persistRepair(originalItems: [OutlineItem], repairedItems: [OutlineItem]) async throws {
        let originalMap = Dictionary(uniqueKeysWithValues: originalItems.map { ($0.id, $0) })
        let changedItems = repairedItems.filter { item in
            originalMap[item.id] != item
        }
        if !changedItems.isEmpty {
            try await outlineRepo.saveAll(changedItems)
        }
    }

    private func rebuildRows() {
        flatRows = engine.flatten(items: items, expandedIDs: expandedIDs)
    }

    private func applyChanges(to newItems: [OutlineItem]) {
        items = newItems
        rebuildRows()
    }

    private func persistInBackground(from oldItems: [OutlineItem], to newItems: [OutlineItem]) {
        let oldMap = Dictionary(uniqueKeysWithValues: oldItems.map { ($0.id, $0) })
        let changed = newItems.filter { item in
            guard let old = oldMap[item.id] else { return true }
            return old != item
        }
        let newIDs = Set(newItems.map(\.id))
        let deletedIDs = oldItems.filter { !newIDs.contains($0.id) }.map(\.id)
        let previous = persistenceTail

        persistenceTail = Task { [outlineRepo, logger, errorStore] in
            await previous?.value
            do {
                if !changed.isEmpty {
                    try await outlineRepo.saveAll(changed)
                }
                if !deletedIDs.isEmpty {
                    try await outlineRepo.deleteAll(ids: deletedIDs)
                }
            } catch {
                logger.error("Failed to persist changes: \(error.localizedDescription)")
                errorStore.present(
                    .persistenceSave(underlying: error.localizedDescription),
                    retryTitle: "Reload List"
                ) { [weak self] in
                    Task { await self?.load() }
                }
            }
        }
    }

    public func waitForPendingPersistence() async {
        await persistenceTail?.value
    }

    // MARK: - Structural commands

    public func addItem(title: String, afterItemID: UUID? = nil, undoManager: UndoManager? = nil) {
        let newItem = OutlineItem(listID: listID, title: title)
        let oldItems = items

        let updatedItems: [OutlineItem]
        if let refID = afterItemID {
            updatedItems = engine.insertBelow(referenceID: refID, newItem: newItem, in: items)
        } else {
            var positioned = newItem
            positioned.position = engine.nextPosition(among: items.filter { $0.parentID == nil })
            updatedItems = items + [positioned]
        }

        registerUndo(undoManager: undoManager, oldItems: oldItems)
        applyChanges(to: updatedItems)
        persistInBackground(from: oldItems, to: updatedItems)
    }

    public func addChild(parentID: UUID, title: String, undoManager: UndoManager? = nil) {
        let newItem = OutlineItem(listID: listID, title: title)
        let oldItems = items
        let updatedItems = engine.insertChild(parentID: parentID, newItem: newItem, in: items)
        expandedIDs.insert(parentID)
        registerUndo(undoManager: undoManager, oldItems: oldItems)
        applyChanges(to: updatedItems)
        persistInBackground(from: oldItems, to: updatedItems)
    }

    public func insertAbove(referenceID: UUID, title: String, undoManager: UndoManager? = nil) {
        let newItem = OutlineItem(listID: listID, title: title)
        let oldItems = items
        let updatedItems = engine.insertAbove(referenceID: referenceID, newItem: newItem, in: items)
        registerUndo(undoManager: undoManager, oldItems: oldItems)
        applyChanges(to: updatedItems)
        persistInBackground(from: oldItems, to: updatedItems)
    }

    public func deleteItem(id: UUID, undoManager: UndoManager? = nil) {
        let oldItems = items
        let (remaining, _) = engine.deleteSubtree(itemID: id, in: items)
        selectedItemIDs.remove(id)
        registerUndo(undoManager: undoManager, oldItems: oldItems)
        applyChanges(to: remaining)
        persistInBackground(from: oldItems, to: remaining)
    }

    public func deleteSelected(undoManager: UndoManager? = nil) {
        let oldItems = items
        var remaining = items
        for id in selectedItemIDs {
            let (r, _) = engine.deleteSubtree(itemID: id, in: remaining)
            remaining = r
        }
        selectedItemIDs.removeAll()
        registerUndo(undoManager: undoManager, oldItems: oldItems)
        applyChanges(to: remaining)
        persistInBackground(from: oldItems, to: remaining)
    }

    public func moveUp(itemID: UUID, undoManager: UndoManager? = nil) {
        guard let moved = engine.moveUp(itemID: itemID, in: items) else { return }
        let oldItems = items
        registerUndo(undoManager: undoManager, oldItems: oldItems)
        applyChanges(to: moved)
        persistInBackground(from: oldItems, to: moved)
    }

    public func moveDown(itemID: UUID, undoManager: UndoManager? = nil) {
        guard let moved = engine.moveDown(itemID: itemID, in: items) else { return }
        let oldItems = items
        registerUndo(undoManager: undoManager, oldItems: oldItems)
        applyChanges(to: moved)
        persistInBackground(from: oldItems, to: moved)
    }

    public func indent(itemID: UUID, undoManager: UndoManager? = nil) {
        do {
            let oldItems = items
            let indented = try engine.indent(itemID: itemID, in: items)
            registerUndo(undoManager: undoManager, oldItems: oldItems)
            applyChanges(to: indented)
            persistInBackground(from: oldItems, to: indented)
        } catch {
            logger.warning("Cannot indent: \(error.localizedDescription)")
        }
    }

    public func outdent(itemID: UUID, undoManager: UndoManager? = nil) {
        do {
            let oldItems = items
            let outdented = try engine.outdent(itemID: itemID, in: items)
            registerUndo(undoManager: undoManager, oldItems: oldItems)
            applyChanges(to: outdented)
            persistInBackground(from: oldItems, to: outdented)
        } catch {
            logger.warning("Cannot outdent: \(error.localizedDescription)")
        }
    }

    public func updateItemTitle(id: UUID, title: String, undoManager: UndoManager? = nil) {
        guard var item = items.first(where: { $0.id == id }) else { return }
        let oldItems = items
        item.title = title
        item.updatedAt = Date()
        let updated = items.map { $0.id == id ? item : $0 }
        registerUndo(undoManager: undoManager, oldItems: oldItems)
        applyChanges(to: updated)
        persistInBackground(from: oldItems, to: updated)
    }

    public func updateItemNotes(id: UUID, notes: String?, undoManager: UndoManager? = nil) {
        guard var item = items.first(where: { $0.id == id }) else { return }
        let oldItems = items
        item.notes = notes
        item.updatedAt = Date()
        let updated = items.map { $0.id == id ? item : $0 }
        registerUndo(undoManager: undoManager, oldItems: oldItems)
        applyChanges(to: updated)
        persistInBackground(from: oldItems, to: updated)
    }

    public func updateItemQuantity(id: UUID, quantity: Int, undoManager: UndoManager? = nil) {
        guard var item = items.first(where: { $0.id == id }) else { return }
        let oldItems = items
        item.quantity = max(1, quantity)
        item.updatedAt = Date()
        let updated = items.map { $0.id == id ? item : $0 }
        registerUndo(undoManager: undoManager, oldItems: oldItems)
        applyChanges(to: updated)
        persistInBackground(from: oldItems, to: updated)
    }

    // MARK: - Check operations

    public func toggleCheck(itemID: UUID, undoManager: UndoManager? = nil) {
        guard items.contains(where: { $0.id == itemID }) else { return }
        let oldItems = items
        let currentState = flatRows.first(where: { $0.id == itemID })?.checkState
            ?? engine.flatten(items: items, expandedIDs: Set(items.map(\.id)))
                .first(where: { $0.id == itemID })?.checkState
            ?? .unchecked
        let newChecked = currentState != .checked
        let updated = engine.setChecked(newChecked, itemID: itemID, in: items)
        registerUndo(undoManager: undoManager, oldItems: oldItems)
        applyChanges(to: updated)
        persistInBackground(from: oldItems, to: updated)
    }

    public func resetAllChecks(undoManager: UndoManager? = nil) {
        let oldItems = items
        let reset = engine.resetChecks(in: items)
        registerUndo(undoManager: undoManager, oldItems: oldItems)
        applyChanges(to: reset)
        persistInBackground(from: oldItems, to: reset)
    }

    public func resetSubtree(itemID: UUID, undoManager: UndoManager? = nil) {
        let oldItems = items
        let reset = engine.resetChecks(subtreeOf: itemID, in: items)
        registerUndo(undoManager: undoManager, oldItems: oldItems)
        applyChanges(to: reset)
        persistInBackground(from: oldItems, to: reset)
    }

    // MARK: - Expansion

    public func toggleExpanded(_ id: UUID) {
        if expandedIDs.contains(id) {
            expandedIDs.remove(id)
        } else {
            expandedIDs.insert(id)
        }
        rebuildRows()
    }

    public func expandAll() {
        expandedIDs = Set(items.filter { _ in true }.map(\.id))
        rebuildRows()
    }

    public func collapseAll() {
        expandedIDs.removeAll()
        rebuildRows()
    }

    // MARK: - Undo

    private func registerUndo(undoManager: UndoManager?, oldItems: [OutlineItem]) {
        guard let undoManager else { return }
        let snapshot = oldItems
        undoManager.registerUndo(withTarget: UndoProxy.shared) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                let currentItems = self.items
                self.registerUndo(undoManager: undoManager, oldItems: currentItems)
                self.applyChanges(to: snapshot)
                self.persistInBackground(from: currentItems, to: snapshot)
            }
        }
    }
}

private final class UndoProxy: @unchecked Sendable {
    static let shared = UndoProxy()
}
