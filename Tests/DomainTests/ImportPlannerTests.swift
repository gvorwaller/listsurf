import XCTest
@testable import Domain

final class ImportPlannerTests: XCTestCase {
    let planner = ImportPlanner()

    // MARK: - JSON

    func testJSONRemapsAllIDsPreservesParentRelationshipAndDates() throws {
        let listID = UUID()
        let parentID = UUID()
        let childID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_000_000)
        let updatedAt = Date(timeIntervalSince1970: 1_000_100)
        let list = ListItem(id: listID, title: "List", createdAt: createdAt, updatedAt: updatedAt)
        let parent = OutlineItem(
            id: parentID, listID: listID, title: "Parent", position: 1,
            createdAt: createdAt, updatedAt: updatedAt
        )
        let child = OutlineItem(
            id: childID, listID: listID, parentID: parentID, title: "Child", position: 2,
            createdAt: createdAt, updatedAt: updatedAt
        )

        let export = ExportService().export(lists: [(list, [parent, child])], appVersion: "1.0")
        let plan = try planner.planAdditiveImport(from: export)

        XCTAssertEqual(plan.summary, ImportSummary(listCount: 1, itemCount: 2, repairedParentCount: 0))

        let newList = plan.archive.lists[0].list
        XCTAssertNotEqual(newList.id, listID)
        XCTAssertEqual(newList.createdAt, createdAt)
        XCTAssertEqual(newList.updatedAt, updatedAt)

        let newItems = plan.archive.lists[0].items
        XCTAssertEqual(Set(newItems.map(\.id)).count, 2)
        XCTAssertFalse(newItems.contains { $0.id == parentID || $0.id == childID })

        let newParent = try XCTUnwrap(newItems.first { $0.title == "Parent" })
        let newChild = try XCTUnwrap(newItems.first { $0.title == "Child" })
        XCTAssertNil(newParent.parentID)
        XCTAssertEqual(newChild.parentID, newParent.id)
        XCTAssertEqual(newParent.listID, newList.id)
        XCTAssertEqual(newChild.listID, newList.id)
        XCTAssertEqual(newParent.createdAt, createdAt)
        XCTAssertEqual(newChild.createdAt, createdAt)
        XCTAssertEqual(newChild.updatedAt, updatedAt)
    }

    func testJSONMissingParentPlacedAtRootCountedAndKept() throws {
        let listID = UUID()
        let itemID = UUID()
        let missingParentID = UUID()
        let list = ListItem(id: listID, title: "List")
        let item = OutlineItem(id: itemID, listID: listID, parentID: missingParentID, title: "Orphan")

        let export = ExportService().export(lists: [(list, [item])], appVersion: "1.0")
        let plan = try planner.planAdditiveImport(from: export)

        XCTAssertEqual(plan.summary.repairedParentCount, 1)
        XCTAssertEqual(plan.archive.lists[0].items.count, 1)
        XCTAssertNil(plan.archive.lists[0].items[0].parentID)
    }

    func testJSONTwoItemCycleRepairedToRootAndCounted() throws {
        let listID = UUID()
        let aID = UUID()
        let bID = UUID()
        let list = ListItem(id: listID, title: "List")
        let itemA = OutlineItem(id: aID, listID: listID, parentID: bID, title: "A")
        let itemB = OutlineItem(id: bID, listID: listID, parentID: aID, title: "B")

        let export = ExportService().export(lists: [(list, [itemA, itemB])], appVersion: "1.0")
        let plan = try planner.planAdditiveImport(from: export)

        XCTAssertEqual(plan.summary.repairedParentCount, 2)
        XCTAssertEqual(plan.archive.lists[0].items.count, 2)
        XCTAssertTrue(plan.archive.lists[0].items.allSatisfy { $0.parentID == nil })
    }

    func testDuplicateItemIDsStillThrowUnderPermitInvalid() {
        let listID = UUID()
        let itemID = UUID()
        let item = OutlineItem(id: itemID, listID: listID, title: "One")
        let export = ExportService().export(
            lists: [(ListItem(id: listID, title: "List"), [item, item])],
            appVersion: "1.0"
        )

        XCTAssertThrowsError(try planner.planAdditiveImport(from: export)) { error in
            guard case ExportValidationError.duplicateItemID(itemID) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testEmptyItemTitleStillThrowsUnderPermitInvalid() {
        let listID = UUID()
        let itemID = UUID()
        let item = OutlineItem(id: itemID, listID: listID, title: "   ")
        let export = ExportService().export(
            lists: [(ListItem(id: listID, title: "List"), [item])],
            appVersion: "1.0"
        )

        XCTAssertThrowsError(try planner.planAdditiveImport(from: export)) { error in
            guard case ExportValidationError.emptyItemTitle(itemID) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testPlanningSameExportTwiceProducesDisjointIDSets() throws {
        let listID = UUID()
        let itemID = UUID()
        let item = OutlineItem(id: itemID, listID: listID, title: "Item")
        let export = ExportService().export(
            lists: [(ListItem(id: listID, title: "List"), [item])],
            appVersion: "1.0"
        )

        let plan1 = try planner.planAdditiveImport(from: export)
        let plan2 = try planner.planAdditiveImport(from: export)

        let ids1 = Set(plan1.archive.lists.flatMap { [$0.list.id] + $0.items.map(\.id) })
        let ids2 = Set(plan2.archive.lists.flatMap { [$0.list.id] + $0.items.map(\.id) })
        XCTAssertTrue(ids1.isDisjoint(with: ids2))
    }

    // MARK: - OPML

    func testOPMLPositionsPerSiblingGroupAndSharedCreatedAt() throws {
        let document = OPMLDocument(
            title: nil,
            nodes: [
                OPMLOutlineNode(text: "A"),
                OPMLOutlineNode(text: "B", children: [
                    OPMLOutlineNode(text: "B1"),
                    OPMLOutlineNode(text: "B2"),
                ]),
            ]
        )

        let plan = planner.planAdditiveImport(from: document, fallbackTitle: "Fallback")
        let items = plan.archive.lists[0].items

        let a = try XCTUnwrap(items.first { $0.title == "A" })
        let b = try XCTUnwrap(items.first { $0.title == "B" })
        let b1 = try XCTUnwrap(items.first { $0.title == "B1" })
        let b2 = try XCTUnwrap(items.first { $0.title == "B2" })

        XCTAssertEqual(a.position, 1)
        XCTAssertEqual(b.position, 2)
        XCTAssertEqual(b1.position, 1)
        XCTAssertEqual(b2.position, 2)
        XCTAssertNil(a.parentID)
        XCTAssertNil(b.parentID)
        XCTAssertEqual(b1.parentID, b.id)
        XCTAssertEqual(b2.parentID, b.id)

        XCTAssertEqual(Set(items.map(\.createdAt)).count, 1)
        XCTAssertEqual(Set(items.map(\.updatedAt)).count, 1)

        XCTAssertEqual(plan.summary, ImportSummary(listCount: 1, itemCount: 4, repairedParentCount: 0))
    }

    func testOPMLUsesFallbackTitleWhenDocumentTitleNil() {
        let document = OPMLDocument(title: nil, nodes: [OPMLOutlineNode(text: "Item")])
        let plan = planner.planAdditiveImport(from: document, fallbackTitle: "My File")
        XCTAssertEqual(plan.archive.lists[0].list.title, "My File")
    }

    func testOPMLUsesDocumentTitleWhenPresent() {
        let document = OPMLDocument(title: "Doc Title", nodes: [OPMLOutlineNode(text: "Item")])
        let plan = planner.planAdditiveImport(from: document, fallbackTitle: "Fallback")
        XCTAssertEqual(plan.archive.lists[0].list.title, "Doc Title")
    }

    func testOPMLFallsBackToImportedListWhenBothTitlesEmpty() {
        let document = OPMLDocument(title: "   ", nodes: [OPMLOutlineNode(text: "Item")])
        let plan = planner.planAdditiveImport(from: document, fallbackTitle: "   ")
        XCTAssertEqual(plan.archive.lists[0].list.title, "Imported List")
    }
}
