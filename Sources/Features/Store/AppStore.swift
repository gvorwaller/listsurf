import SwiftUI
import Domain
import os

@MainActor
@Observable
public final class AppStore {
    public var lists: [ListItem] = []
    public var archivedLists: [ListItem] = []
    public var selectedListID: UUID?

    public let errorStore: AppErrorStore

    private let listRepo: any ListRepository
    private let outlineRepo: any OutlineRepository
    private let logger = Logger(subsystem: "net.vorwaller.listsurf", category: "ui")
    private let exportService = ExportService()
    // Weak registry of issued ListStores so library-wide operations
    // (export, delete) can drain their queued item writes first.
    private var issuedStores: [WeakListStore] = []

    public init(
        listRepository: any ListRepository,
        outlineRepository: any OutlineRepository,
        errorStore: AppErrorStore = AppErrorStore()
    ) {
        self.listRepo = listRepository
        self.outlineRepo = outlineRepository
        self.errorStore = errorStore
    }

    public func loadLists() async {
        do {
            // Fetch both before assigning either, so a mid-load failure can't
            // leave active lists fresh while archived lists are stale.
            let active = try await listRepo.fetchActive()
                .sorted { $0.position < $1.position }
            let archived = try await listRepo.fetchArchived()
            lists = active
            archivedLists = archived
        } catch {
            presentLoadError(error, operation: "load lists")
        }
    }

    public func createList(
        title: String,
        notes: String? = nil,
        icon: String? = nil,
        colorName: String? = nil
    ) async {
        let list = ListItem(
            title: title,
            notes: notes,
            icon: icon,
            colorName: colorName,
            position: nextListPosition()
        )
        do {
            try await listRepo.save(list)
            await loadLists()
            selectedListID = list.id
        } catch {
            presentSaveError(error, operation: "create list", retryTitle: "Try Again") { [weak self] in
                await self?.createList(title: title, notes: notes, icon: icon, colorName: colorName)
            }
        }
    }

    @discardableResult
    public func updateList(_ list: ListItem) async -> Bool {
        do {
            try await listRepo.save(list)
            await loadLists()
            return true
        } catch {
            presentSaveError(error, operation: "update list", retryTitle: "Try Again") { [weak self] in
                await self?.updateList(list)
            }
            return false
        }
    }

    public func deleteList(id: UUID) async {
        do {
            // Let queued item writes land before the delete transaction so
            // the two can't interleave (the repository additionally refuses
            // to save items for a deleted list, as defense in depth).
            await drainPendingItemWrites()
            try await listRepo.deleteListAndItems(id: id)
            if selectedListID == id { selectedListID = nil }
            await loadLists()
        } catch {
            presentSaveError(error, operation: "delete list", retryTitle: "Try Again") { [weak self] in
                await self?.deleteList(id: id)
            }
        }
    }

    public func archiveList(id: UUID) async {
        guard var list = lists.first(where: { $0.id == id }) else {
            await refreshAfterStaleReference(operation: "archive list")
            return
        }
        list.archivedAt = Date()
        list.updatedAt = Date()
        if await updateList(list), selectedListID == id {
            selectedListID = nil
        }
    }

    public func restoreList(id: UUID) async {
        guard var list = archivedLists.first(where: { $0.id == id }) else {
            await refreshAfterStaleReference(operation: "restore list")
            return
        }
        list.archivedAt = nil
        list.updatedAt = Date()
        await updateList(list)
    }

    public func duplicateList(id: UUID, clearChecks: Bool) async {
        guard let list = lists.first(where: { $0.id == id }) else {
            await refreshAfterStaleReference(operation: "duplicate list")
            return
        }
        do {
            let items = try await outlineRepo.fetchItems(forList: id)
            let engine = TreeEngine()
            let (newList, newItems) = engine.duplicateList(
                list,
                items: items,
                clearChecks: clearChecks
            )
            var positioned = newList
            positioned.title = duplicateTitle(for: list.title)
            positioned.position = nextListPosition()
            try await listRepo.saveListAndItems(positioned, items: newItems)
            await loadLists()
            selectedListID = positioned.id
        } catch {
            presentSaveError(error, operation: "duplicate list", retryTitle: "Try Again") { [weak self] in
                await self?.duplicateList(id: id, clearChecks: clearChecks)
            }
        }
    }

    /// Returns the encoded backup, or nil after presenting the failure.
    /// Errors are presented here and never also thrown — a hybrid contract
    /// invites call sites to swallow them.
    public func exportLibrary(appVersion: String = AppStore.bundleVersion) async -> Data? {
        do {
            // A backup must include edits made moments ago: drain queued
            // item writes before taking the snapshot.
            await drainPendingItemWrites()
            let archive = try await listRepo.fetchLibraryArchive()
            let export = exportService.export(
                archive: archive,
                appVersion: appVersion
            )
            return try exportService.encode(export)
        } catch {
            logger.error("Failed to export library: \(error.localizedDescription)")
            errorStore.present(.persistenceLoad(underlying: error.localizedDescription))
            return nil
        }
    }

    /// Returns whether the import succeeded. Errors are presented here.
    @discardableResult
    public func importLibrary(from data: Data) async -> Bool {
        do {
            let decoded = try exportService.decode(from: data)
            let archive = try exportService.archive(from: decoded)
            try await listRepo.replaceAllListsAndItems(with: archive)
            await loadLists()
            selectedListID = lists.first?.id
            return true
        } catch let error as ExportValidationError {
            errorStore.present(.importValidation(message: error.localizedDescription))
            return false
        } catch let error as DecodingError {
            errorStore.present(.importValidation(message: error.localizedDescription))
            return false
        } catch {
            presentSaveError(error, operation: "import library", retryTitle: "Try Again") { [weak self] in
                await self?.importLibrary(from: data)
            }
            return false
        }
    }

    public static var bundleVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private func nextListPosition() -> Double {
        // Consider archived lists too: a restored list keeps its position,
        // and colliding with it would make library order ambiguous.
        ((lists + archivedLists).map(\.position).max() ?? 0) + 1.0
    }

    /// The UI acted on a list that no longer exists (stale row, another
    /// window changed the library). Refresh so the stale entry disappears
    /// instead of silently doing nothing.
    private func refreshAfterStaleReference(operation: String) async {
        logger.warning("Cannot \(operation): list no longer exists; refreshing library")
        await loadLists()
    }

    public func makeListStore(for listID: UUID) -> ListStore {
        let store = ListStore(
            listID: listID,
            outlineRepo: outlineRepo,
            listRepo: listRepo,
            errorStore: errorStore
        )
        issuedStores.removeAll { $0.store == nil }
        issuedStores.append(WeakListStore(store: store))
        return store
    }

    private func drainPendingItemWrites() async {
        issuedStores.removeAll { $0.store == nil }
        for box in issuedStores {
            await box.store?.waitForPendingPersistence()
        }
    }

    private func duplicateTitle(for title: String) -> String {
        let existingTitles = Set((lists + archivedLists).map(\.title))
        if let copySequence = copySequence(for: title) {
            return firstAvailableCopyTitle(
                baseTitle: copySequence.baseTitle,
                startingAt: copySequence.nextNumber,
                existingTitles: existingTitles
            )
        }

        return firstAvailableCopyTitle(
            baseTitle: title,
            startingAt: 1,
            existingTitles: existingTitles
        )
    }

    private func firstAvailableCopyTitle(
        baseTitle: String,
        startingAt startingNumber: Int,
        existingTitles: Set<String>
    ) -> String {
        var number = max(1, startingNumber)
        while true {
            let candidate = number == 1 ? "\(baseTitle) Copy" : "\(baseTitle) Copy \(number)"
            if !existingTitles.contains(candidate) {
                return candidate
            }
            number += 1
        }
    }

    private func copySequence(for title: String) -> (baseTitle: String, nextNumber: Int)? {
        let pattern = #"^(.*) Copy(?: (\d+))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              let range = Range(match.range(at: 1), in: title)
        else {
            return nil
        }

        let base = String(title[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return nil }

        let nextNumber: Int
        if match.range(at: 2).location != NSNotFound,
           let numberRange = Range(match.range(at: 2), in: title),
           let number = Int(title[numberRange]) {
            nextNumber = number + 1
        } else {
            nextNumber = 2
        }

        return (base, nextNumber)
    }

    private struct WeakListStore {
        weak var store: ListStore?
    }

    private func presentLoadError(_ error: Error, operation: String) {
        logger.error("Failed to \(operation): \(error.localizedDescription)")
        errorStore.present(
            .persistenceLoad(underlying: error.localizedDescription),
            retryTitle: "Retry Load"
        ) { [weak self] in
            Task { await self?.loadLists() }
        }
    }

    /// Every save failure retries the operation that actually failed —
    /// a generic "reload" retry would discard the user's pending change.
    private func presentSaveError(
        _ error: Error,
        operation: String,
        retryTitle: String,
        retry: @escaping @MainActor () async -> Void
    ) {
        logger.error("Failed to \(operation): \(error.localizedDescription)")
        errorStore.present(
            .persistenceSave(underlying: error.localizedDescription),
            retryTitle: retryTitle
        ) {
            Task { await retry() }
        }
    }
}
