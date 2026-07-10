import SwiftUI

/// Truncated notes preview under an item title. A plain line-limited Text:
/// no nested scrolling (which steals list scrolling on macOS) and no fixed
/// heights (which clip under Dynamic Type). Full notes live in the inspector.
struct NotePreviewView: View {
    let notes: String
    let lineCount: Int

    var body: some View {
        Text(notes)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(max(1, lineCount))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("note.preview")
    }
}
