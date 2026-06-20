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
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
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
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
