import XCTest
@testable import Domain
@testable import Features

final class AppStoreExportImportTests: XCTestCase {
    @MainActor
    func testDuplicateListAppendsCopyToNewTitle() async throws {
        let source = ListItem(title: "Packing", position: 1)
        let listRepository = ExportImportListRepository(lists: [source])
        let store = AppStore(
            listRepository: listRepository,
            outlineRepository: ExportImportOutlineRepository(items: [])
        )
        await store.loadLists()

        await store.duplicateList(id: source.id, clearChecks: false)

        XCTAssertEqual(store.lists.map(\.title).sorted(), ["Packing", "Packing Copy"])
        XCTAssertEqual(store.selectedListID, store.lists.first { $0.title == "Packing Copy" }?.id)
    }

    @MainActor
    func testDuplicateListUsesNumberedCopyWhenTitleAlreadyExists() async throws {
        let source = ListItem(title: "Packing", position: 1)
        let existingCopy = ListItem(title: "Packing Copy", position: 2)
        let archivedCopy = ListItem(title: "Packing Copy 2", position: 3, archivedAt: Date())
        let listRepository = ExportImportListRepository(lists: [source, existingCopy, archivedCopy])
        let store = AppStore(
            listRepository: listRepository,
            outlineRepository: ExportImportOutlineRepository(items: [])
        )
        await store.loadLists()

        await store.duplicateList(id: source.id, clearChecks: false)

        XCTAssertTrue(store.lists.contains { $0.title == "Packing Copy 3" })
    }

    @MainActor
    func testDuplicateListContinuesCopyNumberWhenSourceIsAlreadyACopy() async throws {
        let source = ListItem(title: "Packing Copy 2", position: 1)
        let listRepository = ExportImportListRepository(lists: [source])
        let store = AppStore(
            listRepository: listRepository,
            outlineRepository: ExportImportOutlineRepository(items: [])
        )
        await store.loadLists()

        await store.duplicateList(id: source.id, clearChecks: false)

        XCTAssertTrue(store.lists.contains { $0.title == "Packing Copy 3" })
    }

    @MainActor
    func testDuplicateListPersistsRemappedItems() async throws {
        // Guards the whole duplicate persistence path: items must be saved,
        // belong to the new list, carry new UUIDs, and keep their hierarchy
        // through parentID remapping.
        let source = ListItem(title: "Packing", position: 1)
        let parent = OutlineItem(listID: source.id, title: "Clothing", position: 1)
        let child = OutlineItem(
            listID: source.id,
            parentID: parent.id,
            title: "Socks",
            isChecked: true,
            position: 1
        )
        let listRepository = ExportImportListRepository(lists: [source])
        let store = AppStore(
            listRepository: listRepository,
            outlineRepository: ExportImportOutlineRepository(items: [parent, child])
        )
        await store.loadLists()

        await store.duplicateList(id: source.id, clearChecks: true)

        let newList = try XCTUnwrap(store.lists.first { $0.title == "Packing Copy" })
        let savedItems = await listRepository.savedItems(forList: newList.id)
        XCTAssertEqual(savedItems.count, 2, "Both items must be persisted with the duplicate")
        XCTAssertTrue(savedItems.allSatisfy { $0.listID == newList.id })
        XCTAssertTrue(savedItems.allSatisfy { $0.id != parent.id && $0.id != child.id })
        XCTAssertTrue(savedItems.allSatisfy { !$0.isChecked }, "clearChecks must reset checks")

        let newParent = try XCTUnwrap(savedItems.first { $0.title == "Clothing" })
        let newChild = try XCTUnwrap(savedItems.first { $0.title == "Socks" })
        XCTAssertEqual(newChild.parentID, newParent.id, "Hierarchy must survive UUID remapping")
    }

    @MainActor
    func testExportLibraryIncludesAllListsAndItemsInPositionOrder() async throws {
        let activeList = ListItem(title: "Active", position: 2)
        let archivedList = ListItem(title: "Archived", position: 1, archivedAt: Date())
        let activeItem = OutlineItem(listID: activeList.id, title: "Active Item")
        let archivedItem = OutlineItem(listID: archivedList.id, title: "Archived Item")
        let listRepository = ExportImportListRepository(
            lists: [activeList, archivedList],
            itemsByList: [
                activeList.id: [activeItem],
                archivedList.id: [archivedItem],
            ]
        )
        let store = AppStore(
            listRepository: listRepository,
            outlineRepository: ExportImportOutlineRepository(items: [activeItem, archivedItem])
        )

        let exported = await store.exportLibrary(appVersion: "test")
        let data = try XCTUnwrap(exported)
        let export = try ExportService().decode(from: data)

        XCTAssertEqual(export.appVersion, "test")
        XCTAssertEqual(export.lists.map(\.id), [archivedList.id, activeList.id])
        XCTAssertEqual(export.lists[0].items.map(\.id), [archivedItem.id])
        XCTAssertEqual(export.lists[1].items.map(\.id), [activeItem.id])
    }

    @MainActor
    func testInvalidImportValidationDoesNotReplaceLibrary() async throws {
        let existingList = ListItem(title: "Existing")
        let listRepository = ExportImportListRepository(lists: [existingList])
        let outlineRepository = ExportImportOutlineRepository(items: [])
        let errorStore = AppErrorStore()
        let store = AppStore(
            listRepository: listRepository,
            outlineRepository: outlineRepository,
            errorStore: errorStore
        )
        let duplicateItem = OutlineItem(listID: existingList.id, title: "Duplicate")
        let invalidExport = ExportService().export(
            lists: [(existingList, [duplicateItem, duplicateItem])],
            appVersion: "test"
        )
        let data = try ExportService().encode(invalidExport)

        let succeeded = await store.importLibrary(from: data)

        XCTAssertFalse(succeeded)
        let replacementCount = await listRepository.replacementCount()
        XCTAssertEqual(replacementCount, 0)
        guard case .importValidation = errorStore.current?.error else {
            return XCTFail("Expected import validation error")
        }
    }

    @MainActor
    func testMalformedImportDataIsReportedAsValidationError() async {
        let listRepository = ExportImportListRepository(lists: [ListItem(title: "Existing")])
        let errorStore = AppErrorStore()
        let store = AppStore(
            listRepository: listRepository,
            outlineRepository: ExportImportOutlineRepository(items: []),
            errorStore: errorStore
        )

        let succeeded = await store.importLibrary(from: Data("{".utf8))

        XCTAssertFalse(succeeded)
        let replacementCount = await listRepository.replacementCount()
        XCTAssertEqual(replacementCount, 0)
        guard case .importValidation = errorStore.current?.error else {
            return XCTFail("Expected import validation error")
        }
    }
}

private actor ExportImportListRepository: ListRepository {
    private var lists: [ListItem]
    private var itemsByList: [UUID: [OutlineItem]]
    private var replacements: [LibraryArchive] = []

    init(lists: [ListItem], itemsByList: [UUID: [OutlineItem]] = [:]) {
        self.lists = lists
        self.itemsByList = itemsByList
    }

    func fetchAll() async throws -> [ListItem] {
        lists
    }

    func fetchActive() async throws -> [ListItem] {
        lists.filter { !$0.isArchived }
    }

    func fetchArchived() async throws -> [ListItem] {
        lists.filter(\.isArchived)
    }

    func fetch(id: UUID) async throws -> ListItem? {
        lists.first { $0.id == id }
    }

    func save(_ list: ListItem) async throws {
        lists.removeAll { $0.id == list.id }
        lists.append(list)
    }

    func saveListAndItems(_ list: ListItem, items: [OutlineItem]) async throws {
        try await save(list)
        itemsByList[list.id] = items
    }

    func replaceAllListsAndItems(with archive: LibraryArchive) async throws {
        replacements.append(archive)
        lists = archive.lists.map(\.list)
        itemsByList = Dictionary(
            uniqueKeysWithValues: archive.lists.map { ($0.list.id, $0.items) }
        )
    }

    func fetchLibraryArchive() async throws -> LibraryArchive {
        let sorted = lists.sorted { $0.position < $1.position }
        return LibraryArchive(lists: sorted.map { list in
            ArchivedList(
                list: list,
                items: (itemsByList[list.id] ?? []).sorted { $0.position < $1.position }
            )
        })
    }

    func deleteListAndItems(id: UUID) async throws {
        lists.removeAll { $0.id == id }
        itemsByList[id] = nil
    }

    func replacementCount() -> Int {
        replacements.count
    }

    func savedItems(forList listID: UUID) -> [OutlineItem] {
        itemsByList[listID] ?? []
    }
}

private actor ExportImportOutlineRepository: OutlineRepository {
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
