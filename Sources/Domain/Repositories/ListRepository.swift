import Foundation

public protocol ListRepository: Sendable {
    func fetchAll() async throws -> [ListItem]
    func fetchActive() async throws -> [ListItem]
    func fetchArchived() async throws -> [ListItem]
    func fetch(id: UUID) async throws -> ListItem?
    func save(_ list: ListItem) async throws
    func saveListAndItems(_ list: ListItem, items: [OutlineItem]) async throws
    func replaceAllListsAndItems(with archive: LibraryArchive) async throws
    func delete(id: UUID) async throws
    func deleteListAndItems(id: UUID) async throws
}
