import SwiftUI
import Domain

/// Presented when an additive import repaired at least one invalid parent
/// reference (spec D8). If `repairedParentCount == 0` the plan is committed
/// immediately with no sheet — selecting the new list is the feedback.
struct ImportSummaryView: View {
    let filename: String
    let listTitle: String
    let summary: ImportSummary
    let onAccept: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Needs Review")
                .font(.title2.bold())

            Text(bodyText)
                .foregroundStyle(.secondary)

            Spacer()

            HStack {
                Button("Discard Import", role: .cancel, action: onDiscard)
                    .accessibilityIdentifier("import.summary.discard")

                Spacer()

                Button("Add to Library", action: onAccept)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("import.summary.accept")
            }
        }
        .padding()
    }

    private var bodyText: String {
        "Imported \(summary.itemCount) item(s) into \u{201C}\(listTitle)\u{201D}. \(summary.repairedParentCount) had invalid parent references and were placed at the root level."
    }
}

#if DEBUG
#Preview {
    ImportSummaryView(
        filename: "Packing.json",
        listTitle: "Packing",
        summary: ImportSummary(listCount: 1, itemCount: 12, repairedParentCount: 2),
        onAccept: {},
        onDiscard: {}
    )
}
#endif
