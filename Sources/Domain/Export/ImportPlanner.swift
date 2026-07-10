import Foundation

public struct ImportSummary: Equatable, Sendable {
    public let listCount: Int
    public let itemCount: Int
    /// Missing-parent remaps + cycle repairs, summed. 0 for OPML (XML nesting
    /// cannot express an invalid parent).
    public let repairedParentCount: Int

    public init(listCount: Int, itemCount: Int, repairedParentCount: Int) {
        self.listCount = listCount
        self.itemCount = itemCount
        self.repairedParentCount = repairedParentCount
    }
}

/// Every UUID in `archive` is freshly minted; nothing here exists in the store yet.
public struct AdditiveImportPlan: Sendable {
    public let archive: LibraryArchive
    public let summary: ImportSummary

    public init(archive: LibraryArchive, summary: ImportSummary) {
        self.archive = archive
        self.summary = summary
    }
}

/// Plans an additive import: mints fresh UUIDs for every list and item (see D2 in
/// docs/2026-07-10-milestone-3-interchange-spec.md §3 — a UUID from a file is never
/// persisted via the additive path) and repairs what an LLM/user cannot reasonably
/// fix by hand (missing parents, cycles), while still hard-failing what they must
/// fix (duplicate IDs, empty titles, etc. — see §4.3).
public struct ImportPlanner: Sendable {
    public init() {}

    // MARK: - JSON

    public func planAdditiveImport(from export: ListsurfExport) throws -> AdditiveImportPlan {
        try ExportService().validate(export, parentPolicy: .permitInvalid)

        var archivedLists: [ArchivedList] = []
        var totalItemCount = 0
        var totalRepairedCount = 0

        for exportedList in export.lists {
            let newListID = UUID()
            var idMap: [UUID: UUID] = [:]
            for item in exportedList.items {
                idMap[item.id] = UUID()
            }

            var missingParentCount = 0
            let remappedItems: [OutlineItem] = exportedList.items.map { item in
                var newParentID: UUID?
                if let oldParentID = item.parentID {
                    if let mappedParentID = idMap[oldParentID] {
                        newParentID = mappedParentID
                    } else {
                        missingParentCount += 1
                    }
                }
                return OutlineItem(
                    id: idMap[item.id]!,
                    listID: newListID,
                    parentID: newParentID,
                    title: item.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    notes: item.notes,
                    quantity: item.quantity,
                    isChecked: item.isChecked,
                    position: item.position,
                    createdAt: item.createdAt,
                    updatedAt: item.updatedAt
                )
            }

            // orphanCount will be 0 here — the loop above already nils missing
            // parents — but cycles survive remapping and are caught here.
            let repairResult = TreeEngine().repairInvalidParents(in: remappedItems)

            let newList = ListItem(
                id: newListID,
                title: exportedList.title.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: exportedList.notes,
                icon: exportedList.icon,
                colorName: exportedList.colorName,
                position: exportedList.position, // provisional — AppStore overrides at commit
                createdAt: exportedList.createdAt,
                updatedAt: exportedList.updatedAt,
                archivedAt: exportedList.archivedAt
            )

            archivedLists.append(ArchivedList(list: newList, items: repairResult.repaired))
            totalItemCount += repairResult.repaired.count
            totalRepairedCount += missingParentCount + repairResult.orphanCount + repairResult.cycleCount
        }

        let summary = ImportSummary(
            listCount: archivedLists.count,
            itemCount: totalItemCount,
            repairedParentCount: totalRepairedCount
        )
        return AdditiveImportPlan(archive: LibraryArchive(lists: archivedLists), summary: summary)
    }

    // MARK: - OPML

    public func planAdditiveImport(from document: OPMLDocument, fallbackTitle: String) -> AdditiveImportPlan {
        let trimmedDocumentTitle = document.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFallbackTitle = fallbackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String
        if let trimmedDocumentTitle, !trimmedDocumentTitle.isEmpty {
            title = trimmedDocumentTitle
        } else if !trimmedFallbackTitle.isEmpty {
            title = trimmedFallbackTitle
        } else {
            title = "Imported List"
        }

        let now = Date()
        let listID = UUID()
        var items: [OutlineItem] = []

        func walk(_ nodes: [OPMLOutlineNode], parentID: UUID?) {
            for (index, node) in nodes.enumerated() {
                let itemID = UUID()
                items.append(OutlineItem(
                    id: itemID,
                    listID: listID,
                    parentID: parentID,
                    title: node.text,
                    notes: node.note,
                    quantity: node.quantity,
                    isChecked: node.isChecked,
                    position: Double(index + 1),
                    createdAt: now,
                    updatedAt: now
                ))
                walk(node.children, parentID: itemID)
            }
        }
        walk(document.nodes, parentID: nil)

        let list = ListItem(
            id: listID,
            title: title,
            position: 1.0, // provisional — AppStore overrides at commit
            createdAt: now,
            updatedAt: now
        )

        let summary = ImportSummary(listCount: 1, itemCount: items.count, repairedParentCount: 0)
        return AdditiveImportPlan(
            archive: LibraryArchive(lists: [ArchivedList(list: list, items: items)]),
            summary: summary
        )
    }
}
