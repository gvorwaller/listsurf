import Domain
import Foundation
import Observation

@MainActor
@Observable
public final class AppErrorStore {
    public private(set) var current: AppErrorPresentation?

    public init() {}

    public func present(
        _ error: AppError,
        retryTitle: String? = nil,
        retry: (@MainActor () -> Void)? = nil
    ) {
        current = AppErrorPresentation(
            error: error,
            retryTitle: retryTitle,
            retry: retry
        )
    }

    public func dismiss() {
        current = nil
    }

    public func retryCurrent() {
        let action = current?.retry
        current = nil
        action?()
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
