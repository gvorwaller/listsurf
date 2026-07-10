import Foundation

/// Renders a list as GitHub/Notes-flavored Markdown checkboxes. Export only —
/// see docs/2026-07-10-milestone-3-interchange-spec.md §4.2 / §11 (no Markdown import).
public struct MarkdownExporter: Sendable {
    public init() {}

    /// Renders per design D6. Sibling order = TreeEngine comparator (position, uuidString).
    public func render(list: ListItem, items: [OutlineItem]) -> String {
        let childrenIndex = Dictionary(grouping: items, by: \.parentID)

        func sortedChildren(of parentID: UUID?) -> [OutlineItem] {
            (childrenIndex[parentID] ?? []).sorted { a, b in
                if a.position != b.position { return a.position < b.position }
                return a.id.uuidString < b.id.uuidString
            }
        }

        var lines: [String] = ["# \(list.title)"]

        if let notes = list.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
            lines.append(notes)
        }

        lines.append("")

        func appendNode(_ item: OutlineItem, depth: Int) {
            let indent = String(repeating: "  ", count: depth)
            let box = item.isChecked ? "x" : " "
            var line = "\(indent)- [\(box)] \(item.title)"
            if item.quantity > 1 {
                line += " ×\(item.quantity)"
            }
            lines.append(line)

            if let notes = item.notes {
                let noteIndent = String(repeating: "  ", count: depth + 1)
                for noteLine in notes.components(separatedBy: "\n") {
                    guard !noteLine.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                    lines.append("\(noteIndent)\(noteLine)")
                }
            }

            for child in sortedChildren(of: item.id) {
                appendNode(child, depth: depth + 1)
            }
        }

        for root in sortedChildren(of: nil) {
            appendNode(root, depth: 0)
        }

        return lines.joined(separator: "\n") + "\n"
    }
}
