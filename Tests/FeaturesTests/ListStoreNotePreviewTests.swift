import XCTest
@testable import Domain
@testable import Features

/// Tests for `ListStore.expandedNoteIDs`/`toggleNoteExpanded` (M5 gate E4,
/// fix plan item 11): the note-preview expand-in-place affordance is
/// transient, per-row UI state — never persisted — and must clear whenever
/// a list (re)loads so an expanded note in one list doesn't leak into the
/// next.
final class ListStoreNotePreviewTests: XCTestCase {
    @MainActor
    private func makeStore(items: [OutlineItem], list: ListItem = ListItem(title: "Test")) -> ListStore {
        let store = ListStore(
            listID: list.id,
            outlineRepo: InMemoryOutlineRepository(items: items),
            listRepo: NotePreviewTestListRepository(list: list)
        )
        store.items = items
        store.expandAll()
        return store
    }

    @MainActor
    func testToggleNoteExpandedTogglesMembership() {
        let list = ListItem(title: "Test")
        let item = OutlineItem(listID: list.id, title: "A", notes: "Some notes", position: 1)
        let store = makeStore(items: [item], list: list)

        XCTAssertFalse(store.expandedNoteIDs.contains(item.id), "Collapsed by default")

        store.toggleNoteExpanded(item.id)
        XCTAssertTrue(store.expandedNoteIDs.contains(item.id))

        store.toggleNoteExpanded(item.id)
        XCTAssertFalse(store.expandedNoteIDs.contains(item.id), "A second toggle collapses it again")
    }

    @MainActor
    func testToggleNoteExpandedIsIndependentPerRow() {
        let list = ListItem(title: "Test")
        let a = OutlineItem(listID: list.id, title: "A", notes: "Notes A", position: 1)
        let b = OutlineItem(listID: list.id, title: "B", notes: "Notes B", position: 2)
        let store = makeStore(items: [a, b], list: list)

        store.toggleNoteExpanded(a.id)

        XCTAssertTrue(store.expandedNoteIDs.contains(a.id))
        XCTAssertFalse(store.expandedNoteIDs.contains(b.id), "Expanding one row's note must not expand another's")
    }

    @MainActor
    func testLoadClearsExpandedNoteIDs() async {
        let list = ListItem(title: "Test")
        let item = OutlineItem(listID: list.id, title: "A", notes: "Some notes", position: 1)
        let store = makeStore(items: [item], list: list)
        store.toggleNoteExpanded(item.id)
        XCTAssertTrue(store.expandedNoteIDs.contains(item.id), "Precondition: expanded before reload")

        await store.load()

        XCTAssertTrue(store.expandedNoteIDs.isEmpty, "A (re)load must clear transient note-expansion state")
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

private actor NotePreviewTestListRepository: ListRepository {
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
