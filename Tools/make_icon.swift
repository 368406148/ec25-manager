import AppKit
import Foundation

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Build/AppIcon.iconset")
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

struct IconImage {
    let name: String
    let size: Int
}

let images = [
    IconImage(name: "icon_16x16.png", size: 16),
    IconImage(name: "icon_16x16@2x.png", size: 32),
    IconImage(name: "icon_32x32.png", size: 32),
    IconImage(name: "icon_32x32@2x.png", size: 64),
    IconImage(name: "icon_128x128.png", size: 128),
    IconImage(name: "icon_128x128@2x.png", size: 256),
    IconImage(name: "icon_256x256.png", size: 256),
    IconImage(name: "icon_256x256@2x.png", size: 512),
    IconImage(name: "icon_512x512.png", size: 512),
    IconImage(name: "icon_512x512@2x.png", size: 1024)
]

func drawIcon(size: Int) -> NSImage {
    let canvas = CGFloat(size)
    let image = NSImage(size: NSSize(width: canvas, height: canvas))
    image.lockFocus()
    defer { image.unlockFocus() }

    NSGraphicsContext.current?.imageInterpolation = .high

    let rect = NSRect(x: 0, y: 0, width: canvas, height: canvas)
    NSColor.clear.setFill()
    rect.fill()

    let baseRect = rect.insetBy(dx: canvas * 0.055, dy: canvas * 0.055)
    let corner = canvas * 0.24
    let background = NSBezierPath(roundedRect: baseRect, xRadius: corner, yRadius: corner)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.89, green: 0.97, blue: 1.00, alpha: 0.96),
        NSColor(calibratedRed: 0.58, green: 0.82, blue: 0.98, alpha: 0.88),
        NSColor(calibratedRed: 0.76, green: 0.95, blue: 0.88, alpha: 0.90)
    ])?.draw(in: background, angle: 125)

    NSColor(calibratedWhite: 1, alpha: 0.72).setStroke()
    background.lineWidth = max(1, canvas * 0.018)
    background.stroke()

    let gloss = NSBezierPath(roundedRect: NSRect(x: baseRect.minX + canvas * 0.08, y: baseRect.midY, width: baseRect.width * 0.80, height: baseRect.height * 0.40), xRadius: corner * 0.75, yRadius: corner * 0.75)
    NSGradient(colors: [
        NSColor(calibratedWhite: 1, alpha: 0.62),
        NSColor(calibratedWhite: 1, alpha: 0.04)
    ])?.draw(in: gloss, angle: 90)

    let cardRect = NSRect(x: canvas * 0.24, y: canvas * 0.24, width: canvas * 0.52, height: canvas * 0.43)
    let card = NSBezierPath(roundedRect: cardRect, xRadius: canvas * 0.045, yRadius: canvas * 0.045)
    NSColor(calibratedWhite: 1, alpha: 0.62).setFill()
    card.fill()

    NSColor(calibratedRed: 0.08, green: 0.34, blue: 0.42, alpha: 0.34).setStroke()
    card.lineWidth = max(1, canvas * 0.012)
    card.stroke()

    NSColor(calibratedRed: 0.06, green: 0.47, blue: 0.52, alpha: 0.92).setFill()
    for offset in [0.10, 0.28, 0.46] {
        let slot = NSBezierPath(roundedRect: NSRect(x: cardRect.minX + canvas * offset, y: cardRect.minY + canvas * 0.11, width: canvas * 0.10, height: canvas * 0.24), xRadius: canvas * 0.018, yRadius: canvas * 0.018)
        slot.fill()
    }

    let dot = NSBezierPath(ovalIn: NSRect(x: cardRect.maxX - canvas * 0.15, y: cardRect.maxY - canvas * 0.15, width: canvas * 0.07, height: canvas * 0.07))
    NSColor(calibratedRed: 0.05, green: 0.24, blue: 0.30, alpha: 0.80).setFill()
    dot.fill()

    let center = NSPoint(x: canvas * 0.50, y: canvas * 0.73)
    NSColor(calibratedRed: 0.00, green: 0.30, blue: 0.42, alpha: 0.84).setStroke()
    for index in 0..<3 {
        let radius = canvas * (0.10 + CGFloat(index) * 0.075)
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius, startAngle: 32, endAngle: 148, clockwise: false)
        arc.lineWidth = max(1.2, canvas * 0.025)
        arc.lineCapStyle = .round
        arc.stroke()
    }

    if size >= 128 {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: canvas * 0.105, weight: .semibold),
            .foregroundColor: NSColor(calibratedRed: 0.03, green: 0.22, blue: 0.28, alpha: 0.82),
            .paragraphStyle: paragraph
        ]
        "EC25".draw(in: NSRect(x: canvas * 0.20, y: canvas * 0.085, width: canvas * 0.60, height: canvas * 0.13), withAttributes: attributes)
    }

    return image
}

for item in images {
    let image = drawIcon(size: item.size)
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "Icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to render \(item.name)"])
    }
    try png.write(to: outputDirectory.appendingPathComponent(item.name))
}
