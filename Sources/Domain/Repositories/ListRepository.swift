import Foundation

public protocol ListRepository: Sendable {
    func fetchAll() async throws -> [ListItem]
    func fetchActive() async throws -> [ListItem]
    func fetchArchived() async throws -> [ListItem]
    func fetch(id: UUID) async throws -> ListItem?
    func save(_ list: ListItem) async throws
    func saveListAndItems(_ list: ListItem, items: [OutlineItem]) async throws
    func replaceAllListsAndItems(with archive: LibraryArchive) async throws

    /// Read the entire library in one transaction so an export can never mix
    /// pre- and post-edit state across lists.
    func fetchLibraryArchive() async throws -> LibraryArchive

    /// Deleting a list always deletes its items with it. There is
    /// intentionally no list-only delete — it would orphan every item.
    func deleteListAndItems(id: UUID) async throws
}
