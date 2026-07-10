import SwiftUI
import Domain

/// Pure row content. Carries no gestures and no selection painting:
/// selection, click handling, and highlight all belong to the owning List.
struct OutlineRowView: View {
    let row: FlatRow
    let isEditing: Bool
    let notePreviewLineCount: Int
    @Binding var editingText: String
    let onToggleExpand: () -> Void
    let onCommitEdit: () -> Void
    let onCancelEdit: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            disclosureIndicator

            titleAndNotes

            Spacer()

            trailingInfo
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var titleAndNotes: some View {
        if isEditing {
            TextField("Title", text: $editingText)
                .focused($isFocused)
                .onSubmit { onCommitEdit() }
                .onKeyPress(.escape) {
                    onCancelEdit()
                    return .handled
                }
                .onAppear { isFocused = true }
                .accessibilityIdentifier("editor.renameField")
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.item.title.isEmpty ? "Untitled" : row.item.title)
                    .foregroundStyle(row.item.title.isEmpty ? .secondary : .primary)

                if notePreviewLineCount > 0,
                   let notes = row.item.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !notes.isEmpty {
                    NotePreviewView(notes: notes, lineCount: notePreviewLineCount)
                }
            }
        }
    }

    @ViewBuilder
    private var disclosureIndicator: some View {
        if row.hasChildren {
            Button(action: onToggleExpand) {
                Image(systemName: "chevron.right")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .rotationEffect(
                        row.isExpanded ? .degrees(90) : .zero
                    )
                    .animation(.easeInOut(duration: 0.15), value: row.isExpanded)
            }
            .buttonStyle(.plain)
            .frame(width: 16)
        } else {
            Color.clear.frame(width: 16, height: 1)
        }
    }

    @ViewBuilder
    private var trailingInfo: some View {
        if row.item.quantity > 1 {
            Text("×\(row.item.quantity)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }

        if notePreviewLineCount == 0, row.item.notes != nil {
            Image(systemName: "note.text")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }

        if row.hasChildren {
            let p = row.leafProgress
            Text("\(p.checked)/\(p.total)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
    }
}
