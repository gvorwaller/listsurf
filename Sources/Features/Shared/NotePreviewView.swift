import SwiftUI

struct NotePreviewView: View {
    let notes: String
    let lineCount: Int

    private var previewHeight: CGFloat {
        CGFloat(max(1, lineCount)) * 16
    }

    var body: some View {
        ScrollView(.vertical) {
            Text(notes)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .scrollIndicators(.visible)
        .frame(maxHeight: previewHeight, alignment: .topLeading)
        .accessibilityIdentifier("note.preview")
    }
}
