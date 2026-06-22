import SwiftUI
import Domain

struct ListIdentityEditor: View {
    @Binding var title: String
    @Binding var notes: String
    @Binding var icon: String
    @Binding var colorName: String

    var body: some View {
        Form {
            Section("Details") {
                TextField("Title", text: $title)
                    .accessibilityIdentifier("newList.title")
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
                    .accessibilityIdentifier("listIdentity.notes")
            }

            Section("Icon") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 8) {
                    ForEach(ListIcons.curated, id: \.self) { symbol in
                        Button {
                            icon = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.title2)
                                .frame(width: 40, height: 40)
                                .background(
                                    icon == symbol
                                        ? Color.accentColor.opacity(0.2)
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Icon \(symbol)"))
                        .accessibilityValue(icon == symbol ? "Selected" : "Not selected")
                        .accessibilityIdentifier("listIdentity.icon.\(symbol)")
                    }
                }
            }

            Section("Color") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 8) {
                    ForEach(ListColor.allCases, id: \.rawValue) { lc in
                        Button {
                            colorName = lc.rawValue
                        } label: {
                            Circle()
                                .fill(lc.color)
                                .frame(width: 32, height: 32)
                                .overlay {
                                    if colorName == lc.rawValue {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("\(lc.rawValue.capitalized) color"))
                        .accessibilityValue(colorName == lc.rawValue ? "Selected" : "Not selected")
                        .accessibilityIdentifier("listIdentity.color.\(lc.rawValue)")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct ListIdentityEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let original: ListItem
    let onSave: (ListItem) -> Void

    @State private var title: String
    @State private var notes: String
    @State private var icon: String
    @State private var colorName: String

    init(list: ListItem, onSave: @escaping (ListItem) -> Void) {
        original = list
        self.onSave = onSave
        _title = State(initialValue: list.title)
        _notes = State(initialValue: list.notes ?? "")
        _icon = State(initialValue: list.icon ?? "list.bullet")
        _colorName = State(initialValue: list.colorName ?? ListColor.blue.rawValue)
    }

    var body: some View {
        NavigationStack {
            ListIdentityEditor(
                title: $title,
                notes: $notes,
                icon: $icon,
                colorName: $colorName
            )
            .navigationTitle("Edit List")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(trimmedTitle.isEmpty)
                    .accessibilityIdentifier("listIdentity.save")
                }
            }
        }
        .frame(minWidth: 360, minHeight: 460)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        var updated = original
        updated.title = trimmedTitle
        updated.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        updated.icon = icon.nilIfEmpty
        updated.colorName = colorName.nilIfEmpty
        updated.updatedAt = Date()
        onSave(updated)
        dismiss()
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
