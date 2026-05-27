import AppKit

extension NSImage {
    /// Custom clipboard template image for the system menu bar.
    /// Drawn programmatically so it's always crisp at any resolution.
    static func clipHistoryMenuBar(pointSize: CGFloat = 18) -> NSImage {
        let img = NSImage(size: NSSize(width: pointSize, height: pointSize),
                          flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            let w = rect.width, h = rect.height

            // ── Board rect ────────────────────────────────────────────────────
            let px = w * 0.09, py = h * 0.07
            let bw = w - px * 2
            let bh = h * 0.80
            let board = CGRect(x: px, y: py, width: bw, height: bh)
            let corner: CGFloat = w * 0.13

            // All shapes are solid black — system renders as a template
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))

            // ── Body (stroke outline) ─────────────────────────────────────────
            let stroke = max(1.0, w * 0.088)
            ctx.setLineWidth(stroke)
            ctx.addPath(CGPath(roundedRect: board,
                               cornerWidth: corner, cornerHeight: corner,
                               transform: nil))
            ctx.strokePath()

            // ── Top tab (filled) ──────────────────────────────────────────────
            let tw = bw * 0.36, th = h * 0.195
            let tabRect = CGRect(x: board.midX - tw / 2,
                                 y: board.maxY - th * 0.42,
                                 width: tw, height: th)
            ctx.addPath(CGPath(roundedRect: tabRect,
                               cornerWidth: th * 0.40, cornerHeight: th * 0.40,
                               transform: nil))
            ctx.fillPath()

            // ── Content lines ─────────────────────────────────────────────────
            let lh   = max(1.0, h * 0.085)
            let lx   = board.minX + bw * 0.155
            let lmw  = bw * 0.69
            let mid  = board.midY - lh / 2

            for (idx, frac) in [(0, 1.0), (1, 0.57)] {
                let ly = mid + CGFloat(idx == 0 ? 1 : -1) * lh * 1.55
                ctx.addPath(CGPath(roundedRect: CGRect(x: lx, y: ly,
                                                       width: lmw * frac, height: lh),
                                   cornerWidth: lh / 2, cornerHeight: lh / 2,
                                   transform: nil))
                ctx.fillPath()
            }

            return true
        }

        img.isTemplate = true   // adapts to light/dark menu bar & highlight
        return img
    }
}
