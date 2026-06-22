import SwiftUI

struct NewListSheet: View {
    @Binding var title: String
    let onCreate: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New List")
                .font(.title2.bold())

            TextField("List name", text: $title)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("newList.title")
                .onSubmit(onCreate)

            HStack {
                Spacer()

                Button("Cancel", role: .cancel, action: onCancel)

                Button("Create", action: onCreate)
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("newList.create")
            }
        }
        .padding(20)
        .frame(minWidth: 320)
        #if os(macOS)
        .frame(idealWidth: 360)
        #endif
    }
}
