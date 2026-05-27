#!/usr/bin/env swift
/// Generates AppIcon.iconset/ at all required sizes using CoreGraphics.
/// Usage:  swift scripts/generate-icons.swift <output-dir>
import AppKit   // for NSBitmapImageRep PNG export
import Foundation

// Initialise AppKit so NSBitmapImageRep works (no dock icon, no UI)
let _app = NSApplication.shared
_app.setActivationPolicy(.prohibited)

// ─── helpers ──────────────────────────────────────────────────────────────────

func ctx(_ px: Int) -> CGContext {
    CGContext(data: nil, width: px, height: px,
              bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func pngData(_ c: CGContext) -> Data {
    let rep = NSBitmapImageRep(cgImage: c.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

func write(_ c: CGContext, to path: String) {
    try! pngData(c).write(to: URL(fileURLWithPath: path))
}

// ─── app icon drawing ─────────────────────────────────────────────────────────
//
//  Design:
//   • Blue (#4086F6) → Purple (#8A54F7) gradient background, rounded-square
//   • White clipboard body with a blue top-tab
//   • Three light-blue content lines
//   • Purple history-badge (bottom-right) with white clock face + 10:10 hands

func drawAppIcon(_ c: CGContext, px: Int) {
    let s = CGFloat(px)

    // ── 1. Rounded-rect clip (macOS app-icon shape) ──────────────────────────
    c.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                     cornerWidth: s * 0.225, cornerHeight: s * 0.225,
                     transform: nil))
    c.clip()

    // ── 2. Gradient background (blue top → purple bottom) ───────────────────
    let grad = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [CGColor(red: 0.25, green: 0.52, blue: 0.96, alpha: 1),   // #4085F5
                 CGColor(red: 0.54, green: 0.33, blue: 0.97, alpha: 1)] as CFArray, // #8A54F7
        locations: [0, 1])!
    c.drawLinearGradient(grad,
                         start: CGPoint(x: s / 2, y: s),
                         end:   CGPoint(x: s / 2, y: 0),
                         options: [])
    c.resetClip()

    // ── 3. Clipboard body ────────────────────────────────────────────────────
    let m     = s * 0.175
    let board = CGRect(x: m, y: m, width: s - m * 2, height: s - m * 2)
    let cr    = s * 0.065

    c.addPath(CGPath(roundedRect: board, cornerWidth: cr, cornerHeight: cr, transform: nil))
    c.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    c.fillPath()

    // ── 4. Top tab / clip ────────────────────────────────────────────────────
    let tw  = board.width * 0.30,  th  = s * 0.082
    let tx  = board.midX - tw / 2, ty  = board.maxY - th * 0.60
    c.addPath(CGPath(roundedRect: CGRect(x: tx, y: ty, width: tw, height: th * 1.2),
                     cornerWidth: th * 0.45, cornerHeight: th * 0.45, transform: nil))
    c.setFillColor(CGColor(red: 0.25, green: 0.52, blue: 0.96, alpha: 1))
    c.fillPath()

    // ── 5. Content lines ─────────────────────────────────────────────────────
    let lh   = s * 0.040
    let lx   = board.minX + board.width * 0.13
    let lmw  = board.width * 0.74
    let ly0  = board.midY + lh
    let gap  = s * 0.070
    let lineClr = CGColor(red: 0.60, green: 0.70, blue: 0.88, alpha: 0.55)

    for (i, w) in [(0, 1.00), (1, 0.85), (2, 0.52)] {
        let ly = ly0 - CGFloat(i) * gap
        c.addPath(CGPath(roundedRect: CGRect(x: lx, y: ly, width: lmw * w, height: lh),
                         cornerWidth: lh / 2, cornerHeight: lh / 2, transform: nil))
        c.setFillColor(lineClr)
        c.fillPath()
    }

    // ── 6. History badge (circle, bottom-right of clipboard) ─────────────────
    let bR  = s * 0.130
    let bCx = board.maxX - bR * 0.80
    let bCy = board.minY + bR * 0.80

    // Badge circle
    c.setFillColor(CGColor(red: 0.54, green: 0.33, blue: 0.97, alpha: 1))
    c.fillEllipse(in: CGRect(x: bCx - bR, y: bCy - bR, width: bR * 2, height: bR * 2))

    // Clock-face ring
    let face = bR * 0.62
    c.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.35))
    c.setLineWidth(s * 0.013)
    c.strokeEllipse(in: CGRect(x: bCx - face, y: bCy - face, width: face * 2, height: face * 2))

    // Clock hands at 10:10 (symmetric, looks like a smile)
    //   In CGContext (y-up): 12 o'clock = π/2, going clockwise decreases angle
    //   10 o'clock = π/2 + 2*(π/6) = 5π/6 ≈ 150°
    //    2 o'clock = π/2 - 2*(π/6) = π/6  ≈  30°
    c.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    c.setLineWidth(s * 0.021)
    c.setLineCap(.round)

    let hourA: CGFloat = 5 * .pi / 6   // 10 o'clock
    let minA:  CGFloat = .pi / 6        // 2 o'clock

    c.move(to: CGPoint(x: bCx, y: bCy))
    c.addLine(to: CGPoint(x: bCx + cos(hourA) * face * 0.54,
                          y: bCy + sin(hourA) * face * 0.54))
    c.strokePath()

    c.move(to: CGPoint(x: bCx, y: bCy))
    c.addLine(to: CGPoint(x: bCx + cos(minA) * face * 0.70,
                          y: bCy + sin(minA) * face * 0.70))
    c.strokePath()

    // Center dot
    let dotR = s * 0.013
    c.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    c.fillEllipse(in: CGRect(x: bCx - dotR, y: bCy - dotR,
                              width: dotR * 2, height: dotR * 2))
}

// ─── main ─────────────────────────────────────────────────────────────────────

let outDir      = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let iconsetPath = outDir + "/AppIcon.iconset"
try! FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let sizes: [(pts: Int, scale: Int)] = [
    (16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)
]

for (pts, scale) in sizes {
    let px  = pts * scale
    let c   = ctx(px)
    drawAppIcon(c, px: px)
    let name = scale == 1 ? "icon_\(pts)x\(pts).png" : "icon_\(pts)x\(pts)@2x.png"
    write(c, to: iconsetPath + "/" + name)
    print("  ✓ \(name)  (\(px)px)")
}

print("✓  iconset → \(iconsetPath)")
