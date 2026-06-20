import CoreData
import os

public final class PersistenceStack: Sendable {
    public let container: NSPersistentContainer

    private static let logger = Logger(subsystem: "com.listsurf.app", category: "persistence")

    public init(inMemory: Bool = false) {
        let model = CoreDataModel.create()
        container = NSPersistentContainer(name: "Listsurf", managedObjectModel: model)

        if inMemory {
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [description]
        }

        container.loadPersistentStores { description, error in
            if let error {
                Self.logger.fault("Failed to load persistent store: \(error.localizedDescription)")
                fatalError("Failed to load persistent store: \(error)")
            }
            Self.logger.info("Persistent store loaded: \(description.type)")
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
    }

    public var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    public func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        return context
    }

    public static func inMemory() -> PersistenceStack {
        PersistenceStack(inMemory: true)
    }
}
