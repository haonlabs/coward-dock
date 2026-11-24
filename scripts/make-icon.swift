// Renders the app icon into an .iconset folder: swift scripts/make-icon.swift <out.iconset>
import AppKit

func rgb(_ hex: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
}

// Drawn on Apple's 1024pt icon grid (824pt body, ~185pt corner radius).
func drawIcon() {
    let body = rounded(100, 100, 824, 824, 185)
    NSGradient(starting: rgb(0x6A8BFF), ending: rgb(0x26296B))!.draw(in: body, angle: -90)
    body.addClip()

    // The Dock, slipping off the bottom edge.
    rounded(232, 118, 560, 120, 44).fill(with: rgb(0xFFFFFF, 0.28))
    for (i, c) in [0xFF6B6B, 0xFFC44D, 0x4DD691, 0x4DB8FF].enumerated() {
        rounded(268 + CGFloat(i) * 128, 146, 92, 92, 24).fill(with: rgb(c, 0.85))
    }

    // A window covering the Dock.
    let shadow = NSShadow()
    shadow.shadowColor = rgb(0x000000, 0.35)
    shadow.shadowBlurRadius = 40
    shadow.shadowOffset = NSSize(width: 0, height: -16)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    rounded(196, 210, 632, 520, 48).fill(with: rgb(0xFFFFFF))
    NSGraphicsContext.restoreGraphicsState()
    rounded(196, 650, 632, 80, 48).fill(with: rgb(0xE9ECF5))
    rgb(0xE9ECF5).setFill(); NSRect(x: 196, y: 650, width: 632, height: 40).fill()
    for (i, c) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
        NSBezierPath(ovalIn: NSRect(x: 236 + CGFloat(i) * 52, y: 672, width: 34, height: 34)).fill(with: rgb(c))
    }
    for (i, w) in [440, 360, 400, 260].enumerated() {
        rounded(250, 560 - CGFloat(i) * 80, CGFloat(w), 36, 18).fill(with: rgb(0xD5DAE8))
    }
}

extension NSBezierPath {
    func fill(with color: NSColor) { color.setFill(); fill() }
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current!.cgContext.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
        drawIcon()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
    }
}
