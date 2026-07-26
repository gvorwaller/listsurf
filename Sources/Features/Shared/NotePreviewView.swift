import SwiftUI

/// Truncated notes preview under an item title. The `Text` itself never
/// scrolls internally (nested scrolling steals list scrolling on macOS) and
/// never gets a fixed height (which clips under Dynamic Type) — full notes
/// otherwise live only in the inspector. td-50f035 (plan item 11, Gaylon's
/// decision) adds a user-controlled "more/less" toggle that grows the row
/// IN PLACE to show the whole note instead: still no inline scrolling, just
/// a taller row when expanded.
struct NotePreviewView: View {
    let notes: String
    let lineCount: Int
    let isExpanded: Bool
    let onToggleExpanded: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(notes)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(isExpanded ? nil : max(1, lineCount))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("note.preview")

            if isPossiblyTruncated {
                Button(action: onToggleExpanded) {
                    HStack(spacing: 2) {
                        Text(isExpanded ? "Less" : "More")
                        Image(systemName: "chevron.down")
                            .rotationEffect(isExpanded ? .degrees(180) : .zero)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.15), value: isExpanded)
                .accessibilityIdentifier("note.preview.toggle")
                .accessibilityLabel(isExpanded ? "Collapse note" : "Show full note")
            }
        }
    }

    /// Cheap truncation heuristic (per plan item 11): a note containing a
    /// line break, or long enough to likely overflow the current
    /// Settings line-limit, gets the toggle. False positives (the chevron
    /// shows on a note that wasn't actually clipped) are explicitly
    /// accepted as harmless — worst case an extra tap that changes nothing
    /// visually, never a lost affordance on a note that WAS truncated.
    private var isPossiblyTruncated: Bool {
        notes.contains("\n") || notes.count > lineCount * 40
    }
}
