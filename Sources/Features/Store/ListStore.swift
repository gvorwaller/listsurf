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
    // expandedIDs/selectedItemIDs/checkFilter are per-list VIEW state
    // (td-5d405a): persisted to UserDefaults via `persistViewState()` on
    // every change (didSet, not per-call-site calls — these three are
    // mutated from many places across ListStore and its views) and seeded
    // back in `load()`. Scroll position is intentionally excluded.
    public var expandedIDs: Set<UUID> = [] {
        didSet { if oldValue != expandedIDs { persistViewState() } }
    }
    /// Row IDs whose note preview is expanded past the Settings line-limit
    /// (td-50f035, plan item 11) — transient UI state, never persisted, and
    /// cleared on `load()` so a note left expanded in one list doesn't leak
    /// into the next.
    public var expandedNoteIDs: Set<UUID> = []
    public var selectedItemIDs: Set<UUID> = [] {
        didSet { if oldValue != selectedItemIDs { persistViewState() } }
    }
    public var checkFilter: CheckFilter = .all {
        didSet {
            if oldValue != checkFilter {
                rowsVersion += 1
                persistViewState()
            }
        }
    }
    public var searchText = "" {
        didSet { if oldValue != searchText { rowsVersion += 1 } }
    }

    /// Cheap change token for `filteredRows`' composition (td-e7c609): bumped
    /// whenever `flatRows` is rebuilt or a filter/search term actually
    /// changes. Lets the editor drive its List's `.animation(value:)` off an
    /// Int instead of remapping `filteredRows` to `[UUID]` on every body pass
    /// just to diff it.
    public private(set) var rowsVersion = 0

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
    private let userDefaults: UserDefaults
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
        errorStore: AppErrorStore = AppErrorStore(),
        userDefaults: UserDefaults = .standard
    ) {
        self.listID = listID
        self.outlineRepo = outlineRepo
        self.listRepo = listRepo
        self.errorStore = errorStore
        self.userDefaults = userDefaults
    }

    public var progress: (checked: Int, total: Int) {
        engine.listProgress(items: items)
    }

    public var filteredRows: [FlatRow] {
        var rows = flatRows

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            // Plan item 12e (E1a): a note-only match must surface the row
            // too, not just a title match — the ancestor-expansion below
            // treats both the same way.
            let matchingIDs = Set(items.filter {
                $0.title.lowercased().contains(query) || ($0.notes?.lowercased().contains(query) ?? false)
            }.map(\.id))
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
        expandedNoteIDs.removeAll()
        do {
            list = try await listRepo.fetch(id: listID)
            let fetchedItems = try await outlineRepo.fetchItems(forList: listID)
            let repair = engine.repairInvalidParents(in: fetchedItems)
            let repairedCount = repair.orphanCount + repair.cycleCount
            items = repair.repaired
            seedViewState()
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
        rowsVersion += 1
    }

    /// Restores persisted view state (td-5d405a) for this list, if any.
    /// Must run AFTER `items` is assigned (stale ids from deleted rows are
    /// pruned against the just-loaded items) and BEFORE `rebuildRows()` —
    /// synchronous back-to-back assignments here let `@Observable` batch
    /// them into one render pass, so there's no visible collapse-then-
    /// expand flash. Missing/undecodable state leaves the current
    /// defaults untouched.
    private func seedViewState() {
        guard let data = userDefaults.data(forKey: ListViewState.viewStateKey(for: listID)),
              let stored = try? JSONDecoder().decode(ListViewState.self, from: data) else { return }
        let itemIDs = Set(items.map(\.id))
        expandedIDs = stored.expandedIDs.intersection(itemIDs)
        selectedItemIDs = stored.selectedItemIDs.intersection(itemIDs)
        checkFilter = CheckFilter(rawValue: stored.checkFilterRawValue) ?? .all
    }

    /// Single write path for per-list view-state persistence (td-5d405a),
    /// called from `expandedIDs`/`selectedItemIDs`/`checkFilter`'s `didSet`
    /// observers so every mutation site — inside `ListStore` and from views
    /// binding directly to these properties — persists without needing its
    /// own call.
    private func persistViewState() {
        let state = ListViewState(
            expandedIDs: expandedIDs,
            checkFilterRawValue: checkFilter.rawValue,
            selectedItemIDs: selectedItemIDs
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        userDefaults.set(data, forKey: ListViewState.viewStateKey(for: listID))
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

    /// Selection-advance on delete (spec M5 gate M2): if the deletion hit the
    /// current selection, the row that took its place (or the previous row,
    /// clamped, if the deleted rows were last) becomes selected — staying in
    /// the editor instead of falling back to the sidebar. Pre-delete state
    /// (`oldFilteredRows`, whether the ids overlap selection) must be
    /// captured before any mutation.
    public func deleteItems(ids: Set<UUID>, undoManager: UndoManager? = nil) {
        guard !ids.isEmpty else { return }
        let oldItems = items
        let oldFilteredRows = filteredRows
        let deletionHitSelection = !ids.isDisjoint(with: selectedItemIDs)

        var remaining = items
        for id in ids {
            let (r, _) = engine.deleteSubtree(itemID: id, in: remaining)
            remaining = r
        }
        let remainingIDs = Set(remaining.map(\.id))

        // Undo must snapshot the selection BEFORE it's emptied below —
        // registering after (the old order) made ⌘Z restore the deleted
        // items into an already-emptied selection (M2 gate: latent bug).
        registerUndo(undoManager: undoManager, oldItems: oldItems)

        selectedItemIDs = selectedItemIDs.intersection(remainingIDs)
        if let editingItemID, !remainingIDs.contains(editingItemID) {
            self.editingItemID = nil
        }
        applyChanges(to: remaining)
        persistInBackground(from: oldItems, to: remaining)

        // Deletion that never touched the selection leaves it alone (minus
        // the survivor intersection above) — a checkbox-style side effect
        // must never relocate a selection it didn't affect.
        guard deletionHitSelection else { return }
        guard let removedIndex = oldFilteredRows.firstIndex(where: { ids.contains($0.id) }) else { return }
        let newRows = filteredRows
        selectedItemIDs = newRows.isEmpty ? [] : [newRows[min(removedIndex, newRows.count - 1)].id]
    }

    public func moveUp(itemID: UUID, undoManager: UndoManager? = nil) {
        moveUp(itemIDs: [itemID], undoManager: undoManager)
    }

    public func moveDown(itemID: UUID, undoManager: UndoManager? = nil) {
        moveDown(itemIDs: [itemID], undoManager: undoManager)
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
        indent(itemIDs: [itemID], undoManager: undoManager)
    }

    public func outdent(itemID: UUID, undoManager: UndoManager? = nil) {
        outdent(itemIDs: [itemID], undoManager: undoManager)
    }

    // MARK: - Multi-select structure ops (plan item 10)

    private enum StructureOpOrder {
        case topToBottom
        case bottomToTop
    }

    /// Drops any id whose ancestor is ALSO in the set — an indent/outdent/
    /// move on a child is redundant (and order-fragile) when its parent is
    /// being processed in the same batch; the child rides along with its
    /// parent's mutation instead of being applied twice.
    private func ancestorFiltered(_ itemIDs: Set<UUID>) -> Set<UUID> {
        itemIDs.filter { id in
            Set(engine.ancestorIDs(of: id, in: items)).isDisjoint(with: itemIDs)
        }
    }

    /// Orders the ancestor-filtered ids by their CURRENT `flatRows` position
    /// (top-to-bottom, or reversed) — indent/moveUp must process top-to-
    /// bottom and outdent/moveDown bottom-to-top to preserve the selection's
    /// relative order (proven against TreeEngine's insertion semantics in
    /// the plan). Any id `flatRows` doesn't (yet) contain — a stale flatRows
    /// snapshot, e.g. in tests that assign `items` directly — still gets
    /// included, just ordered after every id `flatRows` does resolve.
    private func orderedForStructureOp(_ itemIDs: Set<UUID>, order: StructureOpOrder) -> [UUID] {
        let filtered = ancestorFiltered(itemIDs)
        guard !filtered.isEmpty else { return [] }
        let indexByID = Dictionary(uniqueKeysWithValues: flatRows.enumerated().map { ($0.element.id, $0.offset) })
        let sorted = filtered.sorted { (indexByID[$0] ?? Int.max) < (indexByID[$1] ?? Int.max) }
        return order == .topToBottom ? sorted : sorted.reversed()
    }

    /// Multi-select indent (spec item 10): one undo/persist for the whole
    /// batch, all-or-nothing — if ANY member's step is a boundary no-op (or
    /// throws), the entire batch aborts with NO mutation and NO undo entry,
    /// since a partial application could restructure the selection into a
    /// different shape than the one the user picked.
    public func indent(itemIDs: Set<UUID>, undoManager: UndoManager? = nil) {
        let ids = orderedForStructureOp(itemIDs, order: .topToBottom)
        guard !ids.isEmpty else { return }
        let oldItems = items
        var working = items
        var newParentIDs: Set<UUID> = []
        for id in ids {
            do {
                let result = try engine.indent(itemID: id, in: working)
                guard result != working else {
                    logger.warning("Multi-indent aborted: boundary no-op for \(id)")
                    return
                }
                if let newParentID = result.first(where: { $0.id == id })?.parentID {
                    newParentIDs.insert(newParentID)
                }
                working = result
            } catch {
                logger.warning("Multi-indent aborted: \(error.localizedDescription)")
                return
            }
        }
        // Every new parent must be expanded — mirrors the single-item
        // indent's expandedIDs.insert(newParentID) above.
        expandedIDs.formUnion(newParentIDs)
        registerUndo(undoManager: undoManager, oldItems: oldItems)
        applyChanges(to: working)
        persistInBackground(from: oldItems, to: working)
    }

    public func outdent(itemIDs: Set<UUID>, undoManager: UndoManager? = nil) {
        let ids = orderedForStructureOp(itemIDs, order: .bottomToTop)
        guard !ids.isEmpty else { return }
        let oldItems = items
        var working = items
        for id in ids {
            do {
                let result = try engine.outdent(itemID: id, in: working)
                guard result != working else {
                    logger.warning("Multi-outdent aborted: boundary no-op for \(id)")
                    return
                }
                working = result
            } catch {
                logger.warning("Multi-outdent aborted: \(error.localizedDescription)")
                return
            }
        }
        registerUndo(undoManager: undoManager, oldItems: oldItems)
        applyChanges(to: working)
        persistInBackground(from: oldItems, to: working)
    }

    public func moveUp(itemIDs: Set<UUID>, undoManager: UndoManager? = nil) {
        let ids = orderedForStructureOp(itemIDs, order: .topToBottom)
        guard !ids.isEmpty else { return }
        let oldItems = items
        var working = items
        for id in ids {
            guard let result = engine.moveUp(itemID: id, in: working) else {
                logger.warning("Multi-moveUp aborted: boundary no-op for \(id)")
                return
            }
            working = result
        }
        registerUndo(undoManager: undoManager, oldItems: oldItems)
        applyChanges(to: working)
        persistInBackground(from: oldItems, to: working)
    }

    public func moveDown(itemIDs: Set<UUID>, undoManager: UndoManager? = nil) {
        let ids = orderedForStructureOp(itemIDs, order: .bottomToTop)
        guard !ids.isEmpty else { return }
        let oldItems = items
        var working = items
        for id in ids {
            guard let result = engine.moveDown(itemID: id, in: working) else {
                logger.warning("Multi-moveDown aborted: boundary no-op for \(id)")
                return
            }
            working = result
        }
        registerUndo(undoManager: undoManager, oldItems: oldItems)
        applyChanges(to: working)
        persistInBackground(from: oldItems, to: working)
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

    /// Toggles the note-preview expand-in-place affordance (td-50f035,
    /// plan item 11). Presentation-only: no row-tree rebuild needed since
    /// this never changes which rows are visible, only how tall one row's
    /// note preview renders.
    public func toggleNoteExpanded(_ id: UUID) {
        if expandedNoteIDs.contains(id) {
            expandedNoteIDs.remove(id)
        } else {
            expandedNoteIDs.insert(id)
        }
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
