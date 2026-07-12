import Foundation

extension TreeEngine {

    /// Moves `itemID` under `newParentID` at `slot` within the target sibling
    /// group (slot counted with the moved item excluded; clamped to
    /// 0...group.count). Throws `TreeError` for self/cycle/cross-list/missing
    /// targets via `validateReparent`. Returns `items` unchanged (same array
    /// value) when the move is an identity — same parent, same resulting
    /// sibling order — so callers can no-op-guard exactly like indent does.
    public func reparent(
        itemID: UUID,
        toParent newParentID: UUID?,
        atSiblingSlot slot: Int,
        in items: [OutlineItem]
    ) throws -> [OutlineItem] {
        try validateReparent(itemID: itemID, newParentID: newParentID, items: items)

        let itemMap = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        guard let item = itemMap[itemID] else {
            // validateReparent already guarantees this, but the compiler
            // can't see that — surface the same error rather than force-unwrap.
            throw TreeError.itemNotFound(itemID)
        }

        // Target group: canonical sort (position asc, uuidString tie-break —
        // must match TreeEngine.flatten's comparator), item excluded.
        let group = items
            .filter { $0.parentID == newParentID && $0.id != itemID }
            .sorted { a, b in
                if a.position != b.position { return a.position < b.position }
                return a.id.uuidString < b.id.uuidString
            }

        let clampedSlot = max(0, min(slot, group.count))

        // Identity check: same parent, and the item's current index within
        // its FULL current sibling group (item included) equals the index
        // it would land at.
        if item.parentID == newParentID {
            let fullGroup = sortedSiblingGroup(of: itemID, in: items)
            if let currentIndex = fullGroup.firstIndex(where: { $0.id == itemID }),
               currentIndex == clampedSlot {
                return items
            }
        }

        let newPosition: Double
        if group.isEmpty {
            newPosition = 1.0
        } else if clampedSlot == 0 {
            newPosition = group[0].position - 1.0
        } else if clampedSlot == group.count {
            newPosition = group[group.count - 1].position + 1.0
        } else {
            newPosition = midpoint(group[clampedSlot - 1].position, group[clampedSlot].position)
        }

        let now = Date()
        let updated = items.map { i -> OutlineItem in
            guard i.id == itemID else { return i }
            var u = i
            u.parentID = newParentID
            u.position = newPosition
            u.updatedAt = now
            return u
        }

        // Removal never breaks the OLD parent group's invariants, so only
        // the target group needs normalization.
        return normalizeSiblingPositions(in: updated, parentID: newParentID)
    }

    /// Maps a flat-list `.onMove` (source row index, destination gap index in
    /// `visibleRows`) to a same-parent sibling reorder per D2. Returns nil
    /// for: invalid indices, identity moves, or anything else that should be
    /// a silent no-op. Never changes parentID.
    public func moveVisibleRow(
        at sourceIndex: Int,
        toVisibleDestination destination: Int,
        visibleRows: [FlatRow],
        in items: [OutlineItem]
    ) -> [OutlineItem]? {
        guard visibleRows.indices.contains(sourceIndex),
              (0...visibleRows.count).contains(destination) else {
            return nil
        }

        let moved = visibleRows[sourceIndex]
        let parentID = moved.item.parentID

        // Rev 3: `Array.move(fromOffsets:toOffset:)` is SwiftUI-only and
        // Domain imports Foundation only, so the single-element case of its
        // destination semantics is reimplemented here. The off-by-one risk
        // this used to guard against by reusing Apple's implementation is
        // retired instead by a differential oracle test in the test target
        // (which may import SwiftUI) — see TreeEngineReorderTests.
        let ids = TreeEngine.movedSingleElement(visibleRows.map(\.id), from: sourceIndex, to: destination)

        // Search is disabled during drag (D5) and the moved item is visible,
        // so its parent is expanded — every sibling is visible, meaning
        // `desiredOrder` is the complete group. (Roots are always all visible.)
        let groupIDs = Set(sortedSiblingGroup(of: moved.id, in: items).map(\.id))
        let desiredOrder = ids.filter { groupIDs.contains($0) }

        guard let newSlot = desiredOrder.firstIndex(of: moved.id) else { return nil }

        let currentGroup = sortedSiblingGroup(of: moved.id, in: items)
        guard let currentIndex = currentGroup.firstIndex(where: { $0.id == moved.id }) else { return nil }

        // Slot conventions differ: reparent counts slots with the item
        // excluded. Since only one item moved, the members of desiredOrder
        // preceding it are all non-self, so newSlot IS the excluded-self
        // slot already — no further conversion needed.
        if newSlot == currentIndex {
            return nil
        }

        // A same-parent reparent can only throw itemNotFound, which the
        // guards above already preclude — try? documents the impossibility
        // without crashing.
        return try? reparent(itemID: moved.id, toParent: parentID, atSiblingSlot: newSlot, in: items)
    }

    /// The single-element case of `Array.move(fromOffsets:toOffset:)`'s
    /// destination semantics (Rev 3), reimplemented here because that API is
    /// SwiftUI-only and Domain imports Foundation only. `destination` is
    /// expressed against the ORIGINAL array (pre-removal), matching
    /// `.onMove`'s contract: removing the element shifts every later index
    /// down by one, so a destination past the removed slot must be
    /// decremented before inserting.
    static func movedSingleElement(_ ids: [UUID], from sourceIndex: Int, to destination: Int) -> [UUID] {
        var result = ids
        let element = result.remove(at: sourceIndex)
        let insertIndex = destination > sourceIndex ? destination - 1 : destination
        result.insert(element, at: insertIndex)
        return result
    }
}
