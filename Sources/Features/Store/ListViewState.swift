import Foundation

/// Per-list presentation state (td-5d405a): expansion, check filter, and
/// selection survive switching between lists in-session and app relaunch.
/// Deliberately presentation-only — never Core Data, never synced. Scroll
/// position is explicitly out of scope (fragile; expansion+selection restore
/// already covers the visual context).
///
/// Stored as JSON-encoded `Data` in `UserDefaults` under
/// `viewStateKey(for:)`. `ListStore` is the sole seed/persist owner;
/// `AppStore.deleteList` is the sole cleanup owner — both call this same
/// key-builder so the format string lives in exactly one place.
struct ListViewState: Codable, Equatable {
    var expandedIDs: Set<UUID>
    var checkFilterRawValue: String
    var selectedItemIDs: Set<UUID>

    static func viewStateKey(for listID: UUID) -> String {
        "listViewState.\(listID.uuidString)"
    }
}
