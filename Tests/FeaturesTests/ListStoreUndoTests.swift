import XCTest
@testable import Domain
@testable import Features

/// Tests for the live snapshot-based undo path in ListStore — the one the
/// app actually uses. Redo depends on re-registration happening
/// synchronously inside the undo handler; these tests fail if that is ever
/// deferred to a Task again.
final class ListStoreUndoTests: XCTestCase {
    @MainActor
    private func makeStore(items: [OutlineItem] = [], list: ListItem = ListItem(title: "Test")) -> ListStore {
        let store = ListStore(
            listID: list.id,
            outlineRepo: InMemoryOutlineRepository(items: items),
            listRepo: UndoTestListRepository(list: list)
        )
        store.items = items
        store.expandAll()
        return store
    }

    private func makeUndoManager() -> UndoManager {
        UndoManager()
    }

    @MainActor
    func testUndoThenRedoRoundTripsAdd() async {
        let store = makeStore()
        let undoManager = makeUndoManager()

        let newID = store.addItem(title: "A", undoManager: undoManager)
        XCTAssertEqual(store.items.count, 1)

        undoManager.undo()
        XCTAssertEqual(store.items.count, 0, "Undo should remove the added item")

        XCTAssertTrue(undoManager.canRedo, "Undoing must synchronously register the redo entry")
        undoManager.redo()
        XCTAssertEqual(store.items.map(\.id), [newID], "Redo should restore the added item")

        await store.waitForPendingPersistence()
    }

    @MainActor
    func testUndoDeleteRestoresSubtree() async {
        let list = ListItem(title: "Test")
        let parent = OutlineItem(listID: list.id, title: "Parent")
        let child = OutlineItem(listID: list.id, parentID: parent.id, title: "Child")
        let store = makeStore(items: [parent, child], list: list)
        let undoManager = makeUndoManager()

        store.deleteItems(ids: [parent.id], undoManager: undoManager)
        XCTAssertTrue(store.items.isEmpty)

        undoManager.undo()
        XCTAssertEqual(Set(store.items.map(\.id)), [parent.id, child.id])

        await store.waitForPendingPersistence()
    }

    @MainActor
    func testUndoRestoresPriorSelection() async {
        let list = ListItem(title: "Test")
        let existing = OutlineItem(listID: list.id, title: "Existing")
        let store = makeStore(items: [existing], list: list)
        let undoManager = makeUndoManager()

        store.selectedItemIDs = [existing.id]
        let newID = store.addItem(title: "New", afterItemID: existing.id, undoManager: undoManager)
        XCTAssertEqual(store.selectedItemIDs, [newID])

        undoManager.undo()
        XCTAssertEqual(
            store.selectedItemIDs, [existing.id],
            "Undo must not leave selection pointing at an item that no longer exists"
        )

        await store.waitForPendingPersistence()
    }

    @MainActor
    func testTeardownRemovesPendingUndoActions() {
        let store = makeStore()
        let undoManager = makeUndoManager()

        store.addItem(title: "A", undoManager: undoManager)
        // Let the run loop turn so the implicit event group closes, as it
        // does between user actions in the real app.
        RunLoop.current.run(until: Date())
        XCTAssertTrue(undoManager.canUndo)

        store.teardownUndo(undoManager)
        XCTAssertFalse(
            undoManager.canUndo,
            "A retired store must not leave live undo actions targeting it"
        )

        // Even if an action somehow survived, undoing must not mutate the
        // retired store.
        let itemsBefore = store.items
        undoManager.undo()
        XCTAssertEqual(store.items, itemsBefore)
    }

    @MainActor
    func testUndoSpansCheckMutations() async {
        let list = ListItem(title: "Test")
        let item = OutlineItem(listID: list.id, title: "Item")
        let store = makeStore(items: [item], list: list)
        let undoManager = makeUndoManager()

        store.toggleCheck(itemID: item.id, undoManager: undoManager)
        XCTAssertTrue(store.items[0].isChecked)

        undoManager.undo()
        XCTAssertFalse(store.items[0].isChecked)

        XCTAssertTrue(undoManager.canRedo)
        undoManager.redo()
        XCTAssertTrue(store.items[0].isChecked)

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

private actor UndoTestListRepository: ListRepository {
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
