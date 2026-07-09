import SwiftUI

enum ListsurfSettingsKey {
    static let notesPreviewLineLimit = "notesPreviewLineLimit"
}

public struct ListsurfSettingsView: View {
    @AppStorage(ListsurfSettingsKey.notesPreviewLineLimit) private var notesPreviewLineLimit = 1

    public init() {}

    public var body: some View {
        let lineLimitBinding = Binding(
            get: { max(1, self.notesPreviewLineLimit) },
            set: { self.notesPreviewLineLimit = max(1, $0) }
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
                aboutSection
            }
            .tabItem {
                Label("About", systemImage: "info.circle")
            }
        }
        .frame(width: 460, height: 260)
        .scenePadding()
        #else
        Form {
            displaySection(notesPreviewLineLimit: lineLimitBinding)
            aboutSection
        }
        #endif
    }

    private func displaySection(notesPreviewLineLimit: Binding<Int>) -> some View {
        Section("Display") {
            Picker("Notes under items", selection: notesPreviewLineLimit) {
                Text("1 line").tag(1)
                Text("2 lines").tag(2)
                Text("3 lines").tag(3)
                Text("4 lines").tag(4)
                Text("5 lines").tag(5)
            }

            Text("Controls the visible height of the scrollable notes area in edit and check mode rows.")
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

#Preview {
    ListsurfSettingsView()
}
