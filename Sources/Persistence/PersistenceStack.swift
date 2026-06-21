import CoreData
import os

public final class PersistenceStack: Sendable {
    public let container: NSPersistentContainer

    private static let logger = Logger(subsystem: "com.listsurf.app", category: "persistence")

    public init(
        inMemory: Bool = false,
        storeURL: URL? = nil,
        resetStore: Bool = false
    ) {
        let model = CoreDataModel.create()
        container = NSPersistentContainer(name: "Listsurf", managedObjectModel: model)

        if inMemory {
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [description]
        } else if let storeURL {
            let directory = storeURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            if resetStore {
                Self.removeStoreFiles(at: storeURL)
            }
            let description = NSPersistentStoreDescription(url: storeURL)
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

    public static func uiTesting(identifier: String, reset: Bool) -> PersistenceStack {
        let safeIdentifier = identifier.replacingOccurrences(
            of: "[^A-Za-z0-9_-]",
            with: "-",
            options: .regularExpression
        )
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let storeURL = baseURL
            .appendingPathComponent("Listsurf-UITests", isDirectory: true)
            .appendingPathComponent("\(safeIdentifier).sqlite")
        return PersistenceStack(storeURL: storeURL, resetStore: reset)
    }

    private static func removeStoreFiles(at storeURL: URL) {
        let fileManager = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fileManager.removeItem(atPath: storeURL.path + suffix)
        }
    }
}
