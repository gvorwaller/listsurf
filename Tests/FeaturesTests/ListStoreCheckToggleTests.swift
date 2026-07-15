import XCTest
@testable import Domain
@testable import Features

/// Tests for `ListStore.toggleChecked(ids:undoManager:)` (spec §1.3, M5
/// Phase 2 unification): the multi-select toggle rule, one-undo-step batch
/// contract, the no-op guard, and selection-advance under an active filter.
final class ListStoreCheckToggleTests: XCTestCase {
    @MainActor
    private func makeStore(items: [OutlineItem], list: ListItem = ListItem(title: "Test")) -> ListStore {
        let store = ListStore(
            listID: list.id,
            outlineRepo: InMemoryOutlineRepository(items: items),
            listRepo: CheckToggleTestListRepository(list: list)
        )
        store.items = items
        store.expandAll()
        return store
    }

    private func makeUndoManager() -> UndoManager {
        UndoManager()
    }

    @MainActor
    func testToggleCheckedMixedSelectionChecksAll() {
        let list = ListItem(title: "Test")
        let a = OutlineItem(listID: list.id, title: "A", isChecked: true)
        let b = OutlineItem(listID: list.id, title: "B", isChecked: false)
        let store = makeStore(items: [a, b], list: list)

        store.toggleChecked(ids: [a.id, b.id])

        XCTAssertTrue(store.items.allSatisfy(\.isChecked), "A mixed selection must check everything, not uncheck")
    }

    @MainActor
    func testToggleCheckedAllCheckedSelectionUnchecksAll() {
        let list = ListItem(title: "Test")
        let a = OutlineItem(listID: list.id, title: "A", isChecked: true)
        let b = OutlineItem(listID: list.id, title: "B", isChecked: true)
        let store = makeStore(items: [a, b], list: list)

        store.toggleChecked(ids: [a.id, b.id])

        XCTAssertTrue(store.items.allSatisfy { !$0.isChecked }, "An all-checked selection must uncheck everything")
    }

    @MainActor
    func testToggleCheckedBatchIsOneUndoStep() async {
        let list = ListItem(title: "Test")
        let a = OutlineItem(listID: list.id, title: "A", isChecked: false)
        let b = OutlineItem(listID: list.id, title: "B", isChecked: false)
        let c = OutlineItem(listID: list.id, title: "C", isChecked: false)
        let store = makeStore(items: [a, b, c], list: list)
        let undoManager = makeUndoManager()

        store.toggleChecked(ids: [a.id, b.id, c.id], undoManager: undoManager)
        XCTAssertTrue(store.items.allSatisfy(\.isChecked))

        XCTAssertTrue(undoManager.canUndo)
        undoManager.undo()
        XCTAssertTrue(store.items.allSatisfy { !$0.isChecked }, "A single undo must revert the whole batch")

        XCTAssertTrue(undoManager.canRedo, "Undoing must synchronously register the redo entry")
        undoManager.redo()
        XCTAssertTrue(store.items.allSatisfy(\.isChecked), "A single redo must reapply the whole batch")

        await store.waitForPendingPersistence()
    }

    @MainActor
    func testToggleCheckedNoOpRegistersNoUndo() {
        let list = ListItem(title: "Test")
        let a = OutlineItem(listID: list.id, title: "A", isChecked: false)
        let store = makeStore(items: [a], list: list)
        let undoManager = makeUndoManager()
        let itemsBefore = store.items

        // An id that resolves to no row must be a true no-op: nothing to
        // change, nothing to undo.
        store.toggleChecked(ids: [UUID()], undoManager: undoManager)

        XCTAssertEqual(store.items, itemsBefore)
        XCTAssertFalse(undoManager.canUndo, "A no-op toggle must not consume the next Cmd-Z")
    }

    /// Space-Space-Space under Remaining (spec §1.3): after the selected row
    /// is checked and drops out of the filter, selection moves to whatever
    /// now occupies its old filtered index.
    @MainActor
    func testSelectionAdvancesUnderRemainingFilterAfterToggle() {
        let list = ListItem(title: "Test")
        let first = OutlineItem(listID: list.id, title: "First", isChecked: false, position: 1)
        let second = OutlineItem(listID: list.id, title: "Second", isChecked: false, position: 2)
        let third = OutlineItem(listID: list.id, title: "Third", isChecked: false, position: 3)
        let store = makeStore(items: [first, second, third], list: list)
        store.checkFilter = .remaining
        store.selectedItemIDs = [first.id]

        store.toggleChecked(ids: [first.id])

        XCTAssertEqual(
            store.selectedItemIDs, [second.id],
            "Checking off the selected row should advance selection to the row now at its old index"
        )
    }

    /// Emptying the filtered list via toggle must clear selection, not point
    /// at a stale/out-of-range index.
    @MainActor
    func testSelectionClearsWhenLastRemainingRowIsToggled() {
        let list = ListItem(title: "Test")
        let only = OutlineItem(listID: list.id, title: "Only", isChecked: false)
        let store = makeStore(items: [only], list: list)
        store.checkFilter = .remaining
        store.selectedItemIDs = [only.id]

        store.toggleChecked(ids: [only.id])

        XCTAssertEqual(store.selectedItemIDs, [], "Toggling the last remaining row must leave an empty selection")
    }

    /// A checkbox tap always targets exactly the row it belongs to. If that
    /// row is not the current selection, toggling it must never move
    /// selection — even when the toggle has a side effect (via derived
    /// parent state) that removes the SELECTED row from filteredRows too.
    @MainActor
    func testCheckboxTapOnUnselectedRowNeverMovesSelectionEvenWithCascadingParentEffect() {
        let list = ListItem(title: "Test")
        let parent = OutlineItem(listID: list.id, title: "Parent", isChecked: false)
        let childA = OutlineItem(listID: list.id, parentID: parent.id, title: "Child A", isChecked: true)
        let childB = OutlineItem(listID: list.id, parentID: parent.id, title: "Child B", isChecked: false)
        let store = makeStore(items: [parent, childA, childB], list: list)
        store.checkFilter = .remaining
        // Parent is mixed (one checked child, one not) so it's visible under
        // Remaining; select it, then tap the checkbox of the OTHER
        // (unselected) child.
        store.selectedItemIDs = [parent.id]
        XCTAssertTrue(store.filteredRows.contains { $0.id == parent.id }, "Precondition: mixed parent is visible")

        store.toggleCheck(itemID: childB.id)

        // Both children are now checked, so the parent's derived state flips
        // to .checked and it drops out of the Remaining filter as a side
        // effect — but selection must still be untouched.
        XCTAssertFalse(store.filteredRows.contains { $0.id == parent.id }, "Precondition: parent is now fully checked")
        XCTAssertEqual(
            store.selectedItemIDs, [parent.id],
            "A checkbox tap on an unselected row must never move selection, even indirectly"
        )
    }
}

private actor InMemoryOutlineRepository: OutlineRepository {
    private var items: [OutlineItem]

    init(items: [OutlineItem]) {
        self.items = items
    }

    func fetchItems(forList listID: UUID) async throws -> [OutlineItem] {
        items.filter { $0.listID == listID }
    }

    func applyChanges(saving newItems: [OutlineItem], deletingIDs: [UUID]) async throws {
        let savedIDs = Set(newItems.map(\.id))
        items.removeAll { savedIDs.contains($0.id) }
        items.append(contentsOf: newItems)
        let deleted = Set(deletingIDs)
        items.removeAll { deleted.contains($0.id) }
    }
}

private actor CheckToggleTestListRepository: ListRepository {
    private var list: ListItem

    init(list: ListItem) {
        self.list = list
    }

    func fetchAll() async throws -> [ListItem] { [list] }
    func fetchActive() async throws -> [ListItem] { [list] }
    func fetchArchived() async throws -> [ListItem] { [] }
    func fetch(id: UUID) async throws -> ListItem? { id == list.id ? list : nil }
    func save(_ list: ListItem) async throws { self.list = list }
    func saveListAndItems(_ list: ListItem, items: [OutlineItem]) async throws {
        self.list = list
    }
    func replaceAllListsAndItems(with archive: LibraryArchive) async throws {
        if let first = archive.lists.first?.list {
            list = first
        }
    }
    func addListsAndItems(with archive: LibraryArchive) async throws {}
    func fetchLibraryArchive() async throws -> LibraryArchive {
        LibraryArchive(lists: [ArchivedList(list: list, items: [])])
    }
    func deleteListAndItems(id: UUID) async throws {}
}
