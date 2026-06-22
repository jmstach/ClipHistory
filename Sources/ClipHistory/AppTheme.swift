import SwiftUI

enum AppTheme {
    static let panelRadius: CGFloat = 24
    static let cardRadius: CGFloat = 12
    static let controlRadius: CGFloat = 10
    static let rowRadius: CGFloat = 12

    // MARK: - Type scale
    // Semantic text styles (Dynamic Type aware) rather than fixed point sizes,
    // anchored a notch above the macOS default: .title3 ≈ 15, .callout ≈ 12,
    // .subheadline ≈ 11. Default SF (no rounded). Tune the whole popup here.
    static let searchText    = Font.system(.title3).weight(.medium)
    static let rowTitle      = Font.system(.title3).weight(.regular)
    static let imageTitle    = Font.system(.title3).weight(.regular)
    static let sourceLabel   = Font.system(.caption).weight(.regular)
    static let timestamp     = Font.system(.subheadline).weight(.medium)
    static let hintKey       = Font.system(.subheadline, design: .monospaced).weight(.bold)
    static let hintLabel     = Font.system(.subheadline).weight(.semibold)
    static let emptyTitle    = Font.system(.title3).weight(.semibold)
    static let emptySubtitle = Font.system(.callout)

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
