import SwiftUI
import Domain

struct LibraryRow: View {
    let list: ListItem

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(list.title)
                    .lineLimit(1)
                if let notes = list.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } icon: {
            Image(systemName: list.resolvedIcon)
                .foregroundStyle(ListColor.from(list.colorName))
        }
    }
}
