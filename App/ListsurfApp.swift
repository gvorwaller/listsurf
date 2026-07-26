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
        let userDefaults: UserDefaults
        if let identifier = processInfo.environment["LISTSURF_UI_TEST_STORE"] {
            let reset = processInfo.arguments.contains("--ui-testing-reset")
            stack = PersistenceStack.uiTesting(identifier: identifier, reset: reset)
            userDefaults = Self.isolatedUserDefaults(identifier: identifier, reset: reset)
        } else {
            stack = PersistenceStack()
            userDefaults = .standard
        }

        let errorStore = AppErrorStore()
        let appStore = AppStore(
            listRepository: CoreDataListRepository(stack: stack),
            outlineRepository: CoreDataOutlineRepository(stack: stack),
            errorStore: errorStore,
            diagnostics: CoreDataDiagnostics(stack: stack),
            userDefaults: userDefaults
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
        Window("Keyboard Legend", id: "keyboard-legend") {
            KeyboardLegendView()
        }
        .defaultSize(width: 520, height: 620)
        .windowResizability(.contentSize)
        .windowLevel(.floating)
        .restorationBehavior(.disabled)

        Settings {
            ListsurfSettingsView()
                .environment(appStore)
        }
        #endif
    }

    /// UI tests must not read/write `lastSelectedListID` (plan item 12b) in
    /// the real `UserDefaults.standard` domain — that would leak the
    /// previously-selected list across UI test runs the same way an
    /// unscoped sqlite store would leak items. Mirrors
    /// `PersistenceStack.uiTesting`'s per-identifier isolation.
    private static func isolatedUserDefaults(identifier: String, reset: Bool) -> UserDefaults {
        let safeIdentifier = identifier.replacingOccurrences(
            of: "[^A-Za-z0-9_-]",
            with: "-",
            options: .regularExpression
        )
        let suiteName = "net.vorwaller.listsurf.uitests.\(safeIdentifier)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        if reset {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
