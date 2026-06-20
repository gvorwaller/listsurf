import CoreData
import Domain
import os

public final class CoreDataOutlineRepository: OutlineRepository, @unchecked Sendable {
    private let stack: PersistenceStack
    private let logger = Logger(subsystem: "com.listsurf.app", category: "persistence")

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
            let request = NSFetchRequest<OutlineItemEntityMO>(entityName: "OutlineItemEntity")
            request.predicate = NSPredicate(format: "id == %@", item.id as CVarArg)
            request.fetchLimit = 1

            let entity = try context.fetch(request).first
                ?? OutlineItemEntityMO(entity: NSEntityDescription.entity(forEntityName: "OutlineItemEntity", in: context)!, insertInto: context)
            entity.update(from: item)
            try context.save()
        }
    }

    public func saveAll(_ items: [OutlineItem]) async throws {
        let context = stack.newBackgroundContext()
        try await context.perform {
            for item in items {
                let request = NSFetchRequest<OutlineItemEntityMO>(entityName: "OutlineItemEntity")
                request.predicate = NSPredicate(format: "id == %@", item.id as CVarArg)
                request.fetchLimit = 1

                let entity = try context.fetch(request).first
                    ?? OutlineItemEntityMO(entity: NSEntityDescription.entity(forEntityName: "OutlineItemEntity", in: context)!, insertInto: context)
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
        let context = stack.newBackgroundContext()
        try await context.perform {
            for id in ids {
                let request = NSFetchRequest<OutlineItemEntityMO>(entityName: "OutlineItemEntity")
                request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                for entity in try context.fetch(request) {
                    context.delete(entity)
                }
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
}
