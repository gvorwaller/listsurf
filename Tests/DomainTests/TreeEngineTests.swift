import XCTest
@testable import Domain

final class TreeEngineTests: XCTestCase {
    let engine = TreeEngine()
    let listID = UUID()

    private func makeItem(
        id: UUID = UUID(),
        parentID: UUID? = nil,
        title: String = "Item",
        isChecked: Bool = false,
        position: Double = 1.0
    ) -> OutlineItem {
        OutlineItem(
            id: id,
            listID: listID,
            parentID: parentID,
            title: title,
            isChecked: isChecked,
            position: position
        )
    }

    // MARK: - Flatten

    func testFlattenEmitsParentsBeforeChildren() {
        let parent = makeItem(title: "Parent", position: 1.0)
        let child = makeItem(parentID: parent.id, title: "Child", position: 1.0)

        let rows = engine.flatten(items: [child, parent], expandedIDs: [parent.id])

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].item.title, "Parent")
        XCTAssertEqual(rows[0].depth, 0)
        XCTAssertEqual(rows[1].item.title, "Child")
        XCTAssertEqual(rows[1].depth, 1)
    }

    func testFlattenRespectsExpansionState() {
        let parent = makeItem(title: "Parent", position: 1.0)
        let child = makeItem(parentID: parent.id, title: "Child", position: 1.0)

        let rows = engine.flatten(items: [parent, child], expandedIDs: [])

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].item.title, "Parent")
        XCTAssertTrue(rows[0].hasChildren)
    }

    func testFlattenSortsSiblingsByPositionThenUUID() {
        let a = makeItem(title: "A", position: 2.0)
        let b = makeItem(title: "B", position: 1.0)
        let c = makeItem(title: "C", position: 1.0)

        let rows = engine.flatten(items: [a, b, c], expandedIDs: [])

        XCTAssertEqual(rows[0].item.position, 1.0)
        XCTAssertEqual(rows[1].item.position, 1.0)
        XCTAssertEqual(rows[2].item.title, "A")
        XCTAssertLessThan(rows[0].item.id.uuidString, rows[1].item.id.uuidString)
    }

    // MARK: - Check state

    func testParentAllChildrenCheckedIsChecked() {
        let parent = makeItem(title: "Parent")
        let c1 = makeItem(parentID: parent.id, title: "C1", isChecked: true, position: 1.0)
        let c2 = makeItem(parentID: parent.id, title: "C2", isChecked: true, position: 2.0)

        let rows = engine.flatten(items: [parent, c1, c2], expandedIDs: [parent.id])

        XCTAssertEqual(rows[0].checkState, .checked)
    }

    func testParentMixedChildrenIsMixed() {
        let parent = makeItem(title: "Parent")
        let c1 = makeItem(parentID: parent.id, title: "C1", isChecked: true, position: 1.0)
        let c2 = makeItem(parentID: parent.id, title: "C2", isChecked: false, position: 2.0)

        let rows = engine.flatten(items: [parent, c1, c2], expandedIDs: [parent.id])

        XCTAssertEqual(rows[0].checkState, .mixed)
    }

    // MARK: - Progress

    func testProgressCountsOnlyLeaves() {
        let parent = makeItem(title: "Parent")
        let c1 = makeItem(parentID: parent.id, title: "C1", isChecked: true, position: 1.0)
        let c2 = makeItem(parentID: parent.id, title: "C2", isChecked: false, position: 2.0)

        let progress = engine.listProgress(items: [parent, c1, c2])

        XCTAssertEqual(progress.checked, 1)
        XCTAssertEqual(progress.total, 2)
    }

    // MARK: - Validation

    func testSelfParentingRejected() {
        let item = makeItem(title: "Self")

        XCTAssertThrowsError(try engine.validateReparent(itemID: item.id, newParentID: item.id, items: [item])) { error in
            guard case TreeError.selfParenting = error else {
                XCTFail("Expected selfParenting error"); return
            }
        }
    }

    func testCycleDetected() {
        let parent = makeItem(title: "Parent")
        let child = makeItem(parentID: parent.id, title: "Child")
        let grandchild = makeItem(parentID: child.id, title: "Grandchild")

        XCTAssertThrowsError(try engine.validateReparent(itemID: parent.id, newParentID: grandchild.id, items: [parent, child, grandchild])) { error in
            guard case TreeError.cycleDetected = error else {
                XCTFail("Expected cycleDetected error"); return
            }
        }
    }

    func testCrossListParentingRejected() {
        let otherListID = UUID()
        let item = makeItem(title: "Item")
        let foreignParent = OutlineItem(id: UUID(), listID: otherListID, title: "Foreign")

        XCTAssertThrowsError(try engine.validateReparent(itemID: item.id, newParentID: foreignParent.id, items: [item, foreignParent])) { error in
            guard case TreeError.crossListParenting = error else {
                XCTFail("Expected crossListParenting error"); return
            }
        }
    }

    func testReparentToRootIsValid() {
        let parent = makeItem(title: "Parent")
        let child = makeItem(parentID: parent.id, title: "Child")

        XCTAssertNoThrow(try engine.validateReparent(itemID: child.id, newParentID: nil, items: [parent, child]))
    }

    // MARK: - Duplicate

    func testDuplicateCreatesNewUUIDs() {
        let list = ListItem(title: "Test")
        let item = makeItem(title: "Item")

        let (newList, newItems) = engine.duplicateList(list, items: [item], clearChecks: false)

        XCTAssertNotEqual(newList.id, list.id)
        XCTAssertNotEqual(newItems[0].id, item.id)
        XCTAssertEqual(newItems[0].listID, newList.id)
        XCTAssertEqual(newItems[0].title, item.title)
    }

    func testDuplicatePreservesHierarchy() {
        let list = ListItem(title: "Test")
        let parent = makeItem(title: "Parent")
        let child = makeItem(parentID: parent.id, title: "Child")

        let (_, newItems) = engine.duplicateList(list, items: [parent, child], clearChecks: false)

        let newParent = newItems.first { $0.parentID == nil }!
        let newChild = newItems.first { $0.parentID != nil }!
        XCTAssertEqual(newChild.parentID, newParent.id)
    }

    func testDuplicateClearChecks() {
        let list = ListItem(title: "Test")
        let item = makeItem(title: "Checked", isChecked: true)

        let (_, newItems) = engine.duplicateList(list, items: [item], clearChecks: true)

        XCTAssertFalse(newItems[0].isChecked)
    }

    // MARK: - Check operations

    func testCheckCascadesToDescendants() {
        let parent = makeItem(title: "Parent")
        let child = makeItem(parentID: parent.id, title: "Child")
        let grandchild = makeItem(parentID: child.id, title: "Grandchild")

        let updated = engine.setChecked(true, itemID: parent.id, in: [parent, child, grandchild])

        XCTAssertTrue(updated.allSatisfy(\.isChecked))
    }

    func testResetClearsAllChecks() {
        let items = [
            makeItem(title: "A", isChecked: true, position: 1.0),
            makeItem(title: "B", isChecked: true, position: 2.0),
            makeItem(title: "C", isChecked: false, position: 3.0),
        ]

        let reset = engine.resetChecks(in: items)

        XCTAssertTrue(reset.allSatisfy { !$0.isChecked })
    }

    // MARK: - Position

    func testRebalancePreservesOrder() {
        let a = makeItem(title: "A", position: 0.001)
        let b = makeItem(title: "B", position: 0.002)
        let c = makeItem(title: "C", position: 0.003)

        let positions = engine.rebalancedPositions(for: [c, a, b])

        XCTAssertLessThan(positions[a.id]!, positions[b.id]!)
        XCTAssertLessThan(positions[b.id]!, positions[c.id]!)
        XCTAssertEqual(positions[a.id], 1.0)
        XCTAssertEqual(positions[b.id], 2.0)
        XCTAssertEqual(positions[c.id], 3.0)
    }
}
