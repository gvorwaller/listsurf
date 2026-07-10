import CoreData
import Domain
import os

public final class CoreDataListRepository: ListRepository, @unchecked Sendable {
    private let stack: PersistenceStack
    private let logger = Logger(subsystem: "net.vorwaller.listsurf", category: "persistence")

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
            do {
                let entity = try self.listEntity(id: list.id, in: context)
                entity.update(from: list)
                try context.save()
            } catch {
                // The view context is long-lived and shared: without rollback
                // a failed save leaves pending changes that ride along with
                // the next unrelated save.
                context.rollback()
                throw error
            }
        }
    }

    public func fetchLibraryArchive() async throws -> LibraryArchive {
        let context = stack.newBackgroundContext()
        return try await context.perform {
            let listRequest = NSFetchRequest<ListEntityMO>(entityName: "ListEntity")
            listRequest.sortDescriptors = [NSSortDescriptor(key: "position", ascending: true)]
            let lists = try context.fetch(listRequest).map { $0.toDomain() }

            var archivedLists: [ArchivedList] = []
            for list in lists {
                let itemRequest = NSFetchRequest<OutlineItemEntityMO>(entityName: "OutlineItemEntity")
                itemRequest.predicate = NSPredicate(format: "listID == %@", list.id as CVarArg)
                itemRequest.sortDescriptors = [NSSortDescriptor(key: "position", ascending: true)]
                let items = try context.fetch(itemRequest).map { $0.toDomain() }
                archivedLists.append(ArchivedList(list: list, items: items))
            }
            return LibraryArchive(lists: archivedLists)
        }
    }

    public func saveListAndItems(_ list: ListItem, items: [OutlineItem]) async throws {
        let context = stack.newBackgroundContext()
        try await context.perform {
            do {
                let listEntity = try self.listEntity(id: list.id, in: context)
                listEntity.update(from: list)

                let itemIDs = items.map(\.id)
                let request = NSFetchRequest<OutlineItemEntityMO>(entityName: "OutlineItemEntity")
                request.predicate = NSPredicate(format: "id IN %@", itemIDs)
                let existing = try context.fetch(request)
                let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

                for item in items {
                    let entity = existingByID[item.id]
                        ?? OutlineItemEntityMO(
                            entity: NSEntityDescription.entity(
                                forEntityName: "OutlineItemEntity",
                                in: context
                            )!,
                            insertInto: context
                        )
                    entity.update(from: item)
                }

                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    public func replaceAllListsAndItems(with archive: LibraryArchive) async throws {
        let context = stack.newBackgroundContext()
        try await context.perform {
            do {
                let itemRequest = NSFetchRequest<OutlineItemEntityMO>(
                    entityName: "OutlineItemEntity"
                )
                for entity in try context.fetch(itemRequest) {
                    context.delete(entity)
                }

                let listRequest = NSFetchRequest<ListEntityMO>(entityName: "ListEntity")
                for entity in try context.fetch(listRequest) {
                    context.delete(entity)
                }

                for archivedList in archive.lists {
                    let listEntity = ListEntityMO(
                        entity: NSEntityDescription.entity(
                            forEntityName: "ListEntity",
                            in: context
                        )!,
                        insertInto: context
                    )
                    listEntity.update(from: archivedList.list)

                    for item in archivedList.items {
                        let itemEntity = OutlineItemEntityMO(
                            entity: NSEntityDescription.entity(
                                forEntityName: "OutlineItemEntity",
                                in: context
                            )!,
                            insertInto: context
                        )
                        itemEntity.update(from: item)
                    }
                }

                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    public func addListsAndItems(with archive: LibraryArchive) async throws {
        let context = stack.newBackgroundContext()
        try await context.perform {
            do {
                // MANDATORY collision preflight: the background context's
                // NSMergePolicy.mergeByPropertyObjectTrump (PersistenceStack.swift)
                // means a save that violates the `id` uniqueness constraint does NOT
                // throw — it silently upserts onto the existing row. A planner
                // regression that failed to remint even one ID would therefore
                // mutate user data with no error. Fetching for collisions first,
                // in the same transaction, converts that into a loud, tested failure.
                let incomingListIDs = archive.lists.map(\.list.id)
                let incomingItemIDs = archive.lists.flatMap { $0.items.map(\.id) }

                // The archive itself must also be internally consistent:
                // duplicate IDs WITHIN the archive would sail past the
                // store-collision fetches below and then hit the silent-upsert
                // merge policy between two incoming rows; an item whose listID
                // points outside its packaged list would inject rows into an
                // existing user list. Neither may reach the insert loop.
                var seenListIDs = Set<UUID>()
                for id in incomingListIDs where !seenListIDs.insert(id).inserted {
                    throw AddListsAndItemsError.duplicateListIDInArchive(id)
                }
                var seenItemIDs = Set<UUID>()
                for id in incomingItemIDs where !seenItemIDs.insert(id).inserted {
                    throw AddListsAndItemsError.duplicateItemIDInArchive(id)
                }
                for archivedList in archive.lists {
                    for item in archivedList.items where item.listID != archivedList.list.id {
                        throw AddListsAndItemsError.itemOutsideItsList(itemID: item.id)
                    }
                }

                let listCollisionRequest = NSFetchRequest<ListEntityMO>(entityName: "ListEntity")
                listCollisionRequest.predicate = NSPredicate(format: "id IN %@", incomingListIDs)
                listCollisionRequest.fetchLimit = 1
                if let collidingList = try context.fetch(listCollisionRequest).first {
                    throw AddListsAndItemsError.collidingListID(collidingList.id)
                }

                let itemCollisionRequest = NSFetchRequest<OutlineItemEntityMO>(
                    entityName: "OutlineItemEntity"
                )
                itemCollisionRequest.predicate = NSPredicate(format: "id IN %@", incomingItemIDs)
                itemCollisionRequest.fetchLimit = 1
                if let collidingItem = try context.fetch(itemCollisionRequest).first {
                    throw AddListsAndItemsError.collidingItemID(collidingItem.id)
                }

                for archivedList in archive.lists {
                    let listEntity = ListEntityMO(
                        entity: NSEntityDescription.entity(
                            forEntityName: "ListEntity",
                            in: context
                        )!,
                        insertInto: context
                    )
                    listEntity.update(from: archivedList.list)

                    for item in archivedList.items {
                        let itemEntity = OutlineItemEntityMO(
                            entity: NSEntityDescription.entity(
                                forEntityName: "OutlineItemEntity",
                                in: context
                            )!,
                            insertInto: context
                        )
                        itemEntity.update(from: item)
                    }
                }

                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    public func deleteListAndItems(id: UUID) async throws {
        let context = stack.newBackgroundContext()
        try await context.perform {
            do {
                let itemRequest = NSFetchRequest<OutlineItemEntityMO>(
                    entityName: "OutlineItemEntity"
                )
                itemRequest.predicate = NSPredicate(format: "listID == %@", id as CVarArg)
                for entity in try context.fetch(itemRequest) {
                    context.delete(entity)
                }

                let listRequest = NSFetchRequest<ListEntityMO>(entityName: "ListEntity")
                listRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                for entity in try context.fetch(listRequest) {
                    context.delete(entity)
                }

                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    private func perform<T>(_ block: @Sendable @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        let context = stack.viewContext
        return try await context.perform {
            try block(context)
        }
    }

    private func listEntity(
        id: UUID,
        in context: NSManagedObjectContext
    ) throws -> ListEntityMO {
        let request = NSFetchRequest<ListEntityMO>(entityName: "ListEntity")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
            ?? ListEntityMO(
                entity: NSEntityDescription.entity(
                    forEntityName: "ListEntity",
                    in: context
                )!,
                insertInto: context
            )
    }
}

/// Thrown by `addListsAndItems` when an incoming list or item ID already exists in
/// the store — see the collision preflight in `addListsAndItems` for why this check
/// is mandatory rather than relying on the merge policy to fail loudly on its own.
public enum AddListsAndItemsError: LocalizedError, Sendable {
    case collidingListID(UUID)
    case collidingItemID(UUID)
    case duplicateListIDInArchive(UUID)
    case duplicateItemIDInArchive(UUID)
    case itemOutsideItsList(itemID: UUID)

    public var errorDescription: String? {
        switch self {
        case .collidingListID(let id):
            "Cannot add list \(id): a list with that ID already exists in the library."
        case .collidingItemID(let id):
            "Cannot add item \(id): an item with that ID already exists in the library."
        case .duplicateListIDInArchive(let id):
            "Cannot import: the archive contains two lists with the same ID \(id)."
        case .duplicateItemIDInArchive(let id):
            "Cannot import: the archive contains two items with the same ID \(id)."
        case .itemOutsideItsList(let itemID):
            "Cannot import: item \(itemID) does not belong to the list it was packaged with."
        }
    }
}
