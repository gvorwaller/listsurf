import Foundation

public struct ListItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var notes: String?
    public var icon: String?
    public var colorName: String?
    public var position: Double
    public var createdAt: Date
    public var updatedAt: Date
    public var archivedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        icon: String? = nil,
        colorName: String? = nil,
        position: Double = 1.0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.icon = icon
        self.colorName = colorName
        self.position = position
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
    }

    public var isArchived: Bool { archivedAt != nil }

    public var resolvedIcon: String { icon ?? "list.bullet" }
}
