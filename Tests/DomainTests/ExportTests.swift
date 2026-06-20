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
}
