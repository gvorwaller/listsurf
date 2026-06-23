import SwiftUI

struct ListsurfHelpView: View {
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HelpCallout(
                        title: "Start here",
                        text: "Listsurf is an outliner. Create lists in the Library, then add, nest, reorder, check, archive, and back up items from the editor."
                    )
                    .accessibilityIdentifier("help.startHere")
                }

                HelpSection(
                    title: "iPhone and iPad touch controls",
                    systemImage: "hand.tap",
                    items: [
                        HelpItem("Bottom action bar", "Appears after you select an item. It contains Below, Child, Indent, Outdent, Move, Details, and Delete."),
                        HelpItem("Indent", "Moves the selected item one level deeper under the item above it."),
                        HelpItem("Outdent", "Moves the selected item one level higher."),
                        HelpItem("Move Up / Move Down", "Reorders the selected item among its siblings."),
                        HelpItem("Keyboard accessory", "While typing a new item, use Below or Child to commit and immediately start the next item in that position.")
                    ]
                )

                HelpSection(
                    title: "Editor basics",
                    systemImage: "list.bullet.indent",
                    items: [
                        HelpItem("Tap a row", "Selects it and shows item controls."),
                        HelpItem("Below", "Starts a new item under the selected row at the same outline level."),
                        HelpItem("Child", "Starts a nested item inside the selected row."),
                        HelpItem("Details", "Opens notes, title, and item metadata."),
                        HelpItem("Trash", "Deletes the selected item after confirmation.")
                    ]
                )

                HelpSection(
                    title: "Library",
                    systemImage: "books.vertical",
                    items: [
                        HelpItem("New List", "Creates a list. Use this for a separate project, packing list, workflow, or reusable checklist."),
                        HelpItem("Archive", "Moves old lists out of the main Library without deleting them."),
                        HelpItem("Import Backup", "Replaces the current local library with a previously exported JSON backup."),
                        HelpItem("Export Backup", "Writes a full-library JSON backup you can inspect or save elsewhere.")
                    ]
                )

                HelpSection(
                    title: "Check mode",
                    systemImage: "checkmark.circle",
                    items: [
                        HelpItem("Toggle Check Mode", "Switches from editing the outline to checking items off."),
                        HelpItem("Parent items", "Parents summarize child progress so a nested checklist is easier to scan."),
                        HelpItem("Back to Edit", "Use the mode button again to return to outline editing.")
                    ]
                )

                HelpSection(
                    title: "Mac use",
                    systemImage: "keyboard",
                    items: [
                        HelpItem("Bulk entry", "The Mac app is useful for entering many items quickly with a hardware keyboard."),
                        HelpItem("Return", "Adds an item below."),
                        HelpItem("Command-Return", "Adds a child item."),
                        HelpItem("Tab / Shift-Tab", "Indent or outdent the selected item.")
                    ]
                )
            }
            .navigationTitle("Listsurf Help")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                        .accessibilityIdentifier("help.done")
                }
            }
        }
        .accessibilityIdentifier("help.sheet")
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 620, minHeight: 520, idealHeight: 680)
        #endif
    }
}

private struct HelpCallout: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct HelpSection: View {
    let title: String
    let systemImage: String
    let items: [HelpItem]

    var body: some View {
        Section {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.term)
                        .font(.headline)
                    Text(item.description)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Label(title, systemImage: systemImage)
        }
    }
}

private struct HelpItem: Identifiable {
    let id = UUID()
    let term: String
    let description: String

    init(_ term: String, _ description: String) {
        self.term = term
        self.description = description
    }
}

#if DEBUG
#Preview {
    ListsurfHelpView {}
}
#endif
