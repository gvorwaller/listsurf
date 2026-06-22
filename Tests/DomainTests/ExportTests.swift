import XCTest
@testable import Domain

final class ExportTests: XCTestCase {
    let service = ExportService()

    func testJSONRoundTrip() throws {
        let listID = UUID()
        let list = ListItem(
            id: listID,
            title: "Test List",
            notes: "Some notes",
            icon: "suitcase",
            colorName: "blue"
        )
        let item = OutlineItem(
            id: UUID(),
            listID: listID,
            title: "Item One",
            notes: "Item notes",
            quantity: 3,
            isChecked: true
        )

        let export = service.export(lists: [(list, [item])], appVersion: "1.0.0")
        let data = try service.encode(export)
        let decoded = try service.decode(from: data)

        XCTAssertEqual(decoded.format, "listsurf")
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.appVersion, "1.0.0")
        XCTAssertEqual(decoded.lists.count, 1)

        let decodedList = decoded.lists[0]
        XCTAssertEqual(decodedList.id, list.id)
        XCTAssertEqual(decodedList.title, list.title)
        XCTAssertEqual(decodedList.notes, list.notes)
        XCTAssertEqual(decodedList.icon, "suitcase")
        XCTAssertEqual(decodedList.colorName, "blue")

        let decodedItem = decodedList.items[0]
        XCTAssertEqual(decodedItem.id, item.id)
        XCTAssertEqual(decodedItem.title, item.title)
        XCTAssertEqual(decodedItem.notes, item.notes)
        XCTAssertEqual(decodedItem.quantity, 3)
        XCTAssertTrue(decodedItem.isChecked)
    }

    func testExportEnvelope() {
        let export = service.export(lists: [], appVersion: "0.1.0")

        XCTAssertEqual(export.format, "listsurf")
        XCTAssertEqual(export.schemaVersion, 1)
        XCTAssertEqual(export.appVersion, "0.1.0")
        XCTAssertTrue(export.lists.isEmpty)
    }

    func testArchiveFromExportRestoresListAndItemModels() throws {
        let listID = UUID()
        let parentID = UUID()
        let childID = UUID()
        let list = ListItem(id: listID, title: "Restored")
        let parent = OutlineItem(id: parentID, listID: listID, title: "Parent", position: 1)
        let child = OutlineItem(
            id: childID,
            listID: listID,
            parentID: parentID,
            title: "Child",
            quantity: 2,
            isChecked: true,
            position: 2
        )

        let export = service.export(lists: [(list, [parent, child])], appVersion: "1.0")
        let archive = try service.archive(from: export)

        XCTAssertEqual(archive.lists.count, 1)
        XCTAssertEqual(archive.lists[0].list.id, listID)
        XCTAssertEqual(archive.lists[0].items.map(\.listID), [listID, listID])
        XCTAssertEqual(archive.lists[0].items.first { $0.id == childID }?.parentID, parentID)
    }

    func testValidationRejectsDuplicateItemIDs() throws {
        let listID = UUID()
        let itemID = UUID()
        let item = OutlineItem(id: itemID, listID: listID, title: "One")
        let export = service.export(
            lists: [
                (ListItem(id: listID, title: "List"), [item, item])
            ],
            appVersion: "1.0"
        )

        XCTAssertThrowsError(try service.archive(from: export)) { error in
            guard case ExportValidationError.duplicateItemID(itemID) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testValidationRejectsMissingParent() throws {
        let listID = UUID()
        let itemID = UUID()
        let missingParentID = UUID()
        let item = OutlineItem(
            id: itemID,
            listID: listID,
            parentID: missingParentID,
            title: "Child"
        )
        let export = service.export(
            lists: [
                (ListItem(id: listID, title: "List"), [item])
            ],
            appVersion: "1.0"
        )

        XCTAssertThrowsError(try service.archive(from: export)) { error in
            guard case ExportValidationError.missingParent(itemID, missingParentID) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }
}
