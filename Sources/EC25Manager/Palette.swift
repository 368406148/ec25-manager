import AppKit
import SwiftUI

enum Palette {
    // NSColor (used by the menu-bar tray icon rendering)
    static let brand = NSColor(red: 0.31, green: 0.55, blue: 1.0, alpha: 1)
    static let brand2 = NSColor(red: 0.48, green: 0.36, blue: 1.0, alpha: 1)
    static let good = NSColor(red: 0.20, green: 0.83, blue: 0.60, alpha: 1)
    static let warn = NSColor(red: 1.0, green: 0.69, blue: 0.13, alpha: 1)
    static let danger = NSColor(red: 1.0, green: 0.36, blue: 0.42, alpha: 1)
    static let brandNS = brand
    static let goodNS = good
    static let warnNS = warn
    static let dangerNS = danger

    // SwiftUI Color (used by the UI)
    static let brandC = Color(nsColor: brand)
    static let brand2C = Color(nsColor: brand2)
    static let goodC = Color(nsColor: good)
    static let warnC = Color(nsColor: warn)
    static let dangerC = Color(nsColor: danger)
}
