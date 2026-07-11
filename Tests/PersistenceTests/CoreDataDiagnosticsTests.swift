import XCTest
@testable import Domain
@testable import Persistence

final class CoreDataDiagnosticsTests: XCTestCase {

    func testSnapshotCountsMatchSeededData() async throws {
        let stack = PersistenceStack.inMemory()
        let listRepo = CoreDataListRepository(stack: stack)

        let activeOne = ListItem(title: "Active One")
        let activeTwo = ListItem(title: "Active Two")
        let archived = ListItem(title: "Archived One", archivedAt: Date())
        try await listRepo.saveListAndItems(
            activeOne,
            items: [
                OutlineItem(listID: activeOne.id, title: "Item 1"),
                OutlineItem(listID: activeOne.id, title: "Item 2"),
            ]
        )
        try await listRepo.saveListAndItems(
            activeTwo,
            items: [OutlineItem(listID: activeTwo.id, title: "Item 3")]
        )
        try await listRepo.saveListAndItems(archived, items: [])

        let diagnostics = CoreDataDiagnostics(stack: stack)
        let snapshot = try await diagnostics.snapshot()

        XCTAssertEqual(snapshot.activeListCount, 2)
        XCTAssertEqual(snapshot.archivedListCount, 1)
        XCTAssertEqual(snapshot.itemCount, 3)
    }

    func testInMemoryStoreReportsNilURLAndNilSize() async throws {
        let stack = PersistenceStack.inMemory()
        let diagnostics = CoreDataDiagnostics(stack: stack)

        let snapshot = try await diagnostics.snapshot()

        XCTAssertNil(snapshot.storeURL)
        XCTAssertNil(snapshot.storeSizeBytes)
        XCTAssertEqual(snapshot.activeListCount, 0)
        XCTAssertEqual(snapshot.archivedListCount, 0)
        XCTAssertEqual(snapshot.itemCount, 0)
    }

    func testFileBackedStoreReportsURLAndPlausibleSize() async throws {
        let storeURL = try temporaryStoreURL()
        defer { removeStoreFiles(at: storeURL) }

        let stack = PersistenceStack(storeURL: storeURL)
        XCTAssertNil(stack.storeLoadError)
        let listRepo = CoreDataListRepository(stack: stack)
        let list = ListItem(title: "On Disk")
        try await listRepo.saveListAndItems(
            list,
            items: [OutlineItem(listID: list.id, title: "Some content to size the store")]
        )

        let diagnostics = CoreDataDiagnostics(stack: stack)
        let snapshot = try await diagnostics.snapshot()

        XCTAssertEqual(snapshot.storeURL, storeURL)
        let size = try XCTUnwrap(snapshot.storeSizeBytes)
        XCTAssertGreaterThan(size, 0)
    }

    private func temporaryStoreURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsurfDiagnosticsTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("diagnostics.sqlite")
    }

    private func removeStoreFiles(at storeURL: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: storeURL.path + suffix)
        }
        try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent())
    }
}
