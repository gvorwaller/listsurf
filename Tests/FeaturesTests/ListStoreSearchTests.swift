import XCTest
@testable import Domain
@testable import Features

/// Tests for `ListStore.filteredRows`'s in-list search (M5 gate E1a, fix
/// plan item 12e): the query must match item NOTES as well as titles, with
/// the existing ancestor-expansion behavior unchanged either way.
final class ListStoreSearchTests: XCTestCase {
    @MainActor
    private func makeStore(items: [OutlineItem], list: ListItem = ListItem(title: "Test")) -> ListStore {
        let store = ListStore(
            listID: list.id,
            outlineRepo: InMemoryOutlineRepository(items: items),
            listRepo: SearchTestListRepository(list: list)
        )
        store.items = items
        store.expandAll()
        return store
    }

    @MainActor
    func testNoteOnlyMatchSurfacesRowAndAncestors() {
        let list = ListItem(title: "Test")
        let parent = OutlineItem(listID: list.id, title: "Parent", position: 1)
        // Title has no match anywhere in "lighthouse" — only the note does.
        let child = OutlineItem(
            listID: list.id,
            parentID: parent.id,
            title: "Child",
            notes: "Remember the lighthouse keeper's advice",
            position: 1
        )
        let unrelated = OutlineItem(listID: list.id, title: "Unrelated", position: 2)
        let store = makeStore(items: [parent, child, unrelated], list: list)
        store.expandedIDs = []
        store.searchText = "lighthouse"

        let visibleIDs = Set(store.filteredRows.map(\.item.id))

        XCTAssertTrue(visibleIDs.contains(child.id), "The note-only match itself must be visible")
        XCTAssertTrue(visibleIDs.contains(parent.id), "Its ancestor must be expanded into view too")
        XCTAssertFalse(visibleIDs.contains(unrelated.id), "A sibling with no matching title or note must stay hidden")
    }

    @MainActor
    func testTitleMatchingUnchanged() {
        let list = ListItem(title: "Test")
        let a = OutlineItem(listID: list.id, title: "Alpha Item", position: 1)
        let b = OutlineItem(listID: list.id, title: "Bravo Item", position: 2)
        let store = makeStore(items: [a, b], list: list)
        store.searchText = "alpha"

        let visibleIDs = Set(store.filteredRows.map(\.item.id))

        XCTAssertEqual(visibleIDs, [a.id], "Title matching must still work exactly as before")
    }

    @MainActor
    func testQueryMatchingBothTitleAndNoteDoesNotDuplicateRow() {
        let list = ListItem(title: "Test")
        let item = OutlineItem(listID: list.id, title: "Echo Item", notes: "Echo again", position: 1)
        let store = makeStore(items: [item], list: list)
        store.searchText = "echo"

        XCTAssertEqual(store.filteredRows.map(\.item.id), [item.id])
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

private actor SearchTestListRepository: ListRepository {
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
