import SwiftUI
import Domain

struct ArchiveView: View {
    @Environment(AppStore.self) private var appStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if appStore.archivedLists.isEmpty {
                    ContentUnavailableView(
                        "No Archived Lists",
                        systemImage: "archivebox",
                        description: Text("Archived lists will appear here.")
                    )
                } else {
                    List {
                        ForEach(appStore.archivedLists) { list in
                            LibraryRow(list: list)
                                .contextMenu {
                                    Button {
                                        Task { await appStore.restoreList(id: list.id) }
                                    } label: {
                                        Label("Restore", systemImage: "arrow.uturn.backward")
                                    }

                                    Button(role: .destructive) {
                                        Task { await appStore.deleteList(id: list.id) }
                                    } label: {
                                        Label("Delete Permanently", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        Task { await appStore.deleteList(id: list.id) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        Task { await appStore.restoreList(id: list.id) }
                                    } label: {
                                        Label("Restore", systemImage: "arrow.uturn.backward")
                                    }
                                    .tint(.blue)
                                }
                        }
                    }
                }
            }
            .navigationTitle("Archive")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}
