import SwiftUI

enum AppTheme {
    static let panelRadius: CGFloat = 24
    static let cardRadius: CGFloat = 12
    static let controlRadius: CGFloat = 10
    static let rowRadius: CGFloat = 12

    static var hairline: Color {
        Color.primary.opacity(0.06)
    }

    static var subtleHairline: Color {
        Color.primary.opacity(0.04)
    }

    static var softFill: Color {
        Color.primary.opacity(0.035)
    }

    static var strongerFill: Color {
        Color.primary.opacity(0.06)
    }

    static var selectedFill: Color {
        Color.accentColor.opacity(0.12)
    }

    static var selectedStroke: Color {
        Color.accentColor.opacity(0.22)
    }

    static var cardFill: Color {
        Color(nsColor: .controlBackgroundColor).opacity(0.65)
    }

    static var windowFill: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    static func iconFill(_ color: Color = .accentColor) -> Color {
        color.opacity(0.1)
    }
}
