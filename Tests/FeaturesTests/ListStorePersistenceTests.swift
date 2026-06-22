import XCTest
@testable import Domain
@testable import Features

final class ListStorePersistenceTests: XCTestCase {
    @MainActor
    func testRapidEditsPersistInMutationOrder() async {
        let list = ListItem(title: "Test")
        let item = OutlineItem(listID: list.id, title: "Original")
        let outlineRepository = DelayedOutlineRepository(items: [item])
        let listRepository = StubListRepository(list: list)
        let store = ListStore(
            listID: list.id,
            outlineRepo: outlineRepository,
            listRepo: listRepository
        )
        store.items = [item]

        store.updateItemTitle(id: item.id, title: "First")
        store.updateItemTitle(id: item.id, title: "Second")
        await store.waitForPendingPersistence()

        let savedTitles = await outlineRepository.savedTitles
        XCTAssertEqual(savedTitles, ["First", "Second"])
    }

    @MainActor
    func testCheckedFilterUsesAggregateParentState() {
        let list = ListItem(title: "Test")
        let parent = OutlineItem(listID: list.id, title: "Parent", isChecked: false)
        let childOne = OutlineItem(listID: list.id, parentID: parent.id, title: "Child One", isChecked: true)
        let childTwo = OutlineItem(listID: list.id, parentID: parent.id, title: "Child Two", isChecked: true)
        let store = ListStore(
            listID: list.id,
            outlineRepo: DelayedOutlineRepository(items: [parent, childOne, childTwo]),
            listRepo: StubListRepository(list: list)
        )
        store.items = [parent, childOne, childTwo]
        store.expandAll()
        store.isCheckMode = true
        store.checkFilter = .checked

        XCTAssertTrue(store.filteredRows.contains { $0.id == parent.id })
    }

    @MainActor
    func testTogglingVisuallyCheckedParentUnchecksSubtree() async {
        let list = ListItem(title: "Test")
        let parent = OutlineItem(listID: list.id, title: "Parent", isChecked: false)
        let childOne = OutlineItem(listID: list.id, parentID: parent.id, title: "Child One", isChecked: true)
        let childTwo = OutlineItem(listID: list.id, parentID: parent.id, title: "Child Two", isChecked: true)
        let store = ListStore(
            listID: list.id,
            outlineRepo: DelayedOutlineRepository(items: [parent, childOne, childTwo]),
            listRepo: StubListRepository(list: list)
        )
        store.items = [parent, childOne, childTwo]
        store.expandAll()

        store.toggleCheck(itemID: parent.id)
        await store.waitForPendingPersistence()

        XCTAssertTrue(store.items.allSatisfy { !$0.isChecked })
    }

    @MainActor
    func testSearchRevealsCollapsedDescendantWithAncestorContext() {
        let list = ListItem(title: "Test")
        let parent = OutlineItem(listID: list.id, title: "Parent")
        let child = OutlineItem(listID: list.id, parentID: parent.id, title: "Needle")
        let store = ListStore(
            listID: list.id,
            outlineRepo: DelayedOutlineRepository(items: [parent, child]),
            listRepo: StubListRepository(list: list)
        )
        store.items = [parent, child]
        store.collapseAll()
        store.searchText = "needle"

        XCTAssertEqual(store.filteredRows.map(\.id), [parent.id, child.id])
    }

    @MainActor
    func testPersistenceFailureIsPresented() async {
        let list = ListItem(title: "Test")
        let item = OutlineItem(listID: list.id, title: "Original")
        let errorStore = AppErrorStore()
        let outlineRepository = FailingOutlineRepository(items: [item])
        let store = ListStore(
            listID: list.id,
            outlineRepo: outlineRepository,
            listRepo: StubListRepository(list: list),
            errorStore: errorStore
        )
        store.items = [item]

        store.updateItemTitle(id: item.id, title: "Changed")
        await store.waitForPendingPersistence()

        guard case .persistenceSave(let message) = errorStore.current?.error else {
            XCTFail("Expected a persistence-save error")
            return
        }
        XCTAssertTrue(message.contains("intentional failure"))
    }

    @MainActor
    func testLoadRepairsInvalidParentLinksAndPersistsRepair() async throws {
        let list = ListItem(title: "Test")
        let orphan = OutlineItem(listID: list.id, parentID: UUID(), title: "Orphan")
        let errorStore = AppErrorStore()
        let outlineRepository = DelayedOutlineRepository(items: [orphan])
        let store = ListStore(
            listID: list.id,
            outlineRepo: outlineRepository,
            listRepo: StubListRepository(list: list),
            errorStore: errorStore
        )

        await store.load()

        XCTAssertNil(store.items.first?.parentID)
        let persisted = try await outlineRepository.fetchItems(forList: list.id)
        XCTAssertNil(persisted.first?.parentID)
        guard case .orphanRepair(let repairedCount, _) = errorStore.current?.error else {
            XCTFail("Expected an orphan repair notification")
            return
        }
        XCTAssertEqual(repairedCount, 1)
    }

    @MainActor
    func testErrorStoreRetryRunsActionAndDismissesCurrentError() {
        let errorStore = AppErrorStore()
        var didRetry = false

        errorStore.present(.persistenceLoad(underlying: "temporary"), retryTitle: "Retry") {
            didRetry = true
        }
        errorStore.retryCurrent()

        XCTAssertTrue(didRetry)
        XCTAssertNil(errorStore.current)
    }
}

private actor DelayedOutlineRepository: OutlineRepository {
    private var items: [OutlineItem]
    private var saveCount = 0
    private(set) var savedTitles: [String] = []

    init(items: [OutlineItem]) {
        self.items = items
    }

    func fetchItems(forList listID: UUID) async throws -> [OutlineItem] {
        items.filter { $0.listID == listID }
    }

    func fetch(id: UUID) async throws -> OutlineItem? {
        items.first { $0.id == id }
    }

    func save(_ item: OutlineItem) async throws {
        try await saveAll([item])
    }

    func saveAll(_ newItems: [OutlineItem]) async throws {
        saveCount += 1
        let call = saveCount
        try await Task.sleep(for: call == 1 ? .milliseconds(150) : .milliseconds(5))
        savedTitles.append(contentsOf: newItems.map(\.title))
        let ids = Set(newItems.map(\.id))
        items.removeAll { ids.contains($0.id) }
        items.append(contentsOf: newItems)
    }

    func delete(id: UUID) async throws {
        items.removeAll { $0.id == id }
    }

    func deleteAll(ids: [UUID]) async throws {
        let ids = Set(ids)
        items.removeAll { ids.contains($0.id) }
    }
}

private actor FailingOutlineRepository: OutlineRepository {
    private let items: [OutlineItem]

    init(items: [OutlineItem]) {
        self.items = items
    }

    func fetchItems(forList listID: UUID) async throws -> [OutlineItem] { items }
    func fetch(id: UUID) async throws -> OutlineItem? { items.first { $0.id == id } }
    func save(_ item: OutlineItem) async throws { throw TestFailure.intentional }
    func saveAll(_ items: [OutlineItem]) async throws { throw TestFailure.intentional }
    func delete(id: UUID) async throws { throw TestFailure.intentional }
    func deleteAll(ids: [UUID]) async throws { throw TestFailure.intentional }
}

private actor StubListRepository: ListRepository {
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
    func delete(id: UUID) async throws {}
    func deleteListAndItems(id: UUID) async throws {}
}

private enum TestFailure: LocalizedError {
    case intentional

    var errorDescription: String? { "intentional failure" }
}
