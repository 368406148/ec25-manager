import SwiftUI

enum Tab: String, CaseIterable, Identifiable { case overview = "概览", sms = "短信", terminal = "终端", settings = "设置"; var id: String { rawValue } }

struct RootView: View {
    @EnvironmentObject var modem: Modem
    @EnvironmentObject var settings: AppSettings
    @State private var tab: Tab = .overview
    @Namespace private var tabNS

    var body: some View {
        VStack(spacing: 0) {
            header
            hero
            tabBar
            Divider().opacity(0.35)
            content
        }
        .frame(width: 440, height: 620)
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(LinearGradient(colors: [Palette.brandC, Palette.brand2C], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 38, height: 38)
                .overlay(Text("EC").font(.system(size: 15, weight: .heavy)).foregroundStyle(.white))
                .shadow(color: Palette.brandC.opacity(0.35), radius: 6, y: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text("EC25 Manager").font(.system(size: 15, weight: .bold))
                Text(modem.connected ? modem.usbDescription : "设备未连接")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                    .contentTransition(.opacity)
            }
            Spacer()
            statusPill
            Button { modem.refreshAll() } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(modem.busy ? 360 : 0))
                    .animation(modem.busy ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: modem.busy)
            }
            .buttonStyle(.borderless).help("刷新")
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
    }

    private var statusPill: some View {
        let connected = modem.connected
        let color: Color = connected ? Palette.goodC : (modem.busy ? Palette.warnC : Palette.dangerC)
        let text = connected ? (modem.busy ? "执行中" : "在线") : (modem.busy ? "连接中" : "离线")
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.7), radius: 4)
            Text(text).font(.system(size: 12, weight: .semibold)).contentTransition(.opacity)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .glassCard(cornerRadius: 999)
        .animation(.smooth, value: connected)
        .animation(.smooth, value: modem.busy)
    }

    // MARK: hero

    private var hero: some View {
        HStack {
            HStack(spacing: 14) {
                SignalBars(bars: modem.info.signal.bars)
                VStack(alignment: .leading, spacing: 3) {
                    Text(heroSignal).font(.system(size: 22, weight: .heavy)).contentTransition(.numericText())
                    HStack(spacing: 6) {
                        Badge(text: modem.info.networkLabel == "-" ? "--" : modem.info.networkLabel)
                        Text(modem.info.operatorName == "-" ? "--" : modem.info.operatorName)
                            .font(.system(size: 12)).foregroundStyle(.secondary).contentTransition(.opacity)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("注册状态").font(.system(size: 11)).foregroundStyle(.secondary)
                Text(regValue).font(.system(size: 14, weight: .bold)).contentTransition(.opacity)
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 16, tint: Palette.brandC.opacity(0.35))
        .padding(.horizontal, 16).padding(.bottom, 10)
        .animation(.smooth, value: modem.info.signal.bars)
    }

    private var heroSignal: String {
        if modem.info.rsrp != "-" { return modem.info.rsrp }
        if let dbm = modem.info.signal.dbm { return "\(dbm) dBm" }
        return modem.connected ? "未知" : "-- dBm"
    }
    private var regValue: String { modem.info.epsRegistration != "-" ? modem.info.epsRegistration : modem.info.registration }

    // MARK: tabs

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { t in
                Button { withAnimation(.snappy(duration: 0.28)) { tab = t } } label: {
                    HStack(spacing: 4) {
                        Text(t.rawValue).font(.system(size: 13, weight: .semibold))
                        if t == .sms && modem.unreadCount > 0 {
                            Circle().fill(Palette.dangerC).frame(width: 6, height: 6)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
                    .foregroundStyle(tab == t ? Color.primary : Color.secondary)
                    .background {
                        if tab == t {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.primary.opacity(0.10))
                                .matchedGeometryEffect(id: "tabSel", in: tabNS)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
        .padding(.horizontal, 16).padding(.bottom, 10)
        .animation(.snappy, value: modem.unreadCount)
    }

    @ViewBuilder private var content: some View {
        ZStack {
            switch tab {
            case .overview: OverviewView().transition(contentTransition)
            case .sms: MessagesView().transition(contentTransition)
            case .terminal: TerminalView().transition(contentTransition)
            case .settings: SettingsView().transition(contentTransition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var contentTransition: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity)
    }
}
