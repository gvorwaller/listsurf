#if os(macOS)
import SwiftUI
import Combine
import AppKit

@MainActor
enum KeyboardLegendFocus {
    private static weak var previousWindow: NSWindow?

    /// Records the window that was key right before the legend opens.
    static func capture() {
        previousWindow = NSApp.keyWindow
    }

    /// Makes the captured window key again WITHOUT forgetting it. Called on
    /// the legend's `onAppear` so opening the legend never steals key-window
    /// status from the row the user was working in.
    static func restore() {
        previousWindow?.makeKey()
    }

    /// Clears the captured reference. Called once the legend's lifetime is
    /// over (`onDisappear`, after a final `restore()`), so a later legend
    /// open starts from a fresh capture.
    static func release() {
        previousWindow = nil
    }
}

public struct KeyboardLegendView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var highlightedCommandID: String?
    @State private var highlightTask: Task<Void, Never>?
    @FocusState private var containerFocused: Bool

    public init() {}

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(CommandCatalog.macKeyboardHelp) { command in
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text(command.keyDisplay)
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .frame(width: 92, alignment: .trailing)
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
        // Belt-and-suspenders Esc handling (td-0a4af9): onExitCommand is the
        // normal SwiftUI path, but the row content is .focusable(false), so
        // if nothing in the hierarchy is in the focus/responder chain when
        // the legend IS key, onExitCommand may not fire. The focusable
        // container + onKeyPress fallback catches Esc in that case too.
        .focusable()
        .focusEffectDisabled()
        .focused($containerFocused)
        .onExitCommand { dismiss() }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onAppear {
            containerFocused = true
            Task { @MainActor in
                await Task.yield()
                KeyboardLegendFocus.restore()
            }
        }
        .onDisappear {
            highlightTask?.cancel()
            KeyboardLegendFocus.restore()
            KeyboardLegendFocus.release()
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
