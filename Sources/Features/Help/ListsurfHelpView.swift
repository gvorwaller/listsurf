import SwiftUI
import Platform

struct ListsurfHelpView: View {
    let onClose: () -> Void
    @State private var showingCopiedConfirmation = false

    static let llmImportPrompt = """
        Convert the list I paste below into an OPML 2.0 file that the Listsurf app can import.

        Rules:
        - Output only the XML document — no explanations and no Markdown code fences.
        - Start with: <?xml version="1.0" encoding="UTF-8"?>
        - Root element: <opml version="2.0"> containing <head><title>NAME OF LIST</title></head> and a <body>.
        - Every list item is an <outline> element with a text attribute, e.g. <outline text="Socks"/>.
        - Nest sub-items as child <outline> elements inside their parent's <outline>.
        - Optional attributes on any item:
          - _note="extra details" for notes
          - _status="checked" or _status="unchecked" for checkbox state
          - _quantity="4" when more than one is needed
        - Escape &, <, and double quotes inside attribute values (&amp; &lt; &quot;), and use &#10; for line breaks inside _note.
        - Every item must have a non-empty text attribute.

        Here is my list:
        """

    private static var dragReorderHelpText: String {
        #if os(macOS)
        "Drag a row to reorder it among its siblings."
        #else
        "Touch and hold a row, then drag to reorder."
        #endif
    }

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
                        HelpItem("Trash", "Deletes the item after confirmation."),
                        HelpItem("Reorder", Self.dragReorderHelpText)
                    ]
                )

                HelpSection(
                    title: "Library",
                    systemImage: "books.vertical",
                    items: [
                        HelpItem("New List", "Creates a list. Use this for a separate project, packing list, workflow, or reusable checklist."),
                        HelpItem("Duplicate", "Copies a list under a new name — with or without its checks — so a refined list can be reused."),
                        HelpItem("Archived Lists", "Archiving moves old lists out of the main Library without deleting them. Open Archived Lists and use Restore to bring one back."),
                        HelpItem("Import Backup", "Replaces your entire library with a previously exported JSON backup. This is different from Import List, which only adds — use Import List to add lists without replacing anything."),
                        HelpItem("Export Backup", "Writes a full-library JSON backup you can inspect or save elsewhere."),
                        HelpItem("Settings", "Display options, including how many lines of an item's notes appear beneath its title.")
                    ]
                )

                HelpSection(
                    title: "Import & Export",
                    systemImage: "square.and.arrow.up.on.square",
                    items: [
                        HelpItem("Export a list", "Each list's menu can export JSON (lossless, re-importable), OPML (for outliner apps like CarbonFin Outliner or OmniOutliner), or share Markdown checkboxes into Messages, Mail, or Notes."),
                        HelpItem("Import List", "Adds lists from a Listsurf JSON or OPML file to your library. Existing lists are never touched, and imported items get fresh identities — importing twice creates two copies."),
                        HelpItem("Import Backup", "Different from Import List: replaces your entire library with a full JSON backup."),
                        HelpItem("OPML details", "Titles, nesting, notes, and checked state survive OPML round-trips. Quantities are Listsurf-specific and other apps may drop them."),
                        HelpItem("If an import fails", "The error message names the exact problem and location. If an AI generated the file, paste the error back into the same chat and ask it to fix the file.")
                    ]
                )

                Section {
                    Text("Paste this prompt into any AI chat, then paste your rough list after it. Import the file it returns with Import List.")
                        .foregroundStyle(.secondary)
                    Text(Self.llmImportPrompt)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                    Button(showingCopiedConfirmation ? "Copied" : "Copy Prompt") {
                        GeneralPasteboard.copy(Self.llmImportPrompt)
                        showingCopiedConfirmation = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            showingCopiedConfirmation = false
                        }
                    }
                    .accessibilityIdentifier("help.copyPrompt")
                } header: {
                    Label("LLM Prompt", systemImage: "sparkles")
                }

                HelpSection(
                    title: "Checking off items",
                    systemImage: "checkmark.circle",
                    items: [
                        HelpItem("Checkbox", "Tap or click the circle beside a title to check or uncheck it. Checking a parent checks its whole branch."),
                        HelpItem("Parent items", "Parents summarize child progress (a dash means some but not all children are checked) so a nested checklist is easier to scan."),
                        HelpItem("Filters", "Show All, Remaining, or Completed items. New items always start unchecked, so adding one while Completed is filtered switches back to All."),
                        HelpItem("Reset All Checks", "Unchecks every item in the list, after confirmation."),
                        HelpItem("Reset Branch", "From an item's menu: unchecks that item and all of its children, after confirmation.")
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
