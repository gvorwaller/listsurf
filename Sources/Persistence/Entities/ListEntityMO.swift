import CoreData
import Domain

@objc(ListEntity)
public final class ListEntityMO: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var title: String
    @NSManaged public var notes: String?
    @NSManaged public var icon: String?
    @NSManaged public var colorName: String?
    @NSManaged public var position: Double
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
    @NSManaged public var archivedAt: Date?
}

extension ListEntityMO {
    func toDomain() -> ListItem {
        ListItem(
            id: id,
            title: title,
            notes: notes,
            icon: icon,
            colorName: colorName,
            position: position,
            createdAt: createdAt,
            updatedAt: updatedAt,
            archivedAt: archivedAt
        )
    }

    func update(from domain: ListItem) {
        id = domain.id
        title = domain.title
        notes = domain.notes
        icon = domain.icon
        colorName = domain.colorName
        position = domain.position
        createdAt = domain.createdAt
        updatedAt = domain.updatedAt
        archivedAt = domain.archivedAt
    }
}
