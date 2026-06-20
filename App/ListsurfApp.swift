import SwiftUI
import Features
import Domain
import Persistence

@main
struct ListsurfApp: App {
    @State private var appStore: AppStore

    init() {
        let stack = PersistenceStack()
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
