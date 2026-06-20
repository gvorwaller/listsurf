import Foundation

public protocol OutlineRepository: Sendable {
    func fetchItems(forList listID: UUID) async throws -> [OutlineItem]
    func fetch(id: UUID) async throws -> OutlineItem?
    func save(_ item: OutlineItem) async throws
    func saveAll(_ items: [OutlineItem]) async throws
    func delete(id: UUID) async throws
    func deleteAll(ids: [UUID]) async throws
}
