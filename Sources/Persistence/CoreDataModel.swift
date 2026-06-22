import CoreData

enum CoreDataModelVersion: String, CaseIterable {
    case v1Initial = "ListsurfModel.v1.initial"
    case v2ConstraintsAndIndexes = "ListsurfModel.v2.constraints-and-indexes"

    static let current: CoreDataModelVersion = .v2ConstraintsAndIndexes
}

enum CoreDataModel {
    static func create(version: CoreDataModelVersion = .current) -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        model.versionIdentifiers = [version.rawValue]

        let listEntity = NSEntityDescription()
        listEntity.name = "ListEntity"
        listEntity.managedObjectClassName = "ListEntity"

        let outlineItemEntity = NSEntityDescription()
        outlineItemEntity.name = "OutlineItemEntity"
        outlineItemEntity.managedObjectClassName = "OutlineItemEntity"

        let listID = attribute("id", .UUIDAttributeType)
        let listTitle = attribute("title", .stringAttributeType)
        let listNotes = attribute("notes", .stringAttributeType, optional: true)
        let listIcon = attribute("icon", .stringAttributeType, optional: true)
        let listColorName = attribute("colorName", .stringAttributeType, optional: true)
        let listPosition = attribute("position", .doubleAttributeType, defaultValue: 1.0)
        let listCreatedAt = attribute("createdAt", .dateAttributeType)
        let listUpdatedAt = attribute("updatedAt", .dateAttributeType)
        let listArchivedAt = attribute("archivedAt", .dateAttributeType, optional: true)

        listEntity.properties = [
            listID,
            listTitle,
            listNotes,
            listIcon,
            listColorName,
            listPosition,
            listCreatedAt,
            listUpdatedAt,
            listArchivedAt,
        ]

        let outlineID = attribute("id", .UUIDAttributeType)
        let outlineListID = attribute("listID", .UUIDAttributeType)
        let outlineParentID = attribute("parentID", .UUIDAttributeType, optional: true)
        let outlineTitle = attribute("title", .stringAttributeType)
        let outlineNotes = attribute("notes", .stringAttributeType, optional: true)
        let outlineQuantity = attribute("quantity", .integer64AttributeType, defaultValue: 1)
        let outlineIsChecked = attribute("isChecked", .booleanAttributeType, defaultValue: false)
        let outlinePosition = attribute("position", .doubleAttributeType, defaultValue: 1.0)
        let outlineCreatedAt = attribute("createdAt", .dateAttributeType)
        let outlineUpdatedAt = attribute("updatedAt", .dateAttributeType)

        outlineItemEntity.properties = [
            outlineID,
            outlineListID,
            outlineParentID,
            outlineTitle,
            outlineNotes,
            outlineQuantity,
            outlineIsChecked,
            outlinePosition,
            outlineCreatedAt,
            outlineUpdatedAt,
        ]

        switch version {
        case .v1Initial:
            break
        case .v2ConstraintsAndIndexes:
            listEntity.uniquenessConstraints = [["id"]]
            listEntity.indexes = [
                fetchIndex(
                    name: "ListEntity_active_position",
                    properties: [listArchivedAt, listPosition]
                ),
                fetchIndex(
                    name: "ListEntity_archived_position",
                    properties: [listArchivedAt, listPosition]
                ),
            ]
            outlineItemEntity.uniquenessConstraints = [["id"]]
            outlineItemEntity.indexes = [
                fetchIndex(
                    name: "OutlineItemEntity_list_position",
                    properties: [outlineListID, outlinePosition]
                ),
                fetchIndex(
                    name: "OutlineItemEntity_list_parent_position",
                    properties: [outlineListID, outlineParentID, outlinePosition]
                ),
            ]
        }

        model.entities = [listEntity, outlineItemEntity]
        return model
    }

    private static func attribute(
        _ name: String,
        _ type: NSAttributeType,
        optional: Bool = false,
        defaultValue: Any? = nil
    ) -> NSAttributeDescription {
        let attr = NSAttributeDescription()
        attr.name = name
        attr.attributeType = type
        attr.isOptional = optional
        if let defaultValue {
            attr.defaultValue = defaultValue
        }
        return attr
    }

    private static func fetchIndex(
        name: String,
        properties: [NSPropertyDescription]
    ) -> NSFetchIndexDescription {
        NSFetchIndexDescription(
            name: name,
            elements: properties.map {
                NSFetchIndexElementDescription(property: $0, collationType: .binary)
            }
        )
    }
}
