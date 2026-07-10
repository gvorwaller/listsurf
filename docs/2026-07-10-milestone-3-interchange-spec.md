# Milestone 3 — Interchange: Implementation Spec

**Date**: 2026-07-10
**Author**: Claude (planning agent; all anchors verified against the working tree at commit `5ecb285` + uncommitted changes)
**Scope source**: `docs/2026-07-08-independent-plan-fixes-usability-edge.md` (Milestone 3 + Addendum), `docs/CC-listsurf-V1-plan.md` §Import/Export (lines 412–438) and §Error Handling Strategy (lines 227–233)
**Executor**: an implementation model with no access to this spec's research — everything needed is in this document. Follow `cs.md` rules; they override defaults.

**Exit criterion for the milestone**: a faithful CarbonFin Outliner round-trip — title, nesting, notes, and checked state survive importing a real CarbonFin OPML export, and a Listsurf OPML export opens correctly in CarbonFin (Task M3-9).

**Rev 2 (2026-07-10)**: amended after CODEX2 hostile review — BOM-tolerant sniffing (D11), unknown-element SAX rules (§4.1), spelled-out public init (§4.5), mandatory collision preflight in `addListsAndItems` (§5.1–5.2 — the merge policy would otherwise silently upsert), loaded-store URL for diagnostics (§5.4), retry-recomputation documented as intentional (§6.2), MainActor note (§7.4), broadened escaping tests and baseline wording (§10).

---

## 0. What this milestone delivers

1. **Per-list JSON export** from the list's action menu, and **additive JSON import** ("Import List…") that appends to the library with freshly minted UUIDs. The existing whole-library backup (replace-all) is untouched.
2. **OPML export and import** per list (td-e95f67), interoperable with CarbonFin Outliner and the wider `_note`/`_status` OPML convention. Unknown attributes are ignored without failing the document.
3. **Markdown export per list** via a share/copy sheet (`- [ ]` / `- [x]`, indentation = hierarchy, `×N` quantity, notes as indented continuation lines). Export only.
4. **Diagnostics section** in Settings → Data: store path (Reveal in Finder on macOS), store size, list/item counts, last export date. Read-only; file *metadata* only — never opens the SQLite file.
5. **Import quality as the product feature**: actionable validation errors (good enough to paste back into an LLM chat), the V1-plan import summary flow ("N items imported; K had invalid parents and were placed at root — accept or discard"), and a ready-made LLM prompt in Help that generates importable OPML.

---

## 1. Current-code anchor map (verified)

| Concern | Anchor |
|---|---|
| JSON envelope (`format: "listsurf"`, `schemaVersion: 1`) | `Sources/Domain/Export/ListsurfExport.swift:3-20` |
| `ExportedList` / `ExportedOutlineItem` payload structs | `ListsurfExport.swift:40-88` |
| `ExportService` — `export(lists:)` :106, `encode` :117 (ISO-8601, prettyPrinted+sortedKeys), `decode` :124, `archive(from:)` :130, `validate` :163 | `ListsurfExport.swift:90-231` |
| Strict validation rejects missing parents (`:205-209`) and cycles (`:210`, `validateAcyclicItems` :214) | `ListsurfExport.swift` |
| `ExportValidationError` (11 cases, LocalizedError) | `ListsurfExport.swift:233-272` |
| `AppStore.exportLibrary` (present-only error contract, drains pending item writes) | `Sources/Features/Store/AppStore.swift:151-167` |
| `AppStore.importLibrary` (replace-all; error mapping for `ExportValidationError`/`DecodingError`) | `AppStore.swift:170-191` |
| `AppStore.drainPendingItemWrites` / weak `issuedStores` registry | `AppStore.swift:20, 211-228` |
| `AppStore.duplicateTitle` / `firstAvailableCopyTitle` (title-collision machinery) | `AppStore.swift:230-260` |
| `AppStore.nextListPosition` (max over active+archived, +1.0) | `AppStore.swift:197-201` |
| `presentSaveError` / `presentLoadError` helpers | `AppStore.swift:290-315` |
| `ListRepository` protocol | `Sources/Domain/Repositories/ListRepository.swift:3-19` |
| `replaceAllListsAndItems` (background ctx, rollback-on-error; insert loop at :132-152) | `Sources/Persistence/Repositories/CoreDataListRepository.swift:116-160` |
| `fetchLibraryArchive` (single-transaction snapshot) | `CoreDataListRepository.swift:64-81` |
| `saveListAndItems` (upsert, one transaction) | `CoreDataListRepository.swift:83-114` |
| `TreeEngine.duplicateList` — the reference UUID-remap pattern (idMap, parentID remap) | `Sources/Domain/Tree/TreeEngine.swift:332-371` |
| `TreeEngine.repairInvalidParents` (orphan + cycle repair with counts) | `TreeEngine.swift:616-648` |
| Canonical sibling sort (position asc, `id.uuidString` tie-break) | `TreeEngine.swift:70-73` |
| `AppError` enum (has `importValidation`, `backupExportFailed`) | `Sources/Domain/AppError.swift:3-11` |
| `AppErrorStore.present` (queues, never clobbers) | `Sources/Features/Store/AppErrorStore.swift:15-30` |
| `listActionMenu` (single builder used by ellipsis menu :74-85 AND row contextMenu :85) | `Sources/Features/Library/LibrarySidebar.swift:274-309` |
| `LibrarySidebar` callback-injection pattern | `LibrarySidebar.swift:4-28` |
| Sidebar utility section (Import/Export Backup buttons) | `LibrarySidebar.swift:33-64`; app menu duplicates :113-158 |
| Sidebar owns the window's ONE `.searchable` | `LibrarySidebar.swift:90` |
| `ContentView` fileImporter :91-96, replace-confirm dialog :97-112, fileExporter :113-119 | `Sources/Features/ContentView.swift` |
| `beginExportBackup` (async data → document → present exporter) | `ContentView.swift:144-151` |
| `handleImportSelection` (security-scoped read pattern) | `ContentView.swift:202-220` |
| `handleExportCompletion` (failure → `backupExportFailed`) | `ContentView.swift:230-236` |
| `backupFilename` (en_US_POSIX, `yyyy-MM-dd HH.mm.ss`) | `ContentView.swift:195-200` |
| `PendingLibraryImport` (Identifiable wrapper pattern) | `ContentView.swift:239-243` |
| `ListsurfBackupDocument` (FileDocument, `.json` only) | `Sources/Features/Shared/ListsurfBackupDocument.swift:4-21` |
| App command actions struct (add `importList` here) | `Sources/Features/Commands/ListsurfCommandActions.swift:3-8`; menu items in `ListsurfCommands.swift:18-28` |
| macOS `Settings` scene — **currently receives NO environment objects** | `App/ListsurfApp.swift:51-55` |
| Settings view (macOS TabView :18-35, sections :44-65, iOS sheet wrapper :82-104) | `Sources/Features/Settings/ListsurfSettingsView.swift` |
| `PersistenceStack` — store description/URL wiring :23-41, `newBackgroundContext` :65-69 | `Sources/Persistence/PersistenceStack.swift` |
| Help sections + collapsible `HelpSection` | `Sources/Features/Help/ListsurfHelpView.swift:8-85, 119-149` |
| `ListStore.waitForPendingPersistence` | `Sources/Features/Store/ListStore.swift:182` |
| Module layout: Domain (Foundation only), Persistence→Domain, Features→Domain+Persistence+Platform, Platform (no Domain) | `Package.swift` targets block |
| App Info.plist (no `UTImportedTypeDeclarations` yet; `INFOPLIST_FILE: App/Info.plist` in `project.yml:39`) | `App/Info.plist` |
| Test fakes implementing `ListRepository` (all must gain the new method) | `Tests/FeaturesTests/AppStoreExportImportTests.swift:166-232`, `Tests/FeaturesTests/ListStorePersistenceTests.swift:~340`, `Tests/FeaturesTests/ListStoreUndoTests.swift:~158`, `Sources/Features/PreviewFixtures.swift:~92` |
| Domain codec test style | `Tests/DomainTests/ExportTests.swift` |

---

## 2. OPML research findings (do not re-research; verify against a real file in M3-9)

Web evidence gathered 2026-07-10:

- **Notes**: CarbonFin Outliner imports **and** exports the `_note` attribute (confirmed: Jeffrey Kishner, "OPML Interoperability: CarbonFin Outliner, Workflowy, Fargo.io", 2013 — CarbonFin listed among apps that "support the `_note` attribute, meaning that it will import and export its value"). `_note` was popularized by OmniOutliner; Tinderbox maps it to `$Text` with `&#10;` parsed as paragraph breaks (acrobatfaq.com Tinderbox OPML import docs).
- **Checked state**: the ecosystem convention is `_status="checked"` / `_status="unchecked"`. OmniOutliner's checkbox column exports exactly the values `checked` and `unchecked` under `_status`; Tinderbox documents `_status` as "the non-standard but generally used OPML '_status' attribute" and maps it to `$Checked`. OmniOutliner can also emit `indeterminate` for mixed parents.
- Other producers use `_complete="true"` (Workflowy/Dynalist family) or `checked="true"`. Cheap to accept on import; costs nothing.
- **CarbonFin drops what it doesn't understand**: "Outliner will not preserve OPML data it does not understand. After editing and syncing with Outliner, non-standard OPML data will effectively be removed" (carbonfin.com/help). So `_quantity` (ours, below) will not survive a trip *through* CarbonFin — acceptable, documented lossiness.
- **Quantity**: no ecosystem convention exists. We define `_quantity="N"` following the underscore-attribute convention so other apps ignore it cleanly.
- No verbatim CarbonFin OPML sample was obtainable online (FAQ/help/forums checked). **Therefore M3-9 requires a real CarbonFin export file from the user** before the milestone closes. The codec keeps all attribute names as constants in one file so a mismatch is a two-line fix.

Sources: [CarbonFin FAQ](https://carbonfin.com/faq.html), [CarbonFin Help](https://carbonfin.com/help/), [Kishner OPML interoperability post](https://jeffreykishner.com/2013/10/22/opml-interoperability-carbonfin-outliner-workflowy-fargo-io/), [Tinderbox OPML import (acrobatfaq)](https://www.acrobatfaq.com/atbref9/index/Import/OPMLImport.html), [OmniOutliner OPML export docs](https://support.omnigroup.com/documentation/omnioutliner/mac/5.1.2/en/importing-exporting-and-printing/), [OPML 2.0 spec](http://opml.org/spec2.opml).

---

## 3. Design decisions (decided — do not reopen)

**D1 — Per-list JSON reuses the existing envelope; no scope marker, no schema bump.** A single-list export is a `ListsurfExport` with one entry in `lists`. Rationale: one codec, one validation path, and any Listsurf JSON file works in both commands — "Import Backup…" replaces, "Import List…" appends. Replace-vs-additive is the *user's command*, not a file property. `schemaVersion` stays `1` (no shape change).

**D2 — UUID remapping lives in Domain**, in a new `ImportPlanner` (`Sources/Domain/Export/ImportPlanner.swift`), not in the repository. The repository gains only a dumb insert-only transaction (`addListsAndItems`). Collision policy: **always remint on additive import** — every list ID and item ID in the file is discarded and replaced (pattern: `TreeEngine.duplicateList`, `TreeEngine.swift:350-368`). Never persist a UUID that came from a file via the additive path.

**D3 — Lenient-vs-strict validation split.** Replace-all import keeps today's strict `ExportService.validate` unchanged. Additive import *repairs* what the V1 plan says to repair (missing parents → root; cycles → root, both counted) and *hard-fails* what an LLM/user must fix (wrong format, wrong schemaVersion, duplicate IDs, empty titles, quantity < 1, non-finite position, self-parenting) with messages naming the offending item. Rationale: V1 plan line 231 mandates the placed-at-root summary; hard errors remain actionable for the paste-back-into-LLM loop.

**D4 — One OPML file = one list.** `head><title>` → list title (fallback: filename stem; final fallback `"Imported List"`). The `body`'s direct `<outline>` children become root items. CarbonFin exports one outline per file, and this keeps the additive pipeline single-shaped. OPML export writes `_note`, `_status` (always, both values — tells importers these are checkbox rows), `_quantity` (only when > 1). List-level notes/icon/color are **not** exported to OPML (no convention exists); JSON remains the lossless format.

**D5 — Parser: Foundation `XMLParser` (SAX), hand-built XML writer.** Justification: Domain imports Foundation only (`cs.md` / plan line 220), and `XMLDocument` is **macOS-only** — it does not exist on iOS, so it is not an option for a cross-platform Domain codec. Writing is string-building with a strict escaping helper (§4.1).

**D6 — Markdown export format** (justified inline):
- `# {list title}` heading first, then list notes (if any) as a plain paragraph, blank line, then items. A heading makes the paste useful in Notes/GitHub; in Messages it reads as a title line.
- `- [ ]` / `- [x]` per item, `isChecked` verbatim (parents' displayed state is a presentation-layer computation; the stored flag is the honest value).
- **2 spaces per depth level** — CommonMark-correct for `- ` markers (child content column = 2) and what GitHub/Notes produce.
- Quantity: `Socks ×4` (U+00D7) only when quantity > 1 — reads naturally, survives every renderer.
- **Notes are included**, not omitted: each note line indented to the item's content column + 2 (i.e. `(depth+1)*2` spaces), as plain continuation text. Rationale: notes carry real packing/procedure data; silently dropping them would make "share to Messages" lossy in exactly the cases it matters. Renderers treat the indented lines as continuation of the list item; plain-text readers see aligned annotation.

**D7 — Markdown delivery is a preview sheet, not a bare `ShareLink` in the menu.** The menu button asynchronously fetches items, renders, then presents a sheet with a selectable monospaced preview, a **Copy** button, and a `ShareLink`. Rationale: `ShareLink` requires its item eagerly, but sidebar rows don't have items loaded — building Markdown for every row's menu would fetch on menu open. The sheet also gives macOS a sane surface and Copy directly serves the manual-LLM workflow.

**D8 — Import summary flow**: `prepare` (parse/validate/plan, writes nothing) is separated from `commit` (single insert transaction). If `repairedParentCount == 0`, commit immediately — selecting the new list is the feedback. If repairs occurred, show a summary **sheet** (V1 plan line 231): "Imported {itemCount} items into '{title}'. {K} had invalid parent references and were placed at the root level." with **Add to Library** / **Discard Import** buttons. Discard = the plan is dropped; nothing was written.

**D9 — Imported-list title collisions**: do **not** reuse `duplicateTitle` (a "Copy" suffix misstates provenance). New helper mints `"{title} (Imported)"`, then `"{title} (Imported 2)"`… checked against active + archived + earlier-in-batch titles (mirrors `firstAvailableCopyTitle`, `AppStore.swift:247-260`). Lists whose titles don't collide keep them untouched.

**D10 — File naming**: per-list exports are `"{sanitized title}.json"` / `"{sanitized title}.opml"` (sanitize: replace `/` and `:` with `-`, trim whitespace, fallback `"List"`). Library backup keeps the existing `"Listsurf Backup {date}.json"` (`ContentView.swift:195-200`).

**D11 — Format detection by content, not extension**: strip a UTF-8 BOM (`EF BB BF`) if present, then skip ASCII/Unicode whitespace; first remaining byte `{` → JSON, `<` → OPML, else actionable error. LLM-produced and Windows-saved files routinely carry a BOM and/or the wrong extension; both must sniff correctly (unit-test BOM-prefixed JSON and OPML).

**D12 — iOS vs macOS presentation**: identical flows. `fileExporter`/`fileImporter` and `ShareLink` are available on both platforms at the app's minimum OS. The only platform forks: "Reveal in Finder" (macOS-only, `#if os(macOS)`, via Platform), the Settings presentation that already exists, and pasteboard implementation (UIPasteboard/NSPasteboard in Platform).

**D13 — Dates on import**: JSON preserves `createdAt`/`updatedAt` from the file (real data — never fabricate, never discard). OPML has no date convention; imported OPML items get a single `Date()` captured once per import for all rows (the true in-app creation time — not synthetic).

**D14 — Diagnostics data path**: new `DiagnosticsReading` protocol in Domain, `CoreDataDiagnostics` implementation in Persistence, injected into `AppStore` (Features cannot construct it — it needs the stack). Counts via `NSManagedObjectContext.count(for:)` on a background context; store size by summing `FileManager` size attributes of the store file plus `-wal`/`-shm` sidecars — metadata reads only, the SQLite file is never opened (cs.md rule). "Last export" is device-local presentation state → `UserDefaults`/`@AppStorage` (per Addendum 2 storage rule), key `"diagnostics.lastExportAt"` (Double, `timeIntervalSinceReferenceDate`, `0` = never), written on successful `fileExporter` completion (library and per-list; Markdown share does not count — it is not a file the user can restore from).

---

## 4. Domain layer (pure Swift, Foundation only)

### 4.1 New file `Sources/Domain/Export/OPMLCodec.swift`

```swift
import Foundation

/// One OPML document ⇄ one list. See docs/2026-07-10-milestone-3-interchange-spec.md §2
/// for the attribute conventions (_note / _status / _quantity) and their sources.
public struct OPMLDocument: Equatable, Sendable {
    public var title: String?              // <head><title>, trimmed; nil if absent/empty
    public var nodes: [OPMLOutlineNode]    // body's direct <outline> children
    public init(title: String?, nodes: [OPMLOutlineNode])
}

public struct OPMLOutlineNode: Equatable, Sendable {
    public var text: String                // required, non-empty after trimming
    public var note: String?
    public var isChecked: Bool
    public var quantity: Int               // >= 1
    public var children: [OPMLOutlineNode]
    public init(text: String, note: String? = nil, isChecked: Bool = false,
                quantity: Int = 1, children: [OPMLOutlineNode] = [])
}

public enum OPMLDecodeError: LocalizedError, Equatable, Sendable {
    case malformedXML(line: Int, column: Int, detail: String)
    case notOPML                       // root element is not <opml>
    case missingText(line: Int)        // <outline> without a usable text/title attribute
    case emptyOutline                  // no <outline> elements in <body>

    // errorDescription MUST be actionable enough to paste into an LLM chat:
    // "The file is not valid XML at line 12, column 8: <detail>. Fix the XML and re-export."
    // "The <outline> element at line 9 has no text attribute. Every item needs text=\"…\"."
    // "The root element is not <opml>. Wrap the outline in <opml version=\"2.0\">…</opml>."
    // "The document contains no outline items."
}

public struct OPMLCodec: Sendable {
    public init() {}
    public func encode(list: ListItem, items: [OutlineItem]) -> Data
    public func decode(_ data: Data) throws -> OPMLDocument
}
```

**Encoder** (string building; no XML frameworks needed to write):

```
<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0">
  <head>
    <title>Packing</title>
  </head>
  <body>
    <outline text="Clothing" _status="unchecked">
      <outline text="Socks" _status="checked" _quantity="4" _note="Wool&#10;Thick ones"/>
    </outline>
  </body>
</opml>
```

- Sibling order: `position` ascending, tie-break `id.uuidString` — the exact comparator at `TreeEngine.swift:70-73`. Build a children index with `Dictionary(grouping: items, by: \.parentID)` and walk recursively from `parentID == nil`.
- `_status` is written on **every** outline (`"checked"`/`"unchecked"`); `_note` only when notes is non-nil/non-empty; `_quantity` only when `quantity > 1`.
- **Attribute escaping (the load-bearing detail)**: escape `&`→`&amp;`, `<`→`&lt;`, `>`→`&gt;`, `"`→`&quot;`, and — critically — `\n`→`&#10;`, `\r`→`&#13;`, `\t`→`&#9;`. XML attribute-value normalization converts literal newlines in attributes to spaces on any conformant parse; without `&#10;`, multi-line notes are silently flattened on re-import. (This is why OmniOutliner writes `&#10;` too.) Element text (`<title>`) escapes `&`, `<`, `>`.
- Self-close childless outlines (`/>`); indent 2 spaces per depth for human readability (not semantically required).

**Decoder** (Foundation `XMLParser`, SAX):

- Private `final class Delegate: NSObject, XMLParserDelegate` maintaining an element stack and a node stack.
- Root element must be `opml` (case-insensitive) → else store `.notOPML` and `parser.abortParsing()`.
- `<title>` inside `<head>`: accumulate `foundCharacters` (CDATA arrives via `foundCDATA` — CarbonFin-adjacent apps wrap head titles in CDATA; implement `parser(_:foundCDATA:)` decoding UTF-8 and appending).
- `<outline>` start: read attributes:
  - `text` — fallback to `title` attribute (OPML 1.0 legacy producers). Trim; if empty/absent → store `.missingText(line: parser.lineNumber)` and abort. (Hard error by design D3: actionable for the LLM loop; not silently dropped.)
  - `_note` → note. `XMLParser` decodes `&#10;` back to `\n` automatically.
  - checked, first match wins: `_status` (`"checked"` → true; `"unchecked"`/`"indeterminate"`/anything else → false), else `_complete`, else `complete`, else `checked` — each true iff value lowercased ∈ {`"true"`, `"yes"`, `"1"`, `"checked"`}.
  - `_quantity` → `Int`, used only if ≥ 1; malformed/absent → 1 (a malformed `_quantity` is treated as an unknown attribute — ignored, per "unknown attributes must not invalidate the document").
  - **All other attributes ignored** (`type`, `created`, `expansionState` in head, `_complete` companions, etc.).
- **Unknown elements (load-bearing for invariant 10 — specify, don't improvise)**:
  - The node stack is keyed on `<outline>` elements ONLY. Any `<outline>` attaches to the nearest ancestor `<outline>` on the stack, else to the document root — so outlines nested under unknown wrapper elements (`<body><section><outline …/></section></body>`) are still accepted, parented correctly.
  - `foundCharacters`/`foundCDATA` are accumulated ONLY while the element path is exactly `opml > head > title`. Text anywhere else (including inside `<head><expansionState>`, `<ownerName>`, or unknown body elements) is discarded — it must never leak into the list title.
  - All non-`outline`, non-`head`, non-`title`, non-`body`, non-`opml` elements are ignored entirely (no error, no stack effect).
- On `parser.parse() == false`: if the delegate stored a semantic error, throw that; otherwise throw `.malformedXML(line: parser.lineNumber, column: parser.columnNumber, detail: parser.parserError?.localizedDescription ?? "unknown")`.
  **Trap**: `abortParsing()` makes `parserError` report `NSXMLParserDelegateAbortedParseError` (code 512) — always check the delegate's stored error *first* or every semantic error masquerades as malformed XML.
- After parse: if no outline nodes were collected → throw `.emptyOutline`.
- Keep attribute-name constants (`"text"`, `"_note"`, `"_status"`, `"_quantity"`, …) in one private enum in this file so M3-9 adjustments are localized.

### 4.2 New file `Sources/Domain/Export/MarkdownExport.swift`

```swift
import Foundation

public struct MarkdownExporter: Sendable {
    public init() {}
    /// Renders per design D6. Sibling order = TreeEngine comparator (position, uuidString).
    public func render(list: ListItem, items: [OutlineItem]) -> String
}
```

Golden output shape (this exact shape is a unit-test fixture):

```markdown
# Packing

Trip notes here.

- [ ] Clothing
  - [x] Socks ×4
    Wool
    Thick ones
  - [ ] Shirts ×3
- [ ] Toiletries
```

Rules: heading; optional list-notes paragraph; blank line before the first item; item line = `"  " * depth + "- [" + (isChecked ? "x" : " ") + "] " + title` + (quantity > 1 ? `" ×\(quantity)"` : ``); each note line = `"  " * (depth + 1) + line` for every line of the item's notes (split on `\n`, skip all-whitespace lines); output ends with a single trailing newline.

### 4.3 New file `Sources/Domain/Export/ImportPlanner.swift`

```swift
import Foundation

public struct ImportSummary: Equatable, Sendable {
    public let listCount: Int
    public let itemCount: Int
    /// Missing-parent remaps + cycle repairs, summed. 0 for OPML (XML nesting
    /// cannot express an invalid parent).
    public let repairedParentCount: Int
}

/// Every UUID in `archive` is freshly minted; nothing here exists in the store yet.
public struct AdditiveImportPlan: Sendable {
    public let archive: LibraryArchive
    public let summary: ImportSummary
}

public struct ImportPlanner: Sendable {
    public init() {}
    public func planAdditiveImport(from export: ListsurfExport) throws -> AdditiveImportPlan
    public func planAdditiveImport(from document: OPMLDocument, fallbackTitle: String) -> AdditiveImportPlan
}
```

**JSON path** `planAdditiveImport(from export:)`:
1. Lenient validation — see §4.4. Throws `ExportValidationError` (unchanged type, messages already actionable) for hard failures.
2. Per exported list (pattern = `TreeEngine.duplicateList`, `TreeEngine.swift:350-368`): mint `newListID`; build `idMap: [UUID: UUID]` for its items; rebuild each item with `id: idMap[old]!`, `listID: newListID`, `parentID:` — if the old parent is absent from `idMap`, set `nil` and increment the missing-parent count (this replaces strict validation's `missingParent` rejection). Preserve `title` (trimmed), `notes`, `quantity`, `isChecked`, `position`, `createdAt`, `updatedAt` (D13). List fields preserved including `archivedAt`; list `position` is provisional (AppStore overrides at commit).
3. Run `TreeEngine().repairInvalidParents(in:)` (`TreeEngine.swift:616`) on each list's rebuilt items; add its `orphanCount + cycleCount` to the repair total (orphanCount will be 0 here — step 2 already nils missing parents — but cycles survive remapping and are caught here).
4. Return plan with summary.

**OPML path** `planAdditiveImport(from document:fallbackTitle:)`:
- `title` = document.title (trimmed, non-empty) → else `fallbackTitle` (trimmed, non-empty) → else `"Imported List"`.
- One `now = Date()` for the whole import. Mint `listID`; walk `document.nodes` depth-first; each node → `OutlineItem(id: UUID(), listID:, parentID: parentStackTop, title: node.text, notes: node.note, quantity: node.quantity, isChecked: node.isChecked, position: Double(siblingIndex + 1), createdAt: now, updatedAt: now)`.
- `ListItem(id: listID, title:, position: 1.0 /* provisional */, createdAt: now, updatedAt: now)` — no notes/icon/color (D4).
- `repairedParentCount = 0`. Cannot throw (decoder already guaranteed non-empty, non-blank texts).

### 4.4 Modify `Sources/Domain/Export/ListsurfExport.swift` — parent policy on `validate`

Change `validate` (`:163`) to:

```swift
public enum ParentValidationPolicy: Sendable {
    case reject          // today's behavior — used by replace-all import
    case permitInvalid   // additive import: planner repairs instead
}

public func validate(_ export: ListsurfExport, parentPolicy: ParentValidationPolicy = .reject) throws
```

Under `.permitInvalid`, skip only the missing-parent loop (`:205-209`) and `validateAcyclicItems` (`:210`). Everything else (format `:164`, schemaVersion `:167`, duplicate list/item IDs `:175,:187`, empty titles `:178,:191`, quantity `:194`, position `:197`, self-parent `:200`) still throws. The default parameter keeps `archive(from:)` (`:131`) and all existing callers/tests source-compatible.

Also improve two `ExportValidationError` messages for the LLM loop (they currently print bare UUIDs, which an LLM can't act on — `:257-259`): include the item's title when available is *not* possible inside the enum; instead have **`ImportPlanner`** catch `emptyItemTitle`/`invalidQuantity` and rethrow? — **No. Keep it simple**: leave `ExportValidationError` as-is (UUIDs identify items in a file the user can search), and rely on the improved `DecodingError` mapping in §6.3 for the common LLM failure mode (malformed JSON). Do not redesign the error enum.

### 4.5 New file `Sources/Domain/Diagnostics.swift`

```swift
import Foundation

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
```

---

## 5. Persistence layer

### 5.1 `Sources/Domain/Repositories/ListRepository.swift` — add one requirement

```swift
/// Insert-only append for additive import. Every list and item in the archive
/// carries a freshly minted UUID (the import planner guarantees this), so this
/// is a pure insert: one transaction, and a failed import writes nothing.
/// Throws if any incoming ID already exists — it must never mutate a row.
func addListsAndItems(with archive: LibraryArchive) async throws
```

### 5.2 `Sources/Persistence/Repositories/CoreDataListRepository.swift` — implement

Copy `replaceAllListsAndItems` (`:116-160`) minus the two delete loops (`:120-130`): new background context, `context.perform`, the insert loop verbatim from `:132-152`, `try context.save()`, `catch { context.rollback(); throw error }`.

**MANDATORY collision preflight (same transaction, before the insert loop).** The background context uses `NSMergePolicy.mergeByPropertyObjectTrump` (`PersistenceStack.swift:65-69`), which means a save that violates the `id` uniqueness constraints (`CoreDataModel.swift`) does NOT throw — Core Data resolves it by **silently updating the existing row**. A planner regression that failed to remint even one ID class would therefore mutate user data with no error, violating invariant 1 undetectably. So: fetch counts for incoming list IDs (`id IN %@` on `ListEntity`) and item IDs (on `OutlineItemEntity`); if either count > 0, throw a descriptive error (e.g. `CocoaError(.validationMultipleErrors)`-style custom error naming the collision) and write nothing. This converts a silent upsert into a loud, tested failure.

### 5.3 Update every other `ListRepository` conformance (compiler will enforce)

- `Sources/Features/PreviewFixtures.swift` (~`:92`): append the archive's lists/items to the fixture arrays.
- `Tests/FeaturesTests/AppStoreExportImportTests.swift` fake (`:166-232`): append lists, merge `itemsByList`, and add an `addCount()` accessor (mirrors `replacementCount()` `:225`) so tests can assert additive import never calls replace.
- `Tests/FeaturesTests/ListStorePersistenceTests.swift` (~`:340`) and `Tests/FeaturesTests/ListStoreUndoTests.swift` (~`:158`) fakes: minimal append or `fatalError("unused")`-free no-op consistent with their existing style (read the fakes first; they store items now).

### 5.4 New file `Sources/Persistence/CoreDataDiagnostics.swift`

```swift
public final class CoreDataDiagnostics: DiagnosticsReading, @unchecked Sendable {
    private let stack: PersistenceStack
    public init(stack: PersistenceStack) { self.stack = stack }
    public func snapshot() async throws -> DiagnosticsSnapshot
}
```

- `storeURL`: read the **loaded** store — `stack.container.persistentStoreCoordinator.persistentStores.first?.url` — falling back to `persistentStoreDescriptions.first?.url`. The production path never sets a custom description (`PersistenceStack.swift:18-41`), so the post-load store object is the authoritative source; the description default happens to carry a URL but the loaded store cannot lie. If the store type is `NSInMemoryStoreType` or the URL is nil/`/dev/null`, report `nil`.
- Counts on `stack.newBackgroundContext().perform`: `count(for:)` with `NSFetchRequest<NSNumber>`-style count requests — `ListEntity` with `archivedAt == nil`, `ListEntity` with `archivedAt != nil`, `OutlineItemEntity` unfiltered (predicates mirror `CoreDataListRepository.swift:24,33`).
- `storeSizeBytes`: for suffixes `["", "-wal", "-shm"]`, `FileManager.default.attributesOfItem(atPath:)[.size]`, summing what exists; all-missing → `nil`. Comment explicitly: metadata only; never open or read the SQLite file (cs.md).

---

## 6. AppStore (Features)

All new methods follow the two established contracts: **present-only errors** (present via `errorStore`, return nil/false — never also throw; `AppStore.swift:148-150` comment) and **drain pending item writes before any export/import snapshot** (`AppStore.swift:151-167`).

### 6.1 Per-list export

```swift
/// nil after presenting the failure.
public func exportListJSON(id: UUID, appVersion: String = AppStore.bundleVersion) async -> Data?
public func exportListOPML(id: UUID) async -> Data?
public func exportListMarkdown(id: UUID) async -> String?
```

Shared private helper `fetchListSnapshot(id:) async -> (ListItem, [OutlineItem])?`:
1. `await drainPendingItemWrites()`
2. list = `(lists + archivedLists).first { $0.id == id }`; if nil → `refreshAfterStaleReference(operation:)` pattern (`AppStore.swift:206-209`) and return nil.
3. `items = try await outlineRepo.fetchItems(forList: id)` sorted by the canonical comparator; on throw → `errorStore.present(.persistenceLoad(...))`, return nil.

Then: JSON = `exportService.export(lists: [(list, items)], appVersion:)` + `encode` (existing `:106,:117`); OPML = `OPMLCodec().encode(list:items:)`; Markdown = `MarkdownExporter().render(list:items:)`. Encoding failures present `.backupExportFailed`.

### 6.2 Additive import — prepare/commit

```swift
/// Parses, validates, and plans. Writes nothing. nil after presenting the failure.
public func prepareAdditiveImport(from data: Data, filename: String) async -> AdditiveImportPlan?

/// Persists a prepared plan in one transaction; assigns positions and unique titles.
/// Selects the first imported active list. Present-only errors; true on success.
@discardableResult
public func commitAdditiveImport(_ plan: AdditiveImportPlan) async -> Bool
```

`prepareAdditiveImport`:
- Sniff first non-whitespace byte (D11). `{` → `exportService.decode(from:)` then `ImportPlanner().planAdditiveImport(from:)`. `<` → `OPMLCodec().decode(_)` then `planAdditiveImport(from:fallbackTitle: filename-stem)`. Anything else → present `.importValidation(message: "\"\(filename)\" is neither Listsurf JSON nor OPML. Export a .json backup from Listsurf, or an .opml file from an outliner.")`, return nil.
- Catch `ExportValidationError` and `OPMLDecodeError` → `.importValidation(message: error.localizedDescription)`. Catch `DecodingError` → `.importValidation(message: decodingFailureMessage(error))` (§6.3). Unknown errors → `presentSaveError` retry pattern is wrong here (nothing to retry safely); use `.importValidation` with the localized description.

`commitAdditiveImport`:
- `await drainPendingItemWrites()` first — imports are library-level writes and must not interleave with queued item saves (same contract as export/delete; §6 preamble). While implementing, ALSO add the missing drain to the existing replace-all `importLibrary` (`AppStore.swift:170-191`, currently undrained) — the deleted-list write guard makes the race non-corrupting, but draining makes ordering deterministic.
- Compute `basePosition = (lists + archivedLists).map(\.position).max() ?? 0` once (rationale in `nextListPosition`, `AppStore.swift:197-201` — but computed once because the new lists aren't in `lists` yet); assign `basePosition + 1.0, + 2.0, …` in archive order.
- Titles per D9: maintain `var existing = Set((lists + archivedLists).map(\.title))`; for each list, if title collides, first available of `"{t} (Imported)"`, `"{t} (Imported N)"` (N from 2); insert chosen title into `existing` so a multi-list file can't self-collide.
- `try await listRepo.addListsAndItems(with: adjustedArchive)`; on throw → `presentSaveError(..., operation: "import list", retryTitle: "Try Again") { await self?.commitAdditiveImport(plan) }` (retry re-runs commit — safe: nothing was written, rollback is transaction-level).
- **Retry semantics (intentional, do not "fix")**: retry re-runs the whole commit, INCLUDING recomputing titles/positions against the then-current library. If the user created a list while the error banner sat open, the retried import may get a different "(Imported N)" suffix or position — that is correct behavior: recomputation is what prevents the retried import from colliding with the interim list. The prepared plan (content + minted UUIDs) is what "the failed operation" means here; placement metadata is commit-time by design.
- `await loadLists()`; `selectedListID = first imported list with archivedAt == nil` (leave selection alone if all imported lists are archived); return true.

### 6.3 Actionable `DecodingError` mapping (private helper)

Current `importLibrary` surfaces `error.localizedDescription` for `DecodingError` (`AppStore.swift:182-184`), which is the useless "The data couldn't be read because it isn't in the correct format." Add:

```swift
private func decodingFailureMessage(_ error: DecodingError) -> String
```

Map cases to path-bearing messages, e.g. `.keyNotFound(key, ctx)` → `"Missing field \"\(key.stringValue)\" at \(path(ctx))."`; `.typeMismatch(type, ctx)` → `"Expected \(type) at \(path(ctx))."`; `.dataCorrupted(ctx)` → `"Invalid value at \(path(ctx)): \(ctx.debugDescription)"` — where `path(ctx)` joins `ctx.codingPath` as `lists[0].items[3].quantity`. Use it in **both** `importLibrary` (`:182-184`) and `prepareAdditiveImport`. This is the single highest-leverage change for the paste-back-to-LLM loop on the JSON side.

---

## 7. UI wiring (Features)

### 7.1 UTType + Info.plist (do first inside T6 — everything else references it)

`App/Info.plist`: add (no other Info.plist keys exist for types today):

```xml
<key>UTImportedTypeDeclarations</key>
<array>
  <dict>
    <key>UTTypeIdentifier</key><string>org.opml.opml</string>
    <key>UTTypeDescription</key><string>OPML outline</string>
    <key>UTTypeConformsTo</key><array><string>public.xml</string></array>
    <key>UTTypeTagSpecification</key>
    <dict>
      <key>public.filename-extension</key><array><string>opml</string></array>
      <key>public.mime-type</key><array><string>text/x-opml</string></array>
    </dict>
  </dict>
</array>
```

`project.yml:39` already points `INFOPLIST_FILE` at this file for both platform targets — a plain file edit, **no xcodegen run needed**.

New `Sources/Features/Shared/UTType+OPML.swift`:

```swift
import UniformTypeIdentifiers
extension UTType {
    /// Backed by the imported type declaration in App/Info.plist. Without that
    /// declaration UTType(importedAs:) silently degrades to a dynamic type and
    /// .opml files stop matching in file pickers.
    static var opml: UTType { UTType(importedAs: "org.opml.opml", conformingTo: .xml) }
}
```

### 7.2 `Sources/Features/Shared/ListsurfBackupDocument.swift`

Extend `writableContentTypes`/`readableContentTypes` (`:5-6`) to `[.json, .opml]`. Reason: `fileExporter`'s `contentType` must be a member of the document's `writableContentTypes` or SwiftUI asserts. Keep the type name; add a doc comment that it now carries any per-list/library export payload.

### 7.3 `LibrarySidebar.swift`

- New callbacks in `init` (extend the existing pattern `:16-28`): `onImportList: () -> Void`, `onExportList: (ListItem, ListExportFileFormat) -> Void`, `onShareListMarkdown: (ListItem) -> Void`. Define in `Sources/Features/Shared/ListExportFileFormat.swift`: `enum ListExportFileFormat { case json, opml }`.
- `listActionMenu` (`:274-309`) — insert between "Duplicate & Reset Checks" (`:288-292`) and the Archive divider (`:294`):

```swift
Divider()
Button { onExportList(list, .json) } label: { Label("Export List (JSON)…", systemImage: "square.and.arrow.up") }
    .accessibilityIdentifier("library.list.exportJSON")
Button { onExportList(list, .opml) } label: { Label("Export List (OPML)…", systemImage: "square.and.arrow.up") }
    .accessibilityIdentifier("library.list.exportOPML")
Button { onShareListMarkdown(list) } label: { Label("Share as Markdown…", systemImage: "square.and.arrow.up.on.square") }
    .accessibilityIdentifier("library.list.shareMarkdown")
```

  This single builder feeds both the ellipsis menu (`:74-83`) and the row context menu (`:85`) — do **not** add entries anywhere else per-surface.
- "Import List…" button (`Label("Import List…", systemImage: "square.and.arrow.down.on.square")`, id `library.importList.visible`) in the utility section directly after "Import Backup…" (`:34-39`), and a matching entry in the hamburger app menu after `:145` (id `library.importList`). Also add it to the empty-library actions (`:238-239` area, id `library.importFirstList`) — first-run import is a primary CarbonFin-migration path.

### 7.4 `ContentView.swift`

New state:

```swift
@State private var importMode: LibraryImportMode = .replaceLibrary   // enum { replaceLibrary, additiveList }
@State private var exportContentType: UTType = .json
@State private var pendingAdditiveImport: PendingAdditiveImport?     // Identifiable wrapper: id, filename, plan
@State private var markdownShare: MarkdownShareItem?                 // Identifiable: id, listTitle, text
```

- Pass the three new callbacks into `LibrarySidebar` (`:44-50`): `onImportList: beginImportList`, `onExportList: beginExportList`, `onShareListMarkdown: beginShareListMarkdown`.
- `beginImportList()` sets `importMode = .additiveList; showingImporter = true`. `beginImportBackup()` (`:140-142`) now also sets `importMode = .replaceLibrary`.
- `fileImporter` (`:91-96`): `allowedContentTypes: importMode == .replaceLibrary ? [.json] : [.json, .opml, .xml]`. In `handleImportSelection` (`:202-220`) keep the security-scoped read verbatim; branch on `importMode`: replace → existing `pendingImport` confirm flow unchanged; additive →

```swift
Task {
    guard let plan = await appStore.prepareAdditiveImport(from: data, filename: url.lastPathComponent) else { return }
    if plan.summary.repairedParentCount > 0 {
        pendingAdditiveImport = PendingAdditiveImport(filename: url.lastPathComponent, plan: plan)
    } else {
        await appStore.commitAdditiveImport(plan)
    }
}
```

  (Actor note: `View` is `@MainActor`-annotated, so a plain `Task { }` in a ContentView method inherits MainActor — this matches every existing async flow in the file, e.g. `importPendingBackup`. If the compiler under a future language mode disagrees, annotate `Task { @MainActor in … }`; do not restructure.)

- Import summary sheet: `.sheet(item: $pendingAdditiveImport)` presenting a new small view `ImportSummaryView(filename:summary:onAccept:onDiscard:)` (new file `Sources/Features/Library/ImportSummaryView.swift`): title "Import Needs Review", body `"Imported \(itemCount) item(s) into “\(first list title)”. \(repairedParentCount) had invalid parent references and were placed at the root level."`, prominent **Add to Library** (commits, then clears state) and **Discard Import** (clears state only). `presentationDetents([.medium])`; ids `import.summary.accept` / `import.summary.discard`. (Sheet, not `confirmationDialog` — V1 plan line 231 calls it a summary sheet and the text exceeds dialog comfort.)
- `beginExportList(list:format:)` mirrors `beginExportBackup` (`:144-151`):

```swift
Task {
    let data: Data?
    switch format {
    case .json: data = await appStore.exportListJSON(id: list.id)
    case .opml: data = await appStore.exportListOPML(id: list.id)
    }
    guard let data else { return }
    exportDocument = ListsurfBackupDocument(data: data)
    exportFilename = exportFilename(for: list.title, ext: format == .json ? "json" : "opml")  // D10 sanitize
    exportContentType = format == .json ? .json : .opml
    showingExporter = true
}
```

  `fileExporter` (`:113-119`): change `contentType: .json` → `contentType: exportContentType`; `beginExportBackup` must also set `exportContentType = .json`.
- `handleExportCompletion` (`:230-236`): on `.success`, write `UserDefaults.standard.set(Date().timeIntervalSinceReferenceDate, forKey: "diagnostics.lastExportAt")` (key constant in `ListsurfSettingsKey`, `ListsurfSettingsView.swift:3-5`). Failure branch unchanged.
- `beginShareListMarkdown(list)`: `Task { if let text = await appStore.exportListMarkdown(id: list.id) { markdownShare = MarkdownShareItem(listTitle: list.title, text: text) } }`; `.sheet(item: $markdownShare)` presenting new `Sources/Features/Library/MarkdownShareView.swift`: `NavigationStack` + `ScrollView { Text(item.text).font(.body.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding() }`; toolbar: `ShareLink(item: item.text, preview: SharePreview(item.listTitle))` (id `markdown.share`), a **Copy** button calling the Platform pasteboard helper (§7.6, id `markdown.copy`), and Done. `presentationDetents([.medium, .large])`; macOS `frame(minWidth: 480, minHeight: 400)` (mirror Help sheet sizing, `ListsurfHelpView.swift:98-100`).
- File menu (macOS): add `importList: @MainActor () -> Void` to `ListsurfAppCommandActions` (`ListsurfCommandActions.swift:3-8`), wire it in the `focusedSceneValue` block (`ContentView.swift:71-79`), and add a menu item "Import List…" beside the backup items in `ListsurfCommands.swift:18-28`. **No keyboard shortcut** (bare-key/menu-equivalent trap — and none of the neighbors have one).

### 7.5 Diagnostics in Settings

- `AppStore.init` (`AppStore.swift:22-30`) gains `diagnostics: (any DiagnosticsReading)? = nil` (stored). New method:

```swift
/// nil when unavailable or failed (logged) — the read-only screen shows an
/// inline "unavailable" state instead of an error banner.
public func loadDiagnostics() async -> DiagnosticsSnapshot?
```

- `App/ListsurfApp.swift:24-28`: pass `diagnostics: CoreDataDiagnostics(stack: stack)`. **Required**: the macOS `Settings` scene (`:51-55`) currently has no environment — change to `Settings { ListsurfSettingsView().environment(appStore) }` or the Data section crashes on `@Environment(AppStore.self)`.
- `ListsurfSettingsView.swift`: new `DataSectionView` (same file or `Sources/Features/Settings/DiagnosticsSection.swift`) added as a third macOS tab `Label("Data", systemImage: "externaldrive")` between Display and About (`:18-35` TabView; widen frame height if needed) and as a `Section("Data")` between display and about on iOS (`:37-41`). Content:
  - `@Environment(AppStore.self)`; `@State private var snapshot: DiagnosticsSnapshot??` (nil = loading, `.some(nil)` = unavailable); `.task { snapshot = await appStore.loadDiagnostics() }`.
  - `LabeledContent("Lists", value: "\(active) active, \(archived) archived")`, `LabeledContent("Items", value: itemCount formatted)`, `LabeledContent("Database Size", value: bytes via ByteCountFormatStyle or "—")`.
  - Store path: `Text(url.path)` `.font(.footnote.monospaced())` `.truncationMode(.middle)` `.lineLimit(2)` `.textSelection(.enabled)`; `#if os(macOS)` `Button("Reveal in Finder") { FileReveal.revealInFinder(url) }` (id `settings.revealStore`).
  - `LabeledContent("Last Export", value: …)` from `@AppStorage(ListsurfSettingsKey.lastExportAt) private var lastExportAt = 0.0` — `0` → "Never", else `Date(timeIntervalSinceReferenceDate:)` formatted `.dateTime.day().month().year().hour().minute()`.
  - Unavailable state: `Text("Diagnostics unavailable.")` secondary.
- Update the `#Preview` (`ListsurfSettingsView.swift:106-108`) to `.environment(PreviewFixtures.appStore())` — it will crash without an AppStore in scope once the Data section reads it.

### 7.6 Platform helpers (new files; Platform imports no Domain — `Package.swift`)

- `Sources/Platform/FileReveal.swift`: `#if canImport(AppKit)` → `public enum FileReveal { @MainActor public static func revealInFinder(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) } }`.
- `Sources/Platform/GeneralPasteboard.swift`: `public enum GeneralPasteboard { @MainActor public static func copy(_ string: String) }` — `#if canImport(UIKit)` `UIPasteboard.general.string = string` `#elseif canImport(AppKit)` `NSPasteboard.general.clearContents(); NSPasteboard.general.setString(string, forType: .string)`. (Mirror the platform-split style of `Sources/Platform/Haptics.swift`.)

---

## 8. Help view + LLM prompt (`Sources/Features/Help/ListsurfHelpView.swift`)

1. New collapsible section after "Library" (`:53`), using the existing `HelpSection` type (`:119-149`):

```
HelpSection(title: "Import & Export", systemImage: "square.and.arrow.up.on.square", items: [
  HelpItem("Export a list", "Each list's menu can export JSON (lossless, re-importable), OPML (for outliner apps like CarbonFin Outliner or OmniOutliner), or share Markdown checkboxes into Messages, Mail, or Notes."),
  HelpItem("Import List", "Adds lists from a Listsurf JSON or OPML file to your library. Existing lists are never touched, and imported items get fresh identities — importing twice creates two copies."),
  HelpItem("Import Backup", "Different from Import List: replaces your entire library with a full JSON backup."),
  HelpItem("OPML details", "Titles, nesting, notes, and checked state survive OPML round-trips. Quantities are Listsurf-specific and other apps may drop them."),
  HelpItem("If an import fails", "The error message names the exact problem and location. If an AI generated the file, paste the error back into the same chat and ask it to fix the file.")
])
```

2. LLM prompt block directly below that section: a `Section` containing a short lead-in ("Paste this prompt into any AI chat, then paste your rough list after it. Import the file it returns with Import List."), the prompt in a `.footnote.monospaced()` `Text` with `.textSelection(.enabled)`, and `Button("Copy Prompt") { GeneralPasteboard.copy(Self.llmImportPrompt) }` (id `help.copyPrompt`; flip a `@State` "Copied" label for ~2s feedback). Ship this exact prompt as `static let llmImportPrompt`:

```
Convert the list I paste below into an OPML 2.0 file that the Listsurf app can import.

Rules:
- Output only the XML document — no explanations and no Markdown code fences.
- Start with: <?xml version="1.0" encoding="UTF-8"?>
- Root element: <opml version="2.0"> containing <head><title>NAME OF LIST</title></head> and a <body>.
- Every list item is an <outline> element with a text attribute, e.g. <outline text="Socks"/>.
- Nest sub-items as child <outline> elements inside their parent's <outline>.
- Optional attributes on any item:
  - _note="extra details" for notes
  - _status="checked" or _status="unchecked" for checkbox state
  - _quantity="4" when more than one is needed
- Escape &, <, and double quotes inside attribute values (&amp; &lt; &quot;), and use &#10; for line breaks inside _note.
- Every item must have a non-empty text attribute.

Here is my list:
```

3. Update the existing Library section's "Import Backup" item (`:49`) to note it *replaces* the library and point to Import List for adding.

---

## 9. Invariants (must hold when done)

1. **Additive import never mutates or deletes an existing row.** `addListsAndItems` contains no delete or fetch-existing logic; `replaceAllListsAndItems` call count is 0 in every additive-import test.
2. **No UUID from an import file is ever persisted via the additive path** — lists and items alike. (Import the same file twice → four… i.e., 2× lists with disjoint ID sets.)
3. **A failed or discarded import writes nothing**: prepare never touches the repository; commit is one transaction with rollback.
4. **The replace-all backup flow behaves exactly as before** — same strict validation, same confirm dialog, same `importLibrary` semantics.
5. **Domain still imports Foundation only** (`grep -rn "^import" Sources/Domain` shows only Foundation).
6. **Diagnostics never opens the SQLite file** — Core Data count requests + `FileManager` metadata only.
7. **Present-only error contract everywhere**: no new method both throws to its caller and presents.
8. **Every export path drains pending item writes first** (`drainPendingItemWrites` precedes every snapshot read).
9. **OPML export → OPML import is lossless** for title, hierarchy, order, notes (including newlines/special chars), checked state, and quantity.
10. **Unknown OPML attributes and elements never fail an import.**
11. `listActionMenu` remains the single builder for both the ellipsis menu and context menu — no per-surface copies.
12. No new `.searchable`, no new bare-key or keyed menu equivalents.

---

## 10. Testing & verification

### Unit tests (string-literal fixtures only — no bundle resources; the three xcodegen logic-test targets share source paths and have no resource plumbing)

**`Tests/DomainTests/OPMLCodecTests.swift`**
- Encode→decode round-trip: 3-deep nesting, notes containing `\n`, `\r\n`, `\t`, `&`, `<`, `>`, `"`, the literal text `&amp;`, emoji; mixed checked; quantity 1 and 4; order preserved. (Round-trip equality is the assertion — the same literal strings come back; this rules out double-escaping.)
- Encoded output contains `&#10;` for note newlines and never a raw newline inside an attribute value.
- Unknown ELEMENTS (not just attributes): `<head><expansionState>1,2</expansionState><ownerName>X</ownerName></head>` must not pollute the title; `<body><section><outline text="A"/></section></body>` still yields node A at root; text content inside unknown elements is discarded.
- Encode writes `_status` on every outline; `_quantity` only when > 1; no `_note` when notes nil.
- Decode a CarbonFin-shaped literal: CDATA `<title>`, `expansionState` in head, `_note` + `_status="checked"`, unknown attributes (`created`, `type="link"`) → ignored, values correct.
- Decode variants: `_complete="true"`, `checked="true"`, legacy `title=` attribute fallback, `_status="indeterminate"` → unchecked.
- Errors: truncated XML → `.malformedXML` with line > 0; `<html>` root → `.notOPML`; outline missing text → `.missingText(line:)` with a plausible line; `<body/>` → `.emptyOutline`. Assert `errorDescription` mentions the line number / fix.

**`Tests/DomainTests/MarkdownExportTests.swift`**
- Golden full render (exact string, §4.2 shape).
- No `×` for quantity 1; no continuation lines for nil notes; multi-line notes each on their own indented line.

**`Tests/DomainTests/ImportPlannerTests.swift`**
- JSON: all list/item IDs differ from input; `parentID` remapped consistently (child still points at its parent's *new* ID); dates preserved; summary `{1, n, 0}`.
- Missing parent → item at root, `repairedParentCount == 1`, all items kept.
- Two-item cycle (A↔B) → both repaired to root, counted.
- Duplicate item IDs still throw (`validate(_:parentPolicy: .permitInvalid)` keeps that check); empty title still throws.
- Planning the same export twice → disjoint ID sets.
- OPML: positions 1..n per sibling group; single shared `createdAt`; fallback title used when document title nil; `repairedParentCount == 0`.

**`Tests/DomainTests/ExportTests.swift`** — add: `validate(_:parentPolicy: .permitInvalid)` does NOT throw for a missing parent but still throws for duplicate IDs (guards the refactor).

**`Tests/FeaturesTests/AppStoreExportImportTests.swift`** — extend with the existing fakes (§5.3):
- `prepareAdditiveImport` + `commitAdditiveImport` (JSON): existing list untouched; new list appended with position > existing max; selection = imported list; `addCount() == 1`; `replacementCount() == 0`.
- Title collision → `"Packing (Imported)"`; second import → `"Packing (Imported 2)"`.
- OPML data (string literal) through prepare+commit → hierarchy persisted (parent/child relationship via new IDs).
- Garbage data → prepare returns nil, `.importValidation` presented, `addCount() == 0`.
- BOM-prefixed JSON and BOM-prefixed OPML both sniff and import correctly (D11).
- Plan with repairs: prepare alone writes nothing (`addCount() == 0` until commit).
- `exportListJSON/OPML/Markdown`: happy path content checks; repo-throw → nil + error presented (add a throwing-fetch flag to the outline fake).

**`Tests/PersistenceTests/`** (real in-memory Core Data via `PersistenceStack.inMemory()`, style of `PersistenceStackTests.swift`)
- `addListsAndItems` inserts alongside pre-existing rows; both fetchable afterward.
- **Collision preflight (guards invariant 1 against the silent-upsert merge policy)**: `addListsAndItems` with an archive reusing an EXISTING list ID → throws, and the existing row is unchanged afterward; same for an existing item ID.
- `CoreDataDiagnostics.snapshot()`: counts match seeded data; in-memory store → `storeURL == nil`, `storeSizeBytes == nil`.

### Manual verification checklist (both platforms unless noted)

1. Export a nested, partially-checked list as JSON → "Import List…" the same file → appended copy `"… (Imported)"`, all IDs new, original untouched; repeat → `"(Imported 2)"`.
2. Hand-corrupt the JSON (`"parentID": "<random UUID>"` on one item) → import shows the summary sheet with the exact V1-plan wording; **Discard** leaves the library unchanged; re-import + **Add to Library** places the item at root.
3. Export OPML → re-import → title/nesting/notes(with newlines)/checked/quantity identical. Open the .opml in a text editor: `&#10;` present, `_status` on every row.
4. Paste the Help prompt + a rough list into an LLM, import the produced file. Break the file (remove a `text` attr) → error message names the line; paste it back to the LLM → fixed file imports.
5. Markdown share: preview correct, Copy puts text on pasteboard, ShareLink opens the share picker (macOS + iOS).
6. Settings → Data: counts match library, size plausible, Reveal in Finder selects `Listsurf.sqlite` (macOS), Last Export updates after any file export, "Never" on fresh install.
7. Import Backup (replace-all) still works exactly as before, including the destructive confirmation.
8. **CarbonFin round-trip (exit criterion, M3-9)**: real CarbonFin OPML export imports faithfully; Listsurf OPML export uploads/opens in CarbonFin (outliner.carbonfin.com) with hierarchy, notes, and checks intact. If CarbonFin's attribute names differ from `_status`/`_note`, fix the constants in `OPMLCodec.swift` and add a fixture-literal regression test.

### Build verification
Record the pre-M3 `swift test` count at task start (112 at spec time — but measure, don't trust this number); the count must only grow, never shrink except for explicitly removed tests. Then `xcodebuild test` for both test plans (`Listsurf_macOS.xctestplan`, `Listsurf_iOS.xctestplan`) and both app schemes build. Note memory rule: don't run tests/builds if Codex is working in parallel without checking with the user first.

---

## 11. Non-goals & guardrails (do NOT do these)

- **No Markdown import.** It is not nearly-free: checkbox dialects, tab-vs-space indent ambiguity, and lazy-continuation parsing make it a real parser project. The V1-plan path for text ingestion is multiline paste (separate feature) and OPML-via-LLM.
- No CSV, plain-text file import, or whole-library OPML (per-list only).
- No auto-sync, folder watching, iCloud/CloudKit anything (V1.1, td-aad4ca).
- No undo for imports — consistent with list-level operations today (create/duplicate/import-backup are not undoable; deleting the imported list is the recovery). The V1-plan "import undoable" line is superseded by the accept/discard sheet for this milestone.
- No export entries in the detail-view toolbar or item menus — the list's action menu is the single surface this milestone.
- No live database viewer, no SQL, no reading SQLite contents in Diagnostics.
- No Foundation Models / AI parsing in-app (Milestone 6).
- No new settings toggles (Diagnostics is read-only display).
- No schemaVersion bump; no changes to `ListsurfExport` field shapes.
- Do not rename or "clean up" existing export APIs beyond the specified `validate` parameter addition.

**Trap registry, mapped to this milestone**:
- *Bare-key menu equivalents intercept macOS text fields* → no keyboard shortcuts on any new menu item.
- *One `.searchable` per macOS window* (sidebar owns it, `LibrarySidebar.swift:90`; NSToolbar crash documented in devlog 2026-07-09) → none of the new sheets/sections add `.searchable`.
- *Per-surface action copies drift* → all list actions stay inside `listActionMenu`.
- *Store-owned vs view-local state lifecycle* → the additive-import plan lives in ContentView state only until commit; commit path is the single writer.
- *XML attribute newline normalization* → `&#10;` on encode (§4.1) — this is the difference between passing and failing round-trip test 3.
- *`XMLDocument` is macOS-only* → `XMLParser` everywhere.
- *`abortParsing` masks semantic errors as code 512* → check delegate-stored error first.
- *`fileExporter` contentType ∉ `writableContentTypes` asserts* → §7.2 before §7.4.
- *macOS `Settings` scene has no environment* → §7.5 App change is mandatory, and the Settings `#Preview` needs a fixture store.
- *`UTType(importedAs:)` without the Info.plist declaration silently yields a dynamic type* → §7.1 first.
- *NSUndoManager redo re-registration* — not touched this milestone; do not modify undo code.

---

## 12. Proposed td task breakdown (ordered; each independently verifiable)

Create as tasks under epic `td-0f2c1a` (or as children of `td-a8cd2e` "Phase 4: Interchange"); link M3-2/M3-9 to feature `td-e95f67` (OPML).

| # | Title | Depends on | Verify by | Size |
|---|-------|-----------|-----------|------|
| M3-1 | Domain: OPML codec (encode/decode, errors, escaping) — §4.1 | — | `OPMLCodecTests` green via `swift test` | M |
| M3-2 | Domain: Markdown exporter — §4.2 | — | `MarkdownExportTests` golden string | S |
| M3-3 | Domain: ImportPlanner + `validate` parentPolicy refactor — §4.3–4.4 | — | `ImportPlannerTests` + updated `ExportTests` | M |
| M3-4 | Persistence: `addListsAndItems` on protocol + Core Data + all 4 fakes — §5.1–5.3 | — | new `PersistenceTests` case; whole suite compiles | S |
| M3-5 | AppStore: per-list exports, prepare/commit additive import, `decodingFailureMessage` — §6 | M3-1..4 | extended `AppStoreExportImportTests` | M |
| M3-6 | UI: Info.plist UTType, document types, sidebar menu + Import List, ContentView importer/exporter modes, summary sheet, Markdown share sheet, File-menu item — §7.1–7.4, §7.6 (pasteboard) | M3-5 | manual checklist items 1–5, 7; both platforms build | L |
| M3-7 | Diagnostics: Domain protocol, `CoreDataDiagnostics`, AppStore injection + Settings scene environment, Data section UI, `FileReveal`, lastExportAt writes — §4.5, §5.4, §7.5 | M3-6 (shares ContentView/App edits) | manual checklist 6; `CoreDataDiagnostics` unit test | M |
| M3-8 | Help: Import & Export section + shipped LLM prompt + Copy button — §8 | M3-1 (format frozen) | manual checklist 4; help renders both platforms | S |
| M3-9 | CarbonFin round-trip verification with a real export file (**request the file from the user**); adjust codec constants + add regression fixture if needed | M3-6 | manual checklist 8 — **milestone exit criterion** | S–M |
| M3-10 | Full verification pass (`swift test`, both xctestplans, both builds) + devlog entry | all | all green; devlog written | S |

M3-1 through M3-4 are mutually independent (parallelizable). M3-7 and M3-8 can proceed in parallel after their deps.

---

## 13. Open item deliberately left to M3-9

Only one: whether CarbonFin's real exports use exactly `_status="checked"/"unchecked"`. All research points there (§2), the parser already accepts three checked-attribute spellings, and the attribute names are constants in one file. Everything else in this spec is decided.

## 14. Real CarbonFin fixture facts (rev 3, 2026-07-10 — `docs/fixtures/Maine_packing_list.opml`)

A real CarbonFin export is now in the repo. Verified facts, binding on M3-1:

- `<opml version='1.0'>` — NOT 2.0, and attributes are single-quoted. The decoder must accept any or missing `version` attribute (never validate it) — `XMLParser` handles both quote styles natively. Our encoder still writes 2.0/double quotes (both valid XML; CarbonFin reads standard XML).
- `_note` confirmed in the wild, exactly as §2 predicted.
- `_status` is ABSENT — the exported list simply has no checked items, so the checked-state attribute remains unverified until M3-9 does a round-trip with checked items. The multi-spelling import tolerance (§4.1) stands.
- Head contains only `<title>`; childless outlines are self-closed (` />`).
- The "From Notes" item's `_note` is a multi-line note flattened to one line with space runs — real-world proof of the attribute newline-normalization trap (§4.1); CarbonFin's own encoder loses newlines, ours must not.
- Add to `OPMLCodecTests`: a reduced CarbonFin-shape string literal (version='1.0', single-quoted attributes, `_note`, 4-deep nesting, self-closed leaves) asserting title, hierarchy depth, and note values decode correctly.
