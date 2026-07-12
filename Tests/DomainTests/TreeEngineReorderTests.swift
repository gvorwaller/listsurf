import XCTest
import SwiftUI // Rev 3: test target only, for the differential oracle against Array.move.
@testable import Domain

final class TreeEngineReorderTests: XCTestCase {
    let engine = TreeEngine()
    let listID = UUID()

    private func makeItem(
        id: UUID = UUID(),
        parentID: UUID? = nil,
        title: String = "Item",
        isChecked: Bool = false,
        position: Double = 1.0,
        updatedAt: Date = Date()
    ) -> OutlineItem {
        OutlineItem(
            id: id,
            listID: listID,
            parentID: parentID,
            title: title,
            isChecked: isChecked,
            position: position,
            createdAt: updatedAt,
            updatedAt: updatedAt
        )
    }

    // MARK: - reparent

    func testReparentToNewParentAppendsAtSlot() throws {
        let root1 = makeItem(title: "Root1", position: 1.0)
        let root2 = makeItem(title: "Root2", position: 2.0)
        let c1 = makeItem(parentID: root2.id, title: "C1", position: 1.0)
        let c2 = makeItem(parentID: root2.id, title: "C2", position: 2.0)
        let items = [root1, root2, c1, c2]

        let atStart = try engine.reparent(itemID: root1.id, toParent: root2.id, atSiblingSlot: 0, in: items)
        XCTAssertEqual(atStart.first { $0.id == root1.id }?.parentID, root2.id)
        XCTAssertEqual(engine.sortedSiblingGroup(of: root1.id, in: atStart).map(\.id), [root1.id, c1.id, c2.id])

        let atMid = try engine.reparent(itemID: root1.id, toParent: root2.id, atSiblingSlot: 1, in: items)
        XCTAssertEqual(atMid.first { $0.id == root1.id }?.parentID, root2.id)
        XCTAssertEqual(engine.sortedSiblingGroup(of: root1.id, in: atMid).map(\.id), [c1.id, root1.id, c2.id])

        let atEnd = try engine.reparent(itemID: root1.id, toParent: root2.id, atSiblingSlot: 2, in: items)
        XCTAssertEqual(atEnd.first { $0.id == root1.id }?.parentID, root2.id)
        XCTAssertEqual(engine.sortedSiblingGroup(of: root1.id, in: atEnd).map(\.id), [c1.id, c2.id, root1.id])
    }

    func testReparentToRootAtSlot() throws {
        let rootBefore = makeItem(title: "RootBefore", position: 1.0)
        let parent = makeItem(title: "Parent", position: 2.0)
        let a = makeItem(parentID: parent.id, title: "A", position: 1.0)
        let b = makeItem(parentID: parent.id, title: "B", position: 2.0)
        let c = makeItem(parentID: parent.id, title: "C", position: 3.0)
        let items = [rootBefore, parent, a, b, c]

        let result = try engine.reparent(itemID: b.id, toParent: nil, atSiblingSlot: 1, in: items)

        let moved = result.first { $0.id == b.id }
        XCTAssertNil(moved?.parentID)
        XCTAssertEqual(engine.sortedSiblingGroup(of: b.id, in: result).map(\.id), [rootBefore.id, b.id, parent.id])
    }

    func testReparentSubtreeTravelsIntact() throws {
        let a = makeItem(title: "A", position: 1.0)
        let b = makeItem(title: "B", position: 2.0)
        let b1 = makeItem(parentID: b.id, title: "B1", position: 1.0)
        let b2 = makeItem(parentID: b.id, title: "B2", position: 2.0)
        let b2a = makeItem(parentID: b2.id, title: "B2a", position: 1.0)
        let c = makeItem(title: "C", position: 3.0)
        let items = [a, b, b1, b2, b2a, c]

        let result = try engine.reparent(itemID: b.id, toParent: nil, atSiblingSlot: 2, in: items)

        XCTAssertEqual(result.first { $0.id == b1.id }?.parentID, b.id)
        XCTAssertEqual(result.first { $0.id == b2.id }?.parentID, b.id)
        XCTAssertEqual(result.first { $0.id == b2a.id }?.parentID, b2.id)
        XCTAssertEqual(engine.sortedSiblingGroup(of: b1.id, in: result).map(\.id), [b1.id, b2.id])
        XCTAssertEqual(engine.sortedSiblingGroup(of: a.id, in: result).map(\.id), [a.id, c.id, b.id])
    }

    func testReparentIdentityReturnsUnchanged() throws {
        let a = makeItem(title: "A", position: 1.0)
        let b = makeItem(title: "B", position: 2.0)
        let c = makeItem(title: "C", position: 3.0)
        let items = [a, b, c]

        // B is currently at index 1 among roots; slot 1 (excluding B) is the
        // gap between A and C — exactly where B already sits.
        let result = try engine.reparent(itemID: b.id, toParent: nil, atSiblingSlot: 1, in: items)

        XCTAssertEqual(result, items)
    }

    func testReparentSlotClampsOutOfRange() throws {
        let a = makeItem(title: "A", position: 1.0)
        let b = makeItem(title: "B", position: 2.0)
        let c = makeItem(title: "C", position: 3.0)
        let items = [a, b, c]

        let clampedToFront = try engine.reparent(itemID: c.id, toParent: nil, atSiblingSlot: -5, in: items)
        XCTAssertEqual(engine.sortedSiblingGroup(of: c.id, in: clampedToFront).map(\.id), [c.id, a.id, b.id])

        let clampedToEnd = try engine.reparent(itemID: a.id, toParent: nil, atSiblingSlot: 99, in: items)
        XCTAssertEqual(engine.sortedSiblingGroup(of: a.id, in: clampedToEnd).map(\.id), [b.id, c.id, a.id])
    }

    func testReparentSelfParentingThrows() {
        let a = makeItem(title: "A", position: 1.0)

        XCTAssertThrowsError(try engine.reparent(itemID: a.id, toParent: a.id, atSiblingSlot: 0, in: [a])) { error in
            guard case TreeError.selfParenting = error else {
                XCTFail("Expected selfParenting, got \(error)"); return
            }
        }
    }

    func testReparentOntoOwnDescendantThrows() {
        let parent = makeItem(title: "Parent", position: 1.0)
        let child = makeItem(parentID: parent.id, title: "Child", position: 1.0)
        let grandchild = makeItem(parentID: child.id, title: "Grandchild", position: 1.0)
        let items = [parent, child, grandchild]

        XCTAssertThrowsError(try engine.reparent(itemID: parent.id, toParent: grandchild.id, atSiblingSlot: 0, in: items)) { error in
            guard case TreeError.cycleDetected = error else {
                XCTFail("Expected cycleDetected, got \(error)"); return
            }
        }
    }

    func testReparentCrossListThrows() {
        let otherListID = UUID()
        let item = makeItem(title: "Item", position: 1.0)
        let foreignParent = OutlineItem(id: UUID(), listID: otherListID, title: "Foreign")
        let items = [item, foreignParent]

        XCTAssertThrowsError(try engine.reparent(itemID: item.id, toParent: foreignParent.id, atSiblingSlot: 0, in: items)) { error in
            guard case TreeError.crossListParenting = error else {
                XCTFail("Expected crossListParenting, got \(error)"); return
            }
        }
    }

    func testReparentMissingItemThrows() {
        let a = makeItem(title: "A", position: 1.0)
        let fakeID = UUID()

        XCTAssertThrowsError(try engine.reparent(itemID: fakeID, toParent: a.id, atSiblingSlot: 0, in: [a])) { error in
            guard case TreeError.itemNotFound = error else {
                XCTFail("Expected itemNotFound, got \(error)"); return
            }
        }
    }

    func testReparentMidpointExhaustionNormalizes() throws {
        let oldDate = Date(timeIntervalSince1970: 0)

        // Common case: well-spaced target-group siblings. Only the moved
        // item's updatedAt should change.
        let parent = makeItem(title: "Parent", position: 1.0, updatedAt: oldDate)
        let x = makeItem(parentID: parent.id, title: "X", position: 1.0, updatedAt: oldDate)
        let y = makeItem(parentID: parent.id, title: "Y", position: 2.0, updatedAt: oldDate)
        let mover = makeItem(title: "Mover", position: 2.0, updatedAt: oldDate)
        let items = [parent, x, y, mover]

        let result = try engine.reparent(itemID: mover.id, toParent: parent.id, atSiblingSlot: 1, in: items)
        let resultMap = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })

        XCTAssertNotEqual(resultMap[mover.id]?.updatedAt, oldDate, "Moved item must get a fresh updatedAt")
        XCTAssertEqual(resultMap[x.id]?.updatedAt, oldDate, "Untouched sibling keeps its original updatedAt")
        XCTAssertEqual(resultMap[y.id]?.updatedAt, oldDate, "Untouched sibling keeps its original updatedAt")

        // Exhaustion case (D18, rev 2): siblings within 1e-10 of each other
        // force normalizeSiblingPositions to renumber the WHOLE target
        // group — that is the engine's existing conditional contract, and
        // drag inherits it rather than inventing a second timestamp policy.
        let closeX = makeItem(parentID: parent.id, title: "CloseX", position: 1.0, updatedAt: oldDate)
        let closeY = makeItem(parentID: parent.id, title: "CloseY", position: 1.0 + 5e-11, updatedAt: oldDate)
        let exhaustionItems = [parent, closeX, closeY, mover]

        let exhaustionResult = try engine.reparent(itemID: mover.id, toParent: parent.id, atSiblingSlot: 1, in: exhaustionItems)
        let exhaustionMap = Dictionary(uniqueKeysWithValues: exhaustionResult.map { ($0.id, $0) })

        let finalGroup = engine.sortedSiblingGroup(of: mover.id, in: exhaustionResult)
        XCTAssertEqual(finalGroup.map(\.id), [closeX.id, mover.id, closeY.id], "Canonical pre-normalization order must be preserved")

        XCTAssertNotEqual(exhaustionMap[mover.id]?.updatedAt, oldDate)
        let repositionedOthers = [closeX.id, closeY.id].filter { exhaustionMap[$0]?.updatedAt != oldDate }
        XCTAssertFalse(repositionedOthers.isEmpty, "Midpoint exhaustion must legitimately renumber and re-stamp target-group members")
    }

    // MARK: - moveVisibleRow
    // Fixture: roots A, B(children B1, B2), C — B expanded unless stated.

    private struct SiblingFixture {
        let a: OutlineItem
        let b: OutlineItem
        let b1: OutlineItem
        let b2: OutlineItem
        let c: OutlineItem
        let items: [OutlineItem]
    }

    private func makeSiblingFixture() -> SiblingFixture {
        let a = makeItem(title: "A", position: 1.0)
        let b = makeItem(title: "B", position: 2.0)
        let b1 = makeItem(parentID: b.id, title: "B1", position: 1.0)
        let b2 = makeItem(parentID: b.id, title: "B2", position: 2.0)
        let c = makeItem(title: "C", position: 3.0)
        return SiblingFixture(a: a, b: b, b1: b1, b2: b2, c: c, items: [a, b, b1, b2, c])
    }

    func testMoveDownWithinSiblings() throws {
        let f = makeSiblingFixture()
        let visibleRows = engine.flatten(items: f.items, expandedIDs: [f.b.id])
        // visible: A(0) B(1) B1(2) B2(3) C(4)

        let sourceIndex = try XCTUnwrap(visibleRows.firstIndex { $0.id == f.a.id })
        let result = try XCTUnwrap(engine.moveVisibleRow(at: sourceIndex, toVisibleDestination: 4, visibleRows: visibleRows, in: f.items))

        XCTAssertEqual(engine.sortedSiblingGroup(of: f.a.id, in: result).map(\.id), [f.b.id, f.a.id, f.c.id])
        XCTAssertNil(result.first { $0.id == f.a.id }?.parentID)
        XCTAssertNil(result.first { $0.id == f.b.id }?.parentID)
        XCTAssertNil(result.first { $0.id == f.c.id }?.parentID)
    }

    func testMoveUpWithinSiblings() throws {
        let f = makeSiblingFixture()
        let visibleRows = engine.flatten(items: f.items, expandedIDs: [f.b.id])

        let sourceIndex = try XCTUnwrap(visibleRows.firstIndex { $0.id == f.c.id })
        let result = try XCTUnwrap(engine.moveVisibleRow(at: sourceIndex, toVisibleDestination: 1, visibleRows: visibleRows, in: f.items))

        XCTAssertEqual(engine.sortedSiblingGroup(of: f.c.id, in: result).map(\.id), [f.a.id, f.c.id, f.b.id])
        XCTAssertNil(result.first { $0.id == f.a.id }?.parentID)
        XCTAssertNil(result.first { $0.id == f.b.id }?.parentID)
        XCTAssertNil(result.first { $0.id == f.c.id }?.parentID)
    }

    func testIdentityMoveReturnsNil() throws {
        let f = makeSiblingFixture()
        let visibleRows = engine.flatten(items: f.items, expandedIDs: [f.b.id])

        let sourceIndex = try XCTUnwrap(visibleRows.firstIndex { $0.id == f.b.id })

        XCTAssertNil(engine.moveVisibleRow(at: sourceIndex, toVisibleDestination: sourceIndex, visibleRows: visibleRows, in: f.items), "destination == source must be identity")
        XCTAssertNil(engine.moveVisibleRow(at: sourceIndex, toVisibleDestination: sourceIndex + 1, visibleRows: visibleRows, in: f.items), "destination == source + 1 must be identity")
    }

    func testMoveAcrossCollapsedParentHopsSubtree() throws {
        let f = makeSiblingFixture()
        // B collapsed: its children are not visible at all.
        let visibleRows = engine.flatten(items: f.items, expandedIDs: [])
        XCTAssertEqual(visibleRows.map(\.id), [f.a.id, f.b.id, f.c.id])

        let result = try XCTUnwrap(engine.moveVisibleRow(at: 0, toVisibleDestination: 2, visibleRows: visibleRows, in: f.items))

        XCTAssertEqual(engine.sortedSiblingGroup(of: f.a.id, in: result).map(\.id), [f.b.id, f.a.id, f.c.id])
        // The whole subtree hopped with it.
        XCTAssertEqual(result.first { $0.id == f.b1.id }?.parentID, f.b.id)
        XCTAssertEqual(result.first { $0.id == f.b2.id }?.parentID, f.b.id)
    }

    func testDropInsideOtherParentsChildrenClampsAdjacent() throws {
        let f = makeSiblingFixture()
        let visibleRows = engine.flatten(items: f.items, expandedIDs: [f.b.id])
        // visible: A(0) B(1) B1(2) B2(3) C(4). Drop A between B1 and B2 (destination 3).

        let result = try XCTUnwrap(engine.moveVisibleRow(at: 0, toVisibleDestination: 3, visibleRows: visibleRows, in: f.items))

        XCTAssertNil(result.first { $0.id == f.a.id }?.parentID, "A must remain a root — Stage 1 never reparents")
        XCTAssertEqual(engine.sortedSiblingGroup(of: f.a.id, in: result).map(\.id), [f.b.id, f.a.id, f.c.id])
    }

    func testDraggedExpandedParentIntoOwnSubtreeIsNil() throws {
        let f = makeSiblingFixture()
        let visibleRows = engine.flatten(items: f.items, expandedIDs: [f.b.id])
        // visible: A(0) B(1) B1(2) B2(3) C(4). Drag B (index 1) into the gap
        // between B1 and B2 (destination 3): B's root-sibling order can't
        // change since B1/B2 are excluded from the group.

        let sourceIndex = try XCTUnwrap(visibleRows.firstIndex { $0.id == f.b.id })
        let result = engine.moveVisibleRow(at: sourceIndex, toVisibleDestination: 3, visibleRows: visibleRows, in: f.items)

        XCTAssertNil(result)
    }

    func testMoveToListStartAndEnd() throws {
        let f = makeSiblingFixture()
        let visibleRows = engine.flatten(items: f.items, expandedIDs: [f.b.id])
        // visible: A(0) B(1) B1(2) B2(3) C(4)

        let toStart = try XCTUnwrap(engine.moveVisibleRow(
            at: try XCTUnwrap(visibleRows.firstIndex { $0.id == f.c.id }),
            toVisibleDestination: 0,
            visibleRows: visibleRows,
            in: f.items
        ))
        XCTAssertEqual(engine.sortedSiblingGroup(of: f.c.id, in: toStart).map(\.id), [f.c.id, f.a.id, f.b.id])

        let toEnd = try XCTUnwrap(engine.moveVisibleRow(
            at: try XCTUnwrap(visibleRows.firstIndex { $0.id == f.a.id }),
            toVisibleDestination: visibleRows.count,
            visibleRows: visibleRows,
            in: f.items
        ))
        XCTAssertEqual(engine.sortedSiblingGroup(of: f.a.id, in: toEnd).map(\.id), [f.b.id, f.c.id, f.a.id])
    }

    func testChildDraggedBeyondParentRegionClampsToOwnGroupEnds() throws {
        let f = makeSiblingFixture()
        let visibleRows = engine.flatten(items: f.items, expandedIDs: [f.b.id])
        // visible: A(0) B(1) B1(2) B2(3) C(4)

        let b1Index = try XCTUnwrap(visibleRows.firstIndex { $0.id == f.b1.id })

        // B1 is already first among its siblings, so dragging it past the
        // root boundary above A is a legitimate identity no-op — it cannot
        // leave the B1/B2 group, and it's already at slot 0 within it.
        let aboveResult = engine.moveVisibleRow(at: b1Index, toVisibleDestination: 0, visibleRows: visibleRows, in: f.items)
        XCTAssertNil(aboveResult, "B1 is already first in its own group; crossing the root boundary must not change its slot")

        // Dragging B1 past the root boundary below C clamps to the LAST
        // slot of its own group: B1 becomes last child of B, never a root.
        let belowResult = try XCTUnwrap(engine.moveVisibleRow(at: b1Index, toVisibleDestination: visibleRows.count, visibleRows: visibleRows, in: f.items))
        XCTAssertEqual(belowResult.first { $0.id == f.b1.id }?.parentID, f.b.id, "B1 must never be promoted to root")
        XCTAssertEqual(engine.sortedSiblingGroup(of: f.b1.id, in: belowResult).map(\.id), [f.b2.id, f.b1.id])
    }

    func testInvalidIndicesReturnNil() {
        let f = makeSiblingFixture()
        let visibleRows = engine.flatten(items: f.items, expandedIDs: [f.b.id])

        XCTAssertNil(engine.moveVisibleRow(at: -1, toVisibleDestination: 0, visibleRows: visibleRows, in: f.items))
        XCTAssertNil(engine.moveVisibleRow(at: visibleRows.count, toVisibleDestination: 0, visibleRows: visibleRows, in: f.items))
        XCTAssertNil(engine.moveVisibleRow(at: 0, toVisibleDestination: -1, visibleRows: visibleRows, in: f.items))
        XCTAssertNil(engine.moveVisibleRow(at: 0, toVisibleDestination: visibleRows.count + 1, visibleRows: visibleRows, in: f.items))
    }

    // MARK: - Rev 3 differential oracle: movedSingleElement vs Array.move

    func testMovedSingleElementMatchesArrayMoveForEveryPair() {
        let ids = (0..<8).map { _ in UUID() }

        for s in 0..<8 {
            for d in 0...8 {
                var oracle = ids
                oracle.move(fromOffsets: IndexSet(integer: s), toOffset: d)

                let underTest = TreeEngine.movedSingleElement(ids, from: s, to: d)

                XCTAssertEqual(underTest, oracle, "Mismatch for source \(s), destination \(d)")
            }
        }
    }
}
