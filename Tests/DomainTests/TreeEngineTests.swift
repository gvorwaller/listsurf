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

    func testFlattenEmptyTree() {
        let rows = engine.flatten(items: [], expandedIDs: [])
        XCTAssertTrue(rows.isEmpty)
    }

    func testFlattenDeepNesting() {
        var items: [OutlineItem] = []
        var parentID: UUID? = nil
        for i in 0..<10 {
            let item = makeItem(parentID: parentID, title: "Level \(i)", position: 1.0)
            items.append(item)
            parentID = item.id
        }

        let expandedIDs = Set(items.map(\.id))
        let rows = engine.flatten(items: items, expandedIDs: expandedIDs)

        XCTAssertEqual(rows.count, 10)
        for (i, row) in rows.enumerated() {
            XCTAssertEqual(row.depth, i)
            XCTAssertEqual(row.item.title, "Level \(i)")
        }
    }

    func testFlattenMissingParentsTreatedAsRoots() {
        let orphan = makeItem(parentID: UUID(), title: "Orphan", position: 1.0)
        let root = makeItem(title: "Root", position: 2.0)

        let rows = engine.flatten(items: [orphan, root], expandedIDs: [])

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].item.title, "Root")
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

    func testParentAllChildrenUncheckedIsUnchecked() {
        let parent = makeItem(title: "Parent")
        let c1 = makeItem(parentID: parent.id, title: "C1", isChecked: false, position: 1.0)
        let c2 = makeItem(parentID: parent.id, title: "C2", isChecked: false, position: 2.0)

        let rows = engine.flatten(items: [parent, c1, c2], expandedIDs: [parent.id])

        XCTAssertEqual(rows[0].checkState, .unchecked)
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

    func testProgressEmptyList() {
        let progress = engine.listProgress(items: [])
        XCTAssertEqual(progress.checked, 0)
        XCTAssertEqual(progress.total, 0)
    }

    func testProgressSingleLeaf() {
        let item = makeItem(title: "Solo", isChecked: true)
        let progress = engine.listProgress(items: [item])
        XCTAssertEqual(progress.checked, 1)
        XCTAssertEqual(progress.total, 1)
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

    func testReparentToNonexistentItemThrows() {
        let item = makeItem(title: "Item")
        let fakeID = UUID()

        XCTAssertThrowsError(try engine.validateReparent(itemID: item.id, newParentID: fakeID, items: [item])) { error in
            guard case TreeError.itemNotFound = error else {
                XCTFail("Expected itemNotFound error"); return
            }
        }
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

    func testDuplicateEmptyList() {
        let list = ListItem(title: "Empty")
        let (newList, newItems) = engine.duplicateList(list, items: [], clearChecks: false)

        XCTAssertNotEqual(newList.id, list.id)
        XCTAssertEqual(newList.title, "Empty")
        XCTAssertTrue(newItems.isEmpty)
    }

    // MARK: - Check operations

    func testCheckCascadesToDescendants() {
        let parent = makeItem(title: "Parent")
        let child = makeItem(parentID: parent.id, title: "Child")
        let grandchild = makeItem(parentID: child.id, title: "Grandchild")

        let updated = engine.setChecked(true, itemID: parent.id, in: [parent, child, grandchild])

        XCTAssertTrue(updated.allSatisfy(\.isChecked))
    }

    func testUncheckCascadesToDescendants() {
        let parent = makeItem(title: "Parent", isChecked: true)
        let child = makeItem(parentID: parent.id, title: "Child", isChecked: true)

        let updated = engine.setChecked(false, itemID: parent.id, in: [parent, child])

        XCTAssertTrue(updated.allSatisfy { !$0.isChecked })
    }

    func testCheckLeafDoesNotAffectSiblings() {
        let c1 = makeItem(title: "C1", isChecked: false, position: 1.0)
        let c2 = makeItem(title: "C2", isChecked: false, position: 2.0)

        let updated = engine.setChecked(true, itemID: c1.id, in: [c1, c2])

        XCTAssertTrue(updated.first { $0.id == c1.id }!.isChecked)
        XCTAssertFalse(updated.first { $0.id == c2.id }!.isChecked)
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

    // MARK: - Move up/down

    func testMoveUpSwapsWithPreviousSibling() {
        let a = makeItem(title: "A", position: 1.0)
        let b = makeItem(title: "B", position: 2.0)
        let c = makeItem(title: "C", position: 3.0)

        guard let result = engine.moveUp(itemID: b.id, in: [a, b, c]) else {
            XCTFail("moveUp returned nil"); return
        }

        let sorted = result.sorted { $0.position < $1.position }
        XCTAssertEqual(sorted[0].id, b.id)
        XCTAssertEqual(sorted[1].id, a.id)
        XCTAssertEqual(sorted[2].id, c.id)
    }

    func testMoveUpFirstItemReturnsNil() {
        let a = makeItem(title: "A", position: 1.0)
        let b = makeItem(title: "B", position: 2.0)

        XCTAssertNil(engine.moveUp(itemID: a.id, in: [a, b]))
    }

    func testMoveDownSwapsWithNextSibling() {
        let a = makeItem(title: "A", position: 1.0)
        let b = makeItem(title: "B", position: 2.0)
        let c = makeItem(title: "C", position: 3.0)

        guard let result = engine.moveDown(itemID: b.id, in: [a, b, c]) else {
            XCTFail("moveDown returned nil"); return
        }

        let sorted = result.sorted { $0.position < $1.position }
        XCTAssertEqual(sorted[0].id, a.id)
        XCTAssertEqual(sorted[1].id, c.id)
        XCTAssertEqual(sorted[2].id, b.id)
    }

    func testMoveDownLastItemReturnsNil() {
        let a = makeItem(title: "A", position: 1.0)
        let b = makeItem(title: "B", position: 2.0)

        XCTAssertNil(engine.moveDown(itemID: b.id, in: [a, b]))
    }

    func testMoveOnlyAffectsSameParentSiblings() {
        let root1 = makeItem(title: "R1", position: 1.0)
        let root2 = makeItem(title: "R2", position: 2.0)
        let child1 = makeItem(parentID: root1.id, title: "C1", position: 1.0)
        let child2 = makeItem(parentID: root1.id, title: "C2", position: 2.0)

        guard let result = engine.moveDown(itemID: child1.id, in: [root1, root2, child1, child2]) else {
            XCTFail("moveDown returned nil"); return
        }

        let movedChild = result.first { $0.id == child1.id }!
        XCTAssertGreaterThan(movedChild.position, child2.position)
        XCTAssertEqual(result.first { $0.id == root2.id }!.position, 2.0)
    }

    // MARK: - Indent / Outdent

    func testIndentReparentsUnderPreviousSibling() throws {
        let a = makeItem(title: "A", position: 1.0)
        let b = makeItem(title: "B", position: 2.0)

        let result = try engine.indent(itemID: b.id, in: [a, b])
        let indented = result.first { $0.id == b.id }!

        XCTAssertEqual(indented.parentID, a.id)
    }

    func testIndentFirstSiblingThrows() {
        let a = makeItem(title: "A", position: 1.0)
        let b = makeItem(title: "B", position: 2.0)

        XCTAssertThrowsError(try engine.indent(itemID: a.id, in: [a, b]))
    }

    func testOutdentMovesToGrandparentLevel() throws {
        let grandparent = makeItem(title: "GP", position: 1.0)
        let parent = makeItem(parentID: grandparent.id, title: "P", position: 1.0)
        let child = makeItem(parentID: parent.id, title: "C", position: 1.0)

        let result = try engine.outdent(itemID: child.id, in: [grandparent, parent, child])
        let outdented = result.first { $0.id == child.id }!

        XCTAssertEqual(outdented.parentID, grandparent.id)
    }

    func testOutdentToRootLevel() throws {
        let parent = makeItem(title: "P", position: 1.0)
        let child = makeItem(parentID: parent.id, title: "C", position: 1.0)

        let result = try engine.outdent(itemID: child.id, in: [parent, child])
        let outdented = result.first { $0.id == child.id }!

        XCTAssertNil(outdented.parentID)
        XCTAssertGreaterThan(outdented.position, parent.position)
    }

    func testOutdentRootItemThrows() {
        let root = makeItem(title: "Root", position: 1.0)

        XCTAssertThrowsError(try engine.outdent(itemID: root.id, in: [root]))
    }

    func testIndentOutdentRoundTrip() throws {
        let a = makeItem(title: "A", position: 1.0)
        let b = makeItem(title: "B", position: 2.0)
        let c = makeItem(title: "C", position: 3.0)

        let indented = try engine.indent(itemID: b.id, in: [a, b, c])
        let bAfterIndent = indented.first { $0.id == b.id }!
        XCTAssertEqual(bAfterIndent.parentID, a.id)

        let outdented = try engine.outdent(itemID: b.id, in: indented)
        let bAfterOutdent = outdented.first { $0.id == b.id }!
        XCTAssertNil(bAfterOutdent.parentID)
    }

    // MARK: - Insert

    func testInsertAbovePlacesBeforeReference() {
        let existing = makeItem(title: "Existing", position: 2.0)
        let newItem = OutlineItem(listID: listID, title: "New")

        let result = engine.insertAbove(referenceID: existing.id, newItem: newItem, in: [existing])
        let inserted = result.first { $0.id == newItem.id }!

        XCTAssertLessThan(inserted.position, existing.position)
        XCTAssertEqual(inserted.parentID, existing.parentID)
    }

    func testInsertBelowPlacesAfterReference() {
        let existing = makeItem(title: "Existing", position: 2.0)
        let newItem = OutlineItem(listID: listID, title: "New")

        let result = engine.insertBelow(referenceID: existing.id, newItem: newItem, in: [existing])
        let inserted = result.first { $0.id == newItem.id }!

        XCTAssertGreaterThan(inserted.position, existing.position)
        XCTAssertEqual(inserted.parentID, existing.parentID)
    }

    func testInsertBetweenSiblings() {
        let a = makeItem(title: "A", position: 1.0)
        let c = makeItem(title: "C", position: 3.0)
        let newItem = OutlineItem(listID: listID, title: "B")

        let result = engine.insertBelow(referenceID: a.id, newItem: newItem, in: [a, c])
        let inserted = result.first { $0.id == newItem.id }!

        XCTAssertGreaterThan(inserted.position, a.position)
        XCTAssertLessThan(inserted.position, c.position)
    }

    func testInsertAboveBetweenSiblings() {
        let a = makeItem(title: "A", position: 1.0)
        let c = makeItem(title: "C", position: 3.0)
        let newItem = OutlineItem(listID: listID, title: "B")

        let result = engine.insertAbove(referenceID: c.id, newItem: newItem, in: [a, c])
        let inserted = result.first { $0.id == newItem.id }!

        XCTAssertGreaterThan(inserted.position, a.position)
        XCTAssertLessThan(inserted.position, c.position)
    }

    func testInsertChildAppendsToChildren() {
        let parent = makeItem(title: "Parent", position: 1.0)
        let existingChild = makeItem(parentID: parent.id, title: "Existing", position: 1.0)
        let newItem = OutlineItem(listID: listID, title: "New Child")

        let result = engine.insertChild(parentID: parent.id, newItem: newItem, in: [parent, existingChild])
        let inserted = result.first { $0.id == newItem.id }!

        XCTAssertEqual(inserted.parentID, parent.id)
        XCTAssertGreaterThan(inserted.position, existingChild.position)
    }

    func testInsertInheritsListID() {
        let existing = makeItem(title: "Existing", position: 1.0)
        let differentListItem = OutlineItem(listID: UUID(), title: "New")

        let result = engine.insertBelow(referenceID: existing.id, newItem: differentListItem, in: [existing])
        let inserted = result.first { $0.id == differentListItem.id }!

        XCTAssertEqual(inserted.listID, existing.listID)
    }

    // MARK: - Delete subtree

    func testDeleteSubtreeRemovesItemAndDescendants() {
        let parent = makeItem(title: "Parent", position: 1.0)
        let child = makeItem(parentID: parent.id, title: "Child", position: 1.0)
        let grandchild = makeItem(parentID: child.id, title: "Grandchild", position: 1.0)
        let sibling = makeItem(title: "Sibling", position: 2.0)

        let (remaining, deleted) = engine.deleteSubtree(itemID: parent.id, in: [parent, child, grandchild, sibling])

        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining[0].id, sibling.id)
        XCTAssertEqual(deleted.count, 3)
    }

    func testDeleteSubtreeLeafOnly() {
        let a = makeItem(title: "A", position: 1.0)
        let b = makeItem(title: "B", position: 2.0)

        let (remaining, deleted) = engine.deleteSubtree(itemID: a.id, in: [a, b])

        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining[0].id, b.id)
        XCTAssertEqual(deleted.count, 1)
        XCTAssertEqual(deleted[0].id, a.id)
    }

    func testDeleteNonexistentItemPreservesAll() {
        let item = makeItem(title: "Item")
        let fakeID = UUID()

        let (remaining, deleted) = engine.deleteSubtree(itemID: fakeID, in: [item])

        XCTAssertEqual(remaining.count, 1)
        XCTAssertTrue(deleted.isEmpty)
    }

    // MARK: - Subtree reset

    func testResetSubtreeOnlyAffectsSubtree() {
        let parent = makeItem(title: "Parent", isChecked: true, position: 1.0)
        let child = makeItem(parentID: parent.id, title: "Child", isChecked: true, position: 1.0)
        let sibling = makeItem(title: "Sibling", isChecked: true, position: 2.0)

        let result = engine.resetChecks(subtreeOf: parent.id, in: [parent, child, sibling])

        let resetParent = result.first { $0.id == parent.id }!
        let resetChild = result.first { $0.id == child.id }!
        let keptSibling = result.first { $0.id == sibling.id }!

        XCTAssertFalse(resetParent.isChecked)
        XCTAssertFalse(resetChild.isChecked)
        XCTAssertTrue(keptSibling.isChecked)
    }

    func testResetSubtreeSkipsAlreadyUnchecked() {
        let item = makeItem(title: "Unchecked", isChecked: false)
        let before = item.updatedAt

        let result = engine.resetChecks(subtreeOf: item.id, in: [item])
        let after = result.first { $0.id == item.id }!

        XCTAssertEqual(after.updatedAt, before)
    }

    // MARK: - Orphan repair

    func testRepairOrphansPromotesToRoot() {
        let missingParent = UUID()
        let orphan = makeItem(parentID: missingParent, title: "Orphan", position: 1.0)
        let root = makeItem(title: "Root", position: 2.0)

        let (repaired, count) = engine.repairOrphans(in: [orphan, root])

        XCTAssertEqual(count, 1)
        let fixedOrphan = repaired.first { $0.id == orphan.id }!
        XCTAssertNil(fixedOrphan.parentID)
    }

    func testRepairOrphansNoOrphans() {
        let parent = makeItem(title: "Parent", position: 1.0)
        let child = makeItem(parentID: parent.id, title: "Child", position: 1.0)

        let (_, count) = engine.repairOrphans(in: [parent, child])

        XCTAssertEqual(count, 0)
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

    func testMidpoint() {
        XCTAssertEqual(engine.midpoint(1.0, 3.0), 2.0)
        XCTAssertEqual(engine.midpoint(0.0, 1.0), 0.5)
    }

    func testNeedsRebalance() {
        XCTAssertTrue(engine.needsRebalance(1.0, 1.0 + 1e-11))
        XCTAssertFalse(engine.needsRebalance(1.0, 2.0))
    }

    func testNextPosition() {
        let items = [
            makeItem(title: "A", position: 3.0),
            makeItem(title: "B", position: 7.0),
        ]
        XCTAssertEqual(engine.nextPosition(among: items), 8.0)
    }

    func testNextPositionEmptyList() {
        XCTAssertEqual(engine.nextPosition(among: []), 1.0)
    }

    // MARK: - Siblings helper

    func testSiblingsExcludesSelf() {
        let a = makeItem(title: "A", position: 1.0)
        let b = makeItem(title: "B", position: 2.0)

        let sibs = engine.siblings(of: a.id, in: [a, b])

        XCTAssertEqual(sibs.count, 1)
        XCTAssertEqual(sibs[0].id, b.id)
    }

    func testSortedSiblingGroupIncludesSelf() {
        let a = makeItem(title: "A", position: 1.0)
        let b = makeItem(title: "B", position: 2.0)

        let group = engine.sortedSiblingGroup(of: a.id, in: [a, b])

        XCTAssertEqual(group.count, 2)
    }

    // MARK: - TreeCommand undo

    func testCommandExecuteInsertAndUndo() throws {
        let existing = makeItem(title: "Existing", position: 1.0)
        let newItem = OutlineItem(listID: listID, title: "New")

        let insertResult = try engine.execute(
            command: .insertBelow(referenceID: existing.id, newItem: newItem),
            on: [existing]
        )
        XCTAssertEqual(insertResult.items.count, 2)

        guard let inverse = insertResult.inverse else {
            XCTFail("Expected inverse command"); return
        }

        let undoResult = try engine.execute(command: inverse, on: insertResult.items)
        XCTAssertEqual(undoResult.items.count, 1)
        XCTAssertEqual(undoResult.items[0].id, existing.id)
    }

    func testCommandExecuteDeleteAndUndo() throws {
        let parent = makeItem(title: "Parent", position: 1.0)
        let child = makeItem(parentID: parent.id, title: "Child", position: 1.0)
        let sibling = makeItem(title: "Sibling", position: 2.0)
        let items = [parent, child, sibling]

        let deleteResult = try engine.execute(
            command: .deleteSubtree(itemID: parent.id),
            on: items
        )
        XCTAssertEqual(deleteResult.items.count, 1)

        guard let inverse = deleteResult.inverse else {
            XCTFail("Expected inverse command"); return
        }

        let undoResult = try engine.execute(command: inverse, on: deleteResult.items)
        XCTAssertEqual(undoResult.items.count, 3)
    }

    func testCommandExecuteCheckAndUndo() throws {
        let item = makeItem(title: "Item", isChecked: false)

        let checkResult = try engine.execute(
            command: .setChecked(checked: true, itemID: item.id),
            on: [item]
        )
        XCTAssertTrue(checkResult.items[0].isChecked)

        guard let inverse = checkResult.inverse else {
            XCTFail("Expected inverse command"); return
        }

        let undoResult = try engine.execute(command: inverse, on: checkResult.items)
        XCTAssertFalse(undoResult.items[0].isChecked)
    }

    func testCommandMoveUpAtTopIsNoOp() throws {
        let a = makeItem(title: "A", position: 1.0)
        let b = makeItem(title: "B", position: 2.0)

        let result = try engine.execute(command: .moveUp(itemID: a.id), on: [a, b])

        XCTAssertEqual(result.items.first { $0.id == a.id }!.position, 1.0)
    }

    // MARK: - Performance

    func testFlattenPerformance1000Items() {
        var items: [OutlineItem] = []
        var parentStack: [UUID?] = [nil]

        for i in 0..<1000 {
            let depth = i % 10
            while parentStack.count > depth + 1 {
                parentStack.removeLast()
            }
            let item = makeItem(
                parentID: parentStack.last ?? nil,
                title: "Item \(i)",
                position: Double(i % 100)
            )
            items.append(item)
            parentStack.append(item.id)
        }

        let expandedIDs = Set(items.map(\.id))

        measure {
            _ = engine.flatten(items: items, expandedIDs: expandedIDs)
        }
    }

    func testDuplicatePerformance1000Items() {
        let list = ListItem(title: "Big List")
        var items: [OutlineItem] = []
        var parentStack: [UUID?] = [nil]

        for i in 0..<1000 {
            let depth = i % 10
            while parentStack.count > depth + 1 {
                parentStack.removeLast()
            }
            let item = OutlineItem(
                listID: list.id,
                parentID: parentStack.last ?? nil,
                title: "Item \(i)",
                isChecked: i % 3 == 0,
                position: Double(i % 100)
            )
            items.append(item)
            parentStack.append(item.id)
        }

        measure {
            _ = engine.duplicateList(list, items: items, clearChecks: true)
        }
    }
}
