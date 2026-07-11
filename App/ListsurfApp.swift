import SwiftUI
import Features
import Domain
import Persistence

@main
struct ListsurfApp: App {
    @State private var appStore: AppStore
    @State private var errorStore: AppErrorStore

    init() {
        let processInfo = ProcessInfo.processInfo
        let stack: PersistenceStack
        if let identifier = processInfo.environment["LISTSURF_UI_TEST_STORE"] {
            stack = PersistenceStack.uiTesting(
                identifier: identifier,
                reset: processInfo.arguments.contains("--ui-testing-reset")
            )
        } else {
            stack = PersistenceStack()
        }

        let errorStore = AppErrorStore()
        let appStore = AppStore(
            listRepository: CoreDataListRepository(stack: stack),
            outlineRepository: CoreDataOutlineRepository(stack: stack),
            errorStore: errorStore,
            diagnostics: CoreDataDiagnostics(stack: stack)
        )
        if let storeLoadError = stack.storeLoadError {
            errorStore.present(
                .storeCorrupted(reason: storeLoadError),
                retryTitle: "Retry Load"
            ) {
                Task { await appStore.loadLists() }
            }
        }
        self._errorStore = State(initialValue: errorStore)
        self._appStore = State(initialValue: appStore)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appStore)
                .environment(errorStore)
        }
        .commands {
            ListsurfCommands()
        }

        #if os(macOS)
        Settings {
            ListsurfSettingsView()
                .environment(appStore)
        }
        #endif
    }
}
