import CoreData
import Domain

@objc(OutlineItemEntity)
public final class OutlineItemEntityMO: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var listID: UUID
    @NSManaged public var parentID: UUID?
    @NSManaged public var title: String
    @NSManaged public var notes: String?
    @NSManaged public var quantity: Int64
    @NSManaged public var isChecked: Bool
    @NSManaged public var position: Double
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
}

extension OutlineItemEntityMO {
    func toDomain() -> OutlineItem {
        OutlineItem(
            id: id,
            listID: listID,
            parentID: parentID,
            title: title,
            notes: notes,
            quantity: Int(quantity),
            isChecked: isChecked,
            position: position,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func update(from domain: OutlineItem) {
        id = domain.id
        listID = domain.listID
        parentID = domain.parentID
        title = domain.title
        notes = domain.notes
        quantity = Int64(domain.quantity)
        isChecked = domain.isChecked
        position = domain.position
        createdAt = domain.createdAt
        updatedAt = domain.updatedAt
    }
}
