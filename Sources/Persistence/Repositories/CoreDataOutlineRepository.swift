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
        try await perform { context in
            let request = NSFetchRequest<OutlineItemEntityMO>(entityName: "OutlineItemEntity")
            request.predicate = NSPredicate(format: "listID == %@", listID as CVarArg)
            request.sortDescriptors = [NSSortDescriptor(key: "position", ascending: true)]
            return try context.fetch(request).map { $0.toDomain() }
        }
    }

    public func fetch(id: UUID) async throws -> OutlineItem? {
        try await perform { context in
            let request = NSFetchRequest<OutlineItemEntityMO>(entityName: "OutlineItemEntity")
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            return try context.fetch(request).first?.toDomain()
        }
    }

    public func save(_ item: OutlineItem) async throws {
        try await perform { context in
            let entity = try self.itemEntity(id: item.id, in: context)
            entity.update(from: item)
            try context.save()
        }
    }

    public func saveAll(_ items: [OutlineItem]) async throws {
        guard !items.isEmpty else { return }
        let context = stack.newBackgroundContext()
        try await context.perform {
            let existing = try self.fetchExistingItems(
                ids: items.map(\.id),
                in: context
            )
            let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

            for item in items {
                let entity = existingByID[item.id] ?? self.makeItemEntity(in: context)
                entity.update(from: item)
            }
            try context.save()
        }
    }

    public func delete(id: UUID) async throws {
        try await perform { context in
            let request = NSFetchRequest<OutlineItemEntityMO>(entityName: "OutlineItemEntity")
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            for entity in try context.fetch(request) {
                context.delete(entity)
            }
            try context.save()
        }
    }

    public func deleteAll(ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        let context = stack.newBackgroundContext()
        try await context.perform {
            let existing = try self.fetchExistingItems(ids: ids, in: context)
            for entity in existing {
                context.delete(entity)
            }
            try context.save()
        }
    }

    private func perform<T>(_ block: @Sendable @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        let context = stack.viewContext
        return try await context.perform {
            try block(context)
        }
    }

    private func itemEntity(
        id: UUID,
        in context: NSManagedObjectContext
    ) throws -> OutlineItemEntityMO {
        let request = NSFetchRequest<OutlineItemEntityMO>(entityName: "OutlineItemEntity")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first ?? makeItemEntity(in: context)
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
