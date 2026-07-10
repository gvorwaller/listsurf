import Domain
import Foundation
import Observation

@MainActor
@Observable
public final class AppErrorStore {
    public private(set) var current: AppErrorPresentation?
    // Later errors queue rather than clobber: replacing the current error
    // would silently discard its retry action mid-flow.
    private var pending: [AppErrorPresentation] = []

    public init() {}

    public func present(
        _ error: AppError,
        retryTitle: String? = nil,
        retry: (@MainActor () -> Void)? = nil
    ) {
        let presentation = AppErrorPresentation(
            error: error,
            retryTitle: retryTitle,
            retry: retry
        )
        if current == nil {
            current = presentation
        } else {
            pending.append(presentation)
        }
    }

    public func dismiss() {
        advance()
    }

    public func retryCurrent() {
        let action = current?.retry
        advance()
        action?()
    }

    private func advance() {
        current = pending.isEmpty ? nil : pending.removeFirst()
    }
}

public struct AppErrorPresentation: Identifiable {
    public let id: UUID
    public let error: AppError
    public let retryTitle: String?
    fileprivate let retry: (@MainActor () -> Void)?

    public init(
        id: UUID = UUID(),
        error: AppError,
        retryTitle: String? = nil,
        retry: (@MainActor () -> Void)? = nil
    ) {
        self.id = id
        self.error = error
        self.retryTitle = retryTitle
        self.retry = retry
    }

    public var canRetry: Bool { retry != nil }
}
