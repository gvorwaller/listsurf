import Foundation

public struct FlatRow: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let item: OutlineItem
    public let depth: Int
    public let hasChildren: Bool
    public let checkState: CheckState
    public let leafProgress: (checked: Int, total: Int)
    public let isExpanded: Bool

    public init(
        item: OutlineItem,
        depth: Int,
        hasChildren: Bool,
        checkState: CheckState,
        leafProgress: (checked: Int, total: Int),
        isExpanded: Bool
    ) {
        self.id = item.id
        self.item = item
        self.depth = depth
        self.hasChildren = hasChildren
        self.checkState = checkState
        self.leafProgress = leafProgress
        self.isExpanded = isExpanded
    }

    public static func == (lhs: FlatRow, rhs: FlatRow) -> Bool {
        lhs.id == rhs.id
            && lhs.item == rhs.item
            && lhs.depth == rhs.depth
            && lhs.hasChildren == rhs.hasChildren
            && lhs.checkState == rhs.checkState
            && lhs.leafProgress.checked == rhs.leafProgress.checked
            && lhs.leafProgress.total == rhs.leafProgress.total
            && lhs.isExpanded == rhs.isExpanded
    }
}

public enum TreeError: Error, Equatable, Sendable {
    case itemNotFound(UUID)
    case cycleDetected(parent: UUID, child: UUID)
    case crossListParenting(parentList: UUID, childList: UUID)
    case selfParenting(UUID)
}

public struct TreeEngine: Sendable {

    public init() {}

    // MARK: - Index building

    private func buildChildrenIndex(_ items: [OutlineItem]) -> [UUID?: [OutlineItem]] {
        Dictionary(grouping: items) { $0.parentID }
    }

    // MARK: - Flatten

    public func flatten(
        items: [OutlineItem],
        expandedIDs: Set<UUID>
    ) -> [FlatRow] {
        let childrenIndex = buildChildrenIndex(items)
        let itemMap = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var result: [FlatRow] = []

        func walk(parentID: UUID?, depth: Int) {
            let children = (childrenIndex[parentID] ?? [])
                .sorted { a, b in
                    if a.position != b.position { return a.position < b.position }
                    return a.id.uuidString < b.id.uuidString
                }
            for child in children {
                let hasChildren = childrenIndex[child.id] != nil
                let checkState = computeCheckState(for: child.id, childrenIndex: childrenIndex, itemMap: itemMap)
                let progress = computeLeafProgress(for: child.id, childrenIndex: childrenIndex, itemMap: itemMap)
                let isExpanded = hasChildren && expandedIDs.contains(child.id)
                result.append(FlatRow(
                    item: child,
                    depth: depth,
                    hasChildren: hasChildren,
                    checkState: checkState,
                    leafProgress: progress,
                    isExpanded: isExpanded
                ))
                if isExpanded {
                    walk(parentID: child.id, depth: depth + 1)
                }
            }
        }

        walk(parentID: nil, depth: 0)
        return result
    }

    // MARK: - Check state

    public func computeCheckState(
        for itemID: UUID,
        childrenIndex: [UUID?: [OutlineItem]],
        itemMap: [UUID: OutlineItem]
    ) -> CheckState {
        computeCheckState(
            for: itemID,
            childrenIndex: childrenIndex,
            itemMap: itemMap,
            visited: []
        )
    }

    private func computeCheckState(
        for itemID: UUID,
        childrenIndex: [UUID?: [OutlineItem]],
        itemMap: [UUID: OutlineItem],
        visited: Set<UUID>
    ) -> CheckState {
        guard !visited.contains(itemID) else {
            return itemMap[itemID]?.isChecked == true ? .checked : .unchecked
        }
        let visited = visited.union([itemID])
        guard let children = childrenIndex[itemID], !children.isEmpty else {
            return itemMap[itemID]?.isChecked == true ? .checked : .unchecked
        }

        let states = children.map {
            computeCheckState(for: $0.id, childrenIndex: childrenIndex, itemMap: itemMap, visited: visited)
        }
        if states.allSatisfy({ $0 == .checked }) { return .checked }
        if states.allSatisfy({ $0 == .unchecked }) { return .unchecked }
        return .mixed
    }

    // MARK: - Progress (leaves only)

    public func computeLeafProgress(
        for itemID: UUID,
        childrenIndex: [UUID?: [OutlineItem]],
        itemMap: [UUID: OutlineItem]
    ) -> (checked: Int, total: Int) {
        computeLeafProgress(
            for: itemID,
            childrenIndex: childrenIndex,
            itemMap: itemMap,
            visited: []
        )
    }

    private func computeLeafProgress(
        for itemID: UUID,
        childrenIndex: [UUID?: [OutlineItem]],
        itemMap: [UUID: OutlineItem],
        visited: Set<UUID>
    ) -> (checked: Int, total: Int) {
        guard !visited.contains(itemID) else {
            let checked = itemMap[itemID]?.isChecked == true ? 1 : 0
            return (checked, 1)
        }
        let visited = visited.union([itemID])
        guard let children = childrenIndex[itemID], !children.isEmpty else {
            let checked = itemMap[itemID]?.isChecked == true ? 1 : 0
            return (checked, 1)
        }
        var totalChecked = 0
        var totalCount = 0
        for child in children {
            let sub = computeLeafProgress(
                for: child.id,
                childrenIndex: childrenIndex,
                itemMap: itemMap,
                visited: visited
            )
            totalChecked += sub.checked
            totalCount += sub.total
        }
        return (totalChecked, totalCount)
    }

    public func listProgress(items: [OutlineItem]) -> (checked: Int, total: Int) {
        let childrenIndex = buildChildrenIndex(items)
        let itemMap = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let roots = items.filter { $0.parentID == nil }

        var totalChecked = 0
        var totalCount = 0
        for root in roots {
            let sub = computeLeafProgress(for: root.id, childrenIndex: childrenIndex, itemMap: itemMap)
            totalChecked += sub.checked
            totalCount += sub.total
        }
        return (totalChecked, totalCount)
    }

    // MARK: - Descendants

    public func descendants(of itemID: UUID, in items: [OutlineItem]) -> [OutlineItem] {
        let childrenIndex = buildChildrenIndex(items)
        var result: [OutlineItem] = []
        var visited: Set<UUID> = [itemID]
        func collect(_ parentID: UUID) {
            for child in childrenIndex[parentID] ?? [] {
                guard !visited.contains(child.id) else { continue }
                visited.insert(child.id)
                result.append(child)
                collect(child.id)
            }
        }
        collect(itemID)
        return result
    }

    public func ancestorIDs(of itemID: UUID, in items: [OutlineItem]) -> [UUID] {
        let itemMap = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var result: [UUID] = []
        var current = itemMap[itemID]?.parentID
        var visited: Set<UUID> = [itemID]
        while let pid = current {
            guard !visited.contains(pid) else { break }
            visited.insert(pid)
            result.append(pid)
            current = itemMap[pid]?.parentID
        }
        return result
    }

    // MARK: - Validation

    public func validateReparent(
        itemID: UUID,
        newParentID: UUID?,
        items: [OutlineItem]
    ) throws {
        let itemMap = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

        guard let item = itemMap[itemID] else {
            throw TreeError.itemNotFound(itemID)
        }

        guard let newParentID else { return }

        if itemID == newParentID {
            throw TreeError.selfParenting(itemID)
        }

        guard let parent = itemMap[newParentID] else {
            throw TreeError.itemNotFound(newParentID)
        }

        if item.listID != parent.listID {
            throw TreeError.crossListParenting(parentList: parent.listID, childList: item.listID)
        }

        let descendantIDs = Set(descendants(of: itemID, in: items).map(\.id))
        if descendantIDs.contains(newParentID) {
            throw TreeError.cycleDetected(parent: newParentID, child: itemID)
        }
    }

    // MARK: - Position helpers

    public func nextPosition(among siblings: [OutlineItem]) -> Double {
        let maxPos = siblings.map(\.position).max() ?? 0.0
        return maxPos + 1.0
    }

    public func midpoint(_ a: Double, _ b: Double) -> Double {
        (a + b) / 2.0
    }

    public func needsRebalance(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) < 1e-10
    }

    public func rebalancedPositions(for siblings: [OutlineItem]) -> [UUID: Double] {
        let sorted = siblings.sorted { a, b in
            if a.position != b.position { return a.position < b.position }
            return a.id.uuidString < b.id.uuidString
        }
        var result: [UUID: Double] = [:]
        for (index, item) in sorted.enumerated() {
            result[item.id] = Double(index + 1)
        }
        return result
    }

    public func normalizeSiblingPositions(in items: [OutlineItem], parentID: UUID?) -> [OutlineItem] {
        let siblings = items
            .filter { $0.parentID == parentID }
            .sorted { a, b in
                if a.position != b.position { return a.position < b.position }
                return a.id.uuidString < b.id.uuidString
            }

        guard siblingPositionsNeedNormalization(siblings) else {
            return items
        }

        let positions = rebalancedPositions(for: siblings)
        let now = Date()
        return items.map { item in
            guard let position = positions[item.id], item.position != position else {
                return item
            }
            var updated = item
            updated.position = position
            updated.updatedAt = now
            return updated
        }
    }

    private func siblingPositionsNeedNormalization(_ siblings: [OutlineItem]) -> Bool {
        guard siblings.count > 1 else { return false }

        let sorted = siblings.sorted { a, b in
            if a.position != b.position { return a.position < b.position }
            return a.id.uuidString < b.id.uuidString
        }

        for index in sorted.indices.dropFirst() {
            let previous = sorted[sorted.index(before: index)]
            let current = sorted[index]
            if previous.position == current.position || needsRebalance(previous.position, current.position) {
                return true
            }
        }

        return false
    }

    // MARK: - Duplicate

    public func duplicateList(
        _ list: ListItem,
        items: [OutlineItem],
        clearChecks: Bool
    ) -> (list: ListItem, items: [OutlineItem]) {
        let now = Date()
        let newListID = UUID()
        let newList = ListItem(
            id: newListID,
            title: list.title,
            notes: list.notes,
            icon: list.icon,
            colorName: list.colorName,
            position: list.position,
            createdAt: now,
            updatedAt: now
        )

        var idMap: [UUID: UUID] = [:]
        for item in items {
            idMap[item.id] = UUID()
        }

        let newItems = items.map { item in
            OutlineItem(
                id: idMap[item.id]!,
                listID: newListID,
                parentID: item.parentID.flatMap { idMap[$0] },
                title: item.title,
                notes: item.notes,
                quantity: item.quantity,
                isChecked: clearChecks ? false : item.isChecked,
                position: item.position,
                createdAt: now,
                updatedAt: now
            )
        }

        return (newList, newItems)
    }

    // MARK: - Siblings helper

    public func siblings(of itemID: UUID, in items: [OutlineItem]) -> [OutlineItem] {
        let itemMap = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        guard let item = itemMap[itemID] else { return [] }
        return items
            .filter { $0.parentID == item.parentID && $0.id != itemID }
            .sorted { a, b in
                if a.position != b.position { return a.position < b.position }
                return a.id.uuidString < b.id.uuidString
            }
    }

    public func sortedSiblingGroup(of itemID: UUID, in items: [OutlineItem]) -> [OutlineItem] {
        let itemMap = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        guard let item = itemMap[itemID] else { return [] }
        return items
            .filter { $0.parentID == item.parentID }
            .sorted { a, b in
                if a.position != b.position { return a.position < b.position }
                return a.id.uuidString < b.id.uuidString
            }
    }

    // MARK: - Move among siblings

    public func moveUp(itemID: UUID, in items: [OutlineItem]) -> [OutlineItem]? {
        let group = sortedSiblingGroup(of: itemID, in: items)
        guard let idx = group.firstIndex(where: { $0.id == itemID }), idx > 0 else { return nil }

        let above = group[idx - 1]
        let now = Date()

        let moved = items.map { i in
            if i.id == itemID {
                var u = i; u.position = above.position - 0.5; u.updatedAt = now; return u
            }
            return i
        }
        return normalizeSiblingPositions(in: moved, parentID: above.parentID)
    }

    public func moveDown(itemID: UUID, in items: [OutlineItem]) -> [OutlineItem]? {
        let group = sortedSiblingGroup(of: itemID, in: items)
        guard let idx = group.firstIndex(where: { $0.id == itemID }), idx < group.count - 1 else { return nil }

        let below = group[idx + 1]
        let now = Date()

        let moved = items.map { i in
            if i.id == itemID {
                var u = i; u.position = below.position + 0.5; u.updatedAt = now; return u
            }
            return i
        }
        return normalizeSiblingPositions(in: moved, parentID: below.parentID)
    }

    // MARK: - Indent / Outdent

    public func indent(itemID: UUID, in items: [OutlineItem]) throws -> [OutlineItem] {
        let group = sortedSiblingGroup(of: itemID, in: items)
        guard let idx = group.firstIndex(where: { $0.id == itemID }), idx > 0 else {
            throw TreeError.itemNotFound(itemID)
        }

        let newParent = group[idx - 1]
        try validateReparent(itemID: itemID, newParentID: newParent.id, items: items)

        let childrenOfNewParent = items.filter { $0.parentID == newParent.id }
        let newPosition = nextPosition(among: childrenOfNewParent)
        let now = Date()

        let indented = items.map { i in
            if i.id == itemID {
                var u = i; u.parentID = newParent.id; u.position = newPosition; u.updatedAt = now; return u
            }
            return i
        }
        return normalizeSiblingPositions(in: indented, parentID: newParent.id)
    }

    public func outdent(itemID: UUID, in items: [OutlineItem]) throws -> [OutlineItem] {
        let itemMap = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        guard let item = itemMap[itemID] else {
            throw TreeError.itemNotFound(itemID)
        }
        guard let currentParentID = item.parentID else {
            throw TreeError.itemNotFound(itemID)
        }
        guard let currentParent = itemMap[currentParentID] else {
            throw TreeError.itemNotFound(currentParentID)
        }

        let newParentID = currentParent.parentID
        if let newParentID {
            try validateReparent(itemID: itemID, newParentID: newParentID, items: items)
        }

        let newSiblings = items.filter { $0.parentID == newParentID }
        let parentPosition = currentParent.position
        let siblingsAfterParent = newSiblings.filter { $0.position > parentPosition }
        let insertPosition: Double
        if let nextSibling = siblingsAfterParent.min(by: { $0.position < $1.position }) {
            insertPosition = midpoint(parentPosition, nextSibling.position)
        } else {
            insertPosition = parentPosition + 1.0
        }

        let now = Date()
        let outdented = items.map { i in
            if i.id == itemID {
                var u = i; u.parentID = newParentID; u.position = insertPosition; u.updatedAt = now; return u
            }
            return i
        }
        return normalizeSiblingPositions(in: outdented, parentID: newParentID)
    }

    // MARK: - Insert

    public func insertAbove(
        referenceID: UUID,
        newItem: OutlineItem,
        in items: [OutlineItem]
    ) -> [OutlineItem] {
        let itemMap = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        guard let reference = itemMap[referenceID] else { return items + [newItem] }

        let group = sortedSiblingGroup(of: referenceID, in: items)
        guard let idx = group.firstIndex(where: { $0.id == referenceID }) else { return items + [newItem] }

        let insertPosition: Double
        if idx == 0 {
            insertPosition = reference.position - 1.0
        } else {
            insertPosition = midpoint(group[idx - 1].position, reference.position)
        }

        var positioned = newItem
        positioned.parentID = reference.parentID
        positioned.position = insertPosition
        positioned.listID = reference.listID
        return normalizeSiblingPositions(in: items + [positioned], parentID: reference.parentID)
    }

    public func insertBelow(
        referenceID: UUID,
        newItem: OutlineItem,
        in items: [OutlineItem]
    ) -> [OutlineItem] {
        let itemMap = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        guard let reference = itemMap[referenceID] else { return items + [newItem] }

        let group = sortedSiblingGroup(of: referenceID, in: items)
        guard let idx = group.firstIndex(where: { $0.id == referenceID }) else { return items + [newItem] }

        let insertPosition: Double
        if idx == group.count - 1 {
            insertPosition = reference.position + 1.0
        } else {
            insertPosition = midpoint(reference.position, group[idx + 1].position)
        }

        var positioned = newItem
        positioned.parentID = reference.parentID
        positioned.position = insertPosition
        positioned.listID = reference.listID
        return normalizeSiblingPositions(in: items + [positioned], parentID: reference.parentID)
    }

    public func insertChild(
        parentID: UUID,
        newItem: OutlineItem,
        in items: [OutlineItem]
    ) -> [OutlineItem] {
        let children = items.filter { $0.parentID == parentID }
        let position = nextPosition(among: children)

        let itemMap = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let listID = itemMap[parentID]?.listID ?? newItem.listID

        var positioned = newItem
        positioned.parentID = parentID
        positioned.position = position
        positioned.listID = listID
        return normalizeSiblingPositions(in: items + [positioned], parentID: parentID)
    }

    // MARK: - Delete subtree

    public func deleteSubtree(itemID: UUID, in items: [OutlineItem]) -> (remaining: [OutlineItem], deleted: [OutlineItem]) {
        let descIDs = Set(descendants(of: itemID, in: items).map(\.id))
        let allDeletedIDs = descIDs.union([itemID])
        let remaining = items.filter { !allDeletedIDs.contains($0.id) }
        let deleted = items.filter { allDeletedIDs.contains($0.id) }
        return (remaining, deleted)
    }

    // MARK: - Subtree reset

    public func resetChecks(subtreeOf itemID: UUID, in items: [OutlineItem]) -> [OutlineItem] {
        let descIDs = Set(descendants(of: itemID, in: items).map(\.id))
        let affectedIDs = descIDs.union([itemID])
        let now = Date()
        return items.map { item in
            guard affectedIDs.contains(item.id), item.isChecked else { return item }
            var updated = item
            updated.isChecked = false
            updated.updatedAt = now
            return updated
        }
    }

    // MARK: - Orphan repair

    public func repairOrphans(in items: [OutlineItem]) -> (repaired: [OutlineItem], orphanCount: Int) {
        let result = repairInvalidParents(in: items)
        return (result.repaired, result.orphanCount)
    }

    public func repairInvalidParents(
        in items: [OutlineItem]
    ) -> (repaired: [OutlineItem], orphanCount: Int, cycleCount: Int) {
        let itemIDs = Set(items.map(\.id))
        let itemMap = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var orphanCount = 0
        var cycleCount = 0
        let now = Date()

        let repaired = items.map { item in
            guard let parentID = item.parentID else { return item }

            if !itemIDs.contains(parentID) {
                orphanCount += 1
                var fixed = item
                fixed.parentID = nil
                fixed.updatedAt = now
                return fixed
            }

            if parentID == item.id || hasAncestorCycle(startingAt: item.id, itemMap: itemMap) {
                cycleCount += 1
                var fixed = item
                fixed.parentID = nil
                fixed.updatedAt = now
                return fixed
            }

            return item
        }

        return (repaired, orphanCount, cycleCount)
    }

    private func hasAncestorCycle(startingAt itemID: UUID, itemMap: [UUID: OutlineItem]) -> Bool {
        var visited: Set<UUID> = [itemID]
        var current = itemMap[itemID]?.parentID

        while let parentID = current {
            guard let parent = itemMap[parentID] else { return false }
            if visited.contains(parentID) {
                return true
            }
            visited.insert(parentID)
            current = parent.parentID
        }

        return false
    }
}

extension TreeEngine {

    // MARK: - Check operations

    public func setChecked(
        _ checked: Bool,
        itemID: UUID,
        in items: [OutlineItem]
    ) -> [OutlineItem] {
        let descIDs = Set(descendants(of: itemID, in: items).map(\.id))
        let affectedIDs = descIDs.union([itemID])
        return items.map { item in
            guard affectedIDs.contains(item.id) else { return item }
            var updated = item
            updated.isChecked = checked
            updated.updatedAt = Date()
            return updated
        }
    }

    public func resetChecks(in items: [OutlineItem]) -> [OutlineItem] {
        items.map { item in
            guard item.isChecked else { return item }
            var updated = item
            updated.isChecked = false
            updated.updatedAt = Date()
            return updated
        }
    }
}
