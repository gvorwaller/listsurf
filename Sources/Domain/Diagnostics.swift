import Foundation

/// Read-only snapshot of on-device storage facts for Settings → Data (spec §4.5,
/// §7.5). Metadata only — never opens the SQLite file (cs.md rule enforced by
/// the Persistence-layer implementation, `CoreDataDiagnostics`).
public struct DiagnosticsSnapshot: Equatable, Sendable {
    public let storeURL: URL?          // nil for in-memory stores
    public let storeSizeBytes: Int64?  // store + -wal + -shm; nil if metadata unreadable
    public let activeListCount: Int
    public let archivedListCount: Int
    public let itemCount: Int

    // Swift does NOT synthesize a public memberwise init for a public
    // struct — Persistence could not construct this without it.
    public init(
        storeURL: URL?,
        storeSizeBytes: Int64?,
        activeListCount: Int,
        archivedListCount: Int,
        itemCount: Int
    ) {
        self.storeURL = storeURL
        self.storeSizeBytes = storeSizeBytes
        self.activeListCount = activeListCount
        self.archivedListCount = archivedListCount
        self.itemCount = itemCount
    }
}

public protocol DiagnosticsReading: Sendable {
    func snapshot() async throws -> DiagnosticsSnapshot
}
