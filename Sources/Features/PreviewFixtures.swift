#if DEBUG
import Domain
import Foundation

@MainActor
enum PreviewFixtures {
    static let packingListID = UUID(uuidString: "00000000-0000-0000-0000-000000000100")!
    static let clothingID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!

    static let packingList = ListItem(
        id: packingListID,
        title: "Weekend Packing",
        notes: "A compact reusable packing list",
        icon: "suitcase",
        colorName: "blue"
    )

    static let items: [OutlineItem] = [
        OutlineItem(
            id: clothingID,
            listID: packingListID,
            title: "Clothing",
            position: 1
        ),
        OutlineItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
            listID: packingListID,
            parentID: clothingID,
            title: "Shirts",
            quantity: 3,
            isChecked: true,
            position: 1
        ),
        OutlineItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!,
            listID: packingListID,
            parentID: clothingID,
            title: "Socks",
            quantity: 4,
            position: 2
        ),
        OutlineItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000104")!,
            listID: packingListID,
            title: "Passport",
            notes: "Check expiration date",
            position: 2
        ),
    ]

    static func appStore(selected: Bool = false) -> AppStore {
        let listRepo = PreviewListRepository(lists: [packingList])
        let outlineRepo = PreviewOutlineRepository(items: items)
        let store = AppStore(listRepository: listRepo, outlineRepository: outlineRepo)
        store.lists = [packingList]
        store.selectedListID = selected ? packingListID : nil
        return store
    }

    static func listStore(checkMode: Bool = false) -> ListStore {
        let listRepo = PreviewListRepository(lists: [packingList])
        let outlineRepo = PreviewOutlineRepository(items: items)
        let store = ListStore(
            listID: packingListID,
            outlineRepo: outlineRepo,
            listRepo: listRepo
        )
        store.list = packingList
        store.items = items
        store.expandedIDs = [clothingID]
        store.flatRows = TreeEngine().flatten(items: items, expandedIDs: [clothingID])
        store.isCheckMode = checkMode
        return store
    }
}

private actor PreviewListRepository: ListRepository {
    private var lists: [ListItem]

    init(lists: [ListItem]) {
        self.lists = lists
    }

    func fetchAll() async throws -> [ListItem] { lists }
    func fetchActive() async throws -> [ListItem] { lists.filter { !$0.isArchived } }
    func fetchArchived() async throws -> [ListItem] { lists.filter(\.isArchived) }
    func fetch(id: UUID) async throws -> ListItem? { lists.first { $0.id == id } }
    func save(_ list: ListItem) async throws {
        lists.removeAll { $0.id == list.id }
        lists.append(list)
    }
    func saveListAndItems(_ list: ListItem, items: [OutlineItem]) async throws {
        try await save(list)
    }
    func replaceAllListsAndItems(with archive: LibraryArchive) async throws {
        lists = archive.lists.map(\.list)
    }
    func fetchLibraryArchive() async throws -> LibraryArchive {
        LibraryArchive(lists: lists.map { ArchivedList(list: $0, items: []) })
    }
    func deleteListAndItems(id: UUID) async throws {
        lists.removeAll { $0.id == id }
    }
}

private actor PreviewOutlineRepository: OutlineRepository {
    private var items: [OutlineItem]

    init(items: [OutlineItem]) {
        self.items = items
    }

    func fetchItems(forList listID: UUID) async throws -> [OutlineItem] {
        items.filter { $0.listID == listID }
    }
    func applyChanges(saving newItems: [OutlineItem], deletingIDs: [UUID]) async throws {
        let savedIDs = Set(newItems.map(\.id))
        items.removeAll { savedIDs.contains($0.id) }
        items.append(contentsOf: newItems)
        let deleted = Set(deletingIDs)
        items.removeAll { deleted.contains($0.id) }
    }
}
#endif
