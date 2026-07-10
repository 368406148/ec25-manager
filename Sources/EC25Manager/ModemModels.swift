import Foundation

// MARK: - Signal

struct Signal: Equatable {
    var dbm: Int?
    var bars: Int = 0        // 0...4
    var percent: Int = 0
    var text: String = "-"
}

// MARK: - Modem info

struct ModemInfo: Equatable {
    var manufacturer = "-"
    var model = "-"
    var revision = "-"
    var imei = "-"
    var imsi = "-"
    var iccid = "-"
    var ownNumber = "-"
    var simStatus = "-"
    var simInserted = "-"
    var operatorName = "-"
    var signal = Signal()
    var ber = "-"
    var registration = "-"        // CS
    var gprsRegistration = "-"    // PS
    var epsRegistration = "-"     // EPS
    var packetAttached = "-"
    var activePdp = "-"
    var pdpAddress = "-"
    var dataNetworkType = "-"
    var networkLabel = "-"
    var tech = "-"
    var band = "-"
    var channel = "-"             // EARFCN
    var earfcn = "-"
    var freqMhz = "-"
    var servingCell = "-"
    var carrierAggregation = "-"
    var usbNetworkMode = "-"
    var apnProfiles: [ApnProfile] = []
    var currentApn = "-"
    var rsrp = "-"
    var rsrq = "-"
    var rssiDbm = "-"
    var sinr = "-"
    var cqi = "-"
    var modulation = "-"
    var dlBandwidth = "-"
    var ulBandwidth = "-"
    var pci = "-"
    var cellId = "-"
    var tac = "-"
    var temperature = "-"
    var temperatureAvg = "-"
}

struct ApnProfile: Equatable, Identifiable {
    var id: String { cid }
    var cid: String
    var type: String
    var apn: String
}

// MARK: - SMS

struct SMSMessage: Identifiable, Equatable {
    let id: String        // "storage-index" or "SENT-ts"
    let storage: String   // ME | SM | SENT
    let index: Int
    let status: String
    let outgoing: Bool
    let unread: Bool
    let sender: String
    let date: String
    let body: String
}

struct Conversation: Identifiable {
    var id: String { key }
    let key: String
    let messages: [SMSMessage]
    let last: SMSMessage
    let unread: Int
}

func groupConversations(_ messages: [SMSMessage]) -> [Conversation] {
    var map: [String: [SMSMessage]] = [:]
    for m in messages {
        let key = (m.sender.isEmpty || m.sender == "-") ? "未知" : m.sender
        map[key, default: []].append(m)
    }
    var convs: [Conversation] = map.map { key, msgs in
        let sorted = msgs.sorted { a, b in a.date == b.date ? a.index < b.index : a.date < b.date }
        return Conversation(key: key, messages: sorted, last: sorted.last!, unread: sorted.filter { $0.unread }.count)
    }
    convs.sort { $0.last.date > $1.last.date }
    return convs
}

// MARK: - Overview field catalog (selectable status fields)

struct InfoField: Identifiable {
    let key: String
    let label: String
    var wide = false
    var mono = false
    let get: (ModemInfo) -> String
    var id: String { key }
}

let fieldCatalog: [InfoField] = [
    InfoField(key: "dataNetworkType", label: "数据网络类型", wide: true) { $0.dataNetworkType },
    InfoField(key: "operator", label: "运营商") { $0.operatorName },
    InfoField(key: "tech", label: "网络制式") { $0.tech },
    InfoField(key: "regCS", label: "CS 注册") { $0.registration },
    InfoField(key: "regPS", label: "PS 注册") { $0.gprsRegistration },
    InfoField(key: "regEPS", label: "EPS 注册") { $0.epsRegistration },
    InfoField(key: "attach", label: "分组附着") { $0.packetAttached == "1" ? "已附着" : ($0.packetAttached == "0" ? "未附着" : $0.packetAttached) },
    InfoField(key: "imei", label: "IMEI", mono: true) { $0.imei },
    InfoField(key: "imsi", label: "IMSI", mono: true) { $0.imsi },
    InfoField(key: "iccid", label: "ICCID", wide: true, mono: true) { $0.iccid },
    InfoField(key: "simStatus", label: "SIM 状态") { $0.simStatus },
    InfoField(key: "simInserted", label: "SIM 插入") { $0.simInserted },
    InfoField(key: "ownNumber", label: "本机号码") { $0.ownNumber },
    InfoField(key: "pdp", label: "PDP 地址", wide: true, mono: true) { $0.pdpAddress },
    InfoField(key: "band", label: "频段") { $0.band },
    InfoField(key: "earfcn", label: "信道 (EARFCN)") { $0.earfcn },
    InfoField(key: "freq", label: "下行频率") { $0.freqMhz },
    InfoField(key: "rsrp", label: "RSRP") { $0.rsrp },
    InfoField(key: "rsrq", label: "RSRQ") { $0.rsrq },
    InfoField(key: "rssi", label: "RSSI") { $0.rssiDbm },
    InfoField(key: "sinr", label: "SINR") { $0.sinr },
    InfoField(key: "cqi", label: "CQI") { $0.cqi },
    InfoField(key: "modulation", label: "调制状态") { $0.modulation },
    InfoField(key: "dlbw", label: "下行带宽") { $0.dlBandwidth },
    InfoField(key: "ulbw", label: "上行带宽") { $0.ulBandwidth },
    InfoField(key: "pci", label: "PCI") { $0.pci },
    InfoField(key: "cellId", label: "Cell ID", mono: true) { $0.cellId },
    InfoField(key: "tac", label: "TAC") { $0.tac },
    InfoField(key: "temp", label: "模组温度") { $0.temperature },
    InfoField(key: "tempAvg", label: "平均温度") { $0.temperatureAvg },
    InfoField(key: "ber", label: "BER") { $0.ber },
    InfoField(key: "usbnet", label: "USB 模式") { $0.usbNetworkMode }
]

func fieldCatalogEntry(_ key: String) -> InfoField? {
    fieldCatalog.first { $0.key == key }
}

// MARK: - Command log record

struct CommandRecord: Identifiable {
    let id = UUID()
    let title: String
    let command: String
    let lines: [String]
    let error: String?
}
