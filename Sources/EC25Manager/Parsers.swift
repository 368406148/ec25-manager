import Foundation

// MARK: - String helpers

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimQuotes: String { trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
}

/// Split an AT payload on commas, respecting double-quoted segments.
func csvParts(_ line: String) -> [String] {
    var result: [String] = []
    var current = ""
    var quoted = false
    for ch in line {
        if ch == "\"" { quoted.toggle(); current.append(ch) }
        else if ch == "," && !quoted { result.append(current.trimmed); current = "" }
        else { current.append(ch) }
    }
    result.append(current.trimmed)
    return result
}

func firstLine(_ lines: [String], containing needle: String) -> String? {
    lines.first { $0.contains(needle) }
}

func firstNonCommandLine(_ lines: [String]) -> String? {
    lines.first { !$0.hasPrefix("AT") && !$0.hasPrefix("+") }?.trimmed
}

// MARK: - UCS2

enum UCS2 {
    static func encode(_ text: String) -> String {
        text.utf16.map { String(format: "%04X", $0) }.joined()
    }

    static func decode(_ hex: String) -> String {
        let cleaned = hex.trimmed
        guard cleaned.count >= 4, cleaned.count.isMultiple(of: 4), cleaned.allSatisfy(\.isHexDigit) else {
            return hex
        }
        var units: [UInt16] = []
        var idx = cleaned.startIndex
        while idx < cleaned.endIndex {
            let next = cleaned.index(idx, offsetBy: 4)
            if let value = UInt16(cleaned[idx..<next], radix: 16) { units.append(value) }
            idx = next
        }
        return String(decoding: units, as: UTF16.self)
    }
}

// MARK: - Lookup tables

let regStatus: [String: String] = [
    "0": "未注册", "1": "已注册·本地", "2": "正在搜索", "3": "注册被拒", "4": "未知", "5": "已注册·漫游"
]

let actTech: [Int: String] = [
    0: "GSM", 1: "GSM Compact", 2: "UTRAN", 3: "GSM/EGPRS", 4: "UTRAN/HSDPA",
    5: "UTRAN/HSUPA", 6: "UTRAN/HSPA", 7: "LTE", 8: "LTE Cat-M1", 9: "LTE Cat-NB1", 10: "5G NSA", 11: "5G"
]

let usbnetMode: [String: String] = ["0": "QMI", "1": "ECM", "2": "MBIM", "3": "RNDIS"]

let msgStatus: [String: String] = [
    "0": "REC UNREAD", "1": "REC READ", "2": "STO UNSENT", "3": "STO SENT", "4": "ALL"
]

let bwIndex: [String: String] = ["0": "1.4M", "1": "3M", "2": "5M", "3": "10M", "4": "15M", "5": "20M"]

// band -> (FDL_low MHz, NOffs-DL)
let lteBands: [Int: (Double, Double)] = [
    1: (2110, 0), 2: (1930, 600), 3: (1805, 1200), 4: (2110, 1950), 5: (869, 2400),
    7: (2620, 2750), 8: (925, 3450), 12: (729, 5010), 13: (746, 5180), 17: (734, 5730),
    18: (860, 5850), 19: (875, 6000), 20: (791, 6150), 25: (1930, 8040), 26: (859, 8690),
    28: (758, 9210), 38: (2570, 37750), 39: (1880, 38250), 40: (2300, 38650), 41: (2496, 39650), 66: (2110, 66436)
]

func earfcnToDlMhz(band: String, earfcn: String) -> Double? {
    guard let b = Int(band), let n = Double(earfcn), let entry = lteBands[b] else { return nil }
    return (entry.0 + 0.1 * (n - entry.1) * 1).rounded(toPlaces: 1)
}

func cqiToModulation(_ cqi: Int?) -> String {
    guard let c = cqi, c > 0 else { return "-" }
    if c <= 6 { return "QPSK (CQI \(c))" }
    if c <= 9 { return "16QAM (CQI \(c))" }
    return "64QAM (CQI \(c))"
}

func shortNetworkLabel(_ access: String) -> String {
    let a = access.uppercased()
    if a.contains("NR") || a.contains("5G") { return "5G" }
    if a.contains("LTE") { return "4G" }
    if a.contains("TD-SCDMA") || a.contains("WCDMA") || a.contains("HSDPA") || a.contains("HSPA") || a.contains("UMTS") { return "3G" }
    if a.contains("GSM") || a.contains("EDGE") || a.contains("GPRS") { return "2G" }
    return access.isEmpty ? "-" : access
}

func signalFromRssi(_ rssi: Int?) -> Signal {
    guard let rssi, rssi != 99 else { return Signal(dbm: nil, bars: 0, percent: 0, text: "未知") }
    let dbm = 2 * rssi - 113
    let bars: Int = rssi >= 20 ? 4 : rssi >= 15 ? 3 : rssi >= 10 ? 2 : rssi >= 2 ? 1 : 0
    let percent = max(0, min(100, Int((Double(rssi) / 31.0 * 100).rounded())))
    return Signal(dbm: dbm, bars: bars, percent: percent, text: "\(dbm) dBm")
}

func barsFromRsrp(_ rsrp: Int?) -> Int? {
    guard let r = rsrp else { return nil }
    if r >= -85 { return 4 }
    if r >= -95 { return 3 }
    if r >= -105 { return 2 }
    if r >= -115 { return 1 }
    return 0
}

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let f = pow(10.0, Double(places))
        return (self * f).rounded() / f
    }
}
