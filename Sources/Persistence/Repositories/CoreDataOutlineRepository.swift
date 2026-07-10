import CoreData
import Domain
import os

public final class CoreDataOutlineRepository: OutlineRepository, @unchecked Sendable {
    private let stack: PersistenceStack
    private let logger = Logger(subsystem: "net.vorwaller.listsurf", category: "persistence")

    public init(stack: PersistenceStack) {
        self.stack = stack
    }

    public func fetchItems(forList listID: UUID) async throws -> [OutlineItem] {
        let context = stack.viewContext
        return try await context.perform {
            let request = NSFetchRequest<OutlineItemEntityMO>(entityName: "OutlineItemEntity")
            request.predicate = NSPredicate(format: "listID == %@", listID as CVarArg)
            request.sortDescriptors = [NSSortDescriptor(key: "position", ascending: true)]
            return try context.fetch(request).map { $0.toDomain() }
        }
    }

    public func applyChanges(saving items: [OutlineItem], deletingIDs: [UUID]) async throws {
        guard !items.isEmpty || !deletingIDs.isEmpty else { return }
        let context = stack.newBackgroundContext()
        try await context.perform {
            do {
                if !items.isEmpty {
                    // Queued saves can race a list deletion: this transaction
                    // must not resurrect item rows for a list that no longer
                    // exists, so writes are guarded by list existence here,
                    // in the same transaction that commits them.
                    let existingListIDs = try self.fetchExistingListIDs(
                        candidates: Set(items.map(\.listID)),
                        in: context
                    )
                    let orphanedCount = items.count { !existingListIDs.contains($0.listID) }
                    if orphanedCount > 0 {
                        self.logger.warning(
                            "Skipping \(orphanedCount) item save(s) whose list was deleted"
                        )
                    }

                    let saveable = items.filter { existingListIDs.contains($0.listID) }
                    let existing = try self.fetchExistingItems(
                        ids: saveable.map(\.id),
                        in: context
                    )
                    let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

                    for item in saveable {
                        let entity = existingByID[item.id] ?? self.makeItemEntity(in: context)
                        entity.update(from: item)
                    }
                }

                if !deletingIDs.isEmpty {
                    for entity in try self.fetchExistingItems(ids: deletingIDs, in: context) {
                        context.delete(entity)
                    }
                }

                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    private func fetchExistingListIDs(
        candidates: Set<UUID>,
        in context: NSManagedObjectContext
    ) throws -> Set<UUID> {
        let request = NSFetchRequest<ListEntityMO>(entityName: "ListEntity")
        request.predicate = NSPredicate(format: "id IN %@", Array(candidates))
        return Set(try context.fetch(request).compactMap(\.id))
    }

    private func fetchExistingItems(
        ids: [UUID],
        in context: NSManagedObjectContext
    ) throws -> [OutlineItemEntityMO] {
        let request = NSFetchRequest<OutlineItemEntityMO>(entityName: "OutlineItemEntity")
        request.predicate = NSPredicate(format: "id IN %@", ids)
        return try context.fetch(request)
    }

    private func makeItemEntity(in context: NSManagedObjectContext) -> OutlineItemEntityMO {
        OutlineItemEntityMO(
            entity: NSEntityDescription.entity(
                forEntityName: "OutlineItemEntity",
                in: context
            )!,
            insertInto: context
        )
    }
}
