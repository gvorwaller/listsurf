import SwiftUI
import Domain
import Platform

enum ListsurfSettingsKey {
    static let notesPreviewLineLimit = "notesPreviewLineLimit"
    static let lastExportAt = "diagnostics.lastExportAt"
}

public struct ListsurfSettingsView: View {
    @AppStorage(ListsurfSettingsKey.notesPreviewLineLimit) private var notesPreviewLineLimit = 1

    public init() {}

    public var body: some View {
        let lineLimitBinding = Binding(
            get: { max(0, self.notesPreviewLineLimit) },
            set: { self.notesPreviewLineLimit = max(0, $0) }
        )

        #if os(macOS)
        TabView {
            Form {
                displaySection(notesPreviewLineLimit: lineLimitBinding)
            }
            .tabItem {
                Label("Display", systemImage: "text.alignleft")
            }

            Form {
                DataSectionView()
            }
            .tabItem {
                Label("Data", systemImage: "externaldrive")
            }

            Form {
                aboutSection
            }
            .tabItem {
                Label("About", systemImage: "info.circle")
            }
        }
        .frame(width: 480, height: 340)
        .scenePadding()
        #else
        Form {
            displaySection(notesPreviewLineLimit: lineLimitBinding)
            Section("Data") {
                DataSectionView()
            }
            aboutSection
        }
        #endif
    }

    private func displaySection(notesPreviewLineLimit: Binding<Int>) -> some View {
        Section("Display") {
            Picker("Notes under items", selection: notesPreviewLineLimit) {
                Text("Off").tag(0)
                Text("1 line").tag(1)
                Text("2 lines").tag(2)
                Text("3 lines").tag(3)
                Text("4 lines").tag(4)
                Text("5 lines").tag(5)
            }

            Text("Shows the first lines of an item's notes beneath its title. When off, items with notes show a small note icon instead.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: appVersion)
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        if let build, !build.isEmpty {
            return "\(version) (\(build))"
        }
        return version
    }
}

/// Sheet presentation of Settings for iOS. Owns its own chrome, matching the
/// convention that sheet content builds its navigation and dismissal
/// (the bare ListsurfSettingsView stays chrome-free for the macOS Settings scene).
public struct ListsurfSettingsSheet: View {
    let onClose: () -> Void

    public init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    public var body: some View {
        NavigationStack {
            ListsurfSettingsView()
                .navigationTitle("Settings")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: onClose)
                            .accessibilityIdentifier("settings.done")
                    }
                }
        }
    }
}

/// Settings → Data (spec §7.5): read-only counts, store size, store path, and
/// last-export date. `snapshot` uses a double-optional so the view can tell
/// "still loading" (nil) apart from "loaded and unavailable" (`.some(nil)`)
/// from a genuine failed/missing diagnostics reading.
private struct DataSectionView: View {
    @Environment(AppStore.self) private var appStore
    @AppStorage(ListsurfSettingsKey.lastExportAt) private var lastExportAt = 0.0
    @State private var snapshot: DiagnosticsSnapshot??

    var body: some View {
        Group {
            switch snapshot {
            case .none:
                ProgressView()
            case .some(.none):
                Text("Diagnostics unavailable.")
                    .foregroundStyle(.secondary)
            case .some(.some(let snapshot)):
                LabeledContent(
                    "Lists",
                    value: "\(snapshot.activeListCount) active, \(snapshot.archivedListCount) archived"
                )
                LabeledContent("Items", value: "\(snapshot.itemCount)")
                LabeledContent("Database Size", value: sizeText(for: snapshot.storeSizeBytes))

                if let storeURL = snapshot.storeURL {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Store Location")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(storeURL.path)
                            .font(.footnote.monospaced())
                            .truncationMode(.middle)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }

                    #if os(macOS)
                    Button("Reveal in Finder") {
                        FileReveal.revealInFinder(storeURL)
                    }
                    .accessibilityIdentifier("settings.revealStore")
                    #endif
                }

                LabeledContent("Last Export", value: lastExportText)
            }
        }
        .task {
            snapshot = await appStore.loadDiagnostics()
        }
    }

    private func sizeText(for bytes: Int64?) -> String {
        guard let bytes else { return "—" }
        return bytes.formatted(.byteCount(style: .file))
    }

    private var lastExportText: String {
        guard lastExportAt != 0 else { return "Never" }
        let date = Date(timeIntervalSinceReferenceDate: lastExportAt)
        return date.formatted(.dateTime.day().month().year().hour().minute())
    }
}

#if DEBUG
#Preview {
    ListsurfSettingsView()
        .environment(PreviewFixtures.appStore())
}
#endif
