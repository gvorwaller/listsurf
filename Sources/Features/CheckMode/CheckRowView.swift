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
                }
                .buttonStyle(.plain)
                .frame(width: 16)
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
}
