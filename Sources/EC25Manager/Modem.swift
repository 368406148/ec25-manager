import AppKit
import Combine
import Darwin
import Foundation

@MainActor
final class Modem: ObservableObject {
    @Published var connected = false
    @Published var busy = false
    @Published var info = ModemInfo()
    @Published var messages: [SMSMessage] = []
    @Published var unreadCount = 0
    @Published var usbDescription = "USB 2c7c:0125"
    @Published var lastError: String?
    @Published var lastUpdated: Date?
    @Published var logLines: [String] = []
    @Published var terminalLines: [String] = []
    @Published var commandRecords: [CommandRecord] = []
    @Published var networkHints: [String] = []

    private let usb = USBTransport()
    private var chain: Task<Void, Never> = Task {}
    private var recoverFails = 0

    // Local persistent log of sent SMS (the modem doesn't store them).
    private let sentLogURL: URL
    private var sentMessages: [SentRecord] = []

    struct SentRecord: Codable { var ts: Double; var to: String; var body: String; var date: String }

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("EC25Manager", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        sentLogURL = base.appendingPathComponent("sent.json")
        loadSentLog()
    }

    // MARK: - Operation serialization

    private func run(_ op: @escaping () async throws -> Void) {
        let previous = chain
        chain = Task { @MainActor in
            _ = await previous.value
            self.busy = true
            self.lastError = nil
            do { try await op() }
            catch {
                self.lastError = error.localizedDescription
                self.log("错误：\(error.localizedDescription)")
            }
            self.busy = false
        }
    }

    // MARK: - Lifecycle

    func start() { connect() }

    func connect() {
        run {
            let res = try await self.openDevice()
            self.connected = true
            self.usbDescription = res
            self.log("已连接 \(res)")
            try await self.initializeSequence()
        }
    }

    func reconnect() {
        run {
            let res = try await self.openDevice()
            self.connected = true
            self.usbDescription = res
            self.log("已重连 \(res)")
            try await self.initializeSequence()
        }
    }

    private func openDevice() async throws -> String {
        try await usb.open()
        return usb.descriptionText
    }

    /// Called by the presence monitor the instant the device leaves the bus.
    func notifyRemoved() {
        guard connected else { return }
        log("设备已移除")
        connected = false
        info = ModemInfo()
        usbDescription = "USB 2c7c:0125"
        usb.close()
        objectWillChange.send()
    }

    /// Called by the presence monitor / poll when disconnected.
    func attemptRecover() {
        guard !connected, !busy else { return }
        run {
            let res = try await self.openDevice()
            self.connected = true
            self.usbDescription = res
            self.log("设备已接入 \(res)")
            try await self.initializeSequence()
            self.lastUpdated = Date()
        }
    }

    func handleWake(restart: Bool) {
        run {
            self.log("从睡眠恢复…")
            let res = try await self.openDevice()
            if restart {
                self.log("休眠恢复：重启模块以恢复网络…")
                _ = try? await self.send("AT+CFUN=1,1", timeout: 4)
                self.notifyRemoved()
                return
            }
            self.connected = true
            self.usbDescription = res
            try await self.initializeSequence()
            self.lastUpdated = Date()
        }
    }

    // MARK: - Public operations

    func refreshInfoOnly() {
        run {
            do { _ = try await self.send("AT", timeout: 2.5) }
            catch { self.notifyRemoved(); return }
            await self.refreshInfo()
            self.lastUpdated = Date()
        }
    }

    func refreshAll() {
        run {
            await self.refreshInfo()
            try await self.refreshMessages()
            self.lastUpdated = Date()
        }
    }

    func refreshMessagesOnly() {
        run {
            try await self.refreshMessages()
            self.lastUpdated = Date()
        }
    }

    func sendSMS(to number: String, body: String) {
        let n = number.trimmed, b = body.trimmed
        guard !n.isEmpty, !b.isEmpty else { return }
        run {
            _ = try await self.send("AT+CMGF=1")
            _ = try await self.send("AT+CSCS=\"UCS2\"")
            _ = try? await self.send("AT+CSMP=17,167,0,8")   // DCS=8 (UCS2) so the receiver isn't empty
            let payload = UCS2.encode(b) + "\u{1A}"
            _ = try await self.send("AT+CMGS=\"\(UCS2.encode(n))\"", payload: payload, timeout: 25)
            self.sentMessages.append(SentRecord(ts: Date().timeIntervalSince1970 * 1000, to: n, body: b, date: modemDateNow()))
            self.saveSentLog()
            try await self.refreshMessages()
            self.lastUpdated = Date()
        }
    }

    func deleteSMS(index: Int, storage: String) {
        run {
            if storage == "SENT" {
                self.sentMessages.removeAll { Int($0.ts) == index }
                self.saveSentLog()
                try await self.refreshMessages()
                return
            }
            _ = try await self.send("AT+CMGF=1")
            _ = try? await self.send("AT+CPMS=\"\(storage)\",\"\(storage)\",\"\(storage)\"")
            _ = try await self.send("AT+CMGD=\(index)")
            try await self.refreshMessages()
            self.lastUpdated = Date()
        }
    }

    func markAllRead() {
        run {
            try await self.markRead(self.messages)
            try await self.refreshMessages()
        }
    }

    func markConversationRead(_ sender: String) {
        run {
            let msgs = self.messages.filter { ($0.sender.isEmpty ? "未知" : $0.sender) == sender }
            guard msgs.contains(where: { $0.unread }) else { return }
            try await self.markRead(msgs)
            try await self.refreshMessages()
        }
    }

    func runTerminalCommand(_ command: String) {
        let c = command.trimmed
        guard !c.isEmpty else { return }
        run {
            self.appendTerminal("> \(c)")
            do {
                let lines = try await self.send(c, timeout: 15)
                if lines.isEmpty { self.appendTerminal("OK") }
                else { lines.forEach { self.appendTerminal($0) }; self.appendTerminal("OK") }
            } catch {
                self.appendTerminal("ERROR: \(error.localizedDescription)")
                throw error
            }
        }
    }

    func setUsbMode(_ mode: Int) {
        run {
            _ = try await self.send("AT+QCFG=\"usbnet\",\(mode)", timeout: 8)
            _ = try await self.send("AT+QCFG=\"usbnet\"", timeout: 6)
            await self.refreshInfo()
            self.lastUpdated = Date()
        }
    }

    func setApn(_ apn: String, cid: Int = 1, type: String = "IPV4V6") {
        let a = apn.trimmed
        guard !a.isEmpty else { return }
        run {
            _ = try await self.send("AT+CGDCONT=\(cid),\"\(type)\",\"\(a)\"", timeout: 8)
            await self.refreshInfo()
            self.lastUpdated = Date()
        }
    }

    func researchNetwork() {
        run {
            self.log("开始重新搜索网络…")
            _ = try? await self.send("AT+COPS=2", timeout: 20)
            _ = try? await self.send("AT+COPS=0", timeout: 60)
            await self.refreshInfo()
            self.lastUpdated = Date()
        }
    }

    func restartModule() {
        run {
            _ = try? await self.send("AT+CFUN=1,1", timeout: 4)
            self.notifyRemoved()
            self.log("模块重启中，等待重新枚举…")
        }
    }

    // MARK: - Internals

    private func initializeSequence() async throws {
        _ = try await send("AT", timeout: 5)
        _ = try await send("ATE0", timeout: 5)
        _ = try await send("AT+CMEE=2")
        _ = try await send("AT+CMGF=1")
        _ = try await send("AT+CSCS=\"UCS2\"")
        _ = try? await send("AT+CNMI=2,1,0,0,0")
        await refreshInfo()
        try await refreshMessages()
        lastUpdated = Date()
    }

    private func refreshInfo() async {
        refreshNetworkHints()
        commandRecords = []

        let manufacturer = await query("厂商", "AT+CGMI")
        let model = await query("型号", "AT+CGMM")
        let revision = await query("固件", "AT+CGMR")
        let imei = await query("IMEI", "AT+CGSN")
        let imsi = await query("IMSI", "AT+CIMI")
        let iccid = await query("ICCID", "AT+QCCID")
        let ownNumber = await query("本机号码", "AT+CNUM")
        let sim = await query("SIM 状态", "AT+CPIN?")
        let simInserted = await query("SIM 插入", "AT+QSIMSTAT?")
        let cops = await query("运营商", "AT+COPS?")
        let signal = await query("信号", "AT+CSQ")
        let creg = await query("CS 注册", "AT+CREG?")
        let cgreg = await query("PS 注册", "AT+CGREG?")
        let cereg = await query("EPS 注册", "AT+CEREG?")
        let cgatt = await query("分组附着", "AT+CGATT?")
        let cgact = await query("PDP 激活", "AT+CGACT?")
        let cgpaddr = await query("PDP 地址", "AT+CGPADDR")
        let qnwinfo = await query("数据网络类型", "AT+QNWINFO")
        let serving = await query("服务小区", "AT+QENG=\"servingcell\"", timeout: 8)
        let ca = await query("载波聚合", "AT+QCAINFO", timeout: 8)
        let usbnet = await query("USB 网络模式", "AT+QCFG=\"usbnet\"")
        let cgdcont = await query("APN/PDP 配置", "AT+CGDCONT?", timeout: 8)
        let qtemp = await query("温度", "AT+QTEMP")

        var csq = parseSignal(signal)
        let net = parseNetworkType(qnwinfo)
        let cell = parseServingCell(serving)
        let temp = parseTemperatures(qtemp)

        let band = cell.band ?? (net.band != "-" ? net.band.filter(\.isNumber) : "-")
        let earfcn = cell.earfcn ?? (net.channel != "-" ? net.channel : "-")
        let freq = earfcnToDlMhz(band: band, earfcn: earfcn)
        if let b = barsFromRsrp(cell.rsrp) { csq.bars = b }

        let profiles = parseApnProfiles(cgdcont)
        info = ModemInfo(
            manufacturer: firstNonCommandLine(manufacturer) ?? "-",
            model: firstNonCommandLine(model) ?? "-",
            revision: firstNonCommandLine(revision) ?? "-",
            imei: firstNonCommandLine(imei) ?? "-",
            imsi: firstNonCommandLine(imsi) ?? "-",
            iccid: parseICCID(iccid),
            ownNumber: parseOwnNumber(ownNumber),
            simStatus: parsePrefixed(sim, "+CPIN:"),
            simInserted: parsePrefixed(simInserted, "+QSIMSTAT:"),
            operatorName: parseOperator(cops),
            signal: csq,
            ber: parseBER(signal),
            registration: parseRegistration(creg, "+CREG:"),
            gprsRegistration: parseRegistration(cgreg, "+CGREG:"),
            epsRegistration: parseRegistration(cereg, "+CEREG:"),
            packetAttached: parsePrefixed(cgatt, "+CGATT:"),
            activePdp: compactLines(cgact, "+CGACT:"),
            pdpAddress: compactLines(cgpaddr, "+CGPADDR:"),
            dataNetworkType: net.full,
            networkLabel: net.label,
            tech: parseTech(cops, fallback: net.label),
            band: band != "-" && !band.isEmpty ? "Band \(band)" : "-",
            channel: earfcn,
            earfcn: earfcn,
            freqMhz: freq != nil ? "\(freq!) MHz" : "-",
            servingCell: compactLines(serving, "+QENG:"),
            carrierAggregation: compactLines(ca, "+QCAINFO:"),
            usbNetworkMode: parseUSBNetworkMode(usbnet),
            apnProfiles: profiles,
            currentApn: currentApn(profiles),
            rsrp: cell.rsrp != nil ? "\(cell.rsrp!) dBm" : "-",
            rsrq: cell.rsrq != nil ? "\(cell.rsrq!) dB" : "-",
            rssiDbm: cell.rssi != nil ? "\(cell.rssi!) dBm" : csq.text,
            sinr: cell.sinr != nil ? "\(cell.sinr!)" : "-",
            cqi: cell.cqi != nil ? "\(cell.cqi!)" : "-",
            modulation: cqiToModulation(cell.cqi),
            dlBandwidth: cell.dlBw ?? "-",
            ulBandwidth: cell.ulBw ?? "-",
            pci: cell.pci ?? "-",
            cellId: cell.cellId ?? "-",
            tac: cell.tac ?? "-",
            temperature: temp.all,
            temperatureAvg: temp.avg
        )
    }

    private func refreshMessages() async throws {
        _ = try await send("AT+CMGF=1")
        _ = try await send("AT+CSCS=\"UCS2\"")
        var all: [SMSMessage] = []
        for storage in ["ME", "SM"] {
            do { _ = try await send("AT+CPMS=\"\(storage)\",\"\(storage)\",\"\(storage)\"") }
            catch { continue }
            let lines = (try? await send("AT+CMGL=\"ALL\"", timeout: 12)) ?? []
            all.append(contentsOf: parseMessageList(lines, storage: storage))
        }
        all.append(contentsOf: sentAsMessages())
        all.sort { a, b in a.date == b.date ? b.index < a.index : a.date > b.date }
        messages = all
        unreadCount = all.filter(\.unread).count
    }

    private func markRead(_ msgs: [SMSMessage]) async throws {
        let targets = msgs.filter { $0.unread && $0.storage != "SENT" }
        guard !targets.isEmpty else { return }
        var byStorage: [String: [Int]] = [:]
        for m in targets { byStorage[m.storage, default: []].append(m.index) }
        _ = try await send("AT+CMGF=1")
        for (storage, indices) in byStorage {
            _ = try? await send("AT+CPMS=\"\(storage)\",\"\(storage)\",\"\(storage)\"")
            for idx in indices { _ = try? await send("AT+CMGR=\(idx)", timeout: 6) }
        }
    }

    private func parseMessageList(_ lines: [String], storage: String) -> [SMSMessage] {
        var parsed: [SMSMessage] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            guard line.hasPrefix("+CMGL:") else { i += 1; continue }
            let parts = csvParts(line.replacingOccurrences(of: "+CMGL:", with: ""))
            let index = Int((parts[safe: 0] ?? "").trimmed) ?? 0
            let raw = (parts[safe: 1] ?? "").trimQuotes
            let status = msgStatus[raw] ?? raw
            let sender = UCS2.decode((parts[safe: 2] ?? "-").trimQuotes)
            let date = (parts[safe: 4] ?? "-").trimQuotes
            var body: [String] = []
            i += 1
            while i < lines.count, !lines[i].hasPrefix("+CMGL:") {
                body.append(UCS2.decode(lines[i])); i += 1
            }
            let upper = status.uppercased()
            parsed.append(SMSMessage(
                id: "\(storage)-\(index)", storage: storage, index: index, status: status,
                outgoing: upper.contains("STO") || upper.contains("SENT"),
                unread: upper.contains("UNREAD"), sender: sender, date: date, body: body.joined(separator: "\n")
            ))
        }
        return parsed
    }

    private func sentAsMessages() -> [SMSMessage] {
        sentMessages.map {
            SMSMessage(id: "SENT-\(Int($0.ts))", storage: "SENT", index: Int($0.ts), status: "STO SENT",
                       outgoing: true, unread: false, sender: $0.to, date: $0.date, body: $0.body)
        }
    }

    // MARK: - AT plumbing

    @discardableResult
    private func send(_ command: String, payload: String? = nil, timeout: TimeInterval = 4) async throws -> [String] {
        log("> \(command)")
        let lines = try await usb.send(command, payload: payload, timeout: timeout)
        if lines.isEmpty { log("< OK") } else { lines.forEach { log("< \($0)") } }
        return lines
    }

    private func query(_ title: String, _ command: String, timeout: TimeInterval = 5) async -> [String] {
        do {
            let lines = try await send(command, timeout: timeout)
            commandRecords.append(CommandRecord(title: title, command: command, lines: lines, error: nil))
            return lines
        } catch {
            commandRecords.append(CommandRecord(title: title, command: command, lines: [], error: error.localizedDescription))
            return []
        }
    }

    private func log(_ line: String) {
        logLines.append(line)
        if logLines.count > 600 { logLines.removeFirst(logLines.count - 600) }
    }

    private func appendTerminal(_ line: String) {
        terminalLines.append(line)
        if terminalLines.count > 600 { terminalLines.removeFirst(terminalLines.count - 600) }
    }

    private func refreshNetworkHints() {
        var hints: [String] = []
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { networkHints = []; return }
        defer { freeifaddrs(ifap) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = cursor {
            defer { cursor = cur.pointee.ifa_next }
            guard let addr = cur.pointee.ifa_addr, Int32(addr.pointee.sa_family) == AF_INET else { continue }
            guard cur.pointee.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let name = String(cString: cur.pointee.ifa_name)
            let ip = host.withUnsafeBufferPointer { $0.baseAddress.map { String(cString: $0) } ?? "" }
            if ip.hasPrefix("192.168.225.") { hints.append("\(name) · \(ip)") }
        }
        networkHints = hints.sorted()
    }

    // MARK: - Sent log persistence

    private func loadSentLog() {
        guard let data = try? Data(contentsOf: sentLogURL),
              let arr = try? JSONDecoder().decode([SentRecord].self, from: data) else { return }
        sentMessages = arr
    }

    private func saveSentLog() {
        guard let data = try? JSONEncoder().encode(sentMessages) else { return }
        try? data.write(to: sentLogURL)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

func modemDateNow() -> String {
    let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date())
    func p(_ n: Int) -> String { String(format: "%02d", n) }
    return "\(p((c.year ?? 0) % 100))/\(p(c.month ?? 0))/\(p(c.day ?? 0)),\(p(c.hour ?? 0)):\(p(c.minute ?? 0)):\(p(c.second ?? 0))"
}
