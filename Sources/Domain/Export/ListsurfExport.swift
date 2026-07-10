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

public struct LibraryArchive: Sendable {
    public let lists: [ArchivedList]

    public init(lists: [ArchivedList]) {
        self.lists = lists
    }
}

public struct ArchivedList: Sendable {
    public let list: ListItem
    public let items: [OutlineItem]

    public init(list: ListItem, items: [OutlineItem]) {
        self.list = list
        self.items = items
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

/// Controls how `ExportService.validate` treats item `parentID`s that don't resolve
/// within the same list. `.reject` is today's strict behavior (replace-all import);
/// `.permitInvalid` is used by `ImportPlanner`, which repairs instead of rejecting.
public enum ParentValidationPolicy: Sendable {
    case reject
    case permitInvalid
}

public struct ExportService: Sendable {
    public init() {}

    public func export(
        archive: LibraryArchive,
        appVersion: String
    ) -> ListsurfExport {
        let exported = archive.lists.map { archivedList in
            ExportedList(
                list: archivedList.list,
                items: archivedList.items.map { ExportedOutlineItem(item: $0) }
            )
        }
        return ListsurfExport(appVersion: appVersion, lists: exported)
    }

    public func export(lists: [(ListItem, [OutlineItem])], appVersion: String) -> ListsurfExport {
        export(
            archive: LibraryArchive(
                lists: lists.map { list, items in
                    ArchivedList(list: list, items: items)
                }
            ),
            appVersion: appVersion
        )
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

    public func archive(from export: ListsurfExport) throws -> LibraryArchive {
        try validate(export)
        let lists = export.lists.map { exportedList in
            let list = ListItem(
                id: exportedList.id,
                title: exportedList.title.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: exportedList.notes,
                icon: exportedList.icon,
                colorName: exportedList.colorName,
                position: exportedList.position,
                createdAt: exportedList.createdAt,
                updatedAt: exportedList.updatedAt,
                archivedAt: exportedList.archivedAt
            )
            let items = exportedList.items.map { exportedItem in
                OutlineItem(
                    id: exportedItem.id,
                    listID: exportedList.id,
                    parentID: exportedItem.parentID,
                    title: exportedItem.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    notes: exportedItem.notes,
                    quantity: exportedItem.quantity,
                    isChecked: exportedItem.isChecked,
                    position: exportedItem.position,
                    createdAt: exportedItem.createdAt,
                    updatedAt: exportedItem.updatedAt
                )
            }
            return ArchivedList(list: list, items: items)
        }
        return LibraryArchive(lists: lists)
    }

    public func validate(_ export: ListsurfExport, parentPolicy: ParentValidationPolicy = .reject) throws {
        guard export.format == "listsurf" else {
            throw ExportValidationError.unsupportedFormat(export.format)
        }
        guard export.schemaVersion == 1 else {
            throw ExportValidationError.unsupportedSchemaVersion(export.schemaVersion)
        }

        var listIDs = Set<UUID>()
        var itemIDs = Set<UUID>()

        for exportedList in export.lists {
            guard listIDs.insert(exportedList.id).inserted else {
                throw ExportValidationError.duplicateListID(exportedList.id)
            }
            guard !exportedList.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ExportValidationError.emptyListTitle(exportedList.id)
            }
            guard exportedList.position.isFinite else {
                throw ExportValidationError.invalidPosition("list \(exportedList.id)")
            }

            var localItemIDs = Set<UUID>()
            for item in exportedList.items {
                guard itemIDs.insert(item.id).inserted else {
                    throw ExportValidationError.duplicateItemID(item.id)
                }
                localItemIDs.insert(item.id)
                guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ExportValidationError.emptyItemTitle(item.id)
                }
                guard item.quantity >= 1 else {
                    throw ExportValidationError.invalidQuantity(item.id)
                }
                guard item.position.isFinite else {
                    throw ExportValidationError.invalidPosition("item \(item.id)")
                }
                if item.parentID == item.id {
                    throw ExportValidationError.invalidParent(item.id)
                }
            }

            if parentPolicy == .reject {
                for item in exportedList.items {
                    if let parentID = item.parentID, !localItemIDs.contains(parentID) {
                        throw ExportValidationError.missingParent(item.id, parentID)
                    }
                }
                try validateAcyclicItems(exportedList.items)
            }
        }
    }

    private func validateAcyclicItems(_ items: [ExportedOutlineItem]) throws {
        let parentByID = Dictionary(
            uniqueKeysWithValues: items.compactMap { item in
                item.parentID.map { (item.id, $0) }
            }
        )
        for item in items {
            var visited = Set<UUID>()
            var current = item.id
            while let parentID = parentByID[current] {
                guard visited.insert(current).inserted else {
                    throw ExportValidationError.parentCycle(item.id)
                }
                current = parentID
            }
        }
    }
}

public enum ExportValidationError: LocalizedError, Sendable {
    case unsupportedFormat(String)
    case unsupportedSchemaVersion(Int)
    case duplicateListID(UUID)
    case duplicateItemID(UUID)
    case emptyListTitle(UUID)
    case emptyItemTitle(UUID)
    case invalidQuantity(UUID)
    case invalidPosition(String)
    case invalidParent(UUID)
    case missingParent(UUID, UUID)
    case parentCycle(UUID)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            "Unsupported export format “\(format)”."
        case .unsupportedSchemaVersion(let version):
            "Unsupported export schema version \(version)."
        case .duplicateListID(let id):
            "Duplicate list ID \(id)."
        case .duplicateItemID(let id):
            "Duplicate item ID \(id)."
        case .emptyListTitle(let id):
            "List \(id) has an empty title."
        case .emptyItemTitle(let id):
            "Item \(id) has an empty title."
        case .invalidQuantity(let id):
            "Item \(id) has an invalid quantity."
        case .invalidPosition(let subject):
            "\(subject) has an invalid position."
        case .invalidParent(let id):
            "Item \(id) cannot be its own parent."
        case .missingParent(let id, let parentID):
            "Item \(id) references missing parent \(parentID)."
        case .parentCycle(let id):
            "Item \(id) is part of a parent cycle."
        }
    }
}
