import XCTest
@testable import Domain
@testable import Features

final class AppStoreExportImportTests: XCTestCase {
    @MainActor
    func testExportLibraryIncludesAllListsAndItemsInPositionOrder() async throws {
        let activeList = ListItem(title: "Active", position: 2)
        let archivedList = ListItem(title: "Archived", position: 1, archivedAt: Date())
        let activeItem = OutlineItem(listID: activeList.id, title: "Active Item")
        let archivedItem = OutlineItem(listID: archivedList.id, title: "Archived Item")
        let listRepository = ExportImportListRepository(lists: [activeList, archivedList])
        let outlineRepository = ExportImportOutlineRepository(items: [
            activeItem,
            archivedItem,
        ])
        let store = AppStore(
            listRepository: listRepository,
            outlineRepository: outlineRepository
        )

        let data = try await store.exportLibrary(appVersion: "test")
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

        do {
            try await store.importLibrary(from: data)
            XCTFail("Expected invalid import to throw")
        } catch ExportValidationError.duplicateItemID {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

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

        do {
            try await store.importLibrary(from: Data("{".utf8))
            XCTFail("Expected malformed JSON to throw")
        } catch {
            // Expected.
        }

        let replacementCount = await listRepository.replacementCount()
        XCTAssertEqual(replacementCount, 0)
        guard case .importValidation = errorStore.current?.error else {
            return XCTFail("Expected import validation error")
        }
    }
}

private actor ExportImportListRepository: ListRepository {
    private var lists: [ListItem]
    private var replacements: [LibraryArchive] = []

    init(lists: [ListItem]) {
        self.lists = lists
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
    }

    func replaceAllListsAndItems(with archive: LibraryArchive) async throws {
        replacements.append(archive)
        lists = archive.lists.map(\.list)
    }

    func delete(id: UUID) async throws {
        lists.removeAll { $0.id == id }
    }

    func deleteListAndItems(id: UUID) async throws {
        try await delete(id: id)
    }

    func replacementCount() -> Int {
        replacements.count
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

    func fetch(id: UUID) async throws -> OutlineItem? {
        items.first { $0.id == id }
    }

    func save(_ item: OutlineItem) async throws {
        items.removeAll { $0.id == item.id }
        items.append(item)
    }

    func saveAll(_ newItems: [OutlineItem]) async throws {
        for item in newItems {
            try await save(item)
        }
    }

    func delete(id: UUID) async throws {
        items.removeAll { $0.id == id }
    }

    func deleteAll(ids: [UUID]) async throws {
        let ids = Set(ids)
        items.removeAll { ids.contains($0.id) }
    }
}
