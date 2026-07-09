#if os(macOS)
import AppKit
import SwiftUI

struct MacOutlineTabKeyMonitor: NSViewRepresentable {
    let isOutlineActive: Bool
    let isAddFieldActive: Bool
    let onTab: (_ isShiftPressed: Bool) -> Void
    let onCommitAddField: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.view = view
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.view = nsView
        context.coordinator.isOutlineActive = isOutlineActive
        context.coordinator.isAddFieldActive = isAddFieldActive
        context.coordinator.onTab = onTab
        context.coordinator.onCommitAddField = onCommitAddField
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    @MainActor
    final class Coordinator: NSObject {
        weak var view: NSView?
        var isOutlineActive = false
        var isAddFieldActive = false
        var onTab: ((_ isShiftPressed: Bool) -> Void)?
        var onCommitAddField: (() -> Void)?
        private var monitor: Any?

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let view,
                  let window = view.window,
                  event.window === window,
                  !hasDisallowedModifier(event) else {
                return event
            }

            if isAddFieldActive && isAddFieldCommitEvent(event) {
                onCommitAddField?()
                return nil
            }

            if isOutlineActive,
               event.keyCode == 48,
               !isTextInputActive(in: window) {
                onTab?(event.modifierFlags.contains(.shift))
                return nil
            }

            return event
        }

        private func hasDisallowedModifier(_ event: NSEvent) -> Bool {
            let disallowed: NSEvent.ModifierFlags = [.command, .control, .option]
            return !event.modifierFlags.intersection(disallowed).isEmpty
        }

        private func isAddFieldCommitEvent(_ event: NSEvent) -> Bool {
            event.keyCode == 48 || event.keyCode == 36 || event.keyCode == 76
        }

        private func isTextInputActive(in window: NSWindow) -> Bool {
            guard let firstResponder = window.firstResponder else { return false }
            return firstResponder is NSTextView || firstResponder is NSTextField
        }
    }
}
#endif
