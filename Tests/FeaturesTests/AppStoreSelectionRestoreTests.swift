import XCTest
@testable import Domain
@testable import Features

/// Tests for `AppStore`'s last-selected-list restore (M5 gate E5, fix plan
/// item 12b): `selectedListID` persists to an injected `UserDefaults` suite
/// on change, and `loadLists()` restores it exactly once — only if nothing
/// already selected a list, and only if the stored id still names an ACTIVE
/// list (archived excluded).
final class AppStoreSelectionRestoreTests: XCTestCase {
    /// A fresh, uniquely-named suite per test — isolated from both
    /// `UserDefaults.standard` and every other test in this file — cleaned
    /// up in a `defer` so nothing leaks to a later run.
    private func makeScratchDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "net.vorwaller.listsurf.tests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    @MainActor
    func testRestoreWorksAcrossAppStoreInstances() async {
        let scratch = makeScratchDefaults()
        defer { scratch.defaults.removePersistentDomain(forName: scratch.suiteName) }

        let list = ListItem(title: "Packing", position: 1)
        let listRepo = SelectionRestoreListRepository(lists: [list])

        let firstStore = AppStore(
            listRepository: listRepo,
            outlineRepository: SelectionRestoreOutlineRepository(items: []),
            userDefaults: scratch.defaults
        )
        await firstStore.loadLists()
        firstStore.selectedListID = list.id

        let secondStore = AppStore(
            listRepository: listRepo,
            outlineRepository: SelectionRestoreOutlineRepository(items: []),
            userDefaults: scratch.defaults
        )
        XCTAssertNil(secondStore.selectedListID, "Precondition: a fresh store starts with no selection")

        await secondStore.loadLists()

        XCTAssertEqual(secondStore.selectedListID, list.id, "A new AppStore instance must restore the previous session's selection")
    }

    @MainActor
    func testStaleStoredIDStaysNil() async {
        let scratch = makeScratchDefaults()
        defer { scratch.defaults.removePersistentDomain(forName: scratch.suiteName) }
        // The stored id names a list that no longer exists.
        scratch.defaults.set(UUID().uuidString, forKey: ListsurfSettingsKey.lastSelectedListID)

        let list = ListItem(title: "Still Here", position: 1)
        let store = AppStore(
            listRepository: SelectionRestoreListRepository(lists: [list]),
            outlineRepository: SelectionRestoreOutlineRepository(items: []),
            userDefaults: scratch.defaults
        )

        await store.loadLists()

        XCTAssertNil(store.selectedListID, "A stored id for a list that no longer exists must not be restored")
    }

    @MainActor
    func testStoredIDForArchivedListIsNotRestored() async {
        let scratch = makeScratchDefaults()
        defer { scratch.defaults.removePersistentDomain(forName: scratch.suiteName) }

        let archived = ListItem(title: "Archived", position: 1, archivedAt: Date())
        scratch.defaults.set(archived.id.uuidString, forKey: ListsurfSettingsKey.lastSelectedListID)

        let store = AppStore(
            listRepository: SelectionRestoreListRepository(lists: [archived]),
            outlineRepository: SelectionRestoreOutlineRepository(items: []),
            userDefaults: scratch.defaults
        )

        await store.loadLists()

        XCTAssertNil(store.selectedListID, "A stored id naming only an ARCHIVED list must not be restored")
    }

    @MainActor
    func testRestoreIsOneShotAndDoesNotFightExplicitDeselection() async {
        let scratch = makeScratchDefaults()
        defer { scratch.defaults.removePersistentDomain(forName: scratch.suiteName) }

        let list = ListItem(title: "Packing", position: 1)
        scratch.defaults.set(list.id.uuidString, forKey: ListsurfSettingsKey.lastSelectedListID)

        let store = AppStore(
            listRepository: SelectionRestoreListRepository(lists: [list]),
            outlineRepository: SelectionRestoreOutlineRepository(items: []),
            userDefaults: scratch.defaults
        )

        await store.loadLists()
        XCTAssertEqual(store.selectedListID, list.id, "Precondition: the first load restored the stored selection")

        // Explicit deselection (e.g. the user deleted/archived the list).
        store.selectedListID = nil

        // A LATER loadLists() call (any of the many the app makes after
        // mutations) must not resurrect the stale stored id — restore is
        // one-shot, not "whenever selection is nil."
        await store.loadLists()

        XCTAssertNil(store.selectedListID, "Restore must not fight an explicit deselection made after the first load")
    }
}

private actor SelectionRestoreOutlineRepository: OutlineRepository {
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

private actor SelectionRestoreListRepository: ListRepository {
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
