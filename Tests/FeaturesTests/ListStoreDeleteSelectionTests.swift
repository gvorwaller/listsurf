import XCTest
@testable import Domain
@testable import Features

/// Tests for `ListStore.deleteItems(ids:undoManager:)`'s selection-advance
/// (M5 gate M2, fix plan item 6): after a delete that hits the current
/// selection, the row that took its place (or the previous row, clamped, if
/// the deleted rows were last) becomes selected — staying in the editor
/// instead of falling back to the sidebar. Also covers the undo-ordering fix
/// (registerUndo now runs BEFORE the selection is emptied).
final class ListStoreDeleteSelectionTests: XCTestCase {
    @MainActor
    private func makeStore(items: [OutlineItem], list: ListItem = ListItem(title: "Test")) -> ListStore {
        let store = ListStore(
            listID: list.id,
            outlineRepo: InMemoryOutlineRepository(items: items),
            listRepo: DeleteSelectionTestListRepository(list: list)
        )
        store.items = items
        store.expandAll()
        return store
    }

    private func makeUndoManager() -> UndoManager {
        UndoManager()
    }

    @MainActor
    func testDeleteMiddleRowSelectsRowThatTookItsPlace() {
        let list = ListItem(title: "Test")
        let a = OutlineItem(listID: list.id, title: "A", position: 1)
        let b = OutlineItem(listID: list.id, title: "B", position: 2)
        let c = OutlineItem(listID: list.id, title: "C", position: 3)
        let store = makeStore(items: [a, b, c], list: list)
        store.selectedItemIDs = [b.id]

        store.deleteItems(ids: [b.id])

        XCTAssertEqual(store.selectedItemIDs, [c.id], "C slid into B's old slot and should be selected")
    }

    @MainActor
    func testDeleteLastRowSelectsPreviousRow() {
        let list = ListItem(title: "Test")
        let a = OutlineItem(listID: list.id, title: "A", position: 1)
        let b = OutlineItem(listID: list.id, title: "B", position: 2)
        let c = OutlineItem(listID: list.id, title: "C", position: 3)
        let store = makeStore(items: [a, b, c], list: list)
        store.selectedItemIDs = [c.id]

        store.deleteItems(ids: [c.id])

        XCTAssertEqual(store.selectedItemIDs, [b.id], "Deleting the last row must clamp to the previous row")
    }

    @MainActor
    func testDeleteUnderRemainingFilterSelectsNextVisibleRow() {
        let list = ListItem(title: "Test")
        let a = OutlineItem(listID: list.id, title: "A", position: 1)
        let b = OutlineItem(listID: list.id, title: "B", position: 2)
        // Checked — hidden under the Remaining filter. If the advance logic
        // computed against the unfiltered tree it would land here, which
        // must never happen while the filter is active.
        let c = OutlineItem(listID: list.id, title: "C", isChecked: true, position: 3)
        let d = OutlineItem(listID: list.id, title: "D", position: 4)
        let store = makeStore(items: [a, b, c, d], list: list)
        store.checkFilter = .remaining
        XCTAssertEqual(store.filteredRows.map { $0.item.id }, [a.id, b.id, d.id], "Precondition: C is hidden")
        store.selectedItemIDs = [b.id]

        store.deleteItems(ids: [b.id])

        XCTAssertEqual(store.selectedItemIDs, [d.id], "Selection must advance to the next VISIBLE row, skipping the hidden checked row")
    }

    @MainActor
    func testDeleteMultiSelectionSelectsRowAfterLastDeleted() {
        let list = ListItem(title: "Test")
        let a = OutlineItem(listID: list.id, title: "A", position: 1)
        let b = OutlineItem(listID: list.id, title: "B", position: 2)
        let c = OutlineItem(listID: list.id, title: "C", position: 3)
        let d = OutlineItem(listID: list.id, title: "D", position: 4)
        let e = OutlineItem(listID: list.id, title: "E", position: 5)
        let store = makeStore(items: [a, b, c, d, e], list: list)
        store.selectedItemIDs = [b.id, c.id]

        store.deleteItems(ids: [b.id, c.id])

        XCTAssertEqual(store.selectedItemIDs, [d.id], "Selection must advance to the row after the last deleted item")
    }

    @MainActor
    func testDeleteEverythingClearsSelection() {
        let list = ListItem(title: "Test")
        let a = OutlineItem(listID: list.id, title: "A", position: 1)
        let b = OutlineItem(listID: list.id, title: "B", position: 2)
        let store = makeStore(items: [a, b], list: list)
        store.selectedItemIDs = [a.id, b.id]

        store.deleteItems(ids: [a.id, b.id])

        XCTAssertEqual(store.selectedItemIDs, [], "Deleting every row leaves an empty selection")
    }

    @MainActor
    func testDeleteUnselectedRowLeavesSelectionUntouched() {
        let list = ListItem(title: "Test")
        let a = OutlineItem(listID: list.id, title: "A", position: 1)
        let b = OutlineItem(listID: list.id, title: "B", position: 2)
        let c = OutlineItem(listID: list.id, title: "C", position: 3)
        let store = makeStore(items: [a, b, c], list: list)
        store.selectedItemIDs = [a.id]

        // pendingDeletionIDs (here, the direct ids: argument) is disjoint
        // from the current selection — deleting C must never move A's
        // selection, even though A is still a survivor either way.
        store.deleteItems(ids: [c.id])

        XCTAssertEqual(store.selectedItemIDs, [a.id], "A delete disjoint from the selection must not touch it")
    }

    // MARK: - Selected descendant removed via collapsed ancestor (CODEX2 2026-07-26 finding 2)

    @MainActor
    func testDeleteCollapsedParentAdvancesSelectionWhenHiddenChildWasSelected() {
        let list = ListItem(title: "Test")
        let p = OutlineItem(listID: list.id, title: "P", position: 1)
        let child = OutlineItem(listID: list.id, parentID: p.id, title: "Child", position: 1)
        let next = OutlineItem(listID: list.id, title: "Next", position: 2)
        let store = makeStore(items: [p, child, next], list: list)
        // Collapse P: Child is hidden from filteredRows/oldFilteredRows, but
        // trashing P (a row-trash on the parent) deletes the whole subtree,
        // including the hidden, selected Child. `collapseAll()` (not a
        // direct `expandedIDs` assignment) also rebuilds `flatRows`, which
        // `filteredRows` is derived from.
        store.collapseAll()
        XCTAssertEqual(store.filteredRows.map { $0.item.id }, [p.id, next.id], "Precondition: Child is hidden under collapsed P")
        store.selectedItemIDs = [child.id]

        store.deleteItems(ids: [p.id])

        XCTAssertEqual(
            store.selectedItemIDs, [next.id],
            "A selected descendant removed only as collateral of its collapsed ancestor's deletion must still advance selection"
        )
    }

    @MainActor
    func testDeleteCollapsedParentLeavesUnrelatedSelectionUntouched() {
        let list = ListItem(title: "Test")
        let p = OutlineItem(listID: list.id, title: "P", position: 1)
        let child = OutlineItem(listID: list.id, parentID: p.id, title: "Child", position: 1)
        let other = OutlineItem(listID: list.id, title: "Other", position: 2)
        let store = makeStore(items: [p, child, other], list: list)
        store.collapseAll()
        store.selectedItemIDs = [other.id]

        store.deleteItems(ids: [p.id])

        XCTAssertEqual(
            store.selectedItemIDs, [other.id],
            "Deleting a collapsed parent (and its hidden child) must not move a selection disjoint from both"
        )
    }

    @MainActor
    func testUndoRestoresItemsAndPreDeleteSelection() async {
        let list = ListItem(title: "Test")
        let a = OutlineItem(listID: list.id, title: "A", position: 1)
        let b = OutlineItem(listID: list.id, title: "B", position: 2)
        let c = OutlineItem(listID: list.id, title: "C", position: 3)
        let store = makeStore(items: [a, b, c], list: list)
        let undoManager = makeUndoManager()
        store.selectedItemIDs = [b.id]

        store.deleteItems(ids: [b.id], undoManager: undoManager)
        XCTAssertEqual(store.selectedItemIDs, [c.id], "Precondition: selection advanced to C after the delete")

        undoManager.undo()

        XCTAssertEqual(Set(store.items.map(\.id)), [a.id, b.id, c.id], "Undo must restore all three items")
        XCTAssertEqual(store.selectedItemIDs, [b.id], "Undo must restore the PRE-delete selection, not the post-delete one")

        await store.waitForPendingPersistence()
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

private actor DeleteSelectionTestListRepository: ListRepository {
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
