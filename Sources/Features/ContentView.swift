import SwiftUI
import Domain

public struct ContentView: View {
    @Environment(AppStore.self) private var appStore

    public init() {}

    public var body: some View {
        Group {
            if let presentation = appStore.errorStore.current,
               case .storeCorrupted = presentation.error {
                StoreRecoveryView(presentation: presentation)
            } else {
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
                .safeAreaInset(edge: .top, spacing: 0) {
                    if let presentation = appStore.errorStore.current {
                        ErrorBannerView(presentation: presentation) {
                            appStore.errorStore.retryCurrent()
                        } onDismiss: {
                            appStore.errorStore.dismiss()
                        }
                    }
                }
            }
        }
        .task {
            if case .storeCorrupted = appStore.errorStore.current?.error {
                return
            }
            await appStore.loadLists()
        }
    }
}

private struct StoreRecoveryView: View {
    @Environment(AppStore.self) private var appStore
    let presentation: AppErrorPresentation

    var body: some View {
        ContentUnavailableView {
            Label(
                presentation.error.errorDescription ?? "The Database Could Not Be Opened",
                systemImage: "externaldrive.badge.exclamationmark"
            )
        } description: {
            Text(presentation.error.failureReason ?? "Listsurf could not open its local database.")
        } actions: {
            if presentation.canRetry {
                Button(presentation.retryTitle ?? "Retry") {
                    appStore.errorStore.retryCurrent()
                }
                .buttonStyle(.borderedProminent)
            }
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
