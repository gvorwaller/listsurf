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

    // MARK: - Additive import (§6.2)

    @MainActor
    func testPrepareAndCommitAdditiveImportJSONAppendsNewList() async throws {
        let existing = ListItem(title: "Existing", position: 1)
        let listRepository = ExportImportListRepository(lists: [existing])
        let store = AppStore(
            listRepository: listRepository,
            outlineRepository: ExportImportOutlineRepository(items: [])
        )
        await store.loadLists()

        let sourceList = ListItem(title: "Packing", position: 5)
        let sourceItem = OutlineItem(listID: sourceList.id, title: "Socks", position: 1)
        let export = ExportService().export(lists: [(sourceList, [sourceItem])], appVersion: "test")
        let data = try ExportService().encode(export)

        let preparedPlan = await store.prepareAdditiveImport(from: data, filename: "packing.json")
        let plan = try XCTUnwrap(preparedPlan)
        let addCountAfterPrepare = await listRepository.addCount()
        XCTAssertEqual(addCountAfterPrepare, 0, "prepare must write nothing")

        let committed = await store.commitAdditiveImport(plan)
        XCTAssertTrue(committed)

        let addCountAfterCommit = await listRepository.addCount()
        let replacementCountAfterCommit = await listRepository.replacementCount()
        XCTAssertEqual(addCountAfterCommit, 1)
        XCTAssertEqual(replacementCountAfterCommit, 0)

        let importedList = try XCTUnwrap(store.lists.first { $0.title == "Packing" })
        let originalExisting = try XCTUnwrap(store.lists.first { $0.title == "Existing" })
        XCTAssertEqual(originalExisting.position, existing.position, "existing list must be untouched")
        XCTAssertGreaterThan(importedList.position, existing.position)
        XCTAssertEqual(store.selectedListID, importedList.id)
        XCTAssertNotEqual(importedList.id, sourceList.id, "imported list must carry a freshly minted UUID")
    }

    @MainActor
    func testCommitAdditiveImportResolvesTitleCollisions() async throws {
        let existing = ListItem(title: "Packing", position: 1)
        let listRepository = ExportImportListRepository(lists: [existing])
        let store = AppStore(
            listRepository: listRepository,
            outlineRepository: ExportImportOutlineRepository(items: [])
        )
        await store.loadLists()

        let sourceList = ListItem(title: "Packing", position: 1)
        let export = ExportService().export(lists: [(sourceList, [])], appVersion: "test")
        let data = try ExportService().encode(export)

        let preparedFirstPlan = await store.prepareAdditiveImport(from: data, filename: "packing.json")
        let firstPlan = try XCTUnwrap(preparedFirstPlan)
        let firstCommitted = await store.commitAdditiveImport(firstPlan)
        XCTAssertTrue(firstCommitted)
        XCTAssertTrue(store.lists.contains { $0.title == "Packing (Imported)" })

        let preparedSecondPlan = await store.prepareAdditiveImport(from: data, filename: "packing.json")
        let secondPlan = try XCTUnwrap(preparedSecondPlan)
        let secondCommitted = await store.commitAdditiveImport(secondPlan)
        XCTAssertTrue(secondCommitted)
        XCTAssertTrue(store.lists.contains { $0.title == "Packing (Imported 2)" })
    }

    @MainActor
    func testPrepareAndCommitAdditiveImportOPMLPersistsHierarchy() async throws {
        let listRepository = ExportImportListRepository(lists: [])
        let store = AppStore(
            listRepository: listRepository,
            outlineRepository: ExportImportOutlineRepository(items: [])
        )
        await store.loadLists()

        let opml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head>
            <title>Packing</title>
          </head>
          <body>
            <outline text="Clothing" _status="unchecked">
              <outline text="Socks" _status="checked" _quantity="4" _note="Wool"/>
            </outline>
          </body>
        </opml>
        """
        let data = Data(opml.utf8)

        let preparedPlan = await store.prepareAdditiveImport(from: data, filename: "packing.opml")
        let plan = try XCTUnwrap(preparedPlan)
        let committed = await store.commitAdditiveImport(plan)
        XCTAssertTrue(committed)

        let importedList = try XCTUnwrap(store.lists.first { $0.title == "Packing" })
        let items = await listRepository.savedItems(forList: importedList.id)
        let clothing = try XCTUnwrap(items.first { $0.title == "Clothing" })
        let socks = try XCTUnwrap(items.first { $0.title == "Socks" })
        XCTAssertNil(clothing.parentID)
        XCTAssertEqual(socks.parentID, clothing.id, "hierarchy must survive UUID remapping")
        XCTAssertTrue(socks.isChecked)
        XCTAssertEqual(socks.quantity, 4)
        XCTAssertEqual(socks.notes, "Wool")
    }

    @MainActor
    func testPrepareAdditiveImportGarbageDataPresentsValidationError() async throws {
        let listRepository = ExportImportListRepository(lists: [])
        let errorStore = AppErrorStore()
        let store = AppStore(
            listRepository: listRepository,
            outlineRepository: ExportImportOutlineRepository(items: []),
            errorStore: errorStore
        )

        let plan = await store.prepareAdditiveImport(from: Data("not a listsurf file".utf8), filename: "notes.txt")

        XCTAssertNil(plan)
        let addCount = await listRepository.addCount()
        XCTAssertEqual(addCount, 0)
        guard case .importValidation = errorStore.current?.error else {
            return XCTFail("Expected import validation error")
        }
    }

    @MainActor
    func testPrepareAdditiveImportRoutesBadByteOPMLToXMLError() async throws {
        // The sniff is byte-level (D11): a '<'-prefixed file with one invalid
        // UTF-8 byte later must reach the OPML codec and get its actionable
        // XML error — not the generic "neither JSON nor OPML" sniff message.
        let errorStore = AppErrorStore()
        let store = AppStore(
            listRepository: ExportImportListRepository(lists: []),
            outlineRepository: ExportImportOutlineRepository(items: []),
            errorStore: errorStore
        )
        var data = Data("<opml version=\"2.0\"><body><outline text=\"".utf8)
        data.append(0xFF) // invalid UTF-8 byte mid-document
        data.append(contentsOf: Data("\"/></body></opml>".utf8))

        let plan = await store.prepareAdditiveImport(from: data, filename: "bad.opml")

        XCTAssertNil(plan)
        guard case .importValidation(let message) = errorStore.current?.error else {
            return XCTFail("Expected import validation error")
        }
        XCTAssertFalse(
            message.contains("neither Listsurf JSON nor OPML"),
            "Bad byte must not be misclassified as an unrecognized format"
        )
        XCTAssertTrue(message.contains("XML"), "Expected the codec's XML error, got: \(message)")
    }

    @MainActor
    func testTopLevelDecodingErrorMessageSaysTopLevelNotDot() async throws {
        // Missing top-level fields must render "at the top level", not "at .".
        let errorStore = AppErrorStore()
        let store = AppStore(
            listRepository: ExportImportListRepository(lists: []),
            outlineRepository: ExportImportOutlineRepository(items: []),
            errorStore: errorStore
        )

        // Valid JSON object, but not a ListsurfExport: top-level keys missing.
        let plan = await store.prepareAdditiveImport(from: Data("{}".utf8), filename: "backup.json")

        XCTAssertNil(plan)
        guard case .importValidation(let message) = errorStore.current?.error else {
            return XCTFail("Expected import validation error")
        }
        XCTAssertTrue(message.contains("at the top level"), "Got: \(message)")
        XCTAssertFalse(message.contains("at ."), "Got: \(message)")
    }

    @MainActor
    func testPrepareAdditiveImportSniffsBOMPrefixedJSON() async throws {
        let listRepository = ExportImportListRepository(lists: [])
        let store = AppStore(
            listRepository: listRepository,
            outlineRepository: ExportImportOutlineRepository(items: [])
        )
        await store.loadLists()

        let sourceList = ListItem(title: "BOM JSON", position: 1)
        let export = ExportService().export(lists: [(sourceList, [])], appVersion: "test")
        let jsonData = try ExportService().encode(export)
        var bomPrefixed = Data([0xEF, 0xBB, 0xBF])
        bomPrefixed.append(jsonData)

        let preparedPlan = await store.prepareAdditiveImport(from: bomPrefixed, filename: "bom.json")
        let plan = try XCTUnwrap(preparedPlan)
        let committed = await store.commitAdditiveImport(plan)
        XCTAssertTrue(committed)
        XCTAssertTrue(store.lists.contains { $0.title == "BOM JSON" })
    }

    @MainActor
    func testPrepareAdditiveImportSniffsBOMPrefixedOPML() async throws {
        let listRepository = ExportImportListRepository(lists: [])
        let store = AppStore(
            listRepository: listRepository,
            outlineRepository: ExportImportOutlineRepository(items: [])
        )
        await store.loadLists()

        let opml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0"><head><title>BOM OPML</title></head><body><outline text="Root"/></body></opml>
        """
        var bomPrefixed = Data([0xEF, 0xBB, 0xBF])
        bomPrefixed.append(Data(opml.utf8))

        let preparedPlan = await store.prepareAdditiveImport(from: bomPrefixed, filename: "bom.opml")
        let plan = try XCTUnwrap(preparedPlan)
        let committed = await store.commitAdditiveImport(plan)
        XCTAssertTrue(committed)
        XCTAssertTrue(store.lists.contains { $0.title == "BOM OPML" })
    }

    @MainActor
    func testPrepareAdditiveImportWithRepairsWritesNothingUntilCommit() async throws {
        let listRepository = ExportImportListRepository(lists: [])
        let store = AppStore(
            listRepository: listRepository,
            outlineRepository: ExportImportOutlineRepository(items: [])
        )
        await store.loadLists()

        let sourceList = ListItem(title: "Broken Parent", position: 1)
        let orphanItem = OutlineItem(listID: sourceList.id, parentID: UUID(), title: "Orphan", position: 1)
        let export = ExportService().export(lists: [(sourceList, [orphanItem])], appVersion: "test")
        let data = try ExportService().encode(export)

        let preparedPlan = await store.prepareAdditiveImport(from: data, filename: "broken.json")
        let plan = try XCTUnwrap(preparedPlan)
        XCTAssertEqual(plan.summary.repairedParentCount, 1)
        let addCountAfterPrepare = await listRepository.addCount()
        XCTAssertEqual(addCountAfterPrepare, 0, "prepare must write nothing")

        let committed = await store.commitAdditiveImport(plan)
        XCTAssertTrue(committed)
        let addCountAfterCommit = await listRepository.addCount()
        XCTAssertEqual(addCountAfterCommit, 1)

        let importedList = try XCTUnwrap(store.lists.first { $0.title == "Broken Parent" })
        let items = await listRepository.savedItems(forList: importedList.id)
        XCTAssertEqual(items.count, 1)
        XCTAssertNil(items.first?.parentID, "orphan should be repaired to root")
    }

    // MARK: - Per-list export (§6.1)

    @MainActor
    func testExportListJSONOPMLMarkdownHappyPaths() async throws {
        let list = ListItem(title: "Packing", position: 1)
        let parent = OutlineItem(listID: list.id, title: "Clothing", position: 1)
        let child = OutlineItem(listID: list.id, parentID: parent.id, title: "Socks", quantity: 2, position: 1)
        let listRepository = ExportImportListRepository(lists: [list])
        let store = AppStore(
            listRepository: listRepository,
            outlineRepository: ExportImportOutlineRepository(items: [parent, child])
        )
        await store.loadLists()

        let exportedJSON = await store.exportListJSON(id: list.id, appVersion: "test")
        let jsonData = try XCTUnwrap(exportedJSON)
        let decoded = try ExportService().decode(from: jsonData)
        XCTAssertEqual(decoded.lists.count, 1)
        XCTAssertEqual(decoded.lists.first?.items.count, 2)

        let exportedOPML = await store.exportListOPML(id: list.id)
        let opmlData = try XCTUnwrap(exportedOPML)
        let opmlDocument = try OPMLCodec().decode(opmlData)
        XCTAssertEqual(opmlDocument.title, "Packing")
        XCTAssertEqual(opmlDocument.nodes.first?.text, "Clothing")
        XCTAssertEqual(opmlDocument.nodes.first?.children.first?.text, "Socks")

        let exportedMarkdown = await store.exportListMarkdown(id: list.id)
        let markdown = try XCTUnwrap(exportedMarkdown)
        XCTAssertTrue(markdown.contains("# Packing"))
        XCTAssertTrue(markdown.contains("Socks ×2"))
    }

    @MainActor
    func testExportListRepoThrowPresentsErrorAndReturnsNil() async throws {
        let list = ListItem(title: "Packing", position: 1)
        let listRepository = ExportImportListRepository(lists: [list])
        let outlineRepository = ExportImportOutlineRepository(items: [], shouldThrowOnFetch: true)
        let errorStore = AppErrorStore()
        let store = AppStore(
            listRepository: listRepository,
            outlineRepository: outlineRepository,
            errorStore: errorStore
        )
        await store.loadLists()

        let json = await store.exportListJSON(id: list.id)
        XCTAssertNil(json)
        guard case .persistenceLoad = errorStore.current?.error else {
            return XCTFail("Expected persistence load error")
        }
    }
}

private actor ExportImportListRepository: ListRepository {
    private var lists: [ListItem]
    private var itemsByList: [UUID: [OutlineItem]]
    private var replacements: [LibraryArchive] = []
    private var additions: [LibraryArchive] = []

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

    func addListsAndItems(with archive: LibraryArchive) async throws {
        additions.append(archive)
        for archivedList in archive.lists {
            lists.append(archivedList.list)
            itemsByList[archivedList.list.id] = archivedList.items
        }
    }

    func deleteListAndItems(id: UUID) async throws {
        lists.removeAll { $0.id == id }
        itemsByList[id] = nil
    }

    func replacementCount() -> Int {
        replacements.count
    }

    func addCount() -> Int {
        additions.count
    }

    func savedItems(forList listID: UUID) -> [OutlineItem] {
        itemsByList[listID] ?? []
    }
}

private actor ExportImportOutlineRepository: OutlineRepository {
    private var items: [OutlineItem]
    private var shouldThrowOnFetch: Bool

    init(items: [OutlineItem], shouldThrowOnFetch: Bool = false) {
        self.items = items
        self.shouldThrowOnFetch = shouldThrowOnFetch
    }

    struct FakeFetchError: Error {}

    func fetchItems(forList listID: UUID) async throws -> [OutlineItem] {
        if shouldThrowOnFetch {
            throw FakeFetchError()
        }
        return items.filter { $0.listID == listID }
    }

    func applyChanges(saving newItems: [OutlineItem], deletingIDs: [UUID]) async throws {
        let savedIDs = Set(newItems.map(\.id))
        items.removeAll { savedIDs.contains($0.id) }
        items.append(contentsOf: newItems)
        let deleted = Set(deletingIDs)
        items.removeAll { deleted.contains($0.id) }
    }
}
