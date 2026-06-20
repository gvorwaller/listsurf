import Foundation

public enum TreeCommand: Sendable {
    case moveUp(itemID: UUID)
    case moveDown(itemID: UUID)
    case indent(itemID: UUID)
    case outdent(itemID: UUID)
    case insertAbove(referenceID: UUID, newItem: OutlineItem)
    case insertBelow(referenceID: UUID, newItem: OutlineItem)
    case insertChild(parentID: UUID, newItem: OutlineItem)
    case deleteSubtree(itemID: UUID)
    case setChecked(checked: Bool, itemID: UUID)
    case resetChecks
    case resetSubtree(itemID: UUID)
    case updateItem(OutlineItem)

    public var inverse: @Sendable ([OutlineItem]) -> TreeCommand? {
        switch self {
        case .moveUp(let id):
            return { _ in .moveDown(itemID: id) }
        case .moveDown(let id):
            return { _ in .moveUp(itemID: id) }
        case .indent(let id):
            return { _ in .outdent(itemID: id) }
        case .outdent(let id):
            return { _ in .indent(itemID: id) }
        case .insertAbove(_, let newItem):
            return { _ in .deleteSubtree(itemID: newItem.id) }
        case .insertBelow(_, let newItem):
            return { _ in .deleteSubtree(itemID: newItem.id) }
        case .insertChild(_, let newItem):
            return { _ in .deleteSubtree(itemID: newItem.id) }
        case .deleteSubtree(let id):
            return { items in
                let engine = TreeEngine()
                let (_, deleted) = engine.deleteSubtree(itemID: id, in: items)
                return .restoreItems(deleted)
            }
        case .setChecked(let checked, let id):
            return { _ in .setChecked(checked: !checked, itemID: id) }
        case .resetChecks:
            return { items in .restoreItems(items.filter(\.isChecked)) }
        case .resetSubtree(let id):
            return { items in
                let engine = TreeEngine()
                let descs = engine.descendants(of: id, in: items)
                let checked = ([items.first { $0.id == id }].compactMap { $0 } + descs).filter(\.isChecked)
                return .restoreItems(checked)
            }
        case .updateItem(let newVersion):
            return { items in
                guard let old = items.first(where: { $0.id == newVersion.id }) else { return nil }
                return .updateItem(old)
            }
        case .restoreItems:
            return { _ in nil }
        }
    }

    case restoreItems([OutlineItem])
}

public struct TreeCommandResult: Sendable {
    public let items: [OutlineItem]
    public let command: TreeCommand
    public let inverse: TreeCommand?

    public init(items: [OutlineItem], command: TreeCommand, inverse: TreeCommand?) {
        self.items = items
        self.command = command
        self.inverse = inverse
    }
}

extension TreeEngine {
    public func execute(
        command: TreeCommand,
        on items: [OutlineItem]
    ) throws -> TreeCommandResult {
        let inverse = command.inverse(items)

        let result: [OutlineItem]
        switch command {
        case .moveUp(let id):
            guard let moved = moveUp(itemID: id, in: items) else { return TreeCommandResult(items: items, command: command, inverse: inverse) }
            result = moved
        case .moveDown(let id):
            guard let moved = moveDown(itemID: id, in: items) else { return TreeCommandResult(items: items, command: command, inverse: inverse) }
            result = moved
        case .indent(let id):
            result = try indent(itemID: id, in: items)
        case .outdent(let id):
            result = try outdent(itemID: id, in: items)
        case .insertAbove(let refID, let newItem):
            result = insertAbove(referenceID: refID, newItem: newItem, in: items)
        case .insertBelow(let refID, let newItem):
            result = insertBelow(referenceID: refID, newItem: newItem, in: items)
        case .insertChild(let parentID, let newItem):
            result = insertChild(parentID: parentID, newItem: newItem, in: items)
        case .deleteSubtree(let id):
            let (remaining, _) = deleteSubtree(itemID: id, in: items)
            result = remaining
        case .setChecked(let checked, let id):
            result = setChecked(checked, itemID: id, in: items)
        case .resetChecks:
            result = resetChecks(in: items)
        case .resetSubtree(let id):
            result = resetChecks(subtreeOf: id, in: items)
        case .updateItem(let updated):
            result = items.map { $0.id == updated.id ? updated : $0 }
        case .restoreItems(let restored):
            let existingIDs = Set(items.map(\.id))
            let newItems = restored.filter { !existingIDs.contains($0.id) }
            result = items + newItems
        }

        return TreeCommandResult(items: result, command: command, inverse: inverse)
    }
}
