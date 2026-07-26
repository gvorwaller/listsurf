import XCTest
@testable import Domain
@testable import Features

/// Tests for the set-based structure ops (M5 gate E2, fix plan item 10):
/// `ListStore.indent/outdent/moveUp/moveDown(itemIDs:undoManager:)`. Covers
/// the four ordering proofs (indent/moveUp top-to-bottom, outdent/moveDown
/// bottom-to-top), the ancestor filter, the all-or-nothing abort contract,
/// the single-undo-step guarantee, and the multi-indent expandedIDs update.
final class ListStoreMultiStructureTests: XCTestCase {
    @MainActor
    private func makeStore(items: [OutlineItem], list: ListItem = ListItem(title: "Test")) -> ListStore {
        let store = ListStore(
            listID: list.id,
            outlineRepo: InMemoryOutlineRepository(items: items),
            listRepo: MultiStructureTestListRepository(list: list)
        )
        store.items = items
        store.expandAll()
        return store
    }

    private func makeUndoManager() -> UndoManager {
        UndoManager()
    }

    // MARK: - Order preservation

    @MainActor
    func testMultiIndentPreservesOrder() {
        let list = ListItem(title: "Test")
        let p = OutlineItem(listID: list.id, title: "P", position: 1)
        let a = OutlineItem(listID: list.id, parentID: p.id, title: "A", position: 1)
        let b = OutlineItem(listID: list.id, parentID: p.id, title: "B", position: 2)
        let c = OutlineItem(listID: list.id, parentID: p.id, title: "C", position: 3)
        let store = makeStore(items: [p, a, b, c], list: list)

        // B and C indent under their preceding sibling (A, then B) — top-to-
        // bottom processing must leave them as A > (B, C) in that order.
        store.indent(itemIDs: [b.id, c.id])

        let childrenOfA = store.engineChildren(of: a.id)
        XCTAssertEqual(childrenOfA.map(\.id), [b.id, c.id], "Indent must preserve B-then-C order under A")
    }

    @MainActor
    func testMultiOutdentPreservesOrderBottomToTop() {
        let list = ListItem(title: "Test")
        let r = OutlineItem(listID: list.id, title: "R", position: 1)
        let x = OutlineItem(listID: list.id, parentID: r.id, title: "X", position: 1)
        let a = OutlineItem(listID: list.id, parentID: x.id, title: "A", position: 1)
        let b = OutlineItem(listID: list.id, parentID: x.id, title: "B", position: 2)
        let c = OutlineItem(listID: list.id, parentID: x.id, title: "C", position: 3)
        let store = makeStore(items: [r, x, a, b, c], list: list)

        store.outdent(itemIDs: [a.id, b.id, c.id])

        let childrenOfR = store.engineChildren(of: r.id)
        let outdentedIDs = childrenOfR.map(\.id).filter { [a.id, b.id, c.id].contains($0) }
        XCTAssertEqual(outdentedIDs, [a.id, b.id, c.id], "A,B,C must stay A,B,C after outdenting all three (bottom-to-top proof)")
    }

    @MainActor
    func testMultiMoveUpPreservesOrder() {
        let list = ListItem(title: "Test")
        let a = OutlineItem(listID: list.id, title: "A", position: 1)
        let b = OutlineItem(listID: list.id, title: "B", position: 2)
        let c = OutlineItem(listID: list.id, title: "C", position: 3)
        let d = OutlineItem(listID: list.id, title: "D", position: 4)
        let store = makeStore(items: [a, b, c, d], list: list)

        store.moveUp(itemIDs: [b.id, c.id])

        let order = store.engineChildren(of: nil).map(\.id)
        XCTAssertEqual(order, [b.id, c.id, a.id, d.id], "The selected block must leapfrog A as a unit, preserving B-before-C")
    }

    @MainActor
    func testMultiMoveDownPreservesOrder() {
        let list = ListItem(title: "Test")
        let a = OutlineItem(listID: list.id, title: "A", position: 1)
        let b = OutlineItem(listID: list.id, title: "B", position: 2)
        let c = OutlineItem(listID: list.id, title: "C", position: 3)
        let d = OutlineItem(listID: list.id, title: "D", position: 4)
        let store = makeStore(items: [a, b, c, d], list: list)

        store.moveDown(itemIDs: [b.id, c.id])

        let order = store.engineChildren(of: nil).map(\.id)
        XCTAssertEqual(order, [a.id, d.id, b.id, c.id], "The selected block must leapfrog D as a unit, preserving B-before-C")
    }

    // MARK: - Deterministic order for hidden (collapsed-away) selections (CODEX2 2026-07-26 finding 4)

    @MainActor
    func testMultiIndentPreservesOrderWhenSelectionIsHiddenByCollapsedAncestor() {
        let list = ListItem(title: "Test")
        let p = OutlineItem(listID: list.id, title: "P", position: 1)
        let a = OutlineItem(listID: list.id, parentID: p.id, title: "A", position: 1)
        let b = OutlineItem(listID: list.id, parentID: p.id, title: "B", position: 2)
        let c = OutlineItem(listID: list.id, parentID: p.id, title: "C", position: 3)
        let store = makeStore(items: [p, a, b, c], list: list)
        // makeStore's expandAll() leaves everything expanded — collapse P
        // specifically via toggleExpanded (which, unlike a direct
        // `expandedIDs` assignment, also calls rebuildRows()) so A, B, C —
        // the indent targets — are genuinely absent from flatRows. Pre-fix,
        // `orderedForStructureOp` fell back to Int.max for every hidden id,
        // so B and C's relative order was decided by Set-iteration order
        // (hash-seed dependent), not document position.
        store.toggleExpanded(p.id)
        XCTAssertTrue(store.flatRows.filter { [a.id, b.id, c.id].contains($0.id) }.isEmpty, "Precondition: A, B, C are hidden from flatRows")

        store.indent(itemIDs: [b.id, c.id])

        let childrenOfA = store.engineChildren(of: a.id)
        XCTAssertEqual(childrenOfA.map(\.id), [b.id, c.id], "Hidden multi-indent must still process top-to-bottom by true document order")
    }

    @MainActor
    func testMultiOutdentPreservesOrderWhenSelectionIsHiddenByCollapsedAncestor() {
        let list = ListItem(title: "Test")
        let r = OutlineItem(listID: list.id, title: "R", position: 1)
        let x = OutlineItem(listID: list.id, parentID: r.id, title: "X", position: 1)
        let a = OutlineItem(listID: list.id, parentID: x.id, title: "A", position: 1)
        let b = OutlineItem(listID: list.id, parentID: x.id, title: "B", position: 2)
        let c = OutlineItem(listID: list.id, parentID: x.id, title: "C", position: 3)
        let store = makeStore(items: [r, x, a, b, c], list: list)
        // Collapse X specifically (R stays expanded): A, B, C (the outdent
        // targets) become genuinely hidden from flatRows, which then only
        // contains R and X. toggleExpanded (unlike a direct `expandedIDs`
        // assignment) also calls rebuildRows().
        store.toggleExpanded(x.id)
        XCTAssertTrue(store.flatRows.filter { [a.id, b.id, c.id].contains($0.id) }.isEmpty, "Precondition: A, B, C are hidden from flatRows")

        store.outdent(itemIDs: [a.id, b.id, c.id])

        let childrenOfR = store.engineChildren(of: r.id)
        let outdentedIDs = childrenOfR.map(\.id).filter { [a.id, b.id, c.id].contains($0) }
        XCTAssertEqual(outdentedIDs, [a.id, b.id, c.id], "Hidden multi-outdent must still process bottom-to-top by true document order")
    }

    // MARK: - Abort cases

    @MainActor
    func testMultiIndentAbortsWhenSetIncludesFirstSibling() {
        let list = ListItem(title: "Test")
        let a = OutlineItem(listID: list.id, title: "A", position: 1)
        let b = OutlineItem(listID: list.id, title: "B", position: 2)
        let c = OutlineItem(listID: list.id, title: "C", position: 3)
        let store = makeStore(items: [a, b, c], list: list)
        let itemsBefore = store.items
        let undoManager = makeUndoManager()

        // A has no previous sibling — a boundary no-op for A must abort the
        // WHOLE batch, so B must not indent either.
        store.indent(itemIDs: [a.id, b.id], undoManager: undoManager)

        XCTAssertEqual(store.items, itemsBefore, "All-or-nothing: no member may apply if any member is a boundary no-op")
        XCTAssertFalse(undoManager.canUndo, "An aborted batch must register no undo entry")
    }

    @MainActor
    func testMultiOutdentAbortsWhenSetIncludesARoot() {
        let list = ListItem(title: "Test")
        let p = OutlineItem(listID: list.id, title: "P", position: 1)
        let a = OutlineItem(listID: list.id, parentID: p.id, title: "A", position: 1)
        let root = OutlineItem(listID: list.id, title: "Root", position: 2)
        let store = makeStore(items: [p, a, root], list: list)
        let itemsBefore = store.items
        let undoManager = makeUndoManager()

        store.outdent(itemIDs: [a.id, root.id], undoManager: undoManager)

        XCTAssertEqual(store.items, itemsBefore, "A root item has nowhere to outdent to — the whole batch must abort")
        XCTAssertFalse(undoManager.canUndo)
    }

    @MainActor
    func testMultiMoveUpAbortsWhenSetIncludesFirstSibling() {
        let list = ListItem(title: "Test")
        let a = OutlineItem(listID: list.id, title: "A", position: 1)
        let b = OutlineItem(listID: list.id, title: "B", position: 2)
        let store = makeStore(items: [a, b], list: list)
        let itemsBefore = store.items
        let undoManager = makeUndoManager()

        store.moveUp(itemIDs: [a.id, b.id], undoManager: undoManager)

        XCTAssertEqual(store.items, itemsBefore, "A is already first — the whole batch must abort")
        XCTAssertFalse(undoManager.canUndo)
    }

    // MARK: - Ancestor filter

    @MainActor
    func testAncestorFilterDropsChildWhenParentAlsoSelected() {
        let list = ListItem(title: "Test")
        let p = OutlineItem(listID: list.id, title: "P", position: 1)
        let sibling = OutlineItem(listID: list.id, title: "Sibling", position: 2)
        let child = OutlineItem(listID: list.id, parentID: p.id, title: "Child", position: 1)
        let store = makeStore(items: [p, sibling, child], list: list)

        // Selecting both P and its child: P indents under Sibling — wait,
        // P has no previous sibling, so use outdent's simpler shape:
        // select P (a root, boundary no-op) plus its child would abort. Use
        // moveDown instead, which only P can meaningfully do here: P moves
        // below Sibling, taking Child along as part of its subtree. The
        // child must not ALSO be moved independently (double-application).
        store.moveDown(itemIDs: [p.id, child.id])

        let order = store.engineChildren(of: nil).map(\.id)
        XCTAssertEqual(order, [sibling.id, p.id], "Only P (the ancestor) should have been processed")
        XCTAssertEqual(store.items.first(where: { $0.id == child.id })?.parentID, p.id, "Child must still be P's child, untouched by its own move")
    }

    // MARK: - Undo / selection / expandedIDs

    @MainActor
    func testMultiIndentIsOneUndoStepAndRestoresSelection() {
        let list = ListItem(title: "Test")
        let a = OutlineItem(listID: list.id, title: "A", position: 1)
        let b = OutlineItem(listID: list.id, title: "B", position: 2)
        let c = OutlineItem(listID: list.id, title: "C", position: 3)
        let store = makeStore(items: [a, b, c], list: list)
        let undoManager = makeUndoManager()
        store.selectedItemIDs = [b.id, c.id]
        let itemsBefore = store.items

        store.indent(itemIDs: [b.id, c.id], undoManager: undoManager)
        XCTAssertNotEqual(store.items, itemsBefore, "Precondition: the batch actually applied")

        undoManager.undo()

        XCTAssertEqual(store.items, itemsBefore, "One undo step must restore the whole batch")
        XCTAssertEqual(store.selectedItemIDs, [b.id, c.id], "One undo step must also restore the pre-batch selection")
    }

    @MainActor
    func testMultiIndentAddsAllNewParentsToExpandedIDs() {
        let list = ListItem(title: "Test")
        let a = OutlineItem(listID: list.id, title: "A", position: 1)
        let b = OutlineItem(listID: list.id, title: "B", position: 2)
        let c = OutlineItem(listID: list.id, title: "C", position: 3)
        let d = OutlineItem(listID: list.id, title: "D", position: 4)
        let store = makeStore(items: [a, b, c, d], list: list)
        store.expandedIDs = []

        // B indents under A, D indents under C — two distinct new parents.
        store.indent(itemIDs: [b.id, d.id])

        XCTAssertTrue(store.expandedIDs.contains(a.id), "A must be expanded to reveal newly-nested B")
        XCTAssertTrue(store.expandedIDs.contains(c.id), "C must be expanded to reveal newly-nested D")
    }
}

private extension ListStore {
    /// Test-only convenience: children of `parentID` (nil = roots) sorted by
    /// the store's own tree order, for asserting on structural order without
    /// reaching into private TreeEngine internals.
    func engineChildren(of parentID: UUID?) -> [OutlineItem] {
        items
            .filter { $0.parentID == parentID }
            .sorted { a, b in
                if a.position != b.position { return a.position < b.position }
                return a.id.uuidString < b.id.uuidString
            }
    }
}

private actor InMemoryOutlineRepository: OutlineRepository {
    private var items: [OutlineItem]

    init(items: [OutlineItem]) {
        self.items = items
    }

    func fetchItems(forList listID: UUID) async throws -> [OutlineItem] {
        items.filter { $0.listID == listID }
    }

    func applyChanges(saving newItems: [OutlineItem], deletingIDs: [UUID]) async throws {
        let savedIDs = Set(newItems.map(\.id))
        items.removeAll { savedIDs.contains($0.id) }
        items.append(contentsOf: newItems)
        let deleted = Set(deletingIDs)
        items.removeAll { deleted.contains($0.id) }
    }
}

private actor MultiStructureTestListRepository: ListRepository {
    private var list: ListItem

    init(list: ListItem) {
        self.list = list
    }

    func fetchAll() async throws -> [ListItem] { [list] }
    func fetchActive() async throws -> [ListItem] { [list] }
    func fetchArchived() async throws -> [ListItem] { [] }
    func fetch(id: UUID) async throws -> ListItem? { id == list.id ? list : nil }
    func save(_ list: ListItem) async throws { self.list = list }
    func saveListAndItems(_ list: ListItem, items: [OutlineItem]) async throws {
        self.list = list
    }
    func replaceAllListsAndItems(with archive: LibraryArchive) async throws {
        if let first = archive.lists.first?.list {
            list = first
        }
    }
    func addListsAndItems(with archive: LibraryArchive) async throws {}
    func fetchLibraryArchive() async throws -> LibraryArchive {
        LibraryArchive(lists: [ArchivedList(list: list, items: [])])
    }
    func deleteListAndItems(id: UUID) async throws {}
}
