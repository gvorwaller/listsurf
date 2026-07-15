import SwiftUI
import Domain
import os

public enum OutlineAddPlacement: Equatable, Sendable {
    case root
    case below(UUID)
    case child(UUID)
}

@MainActor
@Observable
public final class ListStore {
    public internal(set) var list: ListItem?
    public var items: [OutlineItem] = []
    public var flatRows: [FlatRow] = []
    public var expandedIDs: Set<UUID> = []
    public var selectedItemIDs: Set<UUID> = []
    public var checkFilter: CheckFilter = .all
    public var searchText = ""

    // Per-list presentation state, owned here so every surface
    // (editor, toolbar, menu bar, context menus) reads one source of truth.
    public var editingItemID: UUID?
    public var addPlacement: OutlineAddPlacement?
    public var pendingDeletionIDs: Set<UUID>?
    public var pendingBranchResetID: UUID?

    public var isTextInputActive: Bool {
        editingItemID != nil || addPlacement != nil
    }

    let listID: UUID
    private let outlineRepo: any OutlineRepository
    private let listRepo: any ListRepository
    private let errorStore: AppErrorStore
    private let engine = TreeEngine()
    private let logger = Logger(subsystem: "net.vorwaller.listsurf", category: "tree")
    @ObservationIgnored private var persistenceTail: Task<Void, Never>?

    public enum CheckFilter: String, CaseIterable {
        case all = "All"
        case remaining = "Remaining"
        case completed = "Completed"
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

        switch checkFilter {
        case .all: break
        case .remaining:
            rows = rows.filter { $0.checkState != .checked }
        case .completed:
            rows = rows.filter { $0.checkState == .checked }
        }

        return rows
    }

    public func load() async {
        // Never read past queued writes: a reload racing the persistence
        // chain would overwrite in-memory edits with stale store data.
        await persistenceTail?.value
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
            try await outlineRepo.applyChanges(saving: changedItems, deletingIDs: [])
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
        enqueuePersist(changed: changed, deletedIDs: deletedIDs)
    }

    private func enqueuePersist(changed: [OutlineItem], deletedIDs: [UUID]) {
        let previous = persistenceTail
        persistenceTail = Task { [outlineRepo, logger, errorStore] in
            await previous?.value
            do {
                try await outlineRepo.applyChanges(saving: changed, deletingIDs: deletedIDs)
            } catch {
                logger.error("Failed to persist changes: \(error.localizedDescription)")
                // Retry re-queues the SAME failed mutation. A reload here
                // would fetch the pre-edit store state and silently discard
                // the user's in-memory change.
                errorStore.present(
                    .persistenceSave(underlying: error.localizedDescription),
                    retryTitle: "Try Again"
                ) { [weak self] in
                    self?.enqueuePersist(changed: changed, deletedIDs: deletedIDs)
                }
            }
        }
    }

    public func waitForPendingPersistence() async {
        await persistenceTail?.value
    }

    // MARK: - Add / edit flow

    public func beginAdding(_ placement: OutlineAddPlacement) {
        // A new item is always born unchecked — it must never be born
        // invisible under the Completed filter (spec §1.4).
        if checkFilter == .completed {
            checkFilter = .all
        }
        var resolved = placement
        switch placement {
        case .root:
            break
        case .below(let refID):
            if !items.contains(where: { $0.id == refID }) {
                logger.warning("Add below: reference item missing; adding at root")
                resolved = .root
            }
        case .child(let parentID):
            if items.contains(where: { $0.id == parentID }) {
                expandedIDs.insert(parentID)
                rebuildRows()
            } else {
                logger.warning("Add child: parent item missing; adding at root")
                resolved = .root
            }
        }
        // Add and rename are mutually exclusive text-entry modes.
        editingItemID = nil
        addPlacement = resolved
    }

    public func cancelAdding() {
        addPlacement = nil
    }

    public func beginEditing(itemID: UUID) {
        guard items.contains(where: { $0.id == itemID }) else { return }
        addPlacement = nil
        selectedItemIDs = [itemID]
        editingItemID = itemID
    }

    public func cancelEditing() {
        editingItemID = nil
    }

    // MARK: - Structural commands

    @discardableResult
    public func addItem(title: String, afterItemID: UUID? = nil, undoManager: UndoManager? = nil) -> UUID {
        let newItem = OutlineItem(listID: listID, title: title)
        let oldItems = items

        let updatedItems: [OutlineItem]
        if let refID = afterItemID, items.contains(where: { $0.id == refID }) {
            updatedItems = engine.insertBelow(referenceID: refID, newItem: newItem, in: items)
        } else {
            if afterItemID != nil {
                logger.warning("Insert below: reference item missing; appending at root")
            }
            var positioned = newItem
            positioned.position = engine.nextPosition(among: items.filter { $0.parentID == nil })
            updatedItems = items + [positioned]
        }

        registerUndo(undoManager: undoManager, oldItems: oldItems)
        applyChanges(to: updatedItems)
        persistInBackground(from: oldItems, to: updatedItems)
        selectedItemIDs = [newItem.id]
        return newItem.id
    }

    @discardableResult
    public func addChild(parentID: UUID, title: String, undoManager: UndoManager? = nil) -> UUID {
        // A missing parent must never reach the engine: insertChild would
        // persist an orphan that only surfaces as a repair alert on next load.
        guard items.contains(where: { $0.id == parentID }) else {
            logger.warning("Add child: parent item missing; appending at root")
            return addItem(title: title, undoManager: undoManager)
        }
        let newItem = OutlineItem(listID: listID, title: title)
        let oldItems = items
        let updatedItems = engine.insertChild(parentID: parentID, newItem: newItem, in: items)
        expandedIDs.insert(parentID)
        registerUndo(undoManager: undoManager, oldItems: oldItems)
        applyChanges(to: updatedItems)
        persistInBackground(from: oldItems, to: updatedItems)
        selectedItemIDs = [newItem.id]
        return newItem.id
    }

    @discardableResult
    public func insertAbove(referenceID: UUID, title: String, undoManager: UndoManager? = nil) -> UUID {
        guard items.contains(where: { $0.id == referenceID }) else {
            logger.warning("Insert above: reference item missing; appending at root")
            return addItem(title: title, undoManager: undoManager)
        }
        let newItem = OutlineItem(listID: listID, title: title)
        let oldItems = items
        let updatedItems = engine.insertAbove(referenceID: referenceID, newItem: newItem, in: items)
        registerUndo(undoManager: undoManager, oldItems: oldItems)
        applyChanges(to: updatedItems)
        persistInBackground(from: oldItems, to: updatedItems)
        selectedItemIDs = [newItem.id]
        return newItem.id
    }

    public func deleteItem(id: UUID, undoManager: UndoManager? = nil) {
        deleteItems(ids: [id], undoManager: undoManager)
    }

    public func deleteItems(ids: Set<UUID>, undoManager: UndoManager? = nil) {
        guard !ids.isEmpty else { return }
        let oldItems = items
        var remaining = items
        for id in ids {
            let (r, _) = engine.deleteSubtree(itemID: id, in: remaining)
            remaining = r
        }
        let remainingIDs = Set(remaining.map(\.id))
        selectedItemIDs = selectedItemIDs.intersection(remainingIDs)
        if let editingItemID, !remainingIDs.contains(editingItemID) {
            self.editingItemID = nil
        }
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

    /// Handles a flat-list drag from `.onMove`. Same-parent clamp semantics
    /// (spec D2). Refused/identity drags return silently: no undo entry, no
    /// persistence, and SwiftUI animates the row back on its own.
    public func moveRows(from source: IndexSet, to destination: Int, undoManager: UndoManager? = nil) {
        // D5 defense-in-depth; keeps D9's invariant. checkFilter != .all is
        // Phase 2 (spec §1.4): filtered rows are a non-contiguous excerpt of
        // true sibling order, so a drag there cannot mean what it looks like.
        guard searchText.isEmpty, !isTextInputActive, checkFilter == .all else { return }
        guard source.count == 1, let sourceIndex = source.first else {
            logger.debug("Drag move ignored: multi-index selection drags are not supported")
            return
        }
        guard let moved = engine.moveVisibleRow(
            at: sourceIndex,
            toVisibleDestination: destination,
            visibleRows: filteredRows,
            in: items
        ) else { return }
        let oldItems = items
        registerUndo(undoManager: undoManager, oldItems: oldItems)
        applyChanges(to: moved)
        persistInBackground(from: oldItems, to: moved)
    }

    public func indent(itemID: UUID, undoManager: UndoManager? = nil) {
        do {
            let oldItems = items
            let indented = try engine.indent(itemID: itemID, in: items)
            // Boundary no-op: nothing to undo, nothing to persist. An undo
            // entry here would make the next ⌘Z consume a do-nothing step.
            guard indented != oldItems else { return }
            // The engine reparents itemID under its previous sibling. Without
            // this, the new parent stays collapsed (expandedIDs starts
            // empty) and the just-indented row silently vanishes — mirrors
            // addChild's expandedIDs.insert(parentID) above.
            if let newParentID = indented.first(where: { $0.id == itemID })?.parentID {
                expandedIDs.insert(newParentID)
            }
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
            guard outdented != oldItems else { return }
            registerUndo(undoManager: undoManager, oldItems: oldItems)
            applyChanges(to: outdented)
            persistInBackground(from: oldItems, to: outdented)
        } catch {
            logger.warning("Cannot outdent: \(error.localizedDescription)")
        }
    }

    public func updateItemTitle(id: UUID, title: String, undoManager: UndoManager? = nil) {
        guard var item = items.first(where: { $0.id == id }), item.title != title else { return }
        let oldItems = items
        item.title = title
        item.updatedAt = Date()
        let updated = items.map { $0.id == id ? item : $0 }
        registerUndo(undoManager: undoManager, oldItems: oldItems)
        applyChanges(to: updated)
        persistInBackground(from: oldItems, to: updated)
    }

    public func updateItemNotes(id: UUID, notes: String?, undoManager: UndoManager? = nil) {
        guard var item = items.first(where: { $0.id == id }), item.notes != notes else { return }
        let oldItems = items
        item.notes = notes
        item.updatedAt = Date()
        let updated = items.map { $0.id == id ? item : $0 }
        registerUndo(undoManager: undoManager, oldItems: oldItems)
        applyChanges(to: updated)
        persistInBackground(from: oldItems, to: updated)
    }

    public func updateItemQuantity(id: UUID, quantity: Int, undoManager: UndoManager? = nil) {
        guard var item = items.first(where: { $0.id == id }),
              item.quantity != max(1, quantity) else { return }
        let oldItems = items
        item.quantity = max(1, quantity)
        item.updatedAt = Date()
        let updated = items.map { $0.id == id ? item : $0 }
        registerUndo(undoManager: undoManager, oldItems: oldItems)
        applyChanges(to: updated)
        persistInBackground(from: oldItems, to: updated)
    }

    // MARK: - Check operations

    /// Resolves a row's derived state even when it is currently hidden
    /// (collapsed ancestor) — visible rows already carry a derived
    /// checkState; a collapsed row needs a full flatten to derive its
    /// parent tri-state (the trick `toggleCheck` used pre-unification).
    public func resolvedRow(for id: UUID) -> FlatRow? {
        flatRows.first(where: { $0.id == id })
            ?? engine.flatten(items: items, expandedIDs: Set(items.map(\.id))).first(where: { $0.id == id })
    }

    /// What a `toggleChecked(ids:)` call would do to this set right now:
    /// true = check, false = uncheck (spec §1.3's multi-select rule — every
    /// resolved row already checked → uncheck, otherwise check). Used by
    /// menu surfaces to render a dynamic "Check"/"Uncheck" label without
    /// duplicating the rule.
    public func wouldCheck(ids: Set<UUID>) -> Bool {
        let states = ids.compactMap { resolvedRow(for: $0)?.checkState }
        guard !states.isEmpty else { return true }
        return !states.allSatisfy { $0 == .checked }
    }

    public func toggleCheck(itemID: UUID, undoManager: UndoManager? = nil) {
        toggleChecked(ids: [itemID], undoManager: undoManager)
    }

    /// Multi-select toggle rule (spec §1.3): if every resolved row's
    /// checkState == .checked, uncheck the batch; otherwise check it. One
    /// undo step covers the whole batch, and a no-op (nothing actually
    /// changed) registers no undo entry at all.
    public func toggleChecked(ids: Set<UUID>, undoManager: UndoManager? = nil) {
        guard !ids.isEmpty else { return }
        guard ids.contains(where: { resolvedRow(for: $0) != nil }) else { return }
        let newChecked = wouldCheck(ids: ids)

        let oldItems = items
        var updated = items
        for id in ids {
            updated = engine.setChecked(newChecked, itemID: id, in: updated)
        }
        // No-op guard BEFORE registering undo: an unchanged result must not
        // consume the next ⌘Z.
        guard updated != oldItems else { return }

        // Selection-advance under filter (spec §1.3) needs the pre-toggle
        // selection and filtered order captured before applyChanges rebuilds
        // flatRows/filteredRows against the new items.
        let preToggleSelection = selectedItemIDs
        let oldFilteredRows = filteredRows
        // A checkbox tap on an unselected row must never move selection —
        // only advance when the toggled ids overlap the current selection
        // (Space/⌘K/menu always toggle exactly the selection).
        let togglesSelectedRow = !ids.isDisjoint(with: preToggleSelection)

        registerUndo(undoManager: undoManager, oldItems: oldItems)
        applyChanges(to: updated)
        persistInBackground(from: oldItems, to: updated)

        guard checkFilter != .all, togglesSelectedRow, !preToggleSelection.isEmpty else { return }
        let newFilteredIDs = Set(filteredRows.map(\.id))
        guard preToggleSelection.isDisjoint(with: newFilteredIDs) else { return }
        guard let removedIndex = oldFilteredRows.firstIndex(where: { preToggleSelection.contains($0.id) }) else { return }
        let newRows = filteredRows
        selectedItemIDs = newRows.isEmpty ? [] : [newRows[min(removedIndex, newRows.count - 1)].id]
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
        expandedIDs = Set(items.map(\.id))
        rebuildRows()
    }

    public func collapseAll() {
        expandedIDs.removeAll()
        rebuildRows()
    }

    // MARK: - Undo

    private func registerUndo(undoManager: UndoManager?, oldItems: [OutlineItem]) {
        guard let undoManager else { return }
        let itemsSnapshot = oldItems
        let selectionSnapshot = selectedItemIDs
        // The handler must apply the snapshot and re-register SYNCHRONOUSLY:
        // NSUndoManager only turns registrations made during undo() into redo
        // entries. Deferring to a Task would silently break redo.
        undoManager.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated {
                let currentItems = store.items
                store.registerUndo(undoManager: undoManager, oldItems: currentItems)
                store.applyChanges(to: itemsSnapshot)
                let restoredIDs = Set(itemsSnapshot.map(\.id))
                store.selectedItemIDs = selectionSnapshot.intersection(restoredIDs)
                store.persistInBackground(from: currentItems, to: itemsSnapshot)
            }
        }
    }

    /// Remove this store's pending undo actions. Call when the store is
    /// replaced or its view goes away, so the Undo menu can't resurrect
    /// (and persist) mutations against a list that is no longer on screen.
    public func teardownUndo(_ undoManager: UndoManager?) {
        undoManager?.removeAllActions(withTarget: self)
    }
}
