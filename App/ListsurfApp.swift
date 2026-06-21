import SwiftUI
import Features
import Domain
import Persistence

@main
struct ListsurfApp: App {
    @State private var appStore: AppStore

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
        self._appStore = State(initialValue: AppStore(
            listRepository: CoreDataListRepository(stack: stack),
            outlineRepository: CoreDataOutlineRepository(stack: stack)
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appStore)
        }
        .commands {
            ListsurfCommands()
        }
    }
}
