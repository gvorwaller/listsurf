import SwiftUI

struct NewListSheet: View {
    @Binding var title: String
    @Binding var notes: String
    @Binding var icon: String
    @Binding var colorName: String
    let onCreate: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ListIdentityEditor(
                title: $title,
                notes: $notes,
                icon: $icon,
                colorName: $colorName
            )
            .onSubmit(onCreate)
            .navigationTitle("New List")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel, action: onCancel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: onCreate)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("newList.create")
                }
            }
        }
        .frame(minWidth: 360, minHeight: 460)
    }
}
