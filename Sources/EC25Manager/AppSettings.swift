import Foundation

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    @Published var openAtLogin: Bool { didSet { d.set(openAtLogin, forKey: "openAtLogin") } }
    @Published var infoPollSeconds: Int { didSet { d.set(infoPollSeconds, forKey: "infoPollSeconds") } }
    @Published var smsPollSeconds: Int { didSet { d.set(smsPollSeconds, forKey: "smsPollSeconds") } }
    @Published var restartOnWake: Bool { didSet { d.set(restartOnWake, forKey: "restartOnWake") } }
    @Published var hideWhenDisconnected: Bool { didSet { d.set(hideWhenDisconnected, forKey: "hideWhenDisconnected") } }
    @Published var visibleFields: [String] { didSet { d.set(visibleFields, forKey: "visibleFields") } }

    static let defaultFields = [
        "dataNetworkType", "operator", "regEPS", "imei", "imsi", "iccid",
        "simStatus", "ownNumber", "rsrp", "rsrq", "sinr", "modulation",
        "temp", "tempAvg", "band", "freq", "usbnet"
    ]

    private init() {
        openAtLogin = d.object(forKey: "openAtLogin") as? Bool ?? true
        infoPollSeconds = d.object(forKey: "infoPollSeconds") as? Int ?? 12
        smsPollSeconds = d.object(forKey: "smsPollSeconds") as? Int ?? 30
        restartOnWake = d.object(forKey: "restartOnWake") as? Bool ?? true
        hideWhenDisconnected = d.object(forKey: "hideWhenDisconnected") as? Bool ?? false
        let saved = d.array(forKey: "visibleFields") as? [String]
        visibleFields = (saved?.isEmpty == false) ? saved! : AppSettings.defaultFields
    }

    func toggleField(_ key: String, on: Bool) {
        var set = visibleFields
        if on {
            if !set.contains(key) {
                set.append(key)
                let order = fieldCatalog.map(\.key)
                set = order.filter { set.contains($0) }
            }
        } else {
            set.removeAll { $0 == key }
        }
        visibleFields = set
    }
}
