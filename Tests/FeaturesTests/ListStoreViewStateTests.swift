import XCTest
@testable import Domain
@testable import Features

/// Tests for per-list VIEW state restore (td-5d405a): expansion, check
/// filter, and selection survive switching between lists in-session and app
/// relaunch. Presentation-only state persisted to an injected `UserDefaults`
/// suite, keyed by list UUID via `ListViewState.viewStateKey(for:)`.
final class ListStoreViewStateTests: XCTestCase {
    /// A fresh, uniquely-named suite per test — isolated from both
    /// `UserDefaults.standard` and every other test — cleaned up in a
    /// `defer` so nothing leaks to a later run. Mirrors
    /// `AppStoreSelectionRestoreTests.makeScratchDefaults()`.
    private func makeScratchDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "net.vorwaller.listsurf.tests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    @MainActor
    func testExpansionFilterAndSelectionSurviveReloadForSameList() async {
        let scratch = makeScratchDefaults()
        defer { scratch.defaults.removePersistentDomain(forName: scratch.suiteName) }

        let list = ListItem(title: "Packing")
        let parent = OutlineItem(listID: list.id, title: "Parent", position: 1)
        let child = OutlineItem(listID: list.id, parentID: parent.id, title: "Child", position: 1)
        let outlineRepo = ViewStateOutlineRepository(items: [parent, child])
        let listRepo = ViewStateListRepository(lists: [list])

        let firstStore = ListStore(
            listID: list.id,
            outlineRepo: outlineRepo,
            listRepo: listRepo,
            userDefaults: scratch.defaults
        )
        await firstStore.load()
        firstStore.expandedIDs = [parent.id]
        firstStore.checkFilter = .remaining
        firstStore.selectedItemIDs = [child.id]

        let secondStore = ListStore(
            listID: list.id,
            outlineRepo: outlineRepo,
            listRepo: listRepo,
            userDefaults: scratch.defaults
        )
        await secondStore.load()

        XCTAssertEqual(secondStore.expandedIDs, [parent.id], "A new ListStore for the same list must restore expansion")
        XCTAssertEqual(secondStore.checkFilter, .remaining, "A new ListStore for the same list must restore the check filter")
        XCTAssertEqual(secondStore.selectedItemIDs, [child.id], "A new ListStore for the same list must restore selection")
    }

    @MainActor
    func testPerListIndependence() async {
        let scratch = makeScratchDefaults()
        defer { scratch.defaults.removePersistentDomain(forName: scratch.suiteName) }

        let listA = ListItem(title: "List A")
        let itemA = OutlineItem(listID: listA.id, title: "Item A", position: 1)
        let listB = ListItem(title: "List B")
        let itemB = OutlineItem(listID: listB.id, title: "Item B", position: 1)
        let outlineRepo = ViewStateOutlineRepository(items: [itemA, itemB])
        let listRepo = ViewStateListRepository(lists: [listA, listB])

        let storeA = ListStore(
            listID: listA.id,
            outlineRepo: outlineRepo,
            listRepo: listRepo,
            userDefaults: scratch.defaults
        )
        await storeA.load()
        storeA.expandedIDs = [itemA.id]
        storeA.checkFilter = .completed
        storeA.selectedItemIDs = [itemA.id]

        let storeB = ListStore(
            listID: listB.id,
            outlineRepo: outlineRepo,
            listRepo: listRepo,
            userDefaults: scratch.defaults
        )
        await storeB.load()

        XCTAssertEqual(storeB.expandedIDs, [], "List B must not inherit List A's expansion")
        XCTAssertEqual(storeB.checkFilter, .all, "List B must not inherit List A's check filter")
        XCTAssertEqual(storeB.selectedItemIDs, [], "List B must not inherit List A's selection")
    }

    @MainActor
    func testStaleItemIDsArePruned() async {
        let scratch = makeScratchDefaults()
        defer { scratch.defaults.removePersistentDomain(forName: scratch.suiteName) }

        let list = ListItem(title: "Packing")
        let realItem = OutlineItem(listID: list.id, title: "Real", position: 1)
        let staleID = UUID()
        // Seed a stored state directly — as if it were written by a prior
        // session where `staleID` named a row that has since been deleted.
        let staleState = ListViewState(
            expandedIDs: [staleID],
            checkFilterRawValue: ListStore.CheckFilter.all.rawValue,
            selectedItemIDs: [staleID]
        )
        let data = try! JSONEncoder().encode(staleState)
        scratch.defaults.set(data, forKey: ListViewState.viewStateKey(for: list.id))

        let store = ListStore(
            listID: list.id,
            outlineRepo: ViewStateOutlineRepository(items: [realItem]),
            listRepo: ViewStateListRepository(lists: [list]),
            userDefaults: scratch.defaults
        )
        await store.load()

        XCTAssertFalse(store.expandedIDs.contains(staleID), "A stale expanded id from a deleted row must be pruned")
        XCTAssertFalse(store.selectedItemIDs.contains(staleID), "A stale selected id from a deleted row must be pruned")
    }

    @MainActor
    func testSearchDoesNotCorruptPersistedExpansion() async {
        let scratch = makeScratchDefaults()
        defer { scratch.defaults.removePersistentDomain(forName: scratch.suiteName) }

        let list = ListItem(title: "Packing")
        let parent = OutlineItem(listID: list.id, title: "Parent", position: 1)
        let child = OutlineItem(listID: list.id, parentID: parent.id, title: "Needle", position: 1)
        let store = ListStore(
            listID: list.id,
            outlineRepo: ViewStateOutlineRepository(items: [parent, child]),
            listRepo: ViewStateListRepository(lists: [list]),
            userDefaults: scratch.defaults
        )
        await store.load()
        store.collapseAll()
        // Force an actual write to UserDefaults (collapseAll alone is a
        // same-value no-op against the already-empty default, so didSet's
        // guard would skip persisting) so there is a real persisted state
        // on disk to check for corruption below.
        store.selectedItemIDs = [parent.id]
        let persistedBeforeSearch = store.expandedIDs
        XCTAssertEqual(persistedBeforeSearch, [], "Precondition: collapsed before search")

        // Triggers the ancestor-expansion path in `filteredRows` (line
        // ~95-97: `expandedIDs.union(visibleIDs)`, which returns a NEW set
        // and must not mutate the stored property).
        store.searchText = "needle"
        _ = store.filteredRows

        XCTAssertEqual(store.expandedIDs, persistedBeforeSearch, "Search-driven ancestor expansion must not mutate the stored expandedIDs property")

        guard let data = scratch.defaults.data(forKey: ListViewState.viewStateKey(for: list.id)),
              let stored = try? JSONDecoder().decode(ListViewState.self, from: data) else {
            XCTFail("Expected a persisted view state")
            return
        }
        XCTAssertEqual(stored.expandedIDs, [], "The PERSISTED expandedIDs must also be unaffected by search")
    }

    @MainActor
    func testDeleteListRemovesTheViewStateKey() async {
        let scratch = makeScratchDefaults()
        defer { scratch.defaults.removePersistentDomain(forName: scratch.suiteName) }

        let list = ListItem(title: "Packing")
        let item = OutlineItem(listID: list.id, title: "Item", position: 1)
        let listRepo = ViewStateListRepository(lists: [list])
        let outlineRepo = ViewStateOutlineRepository(items: [item])

        let listStore = ListStore(
            listID: list.id,
            outlineRepo: outlineRepo,
            listRepo: listRepo,
            userDefaults: scratch.defaults
        )
        await listStore.load()
        listStore.expandedIDs = [item.id]
        XCTAssertNotNil(scratch.defaults.data(forKey: ListViewState.viewStateKey(for: list.id)), "Precondition: a view state was persisted")

        let appStore = AppStore(
            listRepository: listRepo,
            outlineRepository: outlineRepo,
            userDefaults: scratch.defaults
        )
        await appStore.loadLists()
        await appStore.deleteList(id: list.id)

        XCTAssertNil(scratch.defaults.object(forKey: ListViewState.viewStateKey(for: list.id)), "Deleting a list must remove its view-state key")
    }

    @MainActor
    func testArchiveListKeepsTheViewStateKey() async {
        let scratch = makeScratchDefaults()
        defer { scratch.defaults.removePersistentDomain(forName: scratch.suiteName) }

        let list = ListItem(title: "Packing")
        let item = OutlineItem(listID: list.id, title: "Item", position: 1)
        let listRepo = ViewStateListRepository(lists: [list])
        let outlineRepo = ViewStateOutlineRepository(items: [item])

        let listStore = ListStore(
            listID: list.id,
            outlineRepo: outlineRepo,
            listRepo: listRepo,
            userDefaults: scratch.defaults
        )
        await listStore.load()
        listStore.expandedIDs = [item.id]
        XCTAssertNotNil(scratch.defaults.data(forKey: ListViewState.viewStateKey(for: list.id)), "Precondition: a view state was persisted")

        let appStore = AppStore(
            listRepository: listRepo,
            outlineRepository: outlineRepo,
            userDefaults: scratch.defaults
        )
        await appStore.loadLists()
        await appStore.archiveList(id: list.id)

        XCTAssertNotNil(scratch.defaults.data(forKey: ListViewState.viewStateKey(for: list.id)), "Archiving a list must NOT remove its view-state key")
    }
}

private actor ViewStateOutlineRepository: OutlineRepository {
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

private actor ViewStateListRepository: ListRepository {
    private var lists: [ListItem]

    init(lists: [ListItem]) {
        self.lists = lists
    }

    func fetchAll() async throws -> [ListItem] { lists }
    func fetchActive() async throws -> [ListItem] { lists.filter { $0.archivedAt == nil } }
    func fetchArchived() async throws -> [ListItem] { lists.filter { $0.archivedAt != nil } }
    func fetch(id: UUID) async throws -> ListItem? { lists.first { $0.id == id } }
    func save(_ list: ListItem) async throws {
        lists.removeAll { $0.id == list.id }
        lists.append(list)
    }
    func saveListAndItems(_ list: ListItem, items: [OutlineItem]) async throws {
        try await save(list)
    }
    func replaceAllListsAndItems(with archive: LibraryArchive) async throws {
        lists = archive.lists.map(\.list)
    }
    func addListsAndItems(with archive: LibraryArchive) async throws {
        lists.append(contentsOf: archive.lists.map(\.list))
    }
    func fetchLibraryArchive() async throws -> LibraryArchive {
        LibraryArchive(lists: lists.map { ArchivedList(list: $0, items: []) })
    }
    func deleteListAndItems(id: UUID) async throws {
        lists.removeAll { $0.id == id }
    }
}
