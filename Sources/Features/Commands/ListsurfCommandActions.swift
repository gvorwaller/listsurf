import SwiftUI

struct ListsurfAppCommandActions {
    let newList: @MainActor () -> Void
    let importBackup: @MainActor () -> Void
    let exportBackup: @MainActor () -> Void
    let showHelp: @MainActor () -> Void
    let importList: @MainActor () -> Void
}

struct ListsurfListCommandActions {
    var addBelow: (@MainActor () -> Void)?
    var addAbove: (@MainActor () -> Void)?
    var addChild: (@MainActor () -> Void)?
    var indent: (@MainActor () -> Void)?
    var outdent: (@MainActor () -> Void)?
    var moveUp: (@MainActor () -> Void)?
    var moveDown: (@MainActor () -> Void)?
    var rename: (@MainActor () -> Void)?
    var toggleChecked: (@MainActor () -> Void)?
    var delete: (@MainActor () -> Void)?
    var resetAllChecks: (@MainActor () -> Void)?
    var setFilter: (@MainActor (ListStore.CheckFilter) -> Void)?
    var toggleInspector: (@MainActor () -> Void)?
    var expandAll: (@MainActor () -> Void)?
    var collapseAll: (@MainActor () -> Void)?
}

private struct ListsurfAppCommandActionsKey: FocusedValueKey {
    typealias Value = ListsurfAppCommandActions
}

private struct ListsurfListCommandActionsKey: FocusedValueKey {
    typealias Value = ListsurfListCommandActions
}

extension FocusedValues {
    var listsurfAppCommands: ListsurfAppCommandActions? {
        get { self[ListsurfAppCommandActionsKey.self] }
        set { self[ListsurfAppCommandActionsKey.self] = newValue }
    }

    var listsurfListCommands: ListsurfListCommandActions? {
        get { self[ListsurfListCommandActionsKey.self] }
        set { self[ListsurfListCommandActionsKey.self] = newValue }
    }
}
