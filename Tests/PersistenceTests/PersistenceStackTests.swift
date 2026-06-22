import XCTest
import CoreData
@testable import Domain
@testable import Persistence

final class PersistenceStackTests: XCTestCase {

    func testInMemoryStoreInitializes() {
        let stack = PersistenceStack.inMemory()
        XCTAssertNotNil(stack.viewContext.persistentStoreCoordinator)
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

        try await itemRepo.save(parent)
        try await itemRepo.save(child)

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
        try await repo.delete(id: list.id)

        let fetched = try await repo.fetchAll()
        XCTAssertTrue(fetched.isEmpty)
    }

    func testBulkSaveItems() async throws {
        let stack = PersistenceStack.inMemory()
        let itemRepo = CoreDataOutlineRepository(stack: stack)
        let listID = UUID()

        let items = (0..<10).map { i in
            OutlineItem(listID: listID, title: "Item \(i)", position: Double(i))
        }

        try await itemRepo.saveAll(items)

        let fetched = try await itemRepo.fetchItems(forList: listID)
        XCTAssertEqual(fetched.count, 10)
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
}
