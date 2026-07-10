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
                        HelpItem("Rename", "Edits the item title in place — from the row menu, or double-click on Mac."),
                        HelpItem("Details", "Opens notes, quantity, and item metadata in the inspector."),
                        HelpItem("Trash", "Deletes the item after confirmation.")
                    ]
                )

                HelpSection(
                    title: "Library",
                    systemImage: "books.vertical",
                    items: [
                        HelpItem("New List", "Creates a list. Use this for a separate project, packing list, workflow, or reusable checklist."),
                        HelpItem("Duplicate", "Copies a list under a new name — with or without its checks — so a refined list can be reused."),
                        HelpItem("Archived Lists", "Archiving moves old lists out of the main Library without deleting them. Open Archived Lists and use Restore to bring one back."),
                        HelpItem("Import Backup", "Replaces the current local library with a previously exported JSON backup."),
                        HelpItem("Export Backup", "Writes a full-library JSON backup you can inspect or save elsewhere."),
                        HelpItem("Settings", "Display options, including how many lines of an item's notes appear beneath its title.")
                    ]
                )

                HelpSection(
                    title: "Check mode",
                    systemImage: "checkmark.circle",
                    items: [
                        HelpItem("Toggle Check Mode", "Switches from editing the outline to checking items off. On Mac: Shift-Command-E."),
                        HelpItem("Parent items", "Parents summarize child progress so a nested checklist is easier to scan."),
                        HelpItem("Filters", "Show all, only unchecked, or only checked items."),
                        HelpItem("Back to Edit", "Use the mode button again to return to outline editing.")
                    ]
                )

                HelpSection(
                    title: "Mac keyboard",
                    systemImage: "keyboard",
                    items: [
                        HelpItem("Arrow keys", "Move the selection up and down the outline. Command-click or Shift-click selects multiple items."),
                        HelpItem("Return", "Starts a new item below the selection."),
                        HelpItem("Shift-Return", "Inserts an item above the selection and renames it."),
                        HelpItem("Command-Return", "Starts a child item inside the selection."),
                        HelpItem("Tab / Shift-Tab", "Indents or outdents the selected item (also Command-] / Command-[ from the Item menu)."),
                        HelpItem("Command-Option-Up / Down", "Moves the selected item among its siblings."),
                        HelpItem("Double-click", "Renames the item in place. Escape cancels; clicking elsewhere commits."),
                        HelpItem("Command-Delete", "Deletes the selected items after confirmation."),
                        HelpItem("Command-Z / Shift-Command-Z", "Undo and redo any edit, including checks."),
                        HelpItem("Shift-Command-E", "Toggles Check Mode."),
                        HelpItem("Option-Command-I", "Toggles the inspector."),
                        HelpItem("Command-N", "Creates a new list."),
                        HelpItem("Command-Comma", "Opens Settings.")
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
    // Persisted per section so collapse choices survive reopening Help.
    @AppStorage private var isExpanded: Bool

    init(title: String, systemImage: String, items: [HelpItem]) {
        self.title = title
        self.systemImage = systemImage
        self.items = items
        _isExpanded = AppStorage(wrappedValue: true, "help.expanded.\(title)")
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.term)
                        .font(.headline)
                    Text(item.description)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
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
