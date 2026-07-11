import SwiftUI
import Platform

/// Preview + share sheet for a list's Markdown export (spec D7). ShareLink
/// needs its item eagerly, and sidebar rows don't have items loaded, so the
/// menu action fetches/render first (ContentView.beginShareListMarkdown)
/// and this sheet presents the already-rendered text.
struct MarkdownShareView: View {
    let listTitle: String
    let text: String
    let onDone: () -> Void

    @State private var showingCopiedConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle(listTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDone)
                        .accessibilityIdentifier("markdown.done")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(showingCopiedConfirmation ? "Copied" : "Copy") {
                        GeneralPasteboard.copy(text)
                        showingCopiedConfirmation = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            showingCopiedConfirmation = false
                        }
                    }
                    .accessibilityIdentifier("markdown.copy")
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: text, preview: SharePreview(listTitle))
                        .accessibilityIdentifier("markdown.share")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 400)
        #endif
    }
}

#if DEBUG
#Preview {
    MarkdownShareView(listTitle: "Packing", text: "# Packing\n\n- [ ] Socks\n", onDone: {})
}
#endif
