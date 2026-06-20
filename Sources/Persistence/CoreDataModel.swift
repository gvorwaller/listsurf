import CoreData

enum CoreDataModel {
    static func create() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let listEntity = NSEntityDescription()
        listEntity.name = "ListEntity"
        listEntity.managedObjectClassName = "ListEntity"

        let outlineItemEntity = NSEntityDescription()
        outlineItemEntity.name = "OutlineItemEntity"
        outlineItemEntity.managedObjectClassName = "OutlineItemEntity"

        listEntity.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("title", .stringAttributeType),
            attribute("notes", .stringAttributeType, optional: true),
            attribute("icon", .stringAttributeType, optional: true),
            attribute("colorName", .stringAttributeType, optional: true),
            attribute("position", .doubleAttributeType, defaultValue: 1.0),
            attribute("createdAt", .dateAttributeType),
            attribute("updatedAt", .dateAttributeType),
            attribute("archivedAt", .dateAttributeType, optional: true),
        ]

        outlineItemEntity.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("listID", .UUIDAttributeType),
            attribute("parentID", .UUIDAttributeType, optional: true),
            attribute("title", .stringAttributeType),
            attribute("notes", .stringAttributeType, optional: true),
            attribute("quantity", .integer64AttributeType, defaultValue: 1),
            attribute("isChecked", .booleanAttributeType, defaultValue: false),
            attribute("position", .doubleAttributeType, defaultValue: 1.0),
            attribute("createdAt", .dateAttributeType),
            attribute("updatedAt", .dateAttributeType),
        ]

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
}
