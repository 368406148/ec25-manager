import AppKit
import Combine

@MainActor
final class PopoverController: NSViewController {
    private let modem: Modem
    private let settings: AppSettings
    private var cancellables = Set<AnyCancellable>()

    private enum TabKind: String, CaseIterable { case overview = "概览", sms = "短信", terminal = "终端", settings = "设置" }
    private var tab: TabKind = .overview

    // header / hero
    private let statusDot = NSView()
    private let statusText = NSTextField(labelWithString: "连接中")
    private let usbDesc = NSTextField(labelWithString: "USB 2c7c:0125")
    private let refreshButton = NSButton()
    private let signalBars = SignalBarsView()
    private let heroDbm = NSTextField(labelWithString: "-- dBm")
    private let netBadge = BadgeLabel(text: "--")
    private let heroOperator = NSTextField(labelWithString: "--")
    private let regValue = NSTextField(labelWithString: "--")

    private var tabButtons: [TabKind: NSButton] = [:]
    private let smsTabDot = NSView()
    private let contentBox = NSView()

    // overview
    private let infoGrid = NSStackView()
    private let caText = NSTextField(wrappingLabelWithString: "-")

    // sms
    private var smsMode: SMSMode = .list
    private enum SMSMode { case list, thread(String?) }
    private let smsCount = NSTextField(labelWithString: "0 个会话")
    private let markReadButton = NSButton()
    private let convStack = NSStackView()
    private let threadStack = NSStackView()
    private let threadTitle = NSTextField(labelWithString: "新短信")
    private let clearButton = NSButton()
    private let smsTo = NSTextField()
    private let smsBody = NSTextView()
    private var smsListContainer = NSView()
    private var smsThreadContainer = NSView()

    // terminal
    private let terminalText = NSTextView()
    private let atInput = NSTextField()

    // settings
    private let loginCheck = NSButton(checkboxWithTitle: "开机自动启动到菜单栏", target: nil, action: nil)
    private let wakeCheck = NSButton(checkboxWithTitle: "休眠唤醒后重启模块（恢复网络）", target: nil, action: nil)
    private let hideCheck = NSButton(checkboxWithTitle: "仅在设备连接时显示菜单栏图标", target: nil, action: nil)
    private let infoPollPopup = NSPopUpButton()
    private let smsPollPopup = NSPopUpButton()
    private var fieldChecks: [String: NSButton] = [:]
    private let usbPopup = NSPopUpButton()
    private let usbCurrent = NSTextField(labelWithString: "当前：-")
    private let apnField = NSTextField()
    private let apnCurrent = NSTextField(labelWithString: "当前 APN -")
    private let apnAll = NSTextField(wrappingLabelWithString: "全部配置：-")
    private let ecmHint = NSTextField(wrappingLabelWithString: "ECM 网络：-")
    private let devManu = NSTextField(labelWithString: "-")
    private let devModel = NSTextField(labelWithString: "-")
    private let devRev = NSTextField(labelWithString: "-")

    init(modem: Modem, settings: AppSettings) {
        self.modem = modem
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 620))
        buildUI()
        modem.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in self?.refreshUI() }.store(in: &cancellables)
        settings.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in self?.refreshUI() }.store(in: &cancellables)
        selectTab(.overview)
        refreshUI()
    }

    // MARK: - Build

    private func buildUI() {
        let root = vstack(spacing: 0)
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            root.topAnchor.constraint(equalTo: view.topAnchor),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        root.addArrangedSubview(buildHeader())
        root.addArrangedSubview(buildHero())
        root.addArrangedSubview(buildTabs())
        contentBox.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(contentBox)

        buildOverview(); buildSMS(); buildTerminal(); buildSettings()
        for c in [smsListContainer, smsThreadContainer] { c.isHidden = true }
    }

    private func buildHeader() -> NSView {
        let logo = NSView()
        logo.wantsLayer = true
        logo.layer?.cornerRadius = 11
        logo.layer?.backgroundColor = Palette.brand.cgColor
        logo.widthAnchor.constraint(equalToConstant: 38).isActive = true
        logo.heightAnchor.constraint(equalToConstant: 38).isActive = true
        let ec = NSTextField(labelWithString: "EC")
        ec.font = .systemFont(ofSize: 15, weight: .heavy); ec.textColor = .white
        ec.translatesAutoresizingMaskIntoConstraints = false
        logo.addSubview(ec)
        NSLayoutConstraint.activate([ec.centerXAnchor.constraint(equalTo: logo.centerXAnchor), ec.centerYAnchor.constraint(equalTo: logo.centerYAnchor)])

        let title = NSTextField(labelWithString: "EC25 Manager")
        title.font = .systemFont(ofSize: 15, weight: .bold)
        usbDesc.font = .monospacedSystemFont(ofSize: 11, weight: .regular); usbDesc.textColor = .secondaryLabelColor
        let titles = vstack(spacing: 1); titles.alignment = .leading
        titles.addArrangedSubview(title); titles.addArrangedSubview(usbDesc)

        let brand = hstack(spacing: 11); brand.addArrangedSubview(logo); brand.addArrangedSubview(titles)

        statusDot.wantsLayer = true; statusDot.layer?.cornerRadius = 4
        statusDot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        statusDot.heightAnchor.constraint(equalToConstant: 8).isActive = true
        statusText.font = .systemFont(ofSize: 12, weight: .semibold)
        let pill = hstack(spacing: 6); pill.edgeInsets = NSEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        pill.addArrangedSubview(statusDot); pill.addArrangedSubview(statusText)
        let pillBox = pillWrap(pill)

        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        refreshButton.bezelStyle = .regularSquare; refreshButton.isBordered = false
        refreshButton.target = self; refreshButton.action = #selector(doRefresh)

        let bar = hstack(spacing: 8)
        bar.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 10, right: 16)
        bar.addArrangedSubview(brand)
        bar.addArrangedSubview(NSView())
        bar.addArrangedSubview(pillBox)
        bar.addArrangedSubview(refreshButton)
        return bar
    }

    private func buildHero() -> NSView {
        heroDbm.font = .systemFont(ofSize: 22, weight: .heavy)
        heroOperator.font = .systemFont(ofSize: 12); heroOperator.textColor = .secondaryLabelColor
        let netRow = hstack(spacing: 6); netRow.addArrangedSubview(netBadge); netRow.addArrangedSubview(heroOperator)
        let left = vstack(spacing: 3); left.alignment = .leading
        left.addArrangedSubview(heroDbm); left.addArrangedSubview(netRow)
        let signalRow = hstack(spacing: 14); signalRow.alignment = .centerY
        signalBars.widthAnchor.constraint(equalToConstant: 44).isActive = true
        signalBars.heightAnchor.constraint(equalToConstant: 34).isActive = true
        signalRow.addArrangedSubview(signalBars); signalRow.addArrangedSubview(left)

        let regLabel = NSTextField(labelWithString: "注册状态"); regLabel.font = .systemFont(ofSize: 11); regLabel.textColor = .secondaryLabelColor
        regValue.font = .systemFont(ofSize: 14, weight: .bold); regValue.alignment = .right
        let right = vstack(spacing: 3); right.alignment = .trailing
        right.addArrangedSubview(regLabel); right.addArrangedSubview(regValue)

        let row = hstack(spacing: 8); row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        row.addArrangedSubview(signalRow); row.addArrangedSubview(NSView()); row.addArrangedSubview(right)

        let box = NSBox(); styleCard(box, tint: true)
        box.contentView = row
        let wrap = NSView(); wrap.translatesAutoresizingMaskIntoConstraints = false
        box.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(box)
        NSLayoutConstraint.activate([
            box.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 16),
            box.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -16),
            box.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 4),
            box.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -10)
        ])
        return wrap
    }

    private func buildTabs() -> NSView {
        let row = hstack(spacing: 4); row.distribution = .fillEqually
        for t in TabKind.allCases {
            let b = NSButton(title: t.rawValue, target: self, action: #selector(tabClicked(_:)))
            b.bezelStyle = .regularSquare; b.isBordered = false
            b.identifier = NSUserInterfaceItemIdentifier(t.rawValue)
            b.font = .systemFont(ofSize: 13, weight: .semibold)
            b.heightAnchor.constraint(equalToConstant: 30).isActive = true
            b.wantsLayer = true; b.layer?.cornerRadius = 9
            tabButtons[t] = b
            if t == .sms {
                let holder = NSView()
                holder.translatesAutoresizingMaskIntoConstraints = false
                b.translatesAutoresizingMaskIntoConstraints = false
                holder.addSubview(b)
                smsTabDot.wantsLayer = true; smsTabDot.layer?.cornerRadius = 3
                smsTabDot.layer?.backgroundColor = Palette.danger.cgColor
                smsTabDot.translatesAutoresizingMaskIntoConstraints = false
                holder.addSubview(smsTabDot)
                NSLayoutConstraint.activate([
                    b.leadingAnchor.constraint(equalTo: holder.leadingAnchor), b.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
                    b.topAnchor.constraint(equalTo: holder.topAnchor), b.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
                    smsTabDot.widthAnchor.constraint(equalToConstant: 6), smsTabDot.heightAnchor.constraint(equalToConstant: 6),
                    smsTabDot.topAnchor.constraint(equalTo: holder.topAnchor, constant: 5),
                    smsTabDot.trailingAnchor.constraint(equalTo: b.centerXAnchor, constant: 22)
                ])
                row.addArrangedSubview(holder)
            } else {
                row.addArrangedSubview(b)
            }
        }
        let box = NSBox(); styleCard(box)
        box.contentView = row
        let wrap = NSView()
        box.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(box)
        NSLayoutConstraint.activate([
            box.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 16),
            box.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -16),
            box.topAnchor.constraint(equalTo: wrap.topAnchor),
            box.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -10)
        ])
        return wrap
    }

    // MARK: Overview

    private func buildOverview() {
        infoGrid.orientation = .vertical; infoGrid.spacing = 10; infoGrid.alignment = .leading
        infoGrid.translatesAutoresizingMaskIntoConstraints = false

        caText.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular); caText.textColor = .secondaryLabelColor
        caText.isSelectable = true
        let caTitle = sectionLabel("载波聚合 / 服务小区")
        let caStack = vstack(spacing: 8); caStack.alignment = .leading
        caStack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        caStack.addArrangedSubview(caTitle); caStack.addArrangedSubview(caText)
        let caBox = NSBox(); styleCard(caBox); caBox.contentView = caStack

        let content = vstack(spacing: 12); content.alignment = .leading
        content.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 16, right: 16)
        content.addArrangedSubview(infoGrid)
        content.addArrangedSubview(caBox)
        infoGrid.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -32).isActive = true
        caBox.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -32).isActive = true
        addTabContent(scrollWrap(content), for: .overview)
    }

    // MARK: SMS

    private func buildSMS() {
        // list
        smsCount.font = .systemFont(ofSize: 12); smsCount.textColor = .secondaryLabelColor
        markReadButton.title = "全部已读"; styleMini(markReadButton, accent: true)
        markReadButton.target = self; markReadButton.action = #selector(markAllRead)
        let newBtn = NSButton(title: "＋ 新建", target: self, action: #selector(newSMS)); styleMini(newBtn)
        let refBtn = NSButton(title: "刷新", target: self, action: #selector(refreshSMSAction)); styleMini(refBtn)
        let toolbar = hstack(spacing: 8); toolbar.alignment = .centerY
        toolbar.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 4, right: 16)
        toolbar.addArrangedSubview(smsCount); toolbar.addArrangedSubview(NSView())
        toolbar.addArrangedSubview(markReadButton); toolbar.addArrangedSubview(newBtn); toolbar.addArrangedSubview(refBtn)

        convStack.orientation = .vertical; convStack.spacing = 8; convStack.alignment = .leading
        let convContent = vstack(spacing: 0); convContent.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 12, right: 16)
        convContent.addArrangedSubview(convStack)
        convStack.widthAnchor.constraint(equalTo: convContent.widthAnchor, constant: -32).isActive = true
        let listStack = vstack(spacing: 0)
        listStack.addArrangedSubview(toolbar)
        listStack.addArrangedSubview(scrollWrap(convContent))
        smsListContainer = listStack

        // thread
        let backBtn = NSButton(title: "‹", target: self, action: #selector(backToList)); styleMini(backBtn)
        backBtn.font = .systemFont(ofSize: 16, weight: .medium)
        threadTitle.font = .systemFont(ofSize: 15, weight: .bold)
        clearButton.title = "清空"; styleMini(clearButton, destructive: true)
        clearButton.target = self; clearButton.action = #selector(clearConversation)
        let thHead = hstack(spacing: 8); thHead.alignment = .centerY
        thHead.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 4, right: 16)
        thHead.addArrangedSubview(backBtn); thHead.addArrangedSubview(threadTitle)
        thHead.addArrangedSubview(NSView()); thHead.addArrangedSubview(clearButton)

        threadStack.orientation = .vertical; threadStack.spacing = 8; threadStack.alignment = .leading
        let thContent = vstack(spacing: 0); thContent.edgeInsets = NSEdgeInsets(top: 6, left: 16, bottom: 6, right: 16)
        thContent.addArrangedSubview(threadStack)
        threadStack.widthAnchor.constraint(equalTo: thContent.widthAnchor, constant: -32).isActive = true

        smsTo.placeholderString = "收件人号码"
        smsBody.isRichText = false; smsBody.font = .systemFont(ofSize: 13); smsBody.drawsBackground = false
        let bodyScroll = NSScrollView(); bodyScroll.documentView = smsBody; bodyScroll.drawsBackground = false
        bodyScroll.borderType = .noBorder; bodyScroll.hasVerticalScroller = true
        bodyScroll.heightAnchor.constraint(equalToConstant: 54).isActive = true
        let bodyBox = NSBox(); styleCard(bodyBox, radius: 10); bodyBox.contentView = bodyScroll
        let sendBtn = NSButton(title: "", target: self, action: #selector(sendSMS))
        sendBtn.image = NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: nil)
        sendBtn.bezelStyle = .circular
        let sendRow = hstack(spacing: 8); sendRow.alignment = .bottom
        sendRow.addArrangedSubview(bodyBox); sendRow.addArrangedSubview(sendBtn)
        let composer = vstack(spacing: 8)
        composer.edgeInsets = NSEdgeInsets(top: 6, left: 16, bottom: 12, right: 16)
        composer.addArrangedSubview(smsTo); composer.addArrangedSubview(sendRow)

        let threadStackContainer = vstack(spacing: 0)
        threadStackContainer.addArrangedSubview(thHead)
        threadStackContainer.addArrangedSubview(scrollWrap(thContent))
        threadStackContainer.addArrangedSubview(composer)
        smsThreadContainer = threadStackContainer

        let container = NSView()
        for v in [smsListContainer, smsThreadContainer] {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
            NSLayoutConstraint.activate([
                v.leadingAnchor.constraint(equalTo: container.leadingAnchor), v.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                v.topAnchor.constraint(equalTo: container.topAnchor), v.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        }
        addTabContent(container, for: .sms)
    }

    // MARK: Terminal

    private func buildTerminal() {
        terminalText.isEditable = false; terminalText.isRichText = false
        terminalText.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        terminalText.textColor = Palette.goodNS; terminalText.drawsBackground = false
        terminalText.textContainerInset = NSSize(width: 12, height: 12)
        let outScroll = NSScrollView(); outScroll.documentView = terminalText; outScroll.hasVerticalScroller = true
        outScroll.drawsBackground = true; outScroll.backgroundColor = NSColor.black.withAlphaComponent(0.28)
        outScroll.borderType = .noBorder
        outScroll.wantsLayer = true; outScroll.layer?.cornerRadius = 14
        outScroll.setContentHuggingPriority(.defaultLow, for: .vertical)

        atInput.placeholderString = "AT+QNWINFO"; atInput.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        atInput.target = self; atInput.action = #selector(sendAT)
        let sendBtn = NSButton(title: "发送", target: self, action: #selector(sendAT)); sendBtn.bezelStyle = .rounded
        let inputRow = hstack(spacing: 8); inputRow.addArrangedSubview(atInput); inputRow.addArrangedSubview(sendBtn)

        let chips = NSStackView(); chips.orientation = .horizontal; chips.spacing = 6; chips.alignment = .leading
        chips.distribution = .gravityAreas
        for c in ["ATI", "AT+CSQ", "AT+QNWINFO", "AT+QTEMP", "AT+CGDCONT?", "AT+QENG=\"servingcell\""] {
            let b = NSButton(title: c, target: self, action: #selector(quickCmd(_:)))
            b.bezelStyle = .roundRect; b.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            chips.addArrangedSubview(b)
        }

        let content = vstack(spacing: 10)
        content.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 16, right: 16)
        content.addArrangedSubview(outScroll)
        content.addArrangedSubview(inputRow)
        content.addArrangedSubview(chips)
        outScroll.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -32).isActive = true
        addTabContent(content, for: .terminal)
    }

    // MARK: Settings

    private func buildSettings() {
        for c in [loginCheck, wakeCheck, hideCheck] { c.target = self; c.action = #selector(settingToggled) }
        infoPollPopup.addItems(withTitles: ["6 秒", "10 秒", "12 秒", "15 秒", "20 秒", "30 秒"])
        smsPollPopup.addItems(withTitles: ["关闭", "15 秒", "30 秒", "60 秒", "120 秒"])
        infoPollPopup.target = self; infoPollPopup.action = #selector(pollChanged)
        smsPollPopup.target = self; smsPollPopup.action = #selector(pollChanged)

        let general = vstack(spacing: 8); general.alignment = .leading
        general.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        general.addArrangedSubview(sectionLabel("通用"))
        general.addArrangedSubview(loginCheck)
        general.addArrangedSubview(kvControl("状态刷新间隔", infoPollPopup))
        general.addArrangedSubview(kvControl("短信轮询间隔", smsPollPopup))
        general.addArrangedSubview(wakeCheck)
        general.addArrangedSubview(hideCheck)

        // field toggles
        let grid = NSGridView(numberOfColumns: 2, rows: 0)
        grid.rowSpacing = 6; grid.columnSpacing = 14
        var rowCells: [NSButton] = []
        for f in fieldCatalog {
            let cb = NSButton(checkboxWithTitle: f.label, target: self, action: #selector(fieldToggled(_:)))
            cb.identifier = NSUserInterfaceItemIdentifier(f.key)
            fieldChecks[f.key] = cb
            rowCells.append(cb)
            if rowCells.count == 2 { grid.addRow(with: rowCells); rowCells = [] }
        }
        if rowCells.count == 1 { grid.addRow(with: [rowCells[0], NSView()]) }
        let fieldsCard = vstack(spacing: 10); fieldsCard.alignment = .leading
        fieldsCard.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        fieldsCard.addArrangedSubview(sectionLabel("状态信息展示")); fieldsCard.addArrangedSubview(grid)

        usbPopup.addItems(withTitles: ["QMI", "ECM", "MBIM", "RNDIS"])
        let usbApply = NSButton(title: "应用", target: self, action: #selector(applyUsb)); usbApply.bezelStyle = .rounded
        usbCurrent.font = .systemFont(ofSize: 11.5); usbCurrent.textColor = .secondaryLabelColor
        let usbCard = vstack(spacing: 8); usbCard.alignment = .leading
        usbCard.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        usbCard.addArrangedSubview(sectionLabel("USB 网络模式"))
        let usbRow = hstack(spacing: 8); usbRow.addArrangedSubview(usbPopup); usbRow.addArrangedSubview(usbApply)
        usbCard.addArrangedSubview(usbRow); usbCard.addArrangedSubview(usbCurrent)

        apnField.placeholderString = "输入新的 APN"
        let apnApply = NSButton(title: "设置", target: self, action: #selector(applyApn)); apnApply.bezelStyle = .rounded
        apnCurrent.font = .systemFont(ofSize: 14, weight: .bold); apnCurrent.textColor = Palette.goodNS
        apnAll.font = .systemFont(ofSize: 11.5); apnAll.textColor = .secondaryLabelColor
        let apnCard = vstack(spacing: 8); apnCard.alignment = .leading
        apnCard.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        apnCard.addArrangedSubview(sectionLabel("APN 配置")); apnCard.addArrangedSubview(apnCurrent)
        let apnRow = hstack(spacing: 8); apnRow.addArrangedSubview(apnField); apnRow.addArrangedSubview(apnApply)
        apnField.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        apnCard.addArrangedSubview(apnRow); apnCard.addArrangedSubview(apnAll)

        let research = NSButton(title: "重新搜索网络", target: self, action: #selector(researchNet)); research.bezelStyle = .rounded
        let recon = NSButton(title: "重连设备", target: self, action: #selector(reconnectDev)); recon.bezelStyle = .rounded
        let restart = NSButton(title: "重启模块", target: self, action: #selector(restartMod)); restart.bezelStyle = .rounded
        restart.contentTintColor = Palette.dangerNS
        ecmHint.font = .systemFont(ofSize: 11.5); ecmHint.textColor = .secondaryLabelColor
        let actionsCard = vstack(spacing: 8); actionsCard.alignment = .leading
        actionsCard.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        actionsCard.addArrangedSubview(sectionLabel("模块操作"))
        let actRow = hstack(spacing: 8); actRow.addArrangedSubview(research); actRow.addArrangedSubview(recon); actRow.addArrangedSubview(restart)
        actionsCard.addArrangedSubview(actRow); actionsCard.addArrangedSubview(ecmHint)

        let quit = NSButton(title: "退出应用", target: self, action: #selector(quitApp)); quit.bezelStyle = .rounded
        let deviceCard = vstack(spacing: 6); deviceCard.alignment = .leading
        deviceCard.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        deviceCard.addArrangedSubview(sectionLabel("设备信息"))
        deviceCard.addArrangedSubview(kv("厂商", devManu)); deviceCard.addArrangedSubview(kv("型号", devModel)); deviceCard.addArrangedSubview(kv("固件", devRev))
        let quitRow = hstack(spacing: 8); quitRow.addArrangedSubview(NSView()); quitRow.addArrangedSubview(quit)
        deviceCard.addArrangedSubview(quitRow)

        let content = vstack(spacing: 12); content.alignment = .leading
        content.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 16, right: 16)
        for c in [general, fieldsCard, usbCard, apnCard, actionsCard, deviceCard] {
            let box = NSBox(); styleCard(box); box.contentView = c
            content.addArrangedSubview(box)
            box.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -32).isActive = true
        }
        addTabContent(scrollWrap(content), for: .settings)
    }

    // MARK: - Tab plumbing

    private var tabContent: [TabKind: NSView] = [:]
    private func addTabContent(_ v: NSView, for tab: TabKind) {
        v.translatesAutoresizingMaskIntoConstraints = false
        contentBox.addSubview(v)
        NSLayoutConstraint.activate([
            v.leadingAnchor.constraint(equalTo: contentBox.leadingAnchor), v.trailingAnchor.constraint(equalTo: contentBox.trailingAnchor),
            v.topAnchor.constraint(equalTo: contentBox.topAnchor), v.bottomAnchor.constraint(equalTo: contentBox.bottomAnchor)
        ])
        v.isHidden = true
        tabContent[tab] = v
    }

    private func selectTab(_ t: TabKind) {
        tab = t
        for (k, v) in tabContent { v.isHidden = k != t }
        for (k, b) in tabButtons {
            let sel = k == t
            b.layer?.backgroundColor = (sel ? NSColor.labelColor.withAlphaComponent(0.10) : .clear).cgColor
            b.contentTintColor = sel ? .labelColor : .secondaryLabelColor
        }
    }

    @objc private func tabClicked(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let t = TabKind(rawValue: raw) else { return }
        selectTab(t)
        refreshUI()
    }


    // MARK: - Refresh

    private func refreshUI() {
        let info = modem.info
        let dotColor: NSColor = modem.connected ? Palette.goodNS : (modem.busy ? Palette.warnNS : Palette.dangerNS)
        statusDot.layer?.backgroundColor = dotColor.cgColor
        statusText.stringValue = modem.connected ? (modem.busy ? "执行中" : "在线") : (modem.busy ? "连接中" : "离线")
        usbDesc.stringValue = modem.connected ? modem.usbDescription : "设备未连接"

        signalBars.bars = info.signal.bars; signalBars.needsDisplay = true
        heroDbm.stringValue = info.rsrp != "-" ? info.rsrp : (info.signal.dbm != nil ? "\(info.signal.dbm!) dBm" : (modem.connected ? "未知" : "-- dBm"))
        netBadge.text = info.networkLabel == "-" ? "--" : info.networkLabel
        heroOperator.stringValue = info.operatorName == "-" ? "--" : info.operatorName
        regValue.stringValue = info.epsRegistration != "-" ? info.epsRegistration : info.registration
        smsTabDot.isHidden = modem.unreadCount == 0

        switch tab {
        case .overview: refreshOverview()
        case .sms: refreshSMS()
        case .terminal: refreshTerminal()
        case .settings: refreshSettings()
        }
    }

    private func refreshOverview() {
        infoGrid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let fields = settings.visibleFields.compactMap(fieldCatalogEntry)
        var pending: InfoField?
        func flushRow(_ cells: [InfoField]) {
            let row = hstack(spacing: 10); row.distribution = .fillEqually
            for f in cells { let t = tileView(f.label, f.get(modem.info), mono: f.mono); row.addArrangedSubview(t) }
            if cells.count == 1 && !(cells.first?.wide ?? false) { row.addArrangedSubview(NSView()) }
            infoGrid.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: infoGrid.widthAnchor).isActive = true
        }
        for f in fields {
            if f.wide { if let p = pending { flushRow([p]); pending = nil }; flushRow([f]) }
            else if let p = pending { flushRow([p, f]); pending = nil }
            else { pending = f }
        }
        if let p = pending { flushRow([p]) }

        let parts = [modem.info.carrierAggregation, modem.info.servingCell].filter { $0 != "-" && !$0.isEmpty }
        caText.stringValue = parts.isEmpty ? "暂无载波聚合信息" : parts.joined(separator: "\n")
    }

    private func refreshSMS() {
        let convs = groupConversations(modem.messages)
        let unread = convs.reduce(0) { $0 + $1.unread }
        smsCount.stringValue = "\(convs.count) 个会话" + (unread > 0 ? " · \(unread) 未读" : "")
        markReadButton.isHidden = unread == 0

        switch smsMode {
        case .list:
            smsListContainer.isHidden = false; smsThreadContainer.isHidden = true
            convStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
            if convs.isEmpty {
                let empty = NSTextField(labelWithString: "暂无短信"); empty.textColor = .secondaryLabelColor
                convStack.addArrangedSubview(empty)
            }
            for c in convs {
                let row = convRow(c)
                convStack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: convStack.widthAnchor).isActive = true
            }
        case .thread(let sender):
            smsListContainer.isHidden = true; smsThreadContainer.isHidden = false
            threadTitle.stringValue = sender ?? "新短信"
            clearButton.isHidden = sender == nil
            threadStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
            let msgs = modem.messages.filter { ($0.sender.isEmpty ? "未知" : $0.sender) == sender }
                .sorted { a, b in a.date == b.date ? a.index < b.index : a.date < b.date }
            for m in msgs {
                let b = bubbleRow(m)
                threadStack.addArrangedSubview(b)
                b.widthAnchor.constraint(equalTo: threadStack.widthAnchor).isActive = true
            }
        }
    }

    private func refreshTerminal() {
        let text = modem.terminalLines.joined(separator: "\n")
        if terminalText.string != text {
            terminalText.string = text
            terminalText.scrollToEndOfDocument(nil)
        }
    }

    private func refreshSettings() {
        loginCheck.state = settings.openAtLogin ? .on : .off
        wakeCheck.state = settings.restartOnWake ? .on : .off
        hideCheck.state = settings.hideWhenDisconnected ? .on : .off
        let infoIdx = [6, 10, 12, 15, 20, 30].firstIndex(of: settings.infoPollSeconds) ?? 2
        infoPollPopup.selectItem(at: infoIdx)
        let smsIdx = [0, 15, 30, 60, 120].firstIndex(of: settings.smsPollSeconds) ?? 2
        smsPollPopup.selectItem(at: smsIdx)
        for (key, cb) in fieldChecks { cb.state = settings.visibleFields.contains(key) ? .on : .off }
        usbCurrent.stringValue = "当前：\(modem.info.usbNetworkMode)"
        if let m = modem.info.usbNetworkMode.range(of: #"\((\d)\)"#, options: .regularExpression) {
            usbPopup.selectItem(at: Int(modem.info.usbNetworkMode[m].filter(\.isNumber)) ?? 1)
        }
        apnCurrent.stringValue = "当前 APN：\(modem.info.currentApn)"
        let all = modem.info.apnProfiles.map { "cid\($0.cid): \($0.apn) (\($0.type))" }.joined(separator: "\n")
        apnAll.stringValue = "全部配置：\n" + (all.isEmpty ? "-" : all)
        ecmHint.stringValue = "ECM 网络：" + (modem.networkHints.isEmpty ? "未检测到 192.168.225.x" : modem.networkHints.joined(separator: "\n"))
        devManu.stringValue = modem.info.manufacturer; devModel.stringValue = modem.info.model; devRev.stringValue = modem.info.revision
    }

    // MARK: - Actions

    @objc private func doRefresh() { modem.refreshAll() }
    @objc private func markAllRead() { modem.markAllRead() }
    @objc private func refreshSMSAction() { modem.refreshMessagesOnly() }
    @objc private func newSMS() { smsMode = .thread(nil); smsTo.stringValue = ""; smsTo.isEditable = true; smsBody.string = ""; refreshUI() }
    @objc private func backToList() { smsMode = .list; refreshUI() }
    @objc private func clearConversation() {
        if case .thread(let s?) = smsMode {
            for m in modem.messages.filter({ ($0.sender.isEmpty ? "未知" : $0.sender) == s }) { modem.deleteSMS(index: m.index, storage: m.storage) }
        }
        smsMode = .list; refreshUI()
    }
    @objc private func sendSMS() {
        let to = smsTo.stringValue.trimmed, body = smsBody.string.trimmed
        guard !to.isEmpty, !body.isEmpty else { return }
        modem.sendSMS(to: to, body: body); smsBody.string = ""
        if case .thread(nil) = smsMode { smsMode = .thread(to) }
        refreshUI()
    }
    private func openThread(_ sender: String) {
        smsMode = .thread(sender); smsTo.stringValue = sender; smsTo.isEditable = false; smsBody.string = ""
        if modem.messages.contains(where: { ($0.sender.isEmpty ? "未知" : $0.sender) == sender && $0.unread }) { modem.markConversationRead(sender) }
        refreshUI()
    }
    @objc private func sendAT() { let c = atInput.stringValue.trimmed; guard !c.isEmpty else { return }; atInput.stringValue = ""; modem.runTerminalCommand(c) }
    @objc private func quickCmd(_ sender: NSButton) { atInput.stringValue = sender.title; sendAT() }
    @objc private func settingToggled() {
        settings.openAtLogin = loginCheck.state == .on
        settings.restartOnWake = wakeCheck.state == .on
        settings.hideWhenDisconnected = hideCheck.state == .on
    }
    @objc private func pollChanged() {
        settings.infoPollSeconds = [6, 10, 12, 15, 20, 30][infoPollPopup.indexOfSelectedItem]
        settings.smsPollSeconds = [0, 15, 30, 60, 120][smsPollPopup.indexOfSelectedItem]
    }
    @objc private func fieldToggled(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        settings.toggleField(key, on: sender.state == .on)
    }
    @objc private func applyUsb() { modem.setUsbMode(usbPopup.indexOfSelectedItem) }
    @objc private func applyApn() { modem.setApn(apnField.stringValue); apnField.stringValue = "" }
    @objc private func researchNet() { modem.researchNetwork() }
    @objc private func reconnectDev() { modem.reconnect() }
    @objc private func restartMod() { modem.restartModule() }
    @objc private func quitApp() { NSApp.terminate(nil) }

    // MARK: - Small view builders

    private func convRow(_ c: Conversation) -> NSView {
        let avatar = NSView(); avatar.wantsLayer = true; avatar.layer?.cornerRadius = 19
        avatar.layer?.backgroundColor = Palette.brand.cgColor
        avatar.widthAnchor.constraint(equalToConstant: 38).isActive = true
        avatar.heightAnchor.constraint(equalToConstant: 38).isActive = true
        let init2 = NSTextField(labelWithString: avatarText(c.key)); init2.font = .systemFont(ofSize: 13, weight: .bold); init2.textColor = .white
        init2.translatesAutoresizingMaskIntoConstraints = false; avatar.addSubview(init2)
        NSLayoutConstraint.activate([init2.centerXAnchor.constraint(equalTo: avatar.centerXAnchor), init2.centerYAnchor.constraint(equalTo: avatar.centerYAnchor)])

        let name = NSTextField(labelWithString: c.key); name.font = .systemFont(ofSize: 13.5, weight: c.unread > 0 ? .heavy : .bold); name.lineBreakMode = .byTruncatingTail
        let time = NSTextField(labelWithString: c.last.date.components(separatedBy: ",").first ?? ""); time.font = .systemFont(ofSize: 10.5); time.textColor = .secondaryLabelColor
        let top = hstack(spacing: 8); top.addArrangedSubview(name); top.addArrangedSubview(NSView()); top.addArrangedSubview(time)
        let preview = NSTextField(labelWithString: c.last.body.replacingOccurrences(of: "\n", with: " ")); preview.font = .systemFont(ofSize: 12); preview.textColor = .secondaryLabelColor; preview.lineBreakMode = .byTruncatingTail
        let mid = vstack(spacing: 3); mid.alignment = .leading; mid.addArrangedSubview(top); mid.addArrangedSubview(preview)

        let badge = BadgeLabel(text: "\(c.unread > 0 ? c.unread : c.messages.count)")
        badge.background = c.unread > 0 ? Palette.brand : NSColor.labelColor.withAlphaComponent(0.10)
        badge.textColorOverride = c.unread > 0 ? .white : .secondaryLabelColor

        let row = hstack(spacing: 11); row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 11, left: 12, bottom: 11, right: 12)
        row.addArrangedSubview(avatar); row.addArrangedSubview(mid); row.addArrangedSubview(badge)
        let box = NSBox(); styleCard(box, radius: 11); box.contentView = row
        let click = NSClickGesture { [weak self] in self?.openThread(c.key) }
        box.addGestureRecognizer(click)
        return box
    }

    private func bubbleRow(_ m: SMSMessage) -> NSView {
        let text = NSTextField(wrappingLabelWithString: m.body)
        text.font = .systemFont(ofSize: 13); text.isSelectable = true
        text.textColor = m.outgoing ? .white : .labelColor
        text.preferredMaxLayoutWidth = 280
        let time = NSTextField(labelWithString: m.date); time.font = .systemFont(ofSize: 9.5)
        time.textColor = m.outgoing ? NSColor.white.withAlphaComponent(0.7) : .secondaryLabelColor
        let v = vstack(spacing: 4); v.alignment = .leading
        v.edgeInsets = NSEdgeInsets(top: 9, left: 12, bottom: 9, right: 12)
        v.addArrangedSubview(text); v.addArrangedSubview(time)
        let bubble = NSView(); bubble.wantsLayer = true; bubble.layer?.cornerRadius = 14
        bubble.layer?.backgroundColor = (m.outgoing ? Palette.brand : NSColor.labelColor.withAlphaComponent(0.09)).cgColor
        v.translatesAutoresizingMaskIntoConstraints = false; bubble.addSubview(v)
        NSLayoutConstraint.activate([v.leadingAnchor.constraint(equalTo: bubble.leadingAnchor), v.trailingAnchor.constraint(equalTo: bubble.trailingAnchor), v.topAnchor.constraint(equalTo: bubble.topAnchor), v.bottomAnchor.constraint(equalTo: bubble.bottomAnchor)])
        bubble.widthAnchor.constraint(lessThanOrEqualToConstant: 320).isActive = true
        let menu = NSMenu(); let del = NSMenuItem(title: "删除", action: #selector(deleteBubble(_:)), keyEquivalent: ""); del.target = self; del.representedObject = m; menu.addItem(del)
        bubble.menu = menu

        let row = hstack(spacing: 0)
        if m.outgoing { row.addArrangedSubview(NSView()); row.addArrangedSubview(bubble) }
        else { row.addArrangedSubview(bubble); row.addArrangedSubview(NSView()) }
        return row
    }
    @objc private func deleteBubble(_ sender: NSMenuItem) {
        guard let m = sender.representedObject as? SMSMessage else { return }
        modem.deleteSMS(index: m.index, storage: m.storage)
    }

    private func tileView(_ label: String, _ value: String, mono: Bool) -> NSView {
        let l = NSTextField(labelWithString: label); l.font = .systemFont(ofSize: 11); l.textColor = .secondaryLabelColor
        let v = NSTextField(wrappingLabelWithString: value.isEmpty ? "-" : value)
        v.font = mono ? .monospacedSystemFont(ofSize: 12, weight: .semibold) : .systemFont(ofSize: 14, weight: .bold)
        v.isSelectable = true; v.maximumNumberOfLines = 3
        let stack = vstack(spacing: 4); stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 11, left: 12, bottom: 11, right: 12)
        stack.addArrangedSubview(l); stack.addArrangedSubview(v)
        let box = NSBox(); styleCard(box, radius: 11); box.contentView = stack
        return box
    }

    // MARK: - Helpers

    private func vstack(spacing: CGFloat) -> NSStackView { let s = NSStackView(); s.orientation = .vertical; s.spacing = spacing; s.alignment = .leading; return s }
    private func hstack(spacing: CGFloat) -> NSStackView { let s = NSStackView(); s.orientation = .horizontal; s.spacing = spacing; return s }
    private func sectionLabel(_ t: String) -> NSTextField { let l = NSTextField(labelWithString: t); l.font = .systemFont(ofSize: 12, weight: .bold); l.textColor = .secondaryLabelColor; return l }
    private func kv(_ k: String, _ valueField: NSTextField) -> NSView {
        let key = NSTextField(labelWithString: k); key.textColor = .secondaryLabelColor; key.font = .systemFont(ofSize: 13)
        valueField.font = .systemFont(ofSize: 13, weight: .semibold); valueField.alignment = .right
        let row = hstack(spacing: 8); row.addArrangedSubview(key); row.addArrangedSubview(NSView()); row.addArrangedSubview(valueField)
        row.widthAnchor.constraint(greaterThanOrEqualToConstant: 340).isActive = true
        return row
    }
    private func kvControl(_ k: String, _ control: NSView) -> NSView {
        let key = NSTextField(labelWithString: k); key.font = .systemFont(ofSize: 13)
        let row = hstack(spacing: 8); row.alignment = .centerY; row.addArrangedSubview(key); row.addArrangedSubview(NSView()); row.addArrangedSubview(control)
        row.widthAnchor.constraint(greaterThanOrEqualToConstant: 340).isActive = true
        return row
    }
    private func pillWrap(_ content: NSView) -> NSBox { let box = NSBox(); styleCard(box, radius: 999); box.contentView = content; return box }
    private func styleCard(_ box: NSBox, radius: CGFloat = 14, tint: Bool = false) {
        box.boxType = .custom; box.titlePosition = .noTitle; box.cornerRadius = radius
        box.fillColor = tint ? Palette.brand.withAlphaComponent(0.14) : NSColor.labelColor.withAlphaComponent(0.05)
        box.borderColor = NSColor.labelColor.withAlphaComponent(0.09); box.borderWidth = 1
        box.contentViewMargins = .zero
        box.translatesAutoresizingMaskIntoConstraints = false
    }
    private func styleMini(_ b: NSButton, accent: Bool = false, destructive: Bool = false) {
        b.bezelStyle = .roundRect; b.font = .systemFont(ofSize: 12)
        if accent { b.contentTintColor = Palette.brandNS }
        if destructive { b.contentTintColor = Palette.dangerNS }
    }
    private func scrollWrap(_ doc: NSView) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false; scroll.borderType = .noBorder
        let flipped = FlippedClip(); flipped.translatesAutoresizingMaskIntoConstraints = false
        doc.translatesAutoresizingMaskIntoConstraints = false
        flipped.addSubview(doc)
        NSLayoutConstraint.activate([
            doc.leadingAnchor.constraint(equalTo: flipped.leadingAnchor), doc.trailingAnchor.constraint(equalTo: flipped.trailingAnchor),
            doc.topAnchor.constraint(equalTo: flipped.topAnchor), doc.bottomAnchor.constraint(equalTo: flipped.bottomAnchor)
        ])
        scroll.documentView = flipped
        NSLayoutConstraint.activate([
            flipped.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            flipped.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            flipped.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            flipped.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])
        return scroll
    }
    private func avatarText(_ name: String) -> String {
        let digits = name.filter(\.isNumber)
        return digits.count >= 2 ? String(digits.suffix(2)) : String(name.prefix(2))
    }
}

// MARK: - Support views

final class FlippedClip: NSView { override var isFlipped: Bool { true } }

final class SignalBarsView: NSView {
    var bars: Int = 0
    override var isFlipped: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        let ratios: [CGFloat] = [0.42, 0.62, 0.82, 1.0]
        let barW: CGFloat = 6, gap: CGFloat = 4
        let h = bounds.height
        for i in 0..<4 {
            let x = CGFloat(i) * (barW + gap)
            let bh = h * ratios[i]
            let color = i < bars ? Palette.goodNS : NSColor.labelColor.withAlphaComponent(0.18)
            color.setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: 0, width: barW, height: bh), xRadius: 2, yRadius: 2).fill()
        }
    }
}

final class BadgeLabel: NSView {
    private let label = NSTextField(labelWithString: "")
    var background: NSColor = Palette.brand { didSet { needsDisplay = true } }
    var textColorOverride: NSColor = .white { didSet { label.textColor = textColorOverride } }
    var text: String { didSet { label.stringValue = text } }
    init(text: String) {
        self.text = text
        super.init(frame: .zero)
        wantsLayer = true
        label.stringValue = text; label.font = .systemFont(ofSize: 11, weight: .bold); label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            heightAnchor.constraint(equalToConstant: 20)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        background.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
    }
}

final class NSClickGesture: NSClickGestureRecognizer {
    private let handler: () -> Void
    init(handler: @escaping () -> Void) { self.handler = handler; super.init(target: nil, action: nil); self.target = self; self.action = #selector(fire) }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func fire() { handler() }
}
