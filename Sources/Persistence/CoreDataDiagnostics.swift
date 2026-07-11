import CoreData
import Domain

/// `DiagnosticsReading` implementation for Settings → Data (spec §5.4).
/// Reads only: Core Data count requests and `FileManager` file-size metadata.
/// The SQLite file itself is never opened (cs.md rule).
public final class CoreDataDiagnostics: DiagnosticsReading, @unchecked Sendable {
    private let stack: PersistenceStack

    public init(stack: PersistenceStack) {
        self.stack = stack
    }

    public func snapshot() async throws -> DiagnosticsSnapshot {
        let storeURL = resolveStoreURL()
        let context = stack.newBackgroundContext()
        let (activeCount, archivedCount, itemCount) = try await context.perform {
            let activeRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "ListEntity")
            activeRequest.predicate = NSPredicate(format: "archivedAt == nil")
            let active = try context.count(for: activeRequest)

            let archivedRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "ListEntity")
            archivedRequest.predicate = NSPredicate(format: "archivedAt != nil")
            let archived = try context.count(for: archivedRequest)

            let itemRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "OutlineItemEntity")
            let items = try context.count(for: itemRequest)

            return (active, archived, items)
        }

        return DiagnosticsSnapshot(
            storeURL: storeURL,
            storeSizeBytes: Self.storeSizeBytes(for: storeURL),
            activeListCount: activeCount,
            archivedListCount: archivedCount,
            itemCount: itemCount
        )
    }

    /// The loaded store is the authoritative source (the production path never
    /// sets a custom description); fall back to the description's URL if the
    /// store somehow isn't loaded yet. In-memory stores and missing URLs
    /// report nil — there is no on-disk file to describe.
    private func resolveStoreURL() -> URL? {
        let loadedStore = stack.container.persistentStoreCoordinator.persistentStores.first
        if let loadedStore, loadedStore.type == NSInMemoryStoreType {
            return nil
        }
        guard let url = loadedStore?.url ?? stack.container.persistentStoreDescriptions.first?.url else {
            return nil
        }
        if url.path.isEmpty || url.path == "/dev/null" {
            return nil
        }
        return url
    }

    /// Sums file-size metadata for the store plus its `-wal`/`-shm` sidecars.
    /// `FileManager.attributesOfItem` reads directory-entry metadata only —
    /// it never opens or parses the SQLite file's contents (cs.md rule).
    private static func storeSizeBytes(for storeURL: URL?) -> Int64? {
        guard let storeURL else { return nil }
        var total: Int64 = 0
        var foundAny = false
        for suffix in ["", "-wal", "-shm"] {
            let path = storeURL.path + suffix
            if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
               let size = attributes[.size] as? Int64 {
                total += size
                foundAny = true
            }
        }
        return foundAny ? total : nil
    }
}
