import AppKit

/// Menu-bar signal icon, drawn as a vector template image so it stays crisp at
/// any Retina scale and auto-tints to the menu-bar appearance.
/// - filled: number of solid bars (0...4)
/// - off: draw faint bars with a slash to mean "no device"
func makeTrayIcon(filled: Int, off: Bool) -> NSImage {
    let size = NSSize(width: 22, height: 22)
    let image = NSImage(size: size, flipped: false) { _ in
        let unit: CGFloat = 1  // 22pt canvas
        let barWidth: CGFloat = 2.7
        let gap: CGFloat = 1.9
        let baseY: CGFloat = 5
        let heights: [CGFloat] = [5.0, 7.3, 9.6, 12.0]
        let totalWidth = barWidth * 4 + gap * 3
        var x = (22 - totalWidth) / 2

        for (i, h) in heights.enumerated() {
            let alpha: CGFloat = off ? 0.22 : (i < filled ? 1.0 : 0.28)
            NSColor(white: 0, alpha: alpha).setFill()
            let r = NSRect(x: x, y: baseY, width: barWidth, height: h)
            NSBezierPath(roundedRect: r, xRadius: 1.0 * unit, yRadius: 1.0 * unit).fill()
            x += barWidth + gap
        }

        if off {
            let slash = NSBezierPath()
            slash.move(to: NSPoint(x: 4, y: 4))
            slash.line(to: NSPoint(x: 18, y: 17.5))
            slash.lineWidth = 1.8
            slash.lineCapStyle = .round
            NSColor(white: 0, alpha: 0.95).setStroke()
            slash.stroke()
        }
        return true
    }
    image.isTemplate = true
    return image
}
