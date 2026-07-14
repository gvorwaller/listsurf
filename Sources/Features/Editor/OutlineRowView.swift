import SwiftUI
import Domain

/// Which text field currently owns keyboard focus in the editor: the add
/// field, or a specific row's rename field. One focus owner for the whole
/// editor — see `OutlineEditorView`'s `@FocusState private var focus: EditorFocus?`.
enum EditorFocus: Hashable {
    case addField
    case rename(UUID)
}

/// Pure row content. Carries no gestures and no selection painting:
/// selection, click handling, and highlight all belong to the owning List.
struct OutlineRowView: View {
    let row: FlatRow
    let isEditing: Bool
    let notePreviewLineCount: Int
    @Binding var editingText: String
    let focus: FocusState<EditorFocus?>.Binding
    let onToggleExpand: () -> Void
    let onCommitEdit: () -> Void
    let onCancelEdit: () -> Void
    /// Non-hover drag-block terms owned by the editor (text entry active,
    /// active search, multi-selection). The row combines this with its own
    /// hover state (macOS) to produce the final `.moveDisabled` value.
    let dragBlocked: Bool
    /// B1 fix (spec §2, Rev 2.2): row-local, not ancestor-shared. A shared
    /// `hoveredDraggableRowID` in the parent re-diffs the whole List on every
    /// hover change and was found (via live instrumentation) to invalidate
    /// the in-flight AppKit drag session — `moveRows` never fired. Row-local
    /// state only re-renders this one row, so the native drag survives.
    #if os(macOS)
    @State private var isContentHovered = false
    #endif

    var body: some View {
        HStack(spacing: 6) {
            disclosureIndicator

            titleAndNotes

            Spacer()

            trailingInfo
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        #if os(macOS)
        .moveDisabled(dragBlocked || !isContentHovered)
        #else
        .moveDisabled(dragBlocked)
        #endif
    }

    @ViewBuilder
    private var titleAndNotes: some View {
        Group {
            if isEditing {
                TextField("Title", text: $editingText)
                    .focused(focus, equals: .rename(row.id))
                    .onSubmit { onCommitEdit() }
                    .onKeyPress(.escape) {
                        onCancelEdit()
                        return .handled
                    }
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
        #if os(macOS)
        .onHover { hovering in
            isContentHovered = hovering
        }
        #endif
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
