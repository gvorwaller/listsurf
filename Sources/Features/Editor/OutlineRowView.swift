import SwiftUI
import Domain

/// Which text field currently owns keyboard focus in the editor: the add
/// field, or a specific row's rename field. One focus owner for the whole
/// editor — see `OutlineEditorView`'s `@FocusState private var focus: EditorFocus?`.
enum EditorFocus: Hashable {
    case addField
    case rename(UUID)
}

/// Reference-type text buffer for one rename/add session (td-e7c609). A
/// class, not `@State String`, so the field that renders it can take the
/// per-keystroke render hit in its OWN body — the editor holds the instance
/// and reads/clears `.text` only inside its own imperative handlers (commit,
/// cancel, iOS keyboard-accessory Done/Cancel), never inside a `body` — so
/// typing invalidates just the one field, not the row or the outline List.
@Observable
final class EditorDraftText {
    var text = ""
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
    let isNoteExpanded: Bool
    let renameDraft: EditorDraftText
    let focus: FocusState<EditorFocus?>.Binding
    let onToggleExpand: () -> Void
    let onToggleCheck: () -> Void
    let onToggleNoteExpanded: () -> Void
    let onCommitEdit: () -> Void
    let onCancelEdit: () -> Void
    var body: some View {
        HStack(spacing: 6) {
            disclosureIndicator

            checkbox

            titleAndNotes
                // td-50f035 (plan item 11): `Spacer()` below is also
                // flexible, and with equal default priority it was winning
                // roughly half of the leftover width — found via UI test
                // evidence (the expanded note wrapped into a near-1-column
                // sliver instead of using the row). Higher priority makes
                // this column claim the row's real estate FIRST; the
                // Spacer only takes what's left, which is correct since its
                // whole job is pushing `trailingInfo` to the row's edge.
                .layoutPriority(1)

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
                RenameFieldView(
                    rowID: row.id,
                    draft: renameDraft,
                    focus: focus,
                    onCommit: onCommitEdit,
                    onCancel: onCancelEdit
                )
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
                        NotePreviewView(
                            notes: notes,
                            lineCount: notePreviewLineCount,
                            isExpanded: isNoteExpanded,
                            onToggleExpanded: onToggleNoteExpanded
                        )
                    }
                }
                // td-50f035 (plan item 11): without this, the column sizes
                // to its own content (a short title leaves the note preview
                // just as narrow), so an EXPANDED multi-line note wraps into
                // a tall, cramped sliver instead of using the row's actual
                // available width — found via UI test evidence, not
                // assumption (see the iOS "note preview expand" test).
                .frame(maxWidth: .infinity, alignment: .leading)
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

/// Rename field, extracted from `OutlineRowView.titleAndNotes` (td-e7c609):
/// a small dedicated leaf view whose OWN body reads/writes `draft.text`, so
/// per-keystroke SwiftUI invalidation stops here — `OutlineRowView` never
/// touches `.text` and re-renders only when `row`/`isEditing` actually
/// change. `OutlineEditorView` keeps the full commit/cancel contract (title
/// trimming, `store.updateItemTitle`, the stranded-draft fallback on
/// external session end); this view only forwards the two session-end
/// signals it alone can observe: Return (submit) and Escape.
private struct RenameFieldView: View {
    let rowID: UUID
    @Bindable var draft: EditorDraftText
    let focus: FocusState<EditorFocus?>.Binding
    let onCommit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        TextField("Title", text: $draft.text)
            .focused(focus, equals: .rename(rowID))
            .onSubmit(onCommit)
            .onKeyPress(.escape) {
                onCancel()
                return .handled
            }
            .accessibilityIdentifier("editor.renameField")
    }
}
