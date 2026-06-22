import Foundation

#if os(iOS)
import UIKit
#endif

public enum Haptics {
    @MainActor
    public static func checkToggle() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}
