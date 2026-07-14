import SwiftUI
import Domain

/// Which text field currently owns keyboard focus in the editor: the add
/// field, or a specific row's rename field. One focus owner for the whole
/// editor — see `OutlineEditorView`'s `@FocusState private var focus: EditorFocus?`.
enum EditorFocus: Hashable {
    case addField
    case rename(UUID)
}


/// Applies the drag gate at the row's content root — the ONLY place List
/// honors the move trait (a `.moveDisabled` on a nested child is silently
/// ignored; proven at Gate M1, 2026-07-14). `blocked` is editor-computed,
/// so changes re-diff the List and re-register correctly.
///
/// Hover-gated arming (M4 spec D10) is RETIRED (spec Rev 2.4): four designs
/// failed empirically — a runtime `.moveDisabled` flip driven by hover never
/// arms an already-diffed row without also risking the in-flight drag
/// session. Drag is armed at rest, as M4 shipped; click latency is judged
/// at the gate and investigated on its own evidence if it regresses.
struct RowMoveDisabled: ViewModifier {
    /// Editor-owned terms: text entry active, active search, row is part
    /// of a multi-selection.
    let blocked: Bool

    func body(content: Content) -> some View {
        content.moveDisabled(blocked)
    }
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
