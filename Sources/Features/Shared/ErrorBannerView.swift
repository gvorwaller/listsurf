import SwiftUI
import Domain

struct ErrorBannerView: View {
    let presentation: AppErrorPresentation
    let onRetry: () -> Void
    let onDismiss: () -> Void

    private var error: AppError { presentation.error }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(error.errorDescription ?? "An Error Occurred")
                    .font(.headline)
                if let reason = error.failureReason, !reason.isEmpty {
                    Text(reason)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

            Spacer(minLength: 8)

            if presentation.canRetry {
                Button(presentation.retryTitle ?? "Retry", action: onRetry)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss Error")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .combine)
    }
}
