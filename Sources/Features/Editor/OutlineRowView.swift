import SwiftUI
import Domain

struct OutlineRowView: View {
    let row: FlatRow
    let isSelected: Bool
    let isEditing: Bool
    @Binding var editingText: String
    let onToggleExpand: () -> Void
    let onCommitEdit: () -> Void
    let onStartEdit: () -> Void
    let onSelect: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            disclosureIndicator

            if isEditing {
                TextField("Title", text: $editingText)
                    .focused($isFocused)
                    .onSubmit { onCommitEdit() }
                    .onAppear { isFocused = true }
            } else {
                Text(row.item.title.isEmpty ? "Untitled" : row.item.title)
                    .foregroundStyle(row.item.title.isEmpty ? .secondary : .primary)
                    .onTapGesture { onSelect() }
                    .onTapGesture(count: 2) { onStartEdit() }
            }

            Spacer()

            trailingInfo
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.selection.opacity(0.18))
            }
        }
        .onTapGesture { onSelect() }
        .onTapGesture(count: 2) { onStartEdit() }
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

        if row.item.notes != nil {
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
