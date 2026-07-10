import Foundation

// Field-level parsers for AT responses (ported from the device-verified modem.js).

func parseSignal(_ lines: [String]) -> Signal {
    guard let line = firstLine(lines, containing: "+CSQ:") else { return Signal(dbm: nil, bars: 0, percent: 0, text: "-") }
    let payload = line.replacingOccurrences(of: "+CSQ:", with: "")
    let rssi = Int((csvParts(payload).first ?? "").trimmed)
    return signalFromRssi(rssi ?? 99)
}

func parseBER(_ lines: [String]) -> String {
    guard let line = firstLine(lines, containing: "+CSQ:") else { return "-" }
    let parts = csvParts(line.replacingOccurrences(of: "+CSQ:", with: ""))
    return (parts[safe: 1] ?? "").trimmed.isEmpty ? "-" : (parts[safe: 1] ?? "-").trimmed
}

func parseOperator(_ lines: [String]) -> String {
    guard let line = firstLine(lines, containing: "+COPS:") else { return "-" }
    let parts = csvParts(line.replacingOccurrences(of: "+COPS:", with: ""))
    return UCS2.decode((parts[safe: 2] ?? line).trimQuotes)
}

func parseTech(_ lines: [String], fallback: String) -> String {
    if let line = firstLine(lines, containing: "+COPS:") {
        let parts = csvParts(line.replacingOccurrences(of: "+COPS:", with: ""))
        if let act = Int((parts[safe: 3] ?? "").trimmed), let name = actTech[act] { return name }
    }
    return fallback.isEmpty ? "-" : fallback
}

func parseICCID(_ lines: [String]) -> String {
    if let line = firstLine(lines, containing: "+QCCID:") {
        return line.replacingOccurrences(of: "+QCCID:", with: "").trimQuotes
    }
    return firstNonCommandLine(lines) ?? "-"
}

func parsePrefixed(_ lines: [String], _ prefix: String) -> String {
    guard let line = firstLine(lines, containing: prefix) else { return "-" }
    return line.replacingOccurrences(of: prefix, with: "").trimQuotes
}

func parseOwnNumber(_ lines: [String]) -> String {
    guard let line = firstLine(lines, containing: "+CNUM:") else { return "-" }
    let parts = csvParts(line.replacingOccurrences(of: "+CNUM:", with: ""))
    return UCS2.decode((parts[safe: 1] ?? line).trimQuotes)
}

func parseRegistration(_ lines: [String], _ prefix: String) -> String {
    guard let line = firstLine(lines, containing: prefix) else { return "-" }
    let parts = csvParts(line.replacingOccurrences(of: prefix, with: ""))
    let stat = (parts.last ?? "-").trimmed
    return regStatus[stat] ?? stat
}

struct NetInfo { var full = "-"; var label = "-"; var band = "-"; var channel = "-" }

func parseNetworkType(_ lines: [String]) -> NetInfo {
    guard let line = firstLine(lines, containing: "+QNWINFO:") else { return NetInfo() }
    let parts = csvParts(line.replacingOccurrences(of: "+QNWINFO:", with: ""))
    let access = (parts[safe: 0] ?? "-").trimQuotes
    let band = (parts[safe: 2] ?? "-").trimQuotes
    let channel = (parts[safe: 3] ?? "-").trimmed
    let up = access.uppercased()
    if access == "-" || access.isEmpty || up.contains("NONE") || up.contains("NO SERVICE") {
        return NetInfo(full: "无服务", label: "无服务", band: "-", channel: "-")
    }
    return NetInfo(full: "\(access) · \(band) · \(channel)", label: shortNetworkLabel(access), band: band, channel: channel)
}

struct CellInfo {
    var band: String?
    var earfcn: String?
    var rsrp: Int?
    var rsrq: Int?
    var rssi: Int?
    var sinr: Int?
    var cqi: Int?
    var dlBw: String?
    var ulBw: String?
    var pci: String?
    var cellId: String?
    var tac: String?
}

func parseServingCell(_ lines: [String]) -> CellInfo {
    guard let line = firstLine(lines, containing: "+QENG:") else { return CellInfo() }
    let parts = csvParts(line.replacingOccurrences(of: "+QENG:", with: "")).map { $0.trimQuotes }
    guard (parts[safe: 2] ?? "").uppercased() == "LTE" else { return CellInfo() }
    // "servingcell",state,"LTE",dup,MCC,MNC,cellID,PCID,EARFCN,band,ULbw,DLbw,TAC,RSRP,RSRQ,RSSI,SINR,CQI,...
    func num(_ i: Int) -> Int? { Int((parts[safe: i] ?? "").trimmed) }
    func str(_ i: Int) -> String? { let v = (parts[safe: i] ?? "").trimmed; return v.isEmpty ? nil : v }
    return CellInfo(
        band: str(9), earfcn: str(8),
        rsrp: num(13), rsrq: num(14), rssi: num(15), sinr: num(16), cqi: num(17),
        dlBw: bwIndex[(parts[safe: 11] ?? "")], ulBw: bwIndex[(parts[safe: 10] ?? "")],
        pci: str(7), cellId: str(6), tac: str(12)
    )
}

func parseUSBNetworkMode(_ lines: [String]) -> String {
    guard let line = firstLine(lines, containing: "+QCFG:") else { return "-" }
    let parts = csvParts(line.replacingOccurrences(of: "+QCFG:", with: ""))
    let mode = (parts.last ?? "-").trimmed
    return "\(usbnetMode[mode] ?? "未知") (\(mode))"
}

func parseApnProfiles(_ lines: [String]) -> [ApnProfile] {
    lines.filter { $0.contains("+CGDCONT:") }.map { l in
        let parts = csvParts(l.replacingOccurrences(of: "+CGDCONT:", with: ""))
        return ApnProfile(cid: (parts[safe: 0] ?? "-").trimmed, type: (parts[safe: 1] ?? "-").trimQuotes, apn: (parts[safe: 2] ?? "-").trimQuotes)
    }
}

func currentApn(_ profiles: [ApnProfile]) -> String {
    let def = profiles.first { $0.cid == "1" } ?? profiles.first
    guard let d = def, d.apn != "-", !d.apn.isEmpty else { return "-" }
    return "\(d.apn) (\(d.type))"
}

func compactLines(_ lines: [String], _ prefix: String) -> String {
    let matched = lines.filter { $0.contains(prefix) }
    guard !matched.isEmpty else { return "-" }
    return matched.map { $0.replacingOccurrences(of: prefix, with: "").trimmed }.joined(separator: "\n")
}

func parseTemperatures(_ lines: [String]) -> (all: String, avg: String) {
    guard let line = firstLine(lines, containing: "+QTEMP:") else { return ("-", "-") }
    let nums = csvParts(line.replacingOccurrences(of: "+QTEMP:", with: ""))
        .map { $0.trimQuotes.trimmed }
        .compactMap { Int($0) }
        .filter { $0 > -50 && $0 < 200 }
    guard !nums.isEmpty else { return ("-", "-") }
    let avg = Int((Double(nums.reduce(0, +)) / Double(nums.count)).rounded())
    return ("\(nums.map(String.init).joined(separator: " / ")) °C", "\(avg) °C")
}
