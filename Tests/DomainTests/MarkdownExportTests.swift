import XCTest
@testable import Domain

final class MarkdownExportTests: XCTestCase {
    let exporter = MarkdownExporter()

    func testGoldenFullRender() {
        let listID = UUID()
        let list = ListItem(id: listID, title: "Packing", notes: "Trip notes here.")

        let clothingID = UUID()
        let clothing = OutlineItem(
            id: clothingID, listID: listID, title: "Clothing", isChecked: false, position: 1
        )
        let socks = OutlineItem(
            id: UUID(), listID: listID, parentID: clothingID, title: "Socks",
            notes: "Wool\nThick ones", quantity: 4, isChecked: true, position: 1
        )
        let shirts = OutlineItem(
            id: UUID(), listID: listID, parentID: clothingID, title: "Shirts",
            quantity: 3, isChecked: false, position: 2
        )
        let toiletries = OutlineItem(
            id: UUID(), listID: listID, title: "Toiletries", isChecked: false, position: 2
        )

        // Deliberately out of hierarchical order to prove sorting is by position, not array order.
        let items = [toiletries, shirts, socks, clothing]

        let expected = """
        # Packing

        Trip notes here.

        - [ ] Clothing
          - [x] Socks ×4
            Wool
            Thick ones
          - [ ] Shirts ×3
        - [ ] Toiletries

        """

        XCTAssertEqual(exporter.render(list: list, items: items), expected)
    }

    func testNoQuantityMarkerWhenQuantityIsOne() {
        let listID = UUID()
        let list = ListItem(id: listID, title: "List")
        let item = OutlineItem(listID: listID, title: "Single", quantity: 1, position: 1)

        let rendered = exporter.render(list: list, items: [item])

        XCTAssertFalse(rendered.contains("×"))
        XCTAssertTrue(rendered.contains("- [ ] Single\n"))
    }

    func testNoContinuationLinesForNilNotes() {
        let listID = UUID()
        let list = ListItem(id: listID, title: "List")
        let item = OutlineItem(listID: listID, title: "Item", position: 1)

        let expected = """
        # List

        - [ ] Item

        """

        XCTAssertEqual(exporter.render(list: list, items: [item]), expected)
    }

    func testMultiLineNotesEachOnOwnIndentedLineAndBlankLinesSkipped() {
        let listID = UUID()
        let list = ListItem(id: listID, title: "List")
        let item = OutlineItem(
            listID: listID, title: "Item", notes: "First\n\n   \nSecond", position: 1
        )

        let expected = """
        # List

        - [ ] Item
          First
          Second

        """

        XCTAssertEqual(exporter.render(list: list, items: [item]), expected)
    }

    func testListWithoutNotesOmitsNotesParagraph() {
        let listID = UUID()
        let list = ListItem(id: listID, title: "No Notes")
        let item = OutlineItem(listID: listID, title: "Item", position: 1)

        let rendered = exporter.render(list: list, items: [item])

        XCTAssertFalse(rendered.contains("\n\n\n"))
        XCTAssertEqual(rendered, "# No Notes\n\n- [ ] Item\n")
    }
}
