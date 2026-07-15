import XCTest
@testable import Domain
@testable import Features

/// Tests for ListStore.moveRows (spec §5.2, D2/D4/D5/D6 invariants): the
/// same-parent sibling clamp, single-undo-step contract, and the
/// search/text-entry drag gates.
final class ListStoreMoveRowsTests: XCTestCase {
    @MainActor
    private func makeStore(items: [OutlineItem], list: ListItem = ListItem(title: "Test")) -> ListStore {
        let store = ListStore(
            listID: list.id,
            outlineRepo: InMemoryOutlineRepository(items: items),
            listRepo: MoveRowsTestListRepository(list: list)
        )
        store.items = items
        store.expandAll()
        return store
    }

    private func makeUndoManager() -> UndoManager {
        UndoManager()
    }

    @MainActor
    func testMoveRowsRegistersOneUndoStepAndRedoes() async {
        let list = ListItem(title: "Test")
        let a = OutlineItem(listID: list.id, title: "A", position: 1.0)
        let b = OutlineItem(listID: list.id, title: "B", position: 2.0)
        let c = OutlineItem(listID: list.id, title: "C", position: 3.0)
        let store = makeStore(items: [a, b, c], list: list)
        let undoManager = makeUndoManager()

        // Drag A (index 0) to the end (index 3): expected order [B, C, A].
        store.moveRows(from: IndexSet(integer: 0), to: 3, undoManager: undoManager)
        XCTAssertEqual(store.filteredRows.map(\.id), [b.id, c.id, a.id])

        XCTAssertTrue(undoManager.canUndo)
        undoManager.undo()
        XCTAssertEqual(store.filteredRows.map(\.id), [a.id, b.id, c.id])

        XCTAssertTrue(undoManager.canRedo, "Undoing must synchronously register the redo entry")
        undoManager.redo()
        XCTAssertEqual(store.filteredRows.map(\.id), [b.id, c.id, a.id])

        await store.waitForPendingPersistence()
    }

    @MainActor
    func testIdentityMoveRegistersNoUndo() {
        let list = ListItem(title: "Test")
        let a = OutlineItem(listID: list.id, title: "A", position: 1.0)
        let b = OutlineItem(listID: list.id, title: "B", position: 2.0)
        let c = OutlineItem(listID: list.id, title: "C", position: 3.0)
        let store = makeStore(items: [a, b, c], list: list)
        let undoManager = makeUndoManager()

        // Drag B (index 1) to index 1: destination == source, an identity move.
        store.moveRows(from: IndexSet(integer: 1), to: 1, undoManager: undoManager)
        RunLoop.current.run(until: Date())

        XCTAssertEqual(store.items.map(\.id), [a.id, b.id, c.id])
        XCTAssertFalse(undoManager.canUndo, "An identity drag must not consume the next Cmd-Z")
    }

    @MainActor
    func testMultiIndexSourceIsNoOp() {
        let list = ListItem(title: "Test")
        let a = OutlineItem(listID: list.id, title: "A", position: 1.0)
        let b = OutlineItem(listID: list.id, title: "B", position: 2.0)
        let c = OutlineItem(listID: list.id, title: "C", position: 3.0)
        let store = makeStore(items: [a, b, c], list: list)
        let undoManager = makeUndoManager()
        let itemsBefore = store.items

        store.moveRows(from: IndexSet([0, 2]), to: 1, undoManager: undoManager)
        RunLoop.current.run(until: Date())

        XCTAssertEqual(store.items, itemsBefore)
        XCTAssertFalse(undoManager.canUndo)
    }

    @MainActor
    func testMoveRowsRefusedWhileSearching() {
        let list = ListItem(title: "Test")
        let a = OutlineItem(listID: list.id, title: "A", position: 1.0)
        let b = OutlineItem(listID: list.id, title: "B", position: 2.0)
        let c = OutlineItem(listID: list.id, title: "C", position: 3.0)
        let store = makeStore(items: [a, b, c], list: list)
        let undoManager = makeUndoManager()
        store.searchText = "a"
        let itemsBefore = store.items

        store.moveRows(from: IndexSet(integer: 0), to: 3, undoManager: undoManager)
        RunLoop.current.run(until: Date())

        XCTAssertEqual(store.items, itemsBefore)
        XCTAssertFalse(undoManager.canUndo)
    }

    @MainActor
    func testMoveRowsRefusedWhileTextEntryActive() {
        let list = ListItem(title: "Test")
        let a = OutlineItem(listID: list.id, title: "A", position: 1.0)
        let b = OutlineItem(listID: list.id, title: "B", position: 2.0)
        let c = OutlineItem(listID: list.id, title: "C", position: 3.0)
        let store = makeStore(items: [a, b, c], list: list)
        let undoManager = makeUndoManager()
        store.beginAdding(.root)
        let itemsBefore = store.items

        store.moveRows(from: IndexSet(integer: 0), to: 3, undoManager: undoManager)
        RunLoop.current.run(until: Date())

        XCTAssertEqual(store.items, itemsBefore)
        XCTAssertFalse(undoManager.canUndo)
    }

    /// spec §1.4: filtered rows are a non-contiguous excerpt of true sibling
    /// order, so a drag there cannot mean what it looks like — same
    /// rationale as the search/text-entry guards above.
    @MainActor
    func testMoveRowsRefusedUnderActiveFilter() {
        let list = ListItem(title: "Test")
        let a = OutlineItem(listID: list.id, title: "A", position: 1.0)
        let b = OutlineItem(listID: list.id, title: "B", position: 2.0)
        let c = OutlineItem(listID: list.id, title: "C", position: 3.0)
        let store = makeStore(items: [a, b, c], list: list)
        let undoManager = makeUndoManager()
        store.checkFilter = .remaining
        let itemsBefore = store.items

        store.moveRows(from: IndexSet(integer: 0), to: 3, undoManager: undoManager)
        RunLoop.current.run(until: Date())

        XCTAssertEqual(store.items, itemsBefore)
        XCTAssertFalse(undoManager.canUndo)
    }

    @MainActor
    func testMoveRowsPersists() async {
        let list = ListItem(title: "Test")
        let a = OutlineItem(listID: list.id, title: "A", position: 1.0)
        let b = OutlineItem(listID: list.id, title: "B", position: 2.0)
        let c = OutlineItem(listID: list.id, title: "C", position: 3.0)
        let repo = InMemoryOutlineRepository(items: [a, b, c])
        let store = ListStore(
            listID: list.id,
            outlineRepo: repo,
            listRepo: MoveRowsTestListRepository(list: list)
        )
        store.items = [a, b, c]
        store.expandAll()

        store.moveRows(from: IndexSet(integer: 0), to: 3)
        await store.waitForPendingPersistence()

        let persisted = try? await repo.fetchItems(forList: list.id)
        let persistedOrder = persisted?
            .sorted { $0.position < $1.position }
            .map(\.id)
        XCTAssertEqual(persistedOrder, [b.id, c.id, a.id])
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

private actor MoveRowsTestListRepository: ListRepository {
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
