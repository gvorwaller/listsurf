import XCTest
@testable import Features

/// D10: per-list export filenames sanitize "/" and ":" to "-", trim
/// whitespace, and fall back to "List" when nothing usable remains.
final class ContentViewExportFilenameTests: XCTestCase {
    @MainActor
    func testPlainTitlePassesThrough() {
        let view = ContentView()
        XCTAssertEqual(view.exportFilename(for: "Packing", ext: "json"), "Packing.json")
    }

    @MainActor
    func testSlashAndColonAreReplacedWithHyphen() {
        let view = ContentView()
        XCTAssertEqual(view.exportFilename(for: "Trip: Maine/Coast", ext: "opml"), "Trip- Maine-Coast.opml")
    }

    @MainActor
    func testWhitespaceIsTrimmed() {
        let view = ContentView()
        XCTAssertEqual(view.exportFilename(for: "  Packing  ", ext: "json"), "Packing.json")
    }

    @MainActor
    func testEmptyAfterSanitizationFallsBackToList() {
        let view = ContentView()
        XCTAssertEqual(view.exportFilename(for: "   ", ext: "json"), "List.json")
        XCTAssertEqual(view.exportFilename(for: "", ext: "opml"), "List.opml")
    }
}
