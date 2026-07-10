import AppKit

enum Palette {
    static let brand = NSColor(red: 0.31, green: 0.55, blue: 1.0, alpha: 1)
    static let brand2 = NSColor(red: 0.48, green: 0.36, blue: 1.0, alpha: 1)
    static let good = NSColor(red: 0.20, green: 0.83, blue: 0.60, alpha: 1)
    static let warn = NSColor(red: 1.0, green: 0.69, blue: 0.13, alpha: 1)
    static let danger = NSColor(red: 1.0, green: 0.36, blue: 0.42, alpha: 1)

    // aliases (used where an NSColor is read explicitly)
    static let brandNS = brand
    static let goodNS = good
    static let warnNS = warn
    static let dangerNS = danger
}
