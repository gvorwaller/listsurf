import Foundation

public struct ListsurfExport: Codable, Sendable {
    public let format: String
    public let schemaVersion: Int
    public let exportedAt: Date
    public let appVersion: String
    public let lists: [ExportedList]

    public init(
        appVersion: String,
        lists: [ExportedList]
    ) {
        self.format = "listsurf"
        self.schemaVersion = 1
        self.exportedAt = Date()
        self.appVersion = appVersion
        self.lists = lists
    }
}

public struct ExportedList: Codable, Sendable {
    public let id: UUID
    public let title: String
    public let notes: String?
    public let icon: String?
    public let colorName: String?
    public let position: Double
    public let createdAt: Date
    public let updatedAt: Date
    public let archivedAt: Date?
    public let items: [ExportedOutlineItem]

    public init(list: ListItem, items: [ExportedOutlineItem]) {
        self.id = list.id
        self.title = list.title
        self.notes = list.notes
        self.icon = list.icon
        self.colorName = list.colorName
        self.position = list.position
        self.createdAt = list.createdAt
        self.updatedAt = list.updatedAt
        self.archivedAt = list.archivedAt
        self.items = items
    }
}

public struct ExportedOutlineItem: Codable, Sendable {
    public let id: UUID
    public let parentID: UUID?
    public let title: String
    public let notes: String?
    public let quantity: Int
    public let isChecked: Bool
    public let position: Double
    public let createdAt: Date
    public let updatedAt: Date

    public init(item: OutlineItem) {
        self.id = item.id
        self.parentID = item.parentID
        self.title = item.title
        self.notes = item.notes
        self.quantity = item.quantity
        self.isChecked = item.isChecked
        self.position = item.position
        self.createdAt = item.createdAt
        self.updatedAt = item.updatedAt
    }
}

public struct ExportService: Sendable {
    public init() {}

    public func export(lists: [(ListItem, [OutlineItem])], appVersion: String) -> ListsurfExport {
        let exported = lists.map { list, items in
            ExportedList(
                list: list,
                items: items.map { ExportedOutlineItem(item: $0) }
            )
        }
        return ListsurfExport(appVersion: appVersion, lists: exported)
    }

    public func encode(_ export: ListsurfExport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(export)
    }

    public func decode(from data: Data) throws -> ListsurfExport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ListsurfExport.self, from: data)
    }
}
