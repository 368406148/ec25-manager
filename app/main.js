'use strict'

const { app, Tray, BrowserWindow, ipcMain, nativeImage, Menu, screen, shell, powerMonitor } = require('electron')
const path = require('path')
const fs = require('fs')
const { execFile, execFileSync } = require('child_process')
const { ModemManager } = require('./src/modem')
const { Settings } = require('./src/settings')

let tray = null
let win = null
let modem = null
let settings = null
let infoTimer = null
let smsTimer = null
let recoverTimer = null
let presenceTimer = null
let devicePresent = false
const trayImages = {}

// USB ids of the modem, in the decimal form `ioreg` prints.
const DEVICE_VID = 0x2c7c   // 11388
const DEVICE_PID = 0x0125   // 293

const WIN_WIDTH = 440
const WIN_HEIGHT = 680

// Resolve the Swift helper binary + the env it needs to find libusb.
function resolveHelper () {
  if (app.isPackaged) {
    const bin = path.join(process.resourcesPath, 'bin', 'EC25Helper')
    return { bin, env: { DYLD_LIBRARY_PATH: path.join(process.resourcesPath, 'bin') } }
  }
  const repoRoot = path.join(__dirname, '..')
  const release = path.join(repoRoot, '.build', 'release', 'EC25Helper')
  const debug = path.join(repoRoot, '.build', 'debug', 'EC25Helper')
  const bin = fs.existsSync(release) ? release : debug
  return { bin, env: { DYLD_FALLBACK_LIBRARY_PATH: '/opt/homebrew/lib' } }
}

function loadTrayImage (name) {
  const p = path.join(__dirname, 'assets', name + '.png')
  const img = fs.existsSync(p) ? nativeImage.createFromPath(p) : nativeImage.createEmpty()
  img.setTemplateImage(true)
  return img
}

function trayImageFor (state) {
  // Slashed "off" icon only when the dongle is truly absent; empty bars while
  // it's plugged in but still connecting.
  if (!state || !state.connected) {
    return devicePresent ? (trayImages[0] ?? trayImages.off) : trayImages.off
  }
  const bars = Math.max(0, Math.min(4, state.info?.signal?.bars ?? 0))
  return trayImages[bars] ?? trayImages.off
}

// Visibility follows real USB presence (fast ioreg poll), so the icon hides the
// instant the dongle is unplugged and reappears the instant it's plugged in.
function trayShouldShow () {
  const hideWhenOff = settings && settings.get().hideWhenDisconnected
  return !hideWhenOff || devicePresent
}

function refreshTray () {
  if (!trayShouldShow()) {
    if (tray) { if (win) win.hide(); tray.destroy(); tray = null }
    return
  }
  ensureTray()
  const state = modem.getState()
  tray.setImage(trayImageFor(state))
  const info = state.info || {}
  const parts = state.connected
    ? [info.operatorName && info.operatorName !== '-' ? info.operatorName : 'EC25',
       info.networkLabel && info.networkLabel !== '-' ? info.networkLabel : null,
       info.rsrp && info.rsrp !== '-' ? info.rsrp : (info.signal?.text || null),
       state.unreadCount > 0 ? `${state.unreadCount} 条未读` : null]
    : (devicePresent ? ['连接中…'] : ['设备未连接'])
  tray.setToolTip('EC25 Manager · ' + parts.filter(Boolean).join(' · '))
}

// --- fast USB presence detection via ioreg (independent of the modem/helper) ---
function scanPresent (stdout) {
  return stdout.includes(`"idVendor" = ${DEVICE_VID}`) && stdout.includes(`"idProduct" = ${DEVICE_PID}`)
}

function detectPresenceSync () {
  try {
    const out = execFileSync('ioreg', ['-rc', 'IOUSBHostDevice', '-l'], { timeout: 3000, maxBuffer: 16 * 1024 * 1024 }).toString()
    return scanPresent(out)
  } catch { return false }
}

function checkPresence () {
  execFile('ioreg', ['-rc', 'IOUSBHostDevice', '-l'], { timeout: 3000, maxBuffer: 16 * 1024 * 1024 }, (err, stdout) => {
    if (err) return // transient ioreg failure: keep the last known state
    const present = scanPresent(stdout)
    if (present === devicePresent) return
    devicePresent = present
    if (present) {
      // Plugged in: bring the connection back quickly, then show the icon.
      const s = modem.getState()
      if (!s.connected && !s.busy) modem.attemptRecover()
    } else {
      // Unplugged: reflect removal immediately (don't wait for the AT poll).
      modem.notifyRemoved()
    }
    refreshTray()
  })
}

function createWindow () {
  win = new BrowserWindow({
    width: WIN_WIDTH,
    height: WIN_HEIGHT,
    show: false,
    frame: false,
    resizable: false,
    fullscreenable: false,
    movable: false,
    skipTaskbar: true,
    alwaysOnTop: true,
    transparent: true,
    backgroundColor: '#00000000',
    hasShadow: true,
    roundedCorners: true,
    vibrancy: 'popover',            // native Liquid Glass menu material
    visualEffectState: 'active',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false
    }
  })

  // canJoinAllSpaces: the popover appears on whatever Space is active instead
  // of yanking you to the window's origin Space (fixes "jumps to Desktop 1").
  win.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true })

  win.loadFile(path.join(__dirname, 'renderer', 'index.html'))
  win.on('blur', () => { if (win && !win.webContents.isDevToolsOpened()) win.hide() })

  modem.on('update', (state) => {
    refreshTray()
    if (win && !win.isDestroyed()) win.webContents.send('state', state)
  })
}

function positionWindow () {
  const trayBounds = tray.getBounds()
  const display = screen.getDisplayNearestPoint({ x: trayBounds.x, y: trayBounds.y })
  const workArea = display.workArea
  let x = Math.round(trayBounds.x + trayBounds.width / 2 - WIN_WIDTH / 2)
  x = Math.max(workArea.x + 8, Math.min(x, workArea.x + workArea.width - WIN_WIDTH - 8))
  const y = Math.round(trayBounds.y + trayBounds.height + 6)
  win.setPosition(x, y, false)
}

function toggleWindow () {
  if (win.isVisible()) {
    win.hide()
    return
  }
  positionWindow()
  win.show()
  win.focus()
  win.webContents.send('settings', settings.get())
  win.webContents.send('state', modem.getState())
}

function ensureTray () {
  if (tray) return tray
  tray = new Tray(trayImageFor(modem.getState()))
  tray.setToolTip('EC25 Manager')
  tray.on('click', () => toggleWindow())
  tray.on('right-click', () => {
    const menu = Menu.buildFromTemplate([
      { label: '打开面板', click: () => { if (!win.isVisible()) toggleWindow() } },
      { label: '刷新', click: () => modem.refreshAll() },
      { label: '重连设备', click: () => modem.reconnect() },
      { type: 'separator' },
      { label: '退出 EC25 Manager', click: () => { app.quit() } }
    ])
    tray.popUpContextMenu(menu)
  })
  return tray
}

function restartTimers () {
  if (infoTimer) { clearInterval(infoTimer); infoTimer = null }
  if (smsTimer) { clearInterval(smsTimer); smsTimer = null }
  if (recoverTimer) { clearInterval(recoverTimer); recoverTimer = null }
  if (presenceTimer) { clearInterval(presenceTimer); presenceTimer = null }
  const cfg = settings.get()

  // Fast USB presence poll: drives seamless tray hide/show and snappy
  // connect-on-plug / disconnect-on-unplug.
  presenceTimer = setInterval(checkPresence, 1500)

  // Gentle status polling when connected (user-configurable; less device load).
  const infoMs = Math.max(2, cfg.infoPollSeconds || 12) * 1000
  infoTimer = setInterval(() => {
    const s = modem.getState()
    if (s.connected && !s.busy) modem.refreshInfoOnly()
  }, infoMs)

  // Fixed fast reconnect retry so replug / wake recovery stays snappy,
  // independent of the (possibly long) status cadence.
  recoverTimer = setInterval(() => {
    const s = modem.getState()
    if (!s.connected && !s.busy) modem.attemptRecover()
  }, 5000)

  if (cfg.smsPollSeconds && cfg.smsPollSeconds > 0) {
    const smsMs = cfg.smsPollSeconds * 1000
    smsTimer = setInterval(() => {
      const s = modem.getState()
      if (s.connected && !s.busy) modem.refreshMessages()
    }, smsMs)
  }
}

function applySettings (partial) {
  const next = settings.update(partial || {})
  app.setLoginItemSettings({ openAtLogin: !!next.openAtLogin })
  restartTimers()
  refreshTray()   // apply "hide when disconnected" immediately
  if (win && !win.isDestroyed()) win.webContents.send('settings', next)
  return next
}

function registerIpc () {
  const wrap = (fn) => async (_e, ...args) => {
    try { return await fn(...args) } catch (e) { return { ok: false, error: String(e.message || e) } }
  }
  ipcMain.handle('getState', () => modem.getState())
  ipcMain.handle('getSettings', () => settings.get())
  ipcMain.handle('setSettings', (_e, partial) => applySettings(partial))
  ipcMain.handle('refresh', wrap(() => modem.refreshAll()))
  ipcMain.handle('refreshMessages', wrap(() => modem.refreshMessages()))
  ipcMain.handle('sendAT', wrap((cmd) => modem.runTerminalCommand(cmd)))
  ipcMain.handle('sendSMS', wrap(({ to, body }) => modem.sendSMS(to, body)))
  ipcMain.handle('deleteSMS', wrap(({ index, storage }) => modem.deleteSMS(index, storage)))
  ipcMain.handle('markAllRead', wrap(() => modem.markAllRead()))
  ipcMain.handle('markConversationRead', wrap((sender) => modem.markConversationRead(sender)))
  ipcMain.handle('setUsbMode', wrap((mode) => modem.setUsbMode(mode)))
  ipcMain.handle('setApn', wrap((apn) => modem.setApn(apn)))
  ipcMain.handle('restartModule', wrap(() => modem.restartModule()))
  ipcMain.handle('researchNetwork', wrap(() => modem.researchNetwork()))
  ipcMain.handle('reconnect', wrap(() => modem.reconnect()))
  ipcMain.handle('quit', () => { app.quit() })
  ipcMain.handle('openExternal', (_e, url) => shell.openExternal(url))
}

app.whenReady().then(() => {
  if (process.platform === 'darwin' && app.dock) app.dock.hide()

  settings = new Settings(path.join(app.getPath('userData'), 'settings.json'))
  app.setLoginItemSettings({ openAtLogin: !!settings.get().openAtLogin })

  for (const n of [0, 1, 2, 3, 4]) trayImages[n] = loadTrayImage('tray-' + n)
  trayImages.off = loadTrayImage('tray-off')

  const { bin, env } = resolveHelper()
  modem = new ModemManager({ binaryPath: bin, env, dataDir: app.getPath('userData') })

  registerIpc()
  createWindow()
  devicePresent = detectPresenceSync()   // seed presence before first tray decision
  refreshTray()                          // create the tray now unless hidden by setting
  restartTimers()

  // After the Mac wakes from sleep the USB modem's ECM interface usually drops;
  // recover (and optionally restart the module) a few seconds after resume.
  powerMonitor.on('resume', () => {
    modem._log && modem._log('系统已唤醒')
    setTimeout(() => modem.handleWake({ restart: !!settings.get().restartOnWake }), 5000)
  })
  powerMonitor.on('suspend', () => { modem._log && modem._log('系统即将休眠') })

  modem.start().catch(() => {})
})

app.on('window-all-closed', (e) => {
  // Menu-bar app: keep running even with no visible window.
  e.preventDefault?.()
})

app.on('before-quit', () => {
  if (infoTimer) clearInterval(infoTimer)
  if (smsTimer) clearInterval(smsTimer)
  if (recoverTimer) clearInterval(recoverTimer)
  if (presenceTimer) clearInterval(presenceTimer)
  if (modem) modem.bridge.stop()
})
