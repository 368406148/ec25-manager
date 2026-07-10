import SwiftUI

struct MessagesView: View {
    @EnvironmentObject var modem: Modem
    @State private var inThread = false
    @State private var activeSender: String?
    @State private var toField = ""
    @State private var bodyField = ""

    private var conversations: [Conversation] { groupConversations(modem.messages) }

    var body: some View {
        ZStack {
            if inThread { threadView.transition(.move(edge: .trailing).combined(with: .opacity)) }
            else { listView.transition(.move(edge: .leading).combined(with: .opacity)) }
        }
        .animation(.snappy(duration: 0.3), value: inThread)
    }

    // MARK: list

    private var listView: some View {
        VStack(spacing: 0) {
            HStack {
                Text(convCountText).font(.system(size: 12)).foregroundStyle(.secondary).contentTransition(.numericText())
                Spacer()
                if modem.unreadCount > 0 {
                    Button("全部已读") { modem.markAllRead() }.buttonStyle(MiniButton(accent: true))
                        .transition(.scale.combined(with: .opacity))
                }
                Button("＋ 新建") { open(nil) }.buttonStyle(MiniButton())
                Button("刷新") { modem.refreshMessagesOnly() }.buttonStyle(MiniButton())
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .animation(.snappy, value: modem.unreadCount)

            if conversations.isEmpty {
                Spacer(); Text("暂无短信").foregroundStyle(.secondary).font(.system(size: 12)); Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(conversations) { convRow($0) }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 12)
                    .animation(.smooth, value: modem.messages.count)
                }
            }
        }
    }

    private func convRow(_ c: Conversation) -> some View {
        Button { open(c.key) } label: {
            HStack(spacing: 11) {
                Circle().fill(LinearGradient(colors: [Palette.brandC, Palette.brand2C], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 38, height: 38)
                    .overlay(Text(avatar(c.key)).font(.system(size: 13, weight: .bold)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(c.key).font(.system(size: 13.5, weight: c.unread > 0 ? .heavy : .bold)).lineLimit(1)
                        Spacer()
                        Text(c.last.date.components(separatedBy: ",").first ?? "").font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                    Text(c.last.body.replacingOccurrences(of: "\n", with: " ")).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                countBadge(c)
            }
            .padding(11).tileBackground()
        }
        .buttonStyle(.plain)
    }

    private func countBadge(_ c: Conversation) -> some View {
        Text("\(c.unread > 0 ? c.unread : c.messages.count)")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(c.unread > 0 ? .white : .secondary)
            .frame(minWidth: 20).padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill(c.unread > 0 ? AnyShapeStyle(Palette.brandC) : AnyShapeStyle(Color.primary.opacity(0.10))))
    }

    // MARK: thread

    private var threadView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { inThread = false } label: { Image(systemName: "chevron.left") }.buttonStyle(MiniButton())
                Text(activeSender ?? "新短信").font(.system(size: 15, weight: .bold)).lineLimit(1)
                Spacer()
                if activeSender != nil {
                    Button("清空") { clear() }.buttonStyle(MiniButton(destructive: true))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(threadMessages) { bubble($0) }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .animation(.smooth, value: threadMessages.count)
                }
                .onChange(of: threadMessages.count) { proxy.scrollTo("bottom", anchor: .bottom) }
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            }

            composer
        }
    }

    private func bubble(_ m: SMSMessage) -> some View {
        HStack {
            if m.outgoing { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 4) {
                Text(m.body).font(.system(size: 13)).textSelection(.enabled).foregroundStyle(m.outgoing ? .white : .primary)
                Text(m.date).font(.system(size: 9.5)).foregroundStyle(m.outgoing ? Color.white.opacity(0.7) : .secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background {
                if m.outgoing {
                    LinearGradient(colors: [Palette.brandC, Palette.brand2C.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.09))
                }
            }
            .frame(maxWidth: 320, alignment: m.outgoing ? .trailing : .leading)
            .contextMenu { Button("删除", role: .destructive) { modem.deleteSMS(index: m.index, storage: m.storage) } }
            if !m.outgoing { Spacer(minLength: 40) }
        }
        .transition(.scale(scale: 0.9, anchor: m.outgoing ? .bottomTrailing : .bottomLeading).combined(with: .opacity))
    }

    private var composer: some View {
        VStack(spacing: 8) {
            TextField("收件人号码", text: $toField).textFieldStyle(.roundedBorder).disabled(activeSender != nil)
            HStack(alignment: .bottom, spacing: 8) {
                TextField("输入短信内容（支持中文）", text: $bodyField, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(1...3)
                sendButton
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 12).padding(.top, 6)
    }

    @ViewBuilder private var sendButton: some View {
        let label = Image(systemName: "paperplane.fill").foregroundStyle(.white).frame(width: 40, height: 40)
        if #available(macOS 26.0, *) {
            Button { send() } label: { label.glassEffect(Glass.regular.tint(Palette.brandC), in: .circle) }.buttonStyle(.plain)
        } else {
            Button { send() } label: { label.background(Circle().fill(Palette.brandC)) }.buttonStyle(.plain)
        }
    }

    private var threadMessages: [SMSMessage] {
        guard let s = activeSender else { return [] }
        return modem.messages.filter { ($0.sender.isEmpty ? "未知" : $0.sender) == s }
            .sorted { a, b in a.date == b.date ? a.index < b.index : a.date < b.date }
    }

    // MARK: actions

    private func open(_ sender: String?) {
        activeSender = sender; toField = sender ?? ""; bodyField = ""; inThread = true
        if let s = sender, modem.messages.contains(where: { ($0.sender.isEmpty ? "未知" : $0.sender) == s && $0.unread }) {
            modem.markConversationRead(s)
        }
    }
    private func send() {
        let to = toField.trimmingCharacters(in: .whitespaces), body = bodyField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !to.isEmpty, !body.isEmpty else { return }
        modem.sendSMS(to: to, body: body); bodyField = ""
        if activeSender == nil { activeSender = to }
    }
    private func clear() {
        guard let s = activeSender else { return }
        for m in modem.messages.filter({ ($0.sender.isEmpty ? "未知" : $0.sender) == s }) { modem.deleteSMS(index: m.index, storage: m.storage) }
        inThread = false
    }
    private var convCountText: String {
        let unread = conversations.reduce(0) { $0 + $1.unread }
        return "\(conversations.count) 个会话" + (unread > 0 ? " · \(unread) 未读" : "")
    }
    private func avatar(_ name: String) -> String {
        let d = name.filter(\.isNumber); return d.count >= 2 ? String(d.suffix(2)) : String(name.prefix(2))
    }
}

struct MiniButton: ButtonStyle {
    var accent = false
    var destructive = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: accent ? .bold : .regular))
            .foregroundStyle(accent ? .white : (destructive ? Palette.dangerC : .primary))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(accent ? AnyShapeStyle(Palette.brandC) : AnyShapeStyle(Color.primary.opacity(0.06))))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}
