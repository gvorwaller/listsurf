#if os(macOS)
import SwiftUI
import Combine
import AppKit

@MainActor
enum KeyboardLegendFocus {
    private static weak var previousWindow: NSWindow?

    static func capture() {
        previousWindow = NSApp.keyWindow
    }

    static func restore() {
        previousWindow?.makeKey()
        previousWindow = nil
    }
}

public struct KeyboardLegendView: View {
    private let onVisibilityChanged: (Bool) -> Void
    @State private var highlightedCommandID: String?
    @State private var highlightTask: Task<Void, Never>?

    public init(onVisibilityChanged: @escaping (Bool) -> Void) {
        self.onVisibilityChanged = onVisibilityChanged
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(CommandCatalog.macKeyboardHelp) { command in
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text(command.keyDisplay)
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .frame(width: 132, alignment: .trailing)
                            .foregroundStyle(.primary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(command.title).fontWeight(.medium)
                            Text(command.helpText)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        command.id == highlightedCommandID
                            ? Color.accentColor.opacity(0.2)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .animation(.easeOut(duration: 0.15), value: highlightedCommandID)
                    .focusable(false)
                }
            }
            .padding(12)
        }
        .frame(minWidth: 460, idealWidth: 520, minHeight: 420, idealHeight: 620)
        .onAppear {
            onVisibilityChanged(true)
            Task { @MainActor in
                await Task.yield()
                KeyboardLegendFocus.restore()
            }
        }
        .onDisappear {
            highlightTask?.cancel()
            onVisibilityChanged(false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .listsurfCommandDidInvoke)) { notification in
            guard let commandID = notification.userInfo?["commandID"] as? String else { return }
            highlightTask?.cancel()
            highlightedCommandID = commandID
            highlightTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled else { return }
                highlightedCommandID = nil
            }
        }
    }
}
#endif
