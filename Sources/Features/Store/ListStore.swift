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
    private let engine = TreeEngine()
    private let logger = Logger(subsystem: "com.listsurf.app", category: "tree")

    public enum CheckFilter: String, CaseIterable {
        case all = "All"
        case unchecked = "Unchecked"
        case checked = "Checked"
    }

    init(listID: UUID, outlineRepo: any OutlineRepository, listRepo: any ListRepository) {
        self.listID = listID
        self.outlineRepo = outlineRepo
        self.listRepo = listRepo
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
            rows = rows.filter { visibleIDs.contains($0.id) }
        }

        if isCheckMode {
            switch checkFilter {
            case .all: break
            case .unchecked:
                rows = rows.filter { !$0.item.isChecked }
            case .checked:
                rows = rows.filter { $0.item.isChecked }
            }
        }

        return rows
    }

    public func load() async {
        do {
            list = try await listRepo.fetch(id: listID)
            items = try await outlineRepo.fetchItems(forList: listID)
            rebuildRows()
        } catch {
            logger.error("Failed to load items: \(error.localizedDescription)")
        }
    }

    private func rebuildRows() {
        flatRows = engine.flatten(items: items, expandedIDs: expandedIDs)
    }

    private func persist(_ updatedItems: [OutlineItem]) async {
        items = updatedItems
        rebuildRows()
        do {
            try await outlineRepo.saveAll(updatedItems)
        } catch {
            logger.error("Failed to persist items: \(error.localizedDescription)")
        }
    }

    private func persistChanged(from oldItems: [OutlineItem], to newItems: [OutlineItem]) async {
        let oldMap = Dictionary(uniqueKeysWithValues: oldItems.map { ($0.id, $0) })
        let changed = newItems.filter { item in
            guard let old = oldMap[item.id] else { return true }
            return old != item
        }
        items = newItems
        rebuildRows()
        do {
            if !changed.isEmpty {
                try await outlineRepo.saveAll(changed)
            }
            let newIDs = Set(newItems.map(\.id))
            let deletedIDs = oldItems.filter { !newIDs.contains($0.id) }.map(\.id)
            if !deletedIDs.isEmpty {
                try await outlineRepo.deleteAll(ids: deletedIDs)
            }
        } catch {
            logger.error("Failed to persist changes: \(error.localizedDescription)")
        }
    }

    // MARK: - Structural commands

    public func addItem(title: String, afterItemID: UUID? = nil, undoManager: UndoManager? = nil) async {
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
        await persistChanged(from: oldItems, to: updatedItems)
    }

    public func addChild(parentID: UUID, title: String, undoManager: UndoManager? = nil) async {
        let newItem = OutlineItem(listID: listID, title: title)
        let oldItems = items
        let updatedItems = engine.insertChild(parentID: parentID, newItem: newItem, in: items)
        expandedIDs.insert(parentID)
        registerUndo(undoManager: undoManager, oldItems: oldItems)
        await persistChanged(from: oldItems, to: updatedItems)
    }

    public func insertAbove(referenceID: UUID, title: String, undoManager: UndoManager? = nil) async {
        let newItem = OutlineItem(listID: listID, title: title)
        let oldItems = items
        let updatedItems = engine.insertAbove(referenceID: referenceID, newItem: newItem, in: items)
        registerUndo(undoManager: undoManager, oldItems: oldItems)
        await persistChanged(from: oldItems, to: updatedItems)
    }

    public func deleteItem(id: UUID, undoManager: UndoManager? = nil) async {
        let oldItems = items
        let (remaining, _) = engine.deleteSubtree(itemID: id, in: items)
        selectedItemIDs.remove(id)
        registerUndo(undoManager: undoManager, oldItems: oldItems)
        await persistChanged(from: oldItems, to: remaining)
    }

    public func deleteSelected(undoManager: UndoManager? = nil) async {
        let oldItems = items
        var remaining = items
        for id in selectedItemIDs {
            let (r, _) = engine.deleteSubtree(itemID: id, in: remaining)
            remaining = r
        }
        selectedItemIDs.removeAll()
        registerUndo(undoManager: undoManager, oldItems: oldItems)
        await persistChanged(from: oldItems, to: remaining)
    }

    public func moveUp(itemID: UUID, undoManager: UndoManager? = nil) async {
        guard let moved = engine.moveUp(itemID: itemID, in: items) else { return }
        let oldItems = items
        registerUndo(undoManager: undoManager, oldItems: oldItems)
        await persistChanged(from: oldItems, to: moved)
    }

    public func moveDown(itemID: UUID, undoManager: UndoManager? = nil) async {
        guard let moved = engine.moveDown(itemID: itemID, in: items) else { return }
        let oldItems = items
        registerUndo(undoManager: undoManager, oldItems: oldItems)
        await persistChanged(from: oldItems, to: moved)
    }

    public func indent(itemID: UUID, undoManager: UndoManager? = nil) async {
        do {
            let oldItems = items
            let indented = try engine.indent(itemID: itemID, in: items)
            registerUndo(undoManager: undoManager, oldItems: oldItems)
            await persistChanged(from: oldItems, to: indented)
        } catch {
            logger.warning("Cannot indent: \(error.localizedDescription)")
        }
    }

    public func outdent(itemID: UUID, undoManager: UndoManager? = nil) async {
        do {
            let oldItems = items
            let outdented = try engine.outdent(itemID: itemID, in: items)
            registerUndo(undoManager: undoManager, oldItems: oldItems)
            await persistChanged(from: oldItems, to: outdented)
        } catch {
            logger.warning("Cannot outdent: \(error.localizedDescription)")
        }
    }

    public func updateItemTitle(id: UUID, title: String, undoManager: UndoManager? = nil) async {
        guard var item = items.first(where: { $0.id == id }) else { return }
        let oldItems = items
        item.title = title
        item.updatedAt = Date()
        let updated = items.map { $0.id == id ? item : $0 }
        registerUndo(undoManager: undoManager, oldItems: oldItems)
        await persistChanged(from: oldItems, to: updated)
    }

    public func updateItemNotes(id: UUID, notes: String?, undoManager: UndoManager? = nil) async {
        guard var item = items.first(where: { $0.id == id }) else { return }
        let oldItems = items
        item.notes = notes
        item.updatedAt = Date()
        let updated = items.map { $0.id == id ? item : $0 }
        registerUndo(undoManager: undoManager, oldItems: oldItems)
        await persistChanged(from: oldItems, to: updated)
    }

    public func updateItemQuantity(id: UUID, quantity: Int, undoManager: UndoManager? = nil) async {
        guard var item = items.first(where: { $0.id == id }) else { return }
        let oldItems = items
        item.quantity = max(1, quantity)
        item.updatedAt = Date()
        let updated = items.map { $0.id == id ? item : $0 }
        registerUndo(undoManager: undoManager, oldItems: oldItems)
        await persistChanged(from: oldItems, to: updated)
    }

    // MARK: - Check operations

    public func toggleCheck(itemID: UUID, undoManager: UndoManager? = nil) async {
        guard let item = items.first(where: { $0.id == itemID }) else { return }
        let oldItems = items
        let newChecked = !item.isChecked
        let updated = engine.setChecked(newChecked, itemID: itemID, in: items)
        registerUndo(undoManager: undoManager, oldItems: oldItems)
        await persistChanged(from: oldItems, to: updated)
    }

    public func resetAllChecks(undoManager: UndoManager? = nil) async {
        let oldItems = items
        let reset = engine.resetChecks(in: items)
        registerUndo(undoManager: undoManager, oldItems: oldItems)
        await persistChanged(from: oldItems, to: reset)
    }

    public func resetSubtree(itemID: UUID, undoManager: UndoManager? = nil) async {
        let oldItems = items
        let reset = engine.resetChecks(subtreeOf: itemID, in: items)
        registerUndo(undoManager: undoManager, oldItems: oldItems)
        await persistChanged(from: oldItems, to: reset)
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
                await self.persistChanged(from: currentItems, to: snapshot)
            }
        }
    }
}

private final class UndoProxy: @unchecked Sendable {
    static let shared = UndoProxy()
}
