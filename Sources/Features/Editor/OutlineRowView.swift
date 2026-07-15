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
    let onToggleCheck: () -> Void
    let onCommitEdit: () -> Void
    let onCancelEdit: () -> Void
    var body: some View {
        HStack(spacing: 6) {
            disclosureIndicator

            checkbox

            titleAndNotes

            Spacer()

            trailingInfo
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
    }

    /// Checkbox anatomy, icon set, identifier, and labels carried verbatim
    /// from `CheckRowView.swift:28-41` (M5 unification, spec §5 Phase 2) —
    /// the iOS UI test asserts these exact accessibility labels.
    private var checkbox: some View {
        Button(action: onToggleCheck) {
            checkIcon
                .font(.title2)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("check.item.\(row.id.uuidString)")
        .accessibilityLabel(
            row.checkState == .checked
                ? "Uncheck \(row.item.title)"
                : "Check \(row.item.title)"
        )
        .accessibilityValue(checkStateDescription)
        .accessibilityHint(row.hasChildren ? "Toggles this branch and all child items" : "Toggles this item")
    }

    @ViewBuilder
    private var checkIcon: some View {
        switch row.checkState {
        case .checked:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .unchecked:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        case .mixed:
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.orange)
        }
    }

    private var checkStateDescription: String {
        switch row.checkState {
        case .checked:
            "Checked"
        case .unchecked:
            "Unchecked"
        case .mixed:
            "Partially checked"
        }
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
                        .strikethrough(row.checkState == .checked)
                        .foregroundStyle(
                            row.item.title.isEmpty || row.checkState == .checked ? .secondary : .primary
                        )

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
