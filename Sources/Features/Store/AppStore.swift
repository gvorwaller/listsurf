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
    private let diagnostics: (any DiagnosticsReading)?
    private let logger = Logger(subsystem: "net.vorwaller.listsurf", category: "ui")
    private let exportService = ExportService()
    private let opmlCodec = OPMLCodec()
    private let markdownExporter = MarkdownExporter()
    private let importPlanner = ImportPlanner()
    // Weak registry of issued ListStores so library-wide operations
    // (export, delete) can drain their queued item writes first.
    private var issuedStores: [WeakListStore] = []

    public init(
        listRepository: any ListRepository,
        outlineRepository: any OutlineRepository,
        errorStore: AppErrorStore = AppErrorStore(),
        diagnostics: (any DiagnosticsReading)? = nil
    ) {
        self.listRepo = listRepository
        self.outlineRepo = outlineRepository
        self.errorStore = errorStore
        self.diagnostics = diagnostics
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
            // A replace-all import is a library-level write; draining first
            // keeps ordering deterministic against any queued item saves
            // (same contract as export/delete — see drainPendingItemWrites).
            await drainPendingItemWrites()
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
            errorStore.present(.importValidation(message: decodingFailureMessage(error)))
            return false
        } catch {
            presentSaveError(error, operation: "import library", retryTitle: "Try Again") { [weak self] in
                await self?.importLibrary(from: data)
            }
            return false
        }
    }

    // MARK: - Per-list export (§6.1)

    /// Returns the encoded per-list export, or nil after presenting the failure.
    public func exportListJSON(id: UUID, appVersion: String = AppStore.bundleVersion) async -> Data? {
        guard let (list, items) = await fetchListSnapshot(id: id) else { return nil }
        let export = exportService.export(lists: [(list, items)], appVersion: appVersion)
        do {
            return try exportService.encode(export)
        } catch {
            logger.error("Failed to encode list export: \(error.localizedDescription)")
            errorStore.present(.backupExportFailed(message: error.localizedDescription))
            return nil
        }
    }

    /// Returns the encoded OPML document, or nil after presenting the failure.
    public func exportListOPML(id: UUID) async -> Data? {
        guard let (list, items) = await fetchListSnapshot(id: id) else { return nil }
        return opmlCodec.encode(list: list, items: items)
    }

    /// Returns the rendered Markdown, or nil after presenting the failure.
    public func exportListMarkdown(id: UUID) async -> String? {
        guard let (list, items) = await fetchListSnapshot(id: id) else { return nil }
        return markdownExporter.render(list: list, items: items)
    }

    /// Shared by all three per-list export paths: drains queued item writes,
    /// resolves the list (stale-reference safe), and fetches its items sorted
    /// by the canonical sibling comparator (position asc, id.uuidString tie-break
    /// — TreeEngine.swift:70-73). Errors are presented here and never thrown.
    private func fetchListSnapshot(id: UUID) async -> (ListItem, [OutlineItem])? {
        await drainPendingItemWrites()
        guard let list = (lists + archivedLists).first(where: { $0.id == id }) else {
            await refreshAfterStaleReference(operation: "export list")
            return nil
        }
        do {
            let items = try await outlineRepo.fetchItems(forList: id).sorted { a, b in
                if a.position != b.position { return a.position < b.position }
                return a.id.uuidString < b.id.uuidString
            }
            return (list, items)
        } catch {
            logger.error("Failed to fetch items for export: \(error.localizedDescription)")
            errorStore.present(.persistenceLoad(underlying: error.localizedDescription))
            return nil
        }
    }

    // MARK: - Diagnostics (§7.5)

    /// nil when unavailable (no diagnostics reader was injected) or on
    /// failure (logged) — the read-only Settings → Data screen shows an
    /// inline "unavailable" state instead of an error banner.
    public func loadDiagnostics() async -> DiagnosticsSnapshot? {
        guard let diagnostics else { return nil }
        do {
            return try await diagnostics.snapshot()
        } catch {
            logger.error("Failed to load diagnostics: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Additive import — prepare/commit (§6.2)

    /// Parses, validates, and plans an additive import. Writes nothing.
    /// Returns nil after presenting an actionable failure.
    public func prepareAdditiveImport(from data: Data, filename: String) async -> AdditiveImportPlan? {
        // D11: strip a UTF-8 BOM, then sniff the first non-whitespace BYTE.
        var content = data
        if content.starts(with: [0xEF, 0xBB, 0xBF]) {
            content = content.dropFirst(3)
        }
        guard let sniffedByte = firstSignificantByte(in: content) else {
            presentImportSniffFailure(filename: filename)
            return nil
        }

        do {
            switch sniffedByte {
            case UInt8(ascii: "{"):
                let export = try exportService.decode(from: content)
                return try importPlanner.planAdditiveImport(from: export)
            case UInt8(ascii: "<"):
                let document = try opmlCodec.decode(content)
                let fallbackTitle = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
                return importPlanner.planAdditiveImport(from: document, fallbackTitle: fallbackTitle)
            default:
                presentImportSniffFailure(filename: filename)
                return nil
            }
        } catch let error as ExportValidationError {
            errorStore.present(.importValidation(message: error.localizedDescription))
            return nil
        } catch let error as OPMLDecodeError {
            errorStore.present(.importValidation(message: error.localizedDescription))
            return nil
        } catch let error as DecodingError {
            errorStore.present(.importValidation(message: decodingFailureMessage(error)))
            return nil
        } catch {
            // Nothing to retry safely here (the file itself is the problem),
            // so this stays inside the present-only validation contract
            // rather than using the retryable presentSaveError path.
            errorStore.present(.importValidation(message: error.localizedDescription))
            return nil
        }
    }

    /// Persists a prepared plan in one transaction; assigns positions and
    /// unique titles. Selects the first imported active list (leaves the
    /// current selection alone if every imported list is archived).
    /// Present-only errors; true on success.
    @discardableResult
    public func commitAdditiveImport(_ plan: AdditiveImportPlan) async -> Bool {
        // Rev-2 amendment: imports are library-level writes and must not
        // interleave with queued item saves (same contract as export/delete).
        await drainPendingItemWrites()

        // Computed once against the current library — the new lists aren't
        // in `lists`/`archivedLists` yet, so there is nothing to re-derive
        // mid-loop. A retry recomputes this against whatever the library
        // looks like at retry time; see the note on the catch block below.
        let basePosition = (lists + archivedLists).map(\.position).max() ?? 0
        var existingTitles = Set((lists + archivedLists).map(\.title))

        var adjustedLists: [ArchivedList] = []
        adjustedLists.reserveCapacity(plan.archive.lists.count)
        for (offset, archivedList) in plan.archive.lists.enumerated() {
            var list = archivedList.list
            list.position = basePosition + Double(offset + 1)
            let title = importTitle(for: list.title, existingTitles: existingTitles)
            existingTitles.insert(title)
            list.title = title
            adjustedLists.append(ArchivedList(list: list, items: archivedList.items))
        }
        let adjustedArchive = LibraryArchive(lists: adjustedLists)

        do {
            try await listRepo.addListsAndItems(with: adjustedArchive)
        } catch {
            // Retry re-runs the whole commit, INCLUDING recomputing titles
            // and positions against the then-current library. That is
            // intentional (rev-2 note, spec §6.2): the prepared plan's
            // content and minted UUIDs are "the failed operation"; placement
            // metadata is commit-time by design so a retried import can't
            // collide with a list created while the error banner sat open.
            presentSaveError(error, operation: "import list", retryTitle: "Try Again") { [weak self] in
                await self?.commitAdditiveImport(plan)
            }
            return false
        }

        await loadLists()
        if let firstActive = adjustedLists.first(where: { $0.list.archivedAt == nil }) {
            selectedListID = firstActive.list.id
        }
        return true
    }

    /// D9: "{title} (Imported)", then "{title} (Imported 2)"… Non-colliding
    /// titles are returned untouched.
    private func importTitle(for title: String, existingTitles: Set<String>) -> String {
        guard existingTitles.contains(title) else { return title }
        let firstCandidate = "\(title) (Imported)"
        if !existingTitles.contains(firstCandidate) {
            return firstCandidate
        }
        var number = 2
        while true {
            let candidate = "\(title) (Imported \(number))"
            if !existingTitles.contains(candidate) {
                return candidate
            }
            number += 1
        }
    }

    /// Byte-level sniff per D11: the format is identified from the first
    /// non-whitespace BYTE. Decoding the whole payload as UTF-8 here would
    /// misroute an OPML/JSON file with one bad byte later in the stream to
    /// the generic "neither" message instead of letting the real codec
    /// produce its actionable error (with line/column for XML).
    private func firstSignificantByte(in data: Data) -> UInt8? {
        let whitespace: Set<UInt8> = [0x09, 0x0A, 0x0D, 0x20]
        return data.first { !whitespace.contains($0) }
    }

    private func presentImportSniffFailure(filename: String) {
        errorStore.present(.importValidation(
            message: "\"\(filename)\" is neither Listsurf JSON nor OPML. Export a .json backup from Listsurf, or an .opml file from an outliner."
        ))
    }

    // MARK: - Actionable DecodingError mapping (§6.3)

    /// Maps a `DecodingError` to a path-bearing message (e.g.
    /// `Missing field "quantity" at lists[0].items[3].`) instead of Foundation's
    /// generic "isn't in the correct format" — the highest-leverage change for
    /// the paste-back-to-LLM loop on the JSON side.
    private func decodingFailureMessage(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            return "Missing field \"\(key.stringValue)\" \(decodingLocation(context.codingPath))."
        case .typeMismatch(let type, let context):
            return "Expected \(type) \(decodingLocation(context.codingPath))."
        case .valueNotFound(let type, let context):
            return "Missing value of type \(type) \(decodingLocation(context.codingPath))."
        case .dataCorrupted(let context):
            return "Invalid value \(decodingLocation(context.codingPath)): \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }

    /// An empty coding path is a top-level failure — rendering "at ." there
    /// would be noise instead of a location.
    private func decodingLocation(_ codingPath: [CodingKey]) -> String {
        let path = decodingPath(codingPath)
        return path.isEmpty ? "at the top level" : "at \(path)"
    }

    /// Renders a coding path as `lists[0].items[3].quantity`: string keys join
    /// with a leading `.` (except the first), integer keys append as `[n]`.
    private func decodingPath(_ codingPath: [CodingKey]) -> String {
        var result = ""
        for key in codingPath {
            if let intValue = key.intValue {
                result += "[\(intValue)]"
            } else {
                if !result.isEmpty { result += "." }
                result += key.stringValue
            }
        }
        return result
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
