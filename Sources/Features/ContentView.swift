import SwiftUI
import Domain

public struct ContentView: View {
    @Environment(AppStore.self) private var appStore

    public init() {}

    public var body: some View {
        NavigationSplitView {
            LibrarySidebar()
        } detail: {
            if let selectedID = appStore.selectedListID {
                ListDetailView(listID: selectedID)
            } else {
                ContentUnavailableView(
                    "Select a List",
                    systemImage: "list.bullet.indent",
                    description: Text("Choose a list from the sidebar, or create a new one.")
                )
            }
        }
        .task {
            await appStore.loadLists()
        }
    }
}

#if DEBUG
#Preview("Library") {
    ContentView()
        .environment(PreviewFixtures.appStore())
}

#Preview("Selected List") {
    ContentView()
        .environment(PreviewFixtures.appStore(selected: true))
}
#endif
