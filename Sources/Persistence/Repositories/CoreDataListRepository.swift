import CoreData
import Domain
import os

public final class CoreDataListRepository: ListRepository, @unchecked Sendable {
    private let stack: PersistenceStack
    private let logger = Logger(subsystem: "com.listsurf.app", category: "persistence")

    public init(stack: PersistenceStack) {
        self.stack = stack
    }

    public func fetchAll() async throws -> [ListItem] {
        try await perform { context in
            let request = NSFetchRequest<ListEntityMO>(entityName: "ListEntity")
            request.sortDescriptors = [NSSortDescriptor(key: "position", ascending: true)]
            return try context.fetch(request).map { $0.toDomain() }
        }
    }

    public func fetchActive() async throws -> [ListItem] {
        try await perform { context in
            let request = NSFetchRequest<ListEntityMO>(entityName: "ListEntity")
            request.predicate = NSPredicate(format: "archivedAt == nil")
            request.sortDescriptors = [NSSortDescriptor(key: "position", ascending: true)]
            return try context.fetch(request).map { $0.toDomain() }
        }
    }

    public func fetchArchived() async throws -> [ListItem] {
        try await perform { context in
            let request = NSFetchRequest<ListEntityMO>(entityName: "ListEntity")
            request.predicate = NSPredicate(format: "archivedAt != nil")
            request.sortDescriptors = [NSSortDescriptor(key: "archivedAt", ascending: false)]
            return try context.fetch(request).map { $0.toDomain() }
        }
    }

    public func fetch(id: UUID) async throws -> ListItem? {
        try await perform { context in
            let request = NSFetchRequest<ListEntityMO>(entityName: "ListEntity")
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            return try context.fetch(request).first?.toDomain()
        }
    }

    public func save(_ list: ListItem) async throws {
        try await perform { context in
            let request = NSFetchRequest<ListEntityMO>(entityName: "ListEntity")
            request.predicate = NSPredicate(format: "id == %@", list.id as CVarArg)
            request.fetchLimit = 1

            let entity = try context.fetch(request).first
                ?? ListEntityMO(entity: NSEntityDescription.entity(forEntityName: "ListEntity", in: context)!, insertInto: context)
            entity.update(from: list)
            try context.save()
        }
    }

    public func delete(id: UUID) async throws {
        try await perform { context in
            let request = NSFetchRequest<ListEntityMO>(entityName: "ListEntity")
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            for entity in try context.fetch(request) {
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
}
