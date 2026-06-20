import SwiftUI

public enum ListColor: String, CaseIterable, Sendable {
    case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple

    public var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .cyan: .cyan
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        }
    }

    public static func from(_ name: String?) -> Color {
        guard let name, let c = ListColor(rawValue: name) else { return .accentColor }
        return c.color
    }
}
