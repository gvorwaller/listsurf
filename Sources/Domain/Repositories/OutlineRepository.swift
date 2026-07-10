import Foundation

public protocol OutlineRepository: Sendable {
    func fetchItems(forList listID: UUID) async throws -> [OutlineItem]

    /// Apply one logical mutation atomically: everything saves and deletes
    /// together, or nothing does. There are deliberately no separate
    /// save/delete entry points — a mutation that saves in one transaction
    /// and deletes in another can commit half of itself.
    func applyChanges(saving items: [OutlineItem], deletingIDs: [UUID]) async throws
}
