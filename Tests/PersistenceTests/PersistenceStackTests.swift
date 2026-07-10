import XCTest
import CoreData
@testable import Domain
@testable import Persistence

final class PersistenceStackTests: XCTestCase {

    func testInMemoryStoreInitializes() {
        let stack = PersistenceStack.inMemory()
        XCTAssertNotNil(stack.viewContext.persistentStoreCoordinator)
    }

    func testModelDefinesUniquenessConstraintsAndFetchIndexes() throws {
        let model = CoreDataModel.create()
        XCTAssertEqual(
            model.versionIdentifiers,
            [CoreDataModelVersion.v2ConstraintsAndIndexes.rawValue]
        )

        let listEntity = try XCTUnwrap(model.entitiesByName["ListEntity"])
        XCTAssertEqual(listEntity.uniquenessConstraints as? [[String]], [["id"]])
        XCTAssertEqual(
            Set(listEntity.indexes.map(\.name)),
            ["ListEntity_active_position", "ListEntity_archived_position"]
        )

        let outlineEntity = try XCTUnwrap(model.entitiesByName["OutlineItemEntity"])
        XCTAssertEqual(outlineEntity.uniquenessConstraints as? [[String]], [["id"]])
        XCTAssertEqual(
            Set(outlineEntity.indexes.map(\.name)),
            ["OutlineItemEntity_list_position", "OutlineItemEntity_list_parent_position"]
        )
    }

    func testCurrentStackMigratesV1Store() async throws {
        let storeURL = try temporaryStoreURL()
        defer { removeStoreFiles(at: storeURL) }

        let list = ListItem(
            title: "Migrated List",
            notes: "Created with v1 model",
            icon: "suitcase.fill",
            colorName: "blue"
        )
        let item = OutlineItem(
            listID: list.id,
            title: "Migrated Item",
            notes: "Still here",
            quantity: 2,
            isChecked: true
        )
        try createV1Store(at: storeURL, list: list, items: [item])

        let stack = PersistenceStack(storeURL: storeURL)
        XCTAssertNil(stack.storeLoadError)

        let listRepo = CoreDataListRepository(stack: stack)
        let itemRepo = CoreDataOutlineRepository(stack: stack)
        let migratedList = try await listRepo.fetch(id: list.id)
        let migratedItems = try await itemRepo.fetchItems(forList: list.id)

        XCTAssertEqual(migratedList?.title, "Migrated List")
        XCTAssertEqual(migratedList?.notes, "Created with v1 model")
        XCTAssertEqual(migratedItems.count, 1)
        XCTAssertEqual(migratedItems.first?.title, "Migrated Item")
        XCTAssertEqual(migratedItems.first?.quantity, 2)
        XCTAssertEqual(migratedItems.first?.isChecked, true)
    }

    func testSaveAndFetchList() async throws {
        let stack = PersistenceStack.inMemory()
        let repo = CoreDataListRepository(stack: stack)

        let list = ListItem(title: "Test List", icon: "suitcase", colorName: "blue")
        try await repo.save(list)

        let fetched = try await repo.fetchAll()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].title, "Test List")
        XCTAssertEqual(fetched[0].icon, "suitcase")
        XCTAssertEqual(fetched[0].colorName, "blue")
        XCTAssertEqual(fetched[0].id, list.id)
    }

    func testActiveVsArchivedFiltering() async throws {
        let stack = PersistenceStack.inMemory()
        let repo = CoreDataListRepository(stack: stack)

        let active = ListItem(title: "Active List", position: 1.0)
        let archived = ListItem(title: "Archived List", position: 2.0, archivedAt: Date())

        try await repo.save(active)
        try await repo.save(archived)

        let activeResults = try await repo.fetchActive()
        let archivedResults = try await repo.fetchArchived()

        XCTAssertEqual(activeResults.count, 1)
        XCTAssertEqual(activeResults[0].title, "Active List")
        XCTAssertEqual(archivedResults.count, 1)
        XCTAssertEqual(archivedResults[0].title, "Archived List")
    }

    func testSaveAndFetchOutlineItems() async throws {
        let stack = PersistenceStack.inMemory()
        let listRepo = CoreDataListRepository(stack: stack)
        let itemRepo = CoreDataOutlineRepository(stack: stack)

        let list = ListItem(title: "Test")
        try await listRepo.save(list)

        let parent = OutlineItem(listID: list.id, title: "Parent", position: 1.0)
        let child = OutlineItem(listID: list.id, parentID: parent.id, title: "Child", quantity: 3, position: 1.0)

        try await itemRepo.applyChanges(saving: [parent, child], deletingIDs: [])

        let items = try await itemRepo.fetchItems(forList: list.id)
        XCTAssertEqual(items.count, 2)

        let fetchedChild = items.first { $0.parentID == parent.id }
        XCTAssertEqual(fetchedChild?.title, "Child")
        XCTAssertEqual(fetchedChild?.quantity, 3)
    }

    func testDeleteRemovesEntity() async throws {
        let stack = PersistenceStack.inMemory()
        let repo = CoreDataListRepository(stack: stack)

        let list = ListItem(title: "To Delete")
        try await repo.save(list)
        try await repo.deleteListAndItems(id: list.id)

        let fetched = try await repo.fetchAll()
        XCTAssertTrue(fetched.isEmpty)
    }

    func testBulkSaveItems() async throws {
        let stack = PersistenceStack.inMemory()
        let listRepo = CoreDataListRepository(stack: stack)
        let itemRepo = CoreDataOutlineRepository(stack: stack)
        let list = ListItem(title: "Bulk")
        try await listRepo.save(list)

        let items = (0..<10).map { i in
            OutlineItem(listID: list.id, title: "Item \(i)", position: Double(i))
        }

        try await itemRepo.applyChanges(saving: items, deletingIDs: [])

        let fetched = try await itemRepo.fetchItems(forList: list.id)
        XCTAssertEqual(fetched.count, 10)
    }

    func testBulkSaveUpdatesExistingItems() async throws {
        let stack = PersistenceStack.inMemory()
        let listRepo = CoreDataListRepository(stack: stack)
        let itemRepo = CoreDataOutlineRepository(stack: stack)
        let list = ListItem(title: "Bulk")
        try await listRepo.save(list)
        let item = OutlineItem(listID: list.id, title: "Original", position: 1.0)
        try await itemRepo.applyChanges(saving: [item], deletingIDs: [])

        var updated = item
        updated.title = "Updated"
        updated.quantity = 4
        try await itemRepo.applyChanges(saving: [updated], deletingIDs: [])

        let fetched = try await itemRepo.fetchItems(forList: list.id)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].id, item.id)
        XCTAssertEqual(fetched[0].title, "Updated")
        XCTAssertEqual(fetched[0].quantity, 4)
    }

    func testBulkDeleteRemovesOnlyMatchingItems() async throws {
        let stack = PersistenceStack.inMemory()
        let listRepo = CoreDataListRepository(stack: stack)
        let itemRepo = CoreDataOutlineRepository(stack: stack)
        let list = ListItem(title: "Bulk")
        try await listRepo.save(list)
        let deleted = OutlineItem(listID: list.id, title: "Deleted", position: 1.0)
        let kept = OutlineItem(listID: list.id, title: "Kept", position: 2.0)
        try await itemRepo.applyChanges(saving: [deleted, kept], deletingIDs: [])

        try await itemRepo.applyChanges(saving: [], deletingIDs: [deleted.id, UUID()])

        let fetched = try await itemRepo.fetchItems(forList: list.id)
        XCTAssertEqual(fetched.map(\.id), [kept.id])
    }

    func testApplyChangesRefusesItemsForDeletedList() async throws {
        // A queued item save racing a list deletion must not resurrect
        // orphaned item rows for the deleted list.
        let stack = PersistenceStack.inMemory()
        let listRepo = CoreDataListRepository(stack: stack)
        let itemRepo = CoreDataOutlineRepository(stack: stack)
        let doomed = ListItem(title: "Doomed")
        let survivor = ListItem(title: "Survivor")
        try await listRepo.save(doomed)
        try await listRepo.save(survivor)

        try await listRepo.deleteListAndItems(id: doomed.id)

        let lateWrite = OutlineItem(listID: doomed.id, title: "Orphan-to-be")
        let validWrite = OutlineItem(listID: survivor.id, title: "Valid")
        try await itemRepo.applyChanges(saving: [lateWrite, validWrite], deletingIDs: [])

        let orphans = try await itemRepo.fetchItems(forList: doomed.id)
        let valid = try await itemRepo.fetchItems(forList: survivor.id)
        XCTAssertTrue(orphans.isEmpty, "Items must not be saved for a deleted list")
        XCTAssertEqual(valid.map(\.title), ["Valid"], "Writes for existing lists must still land")
    }

    func testApplyChangesSavesAndDeletesInOneOperation() async throws {
        let stack = PersistenceStack.inMemory()
        let listRepo = CoreDataListRepository(stack: stack)
        let itemRepo = CoreDataOutlineRepository(stack: stack)
        let list = ListItem(title: "Atomic")
        try await listRepo.save(list)
        let toDelete = OutlineItem(listID: list.id, title: "Going", position: 1.0)
        let toKeep = OutlineItem(listID: list.id, title: "Staying", position: 2.0)
        try await itemRepo.applyChanges(saving: [toDelete, toKeep], deletingIDs: [])

        let incoming = OutlineItem(listID: list.id, title: "Arriving", position: 3.0)
        try await itemRepo.applyChanges(saving: [incoming], deletingIDs: [toDelete.id])

        let fetched = try await itemRepo.fetchItems(forList: list.id)
        XCTAssertEqual(Set(fetched.map(\.title)), ["Staying", "Arriving"])
    }

    func testAtomicSaveCreatesListAndItems() async throws {
        let stack = PersistenceStack.inMemory()
        let listRepo = CoreDataListRepository(stack: stack)
        let itemRepo = CoreDataOutlineRepository(stack: stack)
        let list = ListItem(title: "Atomic Duplicate")
        let parent = OutlineItem(listID: list.id, title: "Parent")
        let child = OutlineItem(listID: list.id, parentID: parent.id, title: "Child")

        try await listRepo.saveListAndItems(list, items: [parent, child])

        let fetchedList = try await listRepo.fetch(id: list.id)
        let fetchedItems = try await itemRepo.fetchItems(forList: list.id)
        XCTAssertEqual(fetchedList?.title, "Atomic Duplicate")
        XCTAssertEqual(Set(fetchedItems.map(\.id)), Set([parent.id, child.id]))
    }

    func testAtomicDeleteRemovesListAndAllItems() async throws {
        let stack = PersistenceStack.inMemory()
        let listRepo = CoreDataListRepository(stack: stack)
        let itemRepo = CoreDataOutlineRepository(stack: stack)
        let list = ListItem(title: "Delete Atomically")
        let items = [
            OutlineItem(listID: list.id, title: "One"),
            OutlineItem(listID: list.id, title: "Two"),
        ]
        try await listRepo.saveListAndItems(list, items: items)

        try await listRepo.deleteListAndItems(id: list.id)

        let deletedList = try await listRepo.fetch(id: list.id)
        let remainingItems = try await itemRepo.fetchItems(forList: list.id)
        XCTAssertNil(deletedList)
        XCTAssertTrue(remainingItems.isEmpty)
    }

    func testReplaceAllListsAndItemsIsFullLibraryRestore() async throws {
        let stack = PersistenceStack.inMemory()
        let listRepo = CoreDataListRepository(stack: stack)
        let itemRepo = CoreDataOutlineRepository(stack: stack)
        let oldList = ListItem(title: "Old")
        try await listRepo.saveListAndItems(
            oldList,
            items: [OutlineItem(listID: oldList.id, title: "Old Item")]
        )

        let newList = ListItem(title: "New")
        let newItem = OutlineItem(listID: newList.id, title: "New Item")
        try await listRepo.replaceAllListsAndItems(
            with: LibraryArchive(
                lists: [ArchivedList(list: newList, items: [newItem])]
            )
        )

        let lists = try await listRepo.fetchAll()
        let deletedOldList = try await listRepo.fetch(id: oldList.id)
        let oldItems = try await itemRepo.fetchItems(forList: oldList.id)
        let newItems = try await itemRepo.fetchItems(forList: newList.id)
        XCTAssertEqual(lists.map(\.id), [newList.id])
        XCTAssertNil(deletedOldList)
        XCTAssertEqual(oldItems, [])
        XCTAssertEqual(newItems.map(\.id), [newItem.id])
    }

    func testInvalidDecodedImportWritesNothingBeforeRepositoryRestore() async throws {
        let stack = PersistenceStack.inMemory()
        let listRepo = CoreDataListRepository(stack: stack)
        let itemRepo = CoreDataOutlineRepository(stack: stack)
        let existingList = ListItem(title: "Existing")
        let existingItem = OutlineItem(listID: existingList.id, title: "Existing Item")
        try await listRepo.saveListAndItems(existingList, items: [existingItem])

        let service = ExportService()
        let badItem = OutlineItem(
            listID: existingList.id,
            parentID: UUID(),
            title: "Bad"
        )
        let badExport = service.export(
            lists: [(ListItem(title: "Replacement"), [badItem])],
            appVersion: "1.0"
        )

        XCTAssertThrowsError(try service.archive(from: badExport))
        let lists = try await listRepo.fetchAll()
        let items = try await itemRepo.fetchItems(forList: existingList.id)
        XCTAssertEqual(lists.map(\.id), [existingList.id])
        XCTAssertEqual(items.map(\.id), [existingItem.id])
    }

    private func createV1Store(
        at storeURL: URL,
        list: ListItem,
        items: [OutlineItem]
    ) throws {
        removeStoreFiles(at: storeURL)
        try FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let container = NSPersistentContainer(
            name: "Listsurf",
            managedObjectModel: CoreDataModel.create(version: .v1Initial)
        )
        let description = NSPersistentStoreDescription(url: storeURL)
        container.persistentStoreDescriptions = [description]

        let loadResult = StoreLoadResult()
        let semaphore = DispatchSemaphore(value: 0)
        container.loadPersistentStores { _, error in
            loadResult.error = error
            semaphore.signal()
        }
        semaphore.wait()
        if let error = loadResult.error {
            throw error
        }

        let context = container.viewContext
        let listEntity = ListEntityMO(
            entity: NSEntityDescription.entity(forEntityName: "ListEntity", in: context)!,
            insertInto: context
        )
        listEntity.update(from: list)

        for item in items {
            let itemEntity = OutlineItemEntityMO(
                entity: NSEntityDescription.entity(
                    forEntityName: "OutlineItemEntity",
                    in: context
                )!,
                insertInto: context
            )
            itemEntity.update(from: item)
        }

        try context.save()
    }

    private func temporaryStoreURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsurfMigrationTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("migration.sqlite")
    }

    private func removeStoreFiles(at storeURL: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: storeURL.path + suffix)
        }
        try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent())
    }
}

private final class StoreLoadResult: @unchecked Sendable {
    var error: Error?
}
