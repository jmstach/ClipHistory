import AppKit

extension NSImage {
    /// Menu bar icon — the system `paperclip.circle.fill` symbol, rendered as a
    /// template so it adapts to the light/dark menu bar and highlight states.
    static func clipHistoryMenuBar(pointSize: CGFloat = 16) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        let img = NSImage(systemSymbolName: "paperclip.circle.fill",
                          accessibilityDescription: "ClipHistory")?
            .withSymbolConfiguration(config) ?? NSImage()
        img.isTemplate = true   // adapts to light/dark menu bar & highlight
        return img
    }
}
