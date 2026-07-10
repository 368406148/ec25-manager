import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var modem: Modem
    @EnvironmentObject var settings: AppSettings
    @State private var usbMode = 1
    @State private var apnField = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                general
                fieldsCard
                usbCard
                apnCard
                actionsCard
                deviceCard
            }
            .padding(16)
        }
        .onAppear { usbMode = currentUsbMode() }
    }

    private var general: some View {
        SectionCard(title: "通用") {
            Toggle("开机自动启动到菜单栏", isOn: $settings.openAtLogin)
            Divider().opacity(0.25)
            HStack {
                Text("状态刷新间隔"); Spacer()
                Picker("", selection: $settings.infoPollSeconds) {
                    ForEach([6, 10, 12, 15, 20, 30], id: \.self) { Text("\($0) 秒").tag($0) }
                }.labelsHidden().frame(width: 96)
            }
            HStack {
                Text("短信轮询间隔"); Spacer()
                Picker("", selection: $settings.smsPollSeconds) {
                    Text("关闭").tag(0)
                    ForEach([15, 30, 60, 120], id: \.self) { Text("\($0) 秒").tag($0) }
                }.labelsHidden().frame(width: 96)
            }
            Toggle("休眠唤醒后重启模块（恢复网络）", isOn: $settings.restartOnWake)
            Toggle("仅在设备连接时显示菜单栏图标", isOn: $settings.hideWhenDisconnected)
        }
        .font(.system(size: 13))
    }

    private var fieldsCard: some View {
        SectionCard(title: "状态信息展示") {
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 7) {
                ForEach(fieldCatalog) { f in
                    Toggle(f.label, isOn: Binding(
                        get: { settings.visibleFields.contains(f.key) },
                        set: { settings.toggleField(f.key, on: $0) }
                    )).toggleStyle(.checkbox).font(.system(size: 12.5))
                }
            }
        }
    }

    private var usbCard: some View {
        SectionCard(title: "USB 网络模式") {
            HStack {
                Picker("", selection: $usbMode) {
                    Text("QMI").tag(0); Text("ECM").tag(1); Text("MBIM").tag(2); Text("RNDIS").tag(3)
                }.labelsHidden()
                Button("应用") { modem.setUsbMode(usbMode) }.buttonStyle(.borderedProminent)
            }
            Text("当前：\(modem.info.usbNetworkMode)").font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
    }

    private var apnCard: some View {
        SectionCard(title: "APN 配置") {
            HStack {
                Text("当前 APN").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Text(modem.info.currentApn).font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.goodC).contentTransition(.opacity)
            }
            HStack {
                TextField("输入新的 APN", text: $apnField).textFieldStyle(.roundedBorder)
                Button("设置") { modem.setApn(apnField); apnField = "" }.buttonStyle(.borderedProminent)
            }
            Text("全部配置：\n" + apnAll).font(.system(size: 11.5)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actionsCard: some View {
        SectionCard(title: "模块操作") {
            HStack {
                Button("重新搜索网络") { modem.researchNetwork() }
                Button("重连设备") { modem.reconnect() }
                Button("重启模块") { modem.restartModule() }.foregroundStyle(Palette.dangerC)
            }
            Text("ECM 网络：" + (modem.networkHints.isEmpty ? "未检测到 192.168.225.x" : modem.networkHints.joined(separator: "\n")))
                .font(.system(size: 11.5)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var deviceCard: some View {
        SectionCard(title: "设备信息") {
            kv("厂商", modem.info.manufacturer)
            kv("型号", modem.info.model)
            kv("固件", modem.info.revision)
            HStack { Spacer(); Button("退出应用") { NSApp.terminate(nil) } }
        }
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(.secondary); Spacer(); Text(v).fontWeight(.semibold) }.font(.system(size: 13))
    }

    private var apnAll: String {
        let s = modem.info.apnProfiles.map { "cid\($0.cid): \($0.apn) (\($0.type))" }.joined(separator: "\n")
        return s.isEmpty ? "-" : s
    }
    private func currentUsbMode() -> Int {
        if let r = modem.info.usbNetworkMode.range(of: #"\((\d)\)"#, options: .regularExpression) {
            return Int(modem.info.usbNetworkMode[r].filter(\.isNumber)) ?? 1
        }
        return 1
    }
}
