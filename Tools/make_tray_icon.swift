import AppKit
import Foundation

// Renders menu-bar template icons (black + alpha; macOS tints them).
// Signal-strength variants tray-0..tray-4 (n filled bars), plus tray-off
// (device removed: faint bars with a slash). Each at 1x (22px) and 2x (44px).
// Also writes trayTemplate.png as a neutral fallback.

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "app/assets")
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func drawTray(pixelSize: CGFloat, filled: Int, off: Bool) -> NSBitmapImageRep {
    // Render into an explicit bitmap so 1 point == 1 pixel regardless of the
    // machine's Retina scale factor (lockFocus would otherwise double the size).
    let px = Int(pixelSize)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixelSize, height: pixelSize)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current?.imageInterpolation = .high

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize).fill()

    let unit = pixelSize / 22.0
    let barWidth = 2.7 * unit
    let gap = 1.9 * unit
    let baseY = 5.0 * unit
    // Smaller glyph with top/bottom padding (max height 12 in a 22 canvas).
    let heights: [CGFloat] = [5.0, 7.3, 9.6, 12.0].map { $0 * unit }
    let totalWidth = barWidth * 4 + gap * 3
    var x = (pixelSize - totalWidth) / 2

    for (i, height) in heights.enumerated() {
        let alpha: CGFloat = off ? 0.22 : (i < filled ? 1.0 : 0.28)
        NSColor(white: 0, alpha: alpha).setFill()
        let path = NSBezierPath(roundedRect: NSRect(x: x, y: baseY, width: barWidth, height: height), xRadius: 1.0 * unit, yRadius: 1.0 * unit)
        path.fill()
        x += barWidth + gap
    }

    if off {
        // Diagonal slash to signal "device removed".
        let slash = NSBezierPath()
        slash.move(to: NSPoint(x: 4.0 * unit, y: 4.0 * unit))
        slash.line(to: NSPoint(x: 18.0 * unit, y: 17.5 * unit))
        slash.lineWidth = 1.8 * unit
        slash.lineCapStyle = .round
        NSColor(white: 0, alpha: 0.95).setStroke()
        slash.stroke()
    }
    return rep
}

func write(_ rep: NSBitmapImageRep, to name: String) throws {
    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "Tray", code: 1, userInfo: [NSLocalizedDescriptionKey: "render failed for \(name)"])
    }
    try png.write(to: outputDirectory.appendingPathComponent(name))
}

func emit(baseName: String, filled: Int, off: Bool) throws {
    try write(drawTray(pixelSize: 22, filled: filled, off: off), to: "\(baseName).png")
    try write(drawTray(pixelSize: 44, filled: filled, off: off), to: "\(baseName)@2x.png")
}

for n in 0...4 {
    try emit(baseName: "tray-\(n)", filled: n, off: false)
}
try emit(baseName: "tray-off", filled: 0, off: true)
try emit(baseName: "trayTemplate", filled: 3, off: false)   // neutral fallback
