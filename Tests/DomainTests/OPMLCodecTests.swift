import XCTest
@testable import Domain

final class OPMLCodecTests: XCTestCase {
    let codec = OPMLCodec()

    // MARK: - Round trip

    func testRoundTripPreservesHierarchyCheckedStateQuantityAndSpecialCharacters() throws {
        let listID = UUID()
        let list = ListItem(id: listID, title: "Packing")

        let clothingID = UUID()
        let socksID = UUID()
        let woolID = UUID()
        let toiletriesID = UUID()

        // Broadened escaping set per spec §10: \n, \r\n, \t, &, <, >, ", literal &amp;, emoji.
        let note = "Line1\nLine2\r\nLine3\tTabbed & <tag> \"quoted\" &amp; 🧦"

        let clothing = OutlineItem(
            id: clothingID, listID: listID, title: "Clothing", isChecked: false, position: 1
        )
        let socks = OutlineItem(
            id: socksID, listID: listID, parentID: clothingID, title: "Socks",
            notes: note, quantity: 4, isChecked: true, position: 1
        )
        let wool = OutlineItem(
            id: woolID, listID: listID, parentID: socksID, title: "Wool Socks",
            quantity: 1, isChecked: false, position: 1
        )
        let toiletries = OutlineItem(
            id: toiletriesID, listID: listID, title: "Toiletries", quantity: 1,
            isChecked: false, position: 2
        )

        // Deliberately out of hierarchical order — encode must sort by position, not array order.
        let items = [toiletries, wool, socks, clothing]
        let data = codec.encode(list: list, items: items)
        let document = try codec.decode(data)

        XCTAssertEqual(document.title, "Packing")
        XCTAssertEqual(document.nodes.count, 2)

        let decodedClothing = document.nodes[0]
        XCTAssertEqual(decodedClothing.text, "Clothing")
        XCTAssertFalse(decodedClothing.isChecked)
        XCTAssertEqual(decodedClothing.quantity, 1)
        XCTAssertNil(decodedClothing.note)
        XCTAssertEqual(decodedClothing.children.count, 1)

        let decodedSocks = decodedClothing.children[0]
        XCTAssertEqual(decodedSocks.text, "Socks")
        XCTAssertTrue(decodedSocks.isChecked)
        XCTAssertEqual(decodedSocks.quantity, 4)
        XCTAssertEqual(decodedSocks.note, note)
        XCTAssertEqual(decodedSocks.children.count, 1)

        let decodedWool = decodedSocks.children[0]
        XCTAssertEqual(decodedWool.text, "Wool Socks")
        XCTAssertFalse(decodedWool.isChecked)
        XCTAssertEqual(decodedWool.quantity, 1)
        XCTAssertTrue(decodedWool.children.isEmpty)

        let decodedToiletries = document.nodes[1]
        XCTAssertEqual(decodedToiletries.text, "Toiletries")
        XCTAssertTrue(decodedToiletries.children.isEmpty)
    }

    func testEncodedOutputEscapesNewlinesInAttributesAndNeverEmitsRawNewline() throws {
        let listID = UUID()
        let list = ListItem(id: listID, title: "Packing")
        let item = OutlineItem(listID: listID, title: "Socks", notes: "Wool\nThick ones", position: 1)
        let data = codec.encode(list: list, items: [item])
        let xml = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(xml.contains("&#10;"))

        guard let noteRange = xml.range(of: "_note=\"") else {
            return XCTFail("expected _note attribute in encoded output")
        }
        let afterNoteStart = xml[noteRange.upperBound...]
        guard let closingQuoteRange = afterNoteStart.range(of: "\"") else {
            return XCTFail("expected closing quote for _note")
        }
        let noteAttributeValue = afterNoteStart[..<closingQuoteRange.lowerBound]
        XCTAssertFalse(noteAttributeValue.contains("\n"))
        XCTAssertFalse(noteAttributeValue.contains("\r"))
    }

    // MARK: - Encode attribute presence rules

    func testEncodeWritesStatusOnEveryOutlineAndQuantityOnlyWhenAboveOne() throws {
        let listID = UUID()
        let list = ListItem(id: listID, title: "List")
        let plain = OutlineItem(listID: listID, title: "Plain", position: 1)
        let quantityOne = OutlineItem(listID: listID, title: "One", quantity: 1, position: 2)
        let quantityFour = OutlineItem(listID: listID, title: "Four", quantity: 4, position: 3)
        let data = codec.encode(list: list, items: [plain, quantityOne, quantityFour])
        let xml = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(xml.contains("text=\"Plain\" _status=\"unchecked\"/>"))
        XCTAssertFalse(xml.contains("_note="))
        XCTAssertTrue(xml.contains("text=\"One\" _status=\"unchecked\"/>"))
        XCTAssertFalse(xml.contains("text=\"One\" _status=\"unchecked\" _quantity="))
        XCTAssertTrue(xml.contains("text=\"Four\" _status=\"unchecked\" _quantity=\"4\""))
    }

    // MARK: - Unknown elements (invariant 10)

    func testUnknownHeadElementsDoNotPolluteTitle() throws {
        let xml = """
        <opml version="2.0">
          <head>
            <title>Real Title</title>
            <expansionState>1,2</expansionState>
            <ownerName>X</ownerName>
          </head>
          <body>
            <outline text="A"/>
          </body>
        </opml>
        """
        let document = try codec.decode(Data(xml.utf8))
        XCTAssertEqual(document.title, "Real Title")
        XCTAssertEqual(document.nodes.map(\.text), ["A"])
    }

    func testOutlineNestedUnderUnknownWrapperElementStillAttachesAtRoot() throws {
        let xml = """
        <opml version="2.0">
          <head><title>Doc</title></head>
          <body>
            <section>
              <outline text="A"/>
            </section>
          </body>
        </opml>
        """
        let document = try codec.decode(Data(xml.utf8))
        XCTAssertEqual(document.nodes.map(\.text), ["A"])
    }

    // MARK: - CarbonFin-shaped decode

    func testDecodeCarbonFinLikeDocumentWithCDATATitleAndUnknownAttributes() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head>
            <title><![CDATA[Packing List]]></title>
            <expansionState>1,2,3</expansionState>
          </head>
          <body>
            <outline text="Socks" _note="Wool" _status="checked" created="Mon, 01 Jan 2024" type="link">
              <outline text="Wool Socks" />
            </outline>
          </body>
        </opml>
        """
        let document = try codec.decode(Data(xml.utf8))
        XCTAssertEqual(document.title, "Packing List")
        XCTAssertEqual(document.nodes.count, 1)
        let socks = document.nodes[0]
        XCTAssertEqual(socks.text, "Socks")
        XCTAssertEqual(socks.note, "Wool")
        XCTAssertTrue(socks.isChecked)
        XCTAssertEqual(socks.children.map(\.text), ["Wool Socks"])
    }

    func testDecodeCheckedAttributeVariantsAndLegacyTitleFallback() throws {
        let xml = """
        <opml version="2.0"><head><title>T</title></head><body>
          <outline text="A" _complete="true"/>
          <outline text="B" checked="true"/>
          <outline title="Legacy Title Attr"/>
          <outline text="D" _status="indeterminate"/>
        </body></opml>
        """
        let document = try codec.decode(Data(xml.utf8))
        XCTAssertEqual(document.nodes.count, 4)
        XCTAssertTrue(document.nodes[0].isChecked)
        XCTAssertTrue(document.nodes[1].isChecked)
        XCTAssertEqual(document.nodes[2].text, "Legacy Title Attr")
        XCTAssertFalse(document.nodes[2].isChecked)
        XCTAssertFalse(document.nodes[3].isChecked)
    }

    func testDecodeMalformedQuantityIgnoredAsUnknownAttribute() throws {
        let xml = """
        <opml version="2.0"><head><title>T</title></head><body>
          <outline text="A" _quantity="not-a-number"/>
        </body></opml>
        """
        let document = try codec.decode(Data(xml.utf8))
        XCTAssertEqual(document.nodes[0].quantity, 1)
    }

    /// Reduced CarbonFin-shape literal per spec §14: version='1.0', single-quoted
    /// attributes, _note, 4-deep nesting, self-closed leaves.
    func testDecodesReducedCarbonFinShapeFixture() throws {
        let xml = """
        <opml version='1.0'>
         <head>
          <title>Maine packing list</title>
         </head>
         <body>
          <outline text='Gaylon'>
           <outline text='Food items'>
            <outline text='Protein powder?' _note='Or buy there?' />
            <outline text='Shoes'>
             <outline text='walking shoes' _note='waterproof the shoes' />
            </outline>
           </outline>
          </outline>
         </body>
        </opml>
        """
        let document = try codec.decode(Data(xml.utf8))
        XCTAssertEqual(document.title, "Maine packing list")
        XCTAssertEqual(document.nodes.count, 1)

        let gaylon = document.nodes[0]
        XCTAssertEqual(gaylon.text, "Gaylon")
        XCTAssertEqual(gaylon.children.count, 1)

        let foodItems = gaylon.children[0]
        XCTAssertEqual(foodItems.text, "Food items")
        XCTAssertEqual(foodItems.children.count, 2)

        let protein = foodItems.children[0]
        XCTAssertEqual(protein.text, "Protein powder?")
        XCTAssertEqual(protein.note, "Or buy there?")

        let shoes = foodItems.children[1]
        XCTAssertEqual(shoes.text, "Shoes")
        XCTAssertEqual(shoes.children.count, 1)
        XCTAssertEqual(shoes.children[0].text, "walking shoes")
        XCTAssertEqual(shoes.children[0].note, "waterproof the shoes")
    }

    // MARK: - Errors

    func testTruncatedXMLThrowsMalformedXMLWithPositiveLine() {
        let xml = "<opml version=\"2.0\"><head><title>T</title>"
        XCTAssertThrowsError(try codec.decode(Data(xml.utf8))) { error in
            guard case OPMLDecodeError.malformedXML(let line, _, _) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertGreaterThan(line, 0)
        }
    }

    func testNonOPMLRootThrowsNotOPML() {
        let xml = "<html><body>Hi</body></html>"
        XCTAssertThrowsError(try codec.decode(Data(xml.utf8))) { error in
            guard case OPMLDecodeError.notOPML = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue((error as? OPMLDecodeError)?.errorDescription?.contains("<opml>") ?? false)
        }
    }

    func testOutlineMissingTextThrowsMissingTextWithPlausibleLine() {
        let xml = """
        <opml version="2.0"><head><title>T</title></head><body>
          <outline text="A"/>
          <outline/>
        </body></opml>
        """
        XCTAssertThrowsError(try codec.decode(Data(xml.utf8))) { error in
            guard case OPMLDecodeError.missingText(let line) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertGreaterThan(line, 0)
            XCTAssertTrue((error as? OPMLDecodeError)?.errorDescription?.contains("line") ?? false)
        }
    }

    func testEmptyBodyThrowsEmptyOutline() {
        let xml = "<opml version=\"2.0\"><head><title>T</title></head><body/></opml>"
        XCTAssertThrowsError(try codec.decode(Data(xml.utf8))) { error in
            guard case OPMLDecodeError.emptyOutline = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testOutlinesOutsideBodyAreIgnoredWithTheirSubtrees() throws {
        // Only <body> outlines are list content: a metadata <outline> in <head>
        // (or anywhere else) must not become an imported row, and its nested
        // children must not corrupt the accepted outline stack.
        let xml = """
        <opml version="2.0">
          <head>
            <title>T</title>
            <outline text="Metadata"><outline text="Nested metadata"/></outline>
          </head>
          <body>
            <outline text="Real"><outline text="Real child"/></outline>
          </body>
        </opml>
        """
        let document = try codec.decode(Data(xml.utf8))
        XCTAssertEqual(document.title, "T")
        XCTAssertEqual(document.nodes.map(\.text), ["Real"])
        XCTAssertEqual(document.nodes[0].children.map(\.text), ["Real child"])
    }
}
