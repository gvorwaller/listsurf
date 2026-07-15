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
        store.checkFilter = .completed

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
    func testAddItemReturnsAndSelectsNewItem() {
        let list = ListItem(title: "Test")
        let store = ListStore(
            listID: list.id,
            outlineRepo: DelayedOutlineRepository(items: []),
            listRepo: StubListRepository(list: list)
        )

        let newID = store.addItem(title: "New")

        XCTAssertEqual(store.selectedItemIDs, [newID])
        XCTAssertTrue(store.items.contains { $0.id == newID && $0.title == "New" })
    }

    @MainActor
    func testInsertAboveReturnsAndSelectsNewItem() {
        let list = ListItem(title: "Test")
        let existing = OutlineItem(listID: list.id, title: "Existing")
        let store = ListStore(
            listID: list.id,
            outlineRepo: DelayedOutlineRepository(items: [existing]),
            listRepo: StubListRepository(list: list)
        )
        store.items = [existing]

        let newID = store.insertAbove(referenceID: existing.id, title: "New")

        XCTAssertEqual(store.selectedItemIDs, [newID])
        XCTAssertEqual(store.flatRows.first?.id, newID)
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
    func testPersistenceRetryRequeuesTheFailedMutation() async {
        // The retry for a failed background save must re-queue the SAME
        // mutation — a reload would discard the user's in-memory edit.
        let list = ListItem(title: "Test")
        let item = OutlineItem(listID: list.id, title: "Original")
        let errorStore = AppErrorStore()
        let outlineRepository = FlakyOutlineRepository(items: [item], failures: 1)
        let store = ListStore(
            listID: list.id,
            outlineRepo: outlineRepository,
            listRepo: StubListRepository(list: list),
            errorStore: errorStore
        )
        store.items = [item]

        store.updateItemTitle(id: item.id, title: "Changed")
        await store.waitForPendingPersistence()

        XCTAssertNotNil(errorStore.current, "First attempt fails and presents")
        errorStore.retryCurrent()
        await store.waitForPendingPersistence()

        let persisted = try? await outlineRepository.fetchItems(forList: list.id)
        XCTAssertEqual(persisted?.first?.title, "Changed", "Retry must persist the original edit")
        XCTAssertEqual(store.items.first?.title, "Changed", "In-memory edit must survive the failure")
    }

    @MainActor
    func testBeginAddingAndBeginEditingAreMutuallyExclusive() {
        let list = ListItem(title: "Test")
        let item = OutlineItem(listID: list.id, title: "Item")
        let store = ListStore(
            listID: list.id,
            outlineRepo: DelayedOutlineRepository(items: [item]),
            listRepo: StubListRepository(list: list)
        )
        store.items = [item]

        store.beginEditing(itemID: item.id)
        store.beginAdding(.below(item.id))
        XCTAssertNil(store.editingItemID, "Starting an add must end an active rename")

        store.beginEditing(itemID: item.id)
        XCTAssertNil(store.addPlacement, "Starting a rename must end an active add")
    }

    /// spec §1.4: a new item is always born unchecked, so it must never be
    /// born invisible under the Completed filter.
    @MainActor
    func testBeginAddingResetsCompletedFilterToAll() {
        let list = ListItem(title: "Test")
        let item = OutlineItem(listID: list.id, title: "Item", isChecked: true)
        let store = ListStore(
            listID: list.id,
            outlineRepo: DelayedOutlineRepository(items: [item]),
            listRepo: StubListRepository(list: list)
        )
        store.items = [item]
        store.checkFilter = .completed

        store.beginAdding(.root)

        XCTAssertEqual(store.checkFilter, .all)
    }

    /// The Remaining filter needs no such rule — a new unchecked item is
    /// already visible there.
    @MainActor
    func testBeginAddingDoesNotDisturbRemainingFilter() {
        let list = ListItem(title: "Test")
        let item = OutlineItem(listID: list.id, title: "Item")
        let store = ListStore(
            listID: list.id,
            outlineRepo: DelayedOutlineRepository(items: [item]),
            listRepo: StubListRepository(list: list)
        )
        store.items = [item]
        store.checkFilter = .remaining

        store.beginAdding(.root)

        XCTAssertEqual(store.checkFilter, .remaining)
    }

    @MainActor
    func testBoundaryIndentRegistersNoUndo() {
        let list = ListItem(title: "Test")
        let first = OutlineItem(listID: list.id, title: "First", position: 1)
        let second = OutlineItem(listID: list.id, title: "Second", position: 2)
        let store = ListStore(
            listID: list.id,
            outlineRepo: DelayedOutlineRepository(items: [first, second]),
            listRepo: StubListRepository(list: list)
        )
        store.items = [first, second]
        let undoManager = UndoManager()

        store.indent(itemID: first.id, undoManager: undoManager)
        RunLoop.current.run(until: Date())

        XCTAssertFalse(undoManager.canUndo, "A boundary no-op must not consume the next ⌘Z")
    }

    /// Phase 1 item 6 (spec §5, Rev 2.2): `indent` reparents an item under
    /// its previous sibling but must also expand that sibling — otherwise
    /// the newly-nested row is immediately invisible (expandedIDs starts
    /// empty), which is indistinguishable from indent silently failing.
    @MainActor
    func testIndentExpandsNewParent() {
        let list = ListItem(title: "Test")
        let first = OutlineItem(listID: list.id, title: "First", position: 1)
        let second = OutlineItem(listID: list.id, title: "Second", position: 2)
        let store = ListStore(
            listID: list.id,
            outlineRepo: DelayedOutlineRepository(items: [first, second]),
            listRepo: StubListRepository(list: list)
        )
        store.items = [first, second]
        let undoManager = UndoManager()

        store.indent(itemID: second.id, undoManager: undoManager)

        XCTAssertEqual(store.items.first(where: { $0.id == second.id })?.parentID, first.id)
        XCTAssertTrue(
            store.flatRows.contains { $0.id == second.id },
            "Second must stay visible after indenting under First — First should auto-expand, mirroring addChild"
        )
        XCTAssertTrue(store.filteredRows.contains { $0.id == second.id })

        undoManager.undo()

        XCTAssertNil(store.items.first(where: { $0.id == second.id })?.parentID, "Undo should restore Second to root")
        XCTAssertTrue(store.flatRows.contains { $0.id == second.id })
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

    func applyChanges(saving newItems: [OutlineItem], deletingIDs: [UUID]) async throws {
        saveCount += 1
        let call = saveCount
        try await Task.sleep(for: call == 1 ? .milliseconds(150) : .milliseconds(5))
        savedTitles.append(contentsOf: newItems.map(\.title))
        let savedIDs = Set(newItems.map(\.id))
        items.removeAll { savedIDs.contains($0.id) }
        items.append(contentsOf: newItems)
        let deleted = Set(deletingIDs)
        items.removeAll { deleted.contains($0.id) }
    }
}

private actor FailingOutlineRepository: OutlineRepository {
    private let items: [OutlineItem]

    init(items: [OutlineItem]) {
        self.items = items
    }

    func fetchItems(forList listID: UUID) async throws -> [OutlineItem] { items }
    func applyChanges(saving items: [OutlineItem], deletingIDs: [UUID]) async throws {
        throw TestFailure.intentional
    }
}

private actor FlakyOutlineRepository: OutlineRepository {
    private var items: [OutlineItem]
    private var remainingFailures: Int

    init(items: [OutlineItem], failures: Int) {
        self.items = items
        self.remainingFailures = failures
    }

    func fetchItems(forList listID: UUID) async throws -> [OutlineItem] {
        items.filter { $0.listID == listID }
    }

    func applyChanges(saving newItems: [OutlineItem], deletingIDs: [UUID]) async throws {
        if remainingFailures > 0 {
            remainingFailures -= 1
            throw TestFailure.intentional
        }
        let savedIDs = Set(newItems.map(\.id))
        items.removeAll { savedIDs.contains($0.id) }
        items.append(contentsOf: newItems)
        let deleted = Set(deletingIDs)
        items.removeAll { deleted.contains($0.id) }
    }
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

private enum TestFailure: LocalizedError {
    case intentional

    var errorDescription: String? { "intentional failure" }
}
