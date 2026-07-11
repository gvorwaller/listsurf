import Foundation

#if canImport(AppKit)
import AppKit

public enum FileReveal {
    @MainActor
    public static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
#endif
