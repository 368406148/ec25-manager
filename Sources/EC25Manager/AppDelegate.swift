import AppKit
import Combine
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let modem = Modem()
    private let settings = AppSettings.shared
    private let presence = USBPresence(vid: 0x2c7c, pid: 0x0125)

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    private var infoTimer: Timer?
    private var smsTimer: Timer?
    private var recoverTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu-bar only, no Dock icon

        // Popover hosting the SwiftUI UI.
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 440, height: 620)
        popover.contentViewController = PopoverController(modem: modem, settings: settings)

        // Status item.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = makeTrayIcon(filled: 0, off: true)
        item.button?.action = #selector(togglePopover)
        item.button?.target = self
        statusItem = item

        // React to modem state → repaint tray.
        modem.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.refreshTray() }
            .store(in: &cancellables)

        // Settings that need side effects.
        settings.$openAtLogin.dropFirst().sink { [weak self] v in self?.applyLoginItem(v) }.store(in: &cancellables)
        settings.$infoPollSeconds.dropFirst().sink { [weak self] _ in self?.restartTimers() }.store(in: &cancellables)
        settings.$smsPollSeconds.dropFirst().sink { [weak self] _ in self?.restartTimers() }.store(in: &cancellables)
        settings.$hideWhenDisconnected.dropFirst().sink { [weak self] _ in self?.refreshTray() }.store(in: &cancellables)

        // Event-driven USB presence.
        presence.onChange = { [weak self] present in
            guard let self else { return }
            if present {
                if !self.modem.connected { self.modem.attemptRecover() }
            } else {
                self.modem.notifyRemoved()
            }
            self.refreshTray()
        }
        presence.start()

        // Wake handling.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil
        )

        applyLoginItem(settings.openAtLogin)
        refreshTray()
        restartTimers()
        modem.start()
    }

    // MARK: - Tray

    private func trayShouldShow() -> Bool {
        !settings.hideWhenDisconnected || presence.present
    }

    private func refreshTray() {
        guard let item = statusItem else { return }
        let show = trayShouldShow()
        item.isVisible = show
        if !show { if popover.isShown { popover.performClose(nil) }; return }
        if !presence.present && !modem.connected {
            item.button?.image = makeTrayIcon(filled: 0, off: true)      // truly absent
        } else if !modem.connected {
            item.button?.image = makeTrayIcon(filled: 0, off: false)     // present, connecting
        } else {
            item.button?.image = makeTrayIcon(filled: modem.info.signal.bars, off: false)
        }
        let op = modem.info.operatorName != "-" ? modem.info.operatorName : "EC25"
        item.button?.toolTip = modem.connected
            ? "EC25 Manager · \(op) · \(modem.info.rsrp != "-" ? modem.info.rsrp : modem.info.signal.text)"
            : (presence.present ? "EC25 Manager · 连接中…" : "EC25 Manager · 设备未连接")
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Timers (presence is event-driven, so no presence timer)

    private func restartTimers() {
        infoTimer?.invalidate(); smsTimer?.invalidate(); recoverTimer?.invalidate()

        let infoInterval = TimeInterval(max(2, settings.infoPollSeconds))
        infoTimer = Timer.scheduledTimer(withTimeInterval: infoInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.modem.connected && !self.modem.busy { self.modem.refreshInfoOnly() }
            }
        }

        recoverTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.presence.present && !self.modem.connected && !self.modem.busy { self.modem.attemptRecover() }
            }
        }

        if settings.smsPollSeconds > 0 {
            smsTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(settings.smsPollSeconds), repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    if self.modem.connected && !self.modem.busy { self.modem.refreshMessagesOnly() }
                }
            }
        }
    }

    @objc private func didWake() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self else { return }
            self.modem.handleWake(restart: self.settings.restartOnWake)
        }
    }

    // MARK: - Login item (packaged app only)

    private func applyLoginItem(_ enabled: Bool) {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return } // skip in dev
        do {
            if enabled { if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() } }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("login item update failed: \(error.localizedDescription)")
        }
    }
}
