import Foundation

public struct OutlineItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var listID: UUID
    public var parentID: UUID?
    public var title: String
    public var notes: String?
    public var quantity: Int
    public var isChecked: Bool
    public var position: Double
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        listID: UUID,
        parentID: UUID? = nil,
        title: String,
        notes: String? = nil,
        quantity: Int = 1,
        isChecked: Bool = false,
        position: Double = 1.0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.listID = listID
        self.parentID = parentID
        self.title = title
        self.notes = notes
        self.quantity = max(1, quantity)
        self.isChecked = isChecked
        self.position = position
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var isRoot: Bool { parentID == nil }
}
