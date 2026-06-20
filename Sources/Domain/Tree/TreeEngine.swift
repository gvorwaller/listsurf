import Foundation

public struct FlatRow: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let item: OutlineItem
    public let depth: Int
    public let hasChildren: Bool
    public let checkState: CheckState
    public let leafProgress: (checked: Int, total: Int)

    public init(item: OutlineItem, depth: Int, hasChildren: Bool, checkState: CheckState, leafProgress: (checked: Int, total: Int)) {
        self.id = item.id
        self.item = item
        self.depth = depth
        self.hasChildren = hasChildren
        self.checkState = checkState
        self.leafProgress = leafProgress
    }

    public static func == (lhs: FlatRow, rhs: FlatRow) -> Bool {
        lhs.id == rhs.id
            && lhs.item == rhs.item
            && lhs.depth == rhs.depth
            && lhs.hasChildren == rhs.hasChildren
            && lhs.checkState == rhs.checkState
            && lhs.leafProgress.checked == rhs.leafProgress.checked
            && lhs.leafProgress.total == rhs.leafProgress.total
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
                result.append(FlatRow(
                    item: child,
                    depth: depth,
                    hasChildren: hasChildren,
                    checkState: checkState,
                    leafProgress: progress
                ))
                if hasChildren && expandedIDs.contains(child.id) {
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
        guard let children = childrenIndex[itemID], !children.isEmpty else {
            return itemMap[itemID]?.isChecked == true ? .checked : .unchecked
        }

        let states = children.map { computeCheckState(for: $0.id, childrenIndex: childrenIndex, itemMap: itemMap) }
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
        guard let children = childrenIndex[itemID], !children.isEmpty else {
            let checked = itemMap[itemID]?.isChecked == true ? 1 : 0
            return (checked, 1)
        }
        var totalChecked = 0
        var totalCount = 0
        for child in children {
            let sub = computeLeafProgress(for: child.id, childrenIndex: childrenIndex, itemMap: itemMap)
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
        func collect(_ parentID: UUID) {
            for child in childrenIndex[parentID] ?? [] {
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
        while let pid = current {
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
