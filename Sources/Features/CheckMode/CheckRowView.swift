import SwiftUI
import Domain

struct CheckRowView: View {
    let row: FlatRow
    let onToggle: () -> Void
    let onToggleExpand: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if row.hasChildren {
                Button(action: onToggleExpand) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .rotationEffect(row.isExpanded ? .degrees(90) : .zero)
                        .animation(.easeInOut(duration: 0.15), value: row.isExpanded)
                }
                .buttonStyle(.plain)
                .frame(width: 16)
                .accessibilityLabel(row.isExpanded ? "Collapse \(row.item.title)" : "Expand \(row.item.title)")
                .accessibilityHint("Shows or hides child items")
            } else {
                Color.clear.frame(width: 16, height: 1)
            }

            Button(action: onToggle) {
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

            VStack(alignment: .leading, spacing: 2) {
                Text(row.item.title)
                    .strikethrough(row.checkState == .checked)
                    .foregroundStyle(row.checkState == .checked ? .secondary : .primary)

                if row.hasChildren {
                    let p = row.leafProgress
                    Text("\(p.checked)/\(p.total)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }

            Spacer()

            if row.item.quantity > 1 {
                Text("×\(row.item.quantity)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
        .accessibilityElement(children: .contain)
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
}
