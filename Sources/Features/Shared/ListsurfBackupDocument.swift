import SwiftUI
import UniformTypeIdentifiers

/// Carries any Listsurf export payload — the whole-library backup, a
/// per-list JSON export, or a per-list OPML export. The content type used
/// at write/read time is chosen by the caller (see `exportContentType` in
/// ContentView); this document just wraps the bytes.
struct ListsurfBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .opml] }
    static var writableContentTypes: [UTType] { [.json, .opml] }

    let data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
