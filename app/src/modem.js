'use strict'

const os = require('os')
const fs = require('fs')
const path = require('path')
const { EventEmitter } = require('events')
const { HelperBridge } = require('./helper-bridge')

// Format the current local time the way the modem reports SMS dates.
function modemDateNow () {
  const d = new Date()
  const p = (n) => String(n).padStart(2, '0')
  return `${p(d.getFullYear() % 100)}/${p(d.getMonth() + 1)}/${p(d.getDate())},${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`
}

// ---------------------------------------------------------------------------
// Small parsing helpers.
// ---------------------------------------------------------------------------

function trimmed (s) {
  return (s ?? '').trim()
}

function trimQuotes (s) {
  return trimmed(s).replace(/^"+|"+$/g, '')
}

// Split an AT payload on commas, respecting double-quoted segments.
function csvParts (line) {
  const result = []
  let current = ''
  let quoted = false
  for (const ch of line) {
    if (ch === '"') {
      quoted = !quoted
      current += ch
    } else if (ch === ',' && !quoted) {
      result.push(current.trim())
      current = ''
    } else {
      current += ch
    }
  }
  result.push(current.trim())
  return result
}

function firstLine (lines, needle) {
  return lines.find((l) => l.includes(needle))
}

function firstNonCommandLine (lines) {
  const found = lines.find((l) => !l.startsWith('AT') && !l.startsWith('+'))
  return found ? found.trim() : undefined
}

const UCS2 = {
  encode (text) {
    let out = ''
    for (let i = 0; i < text.length; i++) {
      out += text.charCodeAt(i).toString(16).toUpperCase().padStart(4, '0')
    }
    return out
  },
  decode (hex) {
    const cleaned = trimmed(hex)
    if (cleaned.length < 4 || cleaned.length % 4 !== 0 || !/^[0-9a-fA-F]+$/.test(cleaned)) {
      return hex
    }
    let out = ''
    for (let i = 0; i < cleaned.length; i += 4) {
      out += String.fromCharCode(parseInt(cleaned.slice(i, i + 4), 16))
    }
    return out
  }
}

const REG_STATUS = {
  0: '未注册', 1: '已注册·本地', 2: '正在搜索', 3: '注册被拒', 4: '未知', 5: '已注册·漫游'
}

const ACT_TECH = {
  0: 'GSM', 1: 'GSM Compact', 2: 'UTRAN', 3: 'GSM/EGPRS', 4: 'UTRAN/HSDPA',
  5: 'UTRAN/HSUPA', 6: 'UTRAN/HSPA', 7: 'LTE', 8: 'LTE Cat-M1', 9: 'LTE Cat-NB1', 10: '5G NSA', 11: '5G'
}

const USBNET_MODE = { 0: 'QMI', 1: 'ECM', 2: 'MBIM', 3: 'RNDIS' }

const MSG_STATUS = {
  0: 'REC UNREAD', 1: 'REC READ', 2: 'STO UNSENT', 3: 'STO SENT', 4: 'ALL'
}

// LTE bandwidth index (QENG) -> MHz.
const BW_INDEX = { 0: '1.4M', 1: '3M', 2: '5M', 3: '10M', 4: '15M', 5: '20M' }

// EARFCN -> downlink MHz: band -> [FDL_low(MHz), NOffs-DL].
const LTE_BANDS = {
  1: [2110, 0], 2: [1930, 600], 3: [1805, 1200], 4: [2110, 1950], 5: [869, 2400],
  7: [2620, 2750], 8: [925, 3450], 12: [729, 5010], 13: [746, 5180], 17: [734, 5730],
  18: [860, 5850], 19: [875, 6000], 20: [791, 6150], 25: [1930, 8040], 26: [859, 8690],
  28: [758, 9210], 38: [2570, 37750], 39: [1880, 38250], 40: [2300, 38650], 41: [2496, 39650], 66: [2110, 66436]
}

// 3GPP standardized QCI -> human label.
const QCI_DESC = {
  1: '会话语音', 2: '会话视频', 3: '实时游戏', 4: '非会话视频',
  5: 'IMS 信令', 6: 'TCP(视频/网页)', 7: '语音/视频/游戏', 8: 'TCP(视频/网页)',
  9: '默认承载(上网)', 65: '任务关键语音', 66: '非任务关键推送', 69: '任务关键信令', 70: '任务关键数据'
}

function earfcnToDlMhz (band, earfcn) {
  const b = LTE_BANDS[Number(band)]
  const n = Number(earfcn)
  if (!b || !Number.isFinite(n)) return null
  return Number((b[0] + 0.1 * (n - b[1])).toFixed(1))
}

// Estimate the current downlink modulation from the reported CQI (table 1).
function cqiToModulation (cqi) {
  const c = Number(cqi)
  if (!Number.isFinite(c) || c <= 0) return '-'
  if (c <= 6) return `QPSK (CQI ${c})`
  if (c <= 9) return `16QAM (CQI ${c})`
  return `64QAM (CQI ${c})`
}

function shortNetworkLabel (access) {
  const a = (access || '').toUpperCase()
  if (a.includes('NR') || a.includes('5G')) return '5G'
  if (a.includes('LTE')) return '4G'
  if (a.includes('TD-SCDMA') || a.includes('WCDMA') || a.includes('HSDPA') || a.includes('HSPA') || a.includes('UMTS')) return '3G'
  if (a.includes('GSM') || a.includes('EDGE') || a.includes('GPRS')) return '2G'
  return access || '-'
}

// Map a 0..31 CSQ rssi into { dbm, bars(0-4), percent }.
function signalFromRssi (rssi) {
  if (rssi === 99 || rssi == null) return { dbm: null, bars: 0, percent: 0, text: '未知' }
  const dbm = 2 * rssi - 113
  let bars = 0
  if (rssi >= 20) bars = 4
  else if (rssi >= 15) bars = 3
  else if (rssi >= 10) bars = 2
  else if (rssi >= 2) bars = 1
  const percent = Math.max(0, Math.min(100, Math.round((rssi / 31) * 100)))
  return { dbm, bars, percent, text: `${dbm} dBm` }
}

// Prefer RSRP (LTE) for the bar count when we have serving-cell data.
function barsFromRsrp (rsrp) {
  const r = Number(rsrp)
  if (!Number.isFinite(r)) return null
  if (r >= -85) return 4
  if (r >= -95) return 3
  if (r >= -105) return 2
  if (r >= -115) return 1
  return 0
}

function emptyInfo () {
  return {
    manufacturer: '-', model: '-', revision: '-', imei: '-', imsi: '-', iccid: '-',
    ownNumber: '-', simStatus: '-', simInserted: '-', operatorName: '-',
    tech: '-', signal: { dbm: null, bars: 0, percent: 0, text: '-' }, ber: '-',
    registration: '-', gprsRegistration: '-', epsRegistration: '-',
    packetAttached: '-', activePdp: '-', pdpAddress: '-',
    dataNetworkType: '-', networkLabel: '-', servingCell: '-', carrierAggregation: '-',
    usbNetworkMode: '-', apnProfiles: [], currentApn: '-', temperature: '-', band: '-', channel: '-',
    // serving-cell derived metrics
    rsrp: '-', rsrq: '-', rssiDbm: '-', sinr: '-', cqi: '-', modulation: '-',
    dlBandwidth: '-', ulBandwidth: '-', pci: '-', cellId: '-', tac: '-',
    earfcn: '-', freqMhz: '-', qos: '-'
  }
}

// ---------------------------------------------------------------------------

class ModemManager extends EventEmitter {
  constructor ({ binaryPath, env, dataDir }) {
    super()
    this.bridge = new HelperBridge(binaryPath, env)
    this.bridge.on('stderr', (t) => this._log('helper: ' + t.trim()))
    this.bridge.on('exit', () => { this.state.connected = false; this._log('helper 已退出'); this.emitUpdate() })

    // Sent SMS aren't stored on the modem, so keep a local persistent log.
    this._sentLogPath = dataDir ? path.join(dataDir, 'sent.json') : null

    this.state = {
      connected: false,
      busy: false,
      usbDescription: 'USB 2c7c:0125',
      lastError: null,
      lastUpdated: null,
      info: emptyInfo(),
      messages: [],
      unreadCount: 0,
      sentMessages: this._loadSentLog(),
      logLines: [],
      terminalLines: [],
      commandRecords: [],
      networkHints: []
    }
    this._chain = Promise.resolve()
  }

  _loadSentLog () {
    if (!this._sentLogPath) return []
    try {
      const arr = JSON.parse(fs.readFileSync(this._sentLogPath, 'utf8'))
      return Array.isArray(arr) ? arr : []
    } catch { return [] }
  }

  _saveSentLog () {
    if (!this._sentLogPath) return
    try {
      fs.mkdirSync(path.dirname(this._sentLogPath), { recursive: true })
      fs.writeFileSync(this._sentLogPath, JSON.stringify(this.state.sentMessages))
    } catch { /* best-effort */ }
  }

  // Local sent records rendered as conversation messages (grouped by recipient).
  _sentAsMessages () {
    return (this.state.sentMessages || []).map((s) => ({
      id: 'SENT-' + s.ts,
      storage: 'SENT',
      index: s.ts,
      status: 'STO SENT',
      outgoing: true,
      sender: s.to,
      date: s.date,
      body: s.body
    }))
  }

  // ----- public state / lifecycle -----------------------------------------

  getState () {
    return this.state
  }

  emitUpdate () {
    this.emit('update', this.state)
  }

  start () {
    this.bridge.start()
    return this.connect()
  }

  connect () {
    return this._run(async () => {
      this._closeSession()
      if (!this.bridge.running) this.bridge.start()
      const res = await this.bridge.request('open', {}, 20000)
      this.state.connected = true
      this.state.usbDescription = res.description || this.state.usbDescription
      this._log('已连接 ' + this.state.usbDescription)
      await this._initialize()
    })
  }

  reconnect () {
    return this._run(async () => {
      // Re-open on the existing helper (its `open` re-inits libusb); restarting
      // the process would race the kernel's release of the USB interface.
      if (!this.bridge.running) this.bridge.start()
      const res = await this.bridge.request('open', {}, 20000)
      this.state.connected = true
      this.state.usbDescription = res.description || this.state.usbDescription
      this._log('已重连 ' + this.state.usbDescription)
      await this._initialize()
    })
  }

  _closeSession () {
    if (this.bridge.running) {
      this.bridge.request('close').catch(() => {})
    }
    this.state.connected = false
  }

  // ----- public operations -------------------------------------------------

  refreshInfoOnly () {
    return this._run(async () => {
      // Health check: if the modem no longer answers, treat it as removed
      // (but keep polling so we auto-recover when it comes back).
      try {
        await this._send('AT', { timeout: 2500 })
      } catch {
        this._markDisconnected()
        return
      }
      await this._refreshInfo()
      this.state.lastUpdated = Date.now()
    })
  }

  // Recover after the Mac wakes from sleep. The USB handle is usually stale
  // and the ECM data interface often drops, so re-open with a fresh helper and
  // (optionally) reboot the module so the network interface re-enumerates.
  handleWake ({ restart }) {
    return this._run(async () => {
      this._log('从睡眠恢复…')
      // The helper survives sleep; its `open` auto-closes the stale session and
      // re-inits libusb (fresh context), so just re-open — no process restart
      // (which would race the kernel's release of the USB interface).
      if (!this.bridge.running) this.bridge.start()

      // USB can be slow to re-attach after resume; retry the open a few times.
      let res = null
      for (let i = 0; i < 3 && !res; i++) {
        try { res = await this.bridge.request('open', {}, 10000) } catch { /* not ready */ }
        if (!res && i < 2) await new Promise((r) => setTimeout(r, 2000))
      }
      if (!res) { this._markDisconnected(); return { ok: true } } // recoverTimer keeps retrying

      if (restart) {
        // Reboot the module so the ECM/eth interface re-enumerates cleanly
        // (fixes "network drops after sleep"). It won't ack, so ignore errors.
        this._log('休眠恢复：重启模块以恢复网络…')
        await this._send('AT+CFUN=1,1', { timeout: 4000 }).catch(() => {})
        this._markDisconnected()   // module rebooting; recoverTimer re-opens after re-enumeration
        return { ok: true }
      }

      this.state.connected = true
      this.state.usbDescription = res.description || this.state.usbDescription
      this._log('休眠恢复：已重连 ' + this.state.usbDescription)
      await this._initialize()
      this.state.lastUpdated = Date.now()
      return { ok: true }
    })
  }

  // Called by the poll timer when disconnected: quietly try to (re)open.
  attemptRecover () {
    return this._run(async () => {
      if (!this.bridge.running) this.bridge.start()
      let res
      try {
        res = await this.bridge.request('open', {}, 15000)
      } catch {
        return // device still absent; stay disconnected and retry next tick
      }
      this.state.connected = true
      this.state.usbDescription = res.description || this.state.usbDescription
      this._log('设备已接入 ' + this.state.usbDescription)
      await this._initialize()
      this.state.lastUpdated = Date.now()
    })
  }

  _markDisconnected () {
    if (this.state.connected) this._log('设备已移除')
    this.state.connected = false
    this.state.info = emptyInfo()
    this.state.usbDescription = 'USB 2c7c:0125'
    this.bridge.request('close').catch(() => {})
    this.emitUpdate()
  }

  refreshAll () {
    return this._run(async () => {
      await this._refreshInfo()
      await this._refreshMessages()
      this.state.lastUpdated = Date.now()
    })
  }

  refreshMessages () {
    return this._run(async () => {
      await this._refreshMessages()
      this.state.lastUpdated = Date.now()
    })
  }

  sendSMS (number, body) {
    const cleanNumber = trimmed(number)
    const cleanBody = trimmed(body)
    if (!cleanNumber || !cleanBody) return Promise.resolve({ ok: false, error: '收件人和内容不能为空' })
    return this._run(async () => {
      await this._send('AT+CMGF=1')
      await this._send('AT+CSCS="UCS2"')
      const encodedNumber = UCS2.encode(cleanNumber)
      const encodedBody = UCS2.encode(cleanBody)
      // Payload terminates with Ctrl-Z (0x1A) to submit the message.
      await this._send(`AT+CMGS="${encodedNumber}"`, { payload: encodedBody + String.fromCharCode(0x1A), timeout: 25000 })
      // Record locally so it shows as an outgoing bubble in the conversation.
      this.state.sentMessages.push({ ts: Date.now(), to: cleanNumber, body: cleanBody, date: modemDateNow() })
      this._saveSentLog()
      await this._refreshMessages()
      this.state.lastUpdated = Date.now()
      return { ok: true }
    })
  }

  // storage: 'ME' | 'SM' (on the modem) or 'SENT' (local sent log).
  deleteSMS (index, storage = 'ME') {
    return this._run(async () => {
      if (storage === 'SENT') {
        this.state.sentMessages = this.state.sentMessages.filter((s) => s.ts !== index)
        this._saveSentLog()
        await this._refreshMessages()
        return { ok: true }
      }
      await this._send('AT+CMGF=1')
      await this._send(`AT+CPMS="${storage}","${storage}","${storage}"`).catch(() => {})
      await this._send(`AT+CMGD=${index}`)
      await this._refreshMessages()
      this.state.lastUpdated = Date.now()
      return { ok: true }
    })
  }

  runTerminalCommand (command) {
    const clean = trimmed(command)
    if (!clean) return Promise.resolve({ ok: false })
    return this._run(async () => {
      this._appendTerminal('> ' + clean)
      try {
        const lines = await this._send(clean, { timeout: 15000 })
        if (lines.length === 0) this._appendTerminal('OK')
        else { lines.forEach((l) => this._appendTerminal(l)); this._appendTerminal('OK') }
        return { ok: true }
      } catch (e) {
        this._appendTerminal('ERROR: ' + (e.message || e))
        throw e
      }
    })
  }

  setUsbMode (mode) {
    return this._run(async () => {
      await this._send(`AT+QCFG="usbnet",${mode}`, { timeout: 8000 })
      await this._send('AT+QCFG="usbnet"', { timeout: 6000 })
      await this._refreshInfo()
      this.state.lastUpdated = Date.now()
      return { ok: true }
    })
  }

  setApn (apn, cid = 1, type = 'IPV4V6') {
    const clean = trimmed(apn)
    if (!clean) return Promise.resolve({ ok: false, error: 'APN 不能为空' })
    return this._run(async () => {
      await this._send(`AT+CGDCONT=${cid},"${type}","${clean}"`, { timeout: 8000 })
      await this._refreshInfo()
      this.state.lastUpdated = Date.now()
      return { ok: true }
    })
  }

  researchNetwork () {
    return this._run(async () => {
      this._log('开始重新搜索网络…')
      await this._send('AT+COPS=2', { timeout: 20000 })   // deregister
      await this._send('AT+COPS=0', { timeout: 60000 })   // automatic re-selection
      await this._refreshInfo()
      this.state.lastUpdated = Date.now()
      return { ok: true }
    })
  }

  restartModule () {
    return this._run(async () => {
      await this._send('AT+CFUN=1,1', { timeout: 4000 }).catch(() => {})
      this.state.connected = false
      this._closeSession()
      this._log('模块重启中，等待重新枚举…')
      return { ok: true }
    })
  }

  // ----- internals ---------------------------------------------------------

  async _initialize () {
    await this._send('AT', { timeout: 5000 })
    await this._send('ATE0', { timeout: 5000 })
    await this._send('AT+CMEE=2')
    await this._send('AT+CMGF=1')
    await this._send('AT+CSCS="UCS2"')
    await this._send('AT+CNMI=2,1,0,0,0').catch(() => {})
    await this._refreshInfo()
    await this._refreshMessages()
    this.state.lastUpdated = Date.now()
  }

  async _refreshInfo () {
    this._refreshNetworkHints()
    this.state.commandRecords = []

    const manufacturer = await this._query('厂商', 'AT+CGMI')
    const model = await this._query('型号', 'AT+CGMM')
    const revision = await this._query('固件', 'AT+CGMR')
    const imei = await this._query('IMEI', 'AT+CGSN')
    const imsi = await this._query('IMSI', 'AT+CIMI')
    const iccid = await this._query('ICCID', 'AT+QCCID')
    const ownNumber = await this._query('本机号码', 'AT+CNUM')
    const sim = await this._query('SIM 状态', 'AT+CPIN?')
    const simInserted = await this._query('SIM 插入', 'AT+QSIMSTAT?')
    const operatorName = await this._query('运营商', 'AT+COPS?')
    const signal = await this._query('信号', 'AT+CSQ')
    const registration = await this._query('CS 注册', 'AT+CREG?')
    const gprsRegistration = await this._query('PS 注册', 'AT+CGREG?')
    const epsRegistration = await this._query('EPS 注册', 'AT+CEREG?')
    const packetAttached = await this._query('分组附着', 'AT+CGATT?')
    const activePdp = await this._query('PDP 激活', 'AT+CGACT?')
    const pdpAddress = await this._query('PDP 地址', 'AT+CGPADDR')
    const networkInfo = await this._query('数据网络类型', 'AT+QNWINFO')
    const servingCell = await this._query('服务小区', 'AT+QENG="servingcell"', 8000)
    const carrierAggregation = await this._query('载波聚合', 'AT+QCAINFO', 8000)
    const usbNetworkMode = await this._query('USB 网络模式', 'AT+QCFG="usbnet"')
    const apnProfiles = await this._query('APN/PDP 配置', 'AT+CGDCONT?', 8000)
    const qosLines = await this._query('QoS', 'AT+CGEQOSRDP')
    const temperature = await this._query('温度', 'AT+QTEMP')

    const csq = this._parseSignal(signal)
    const net = this._parseNetworkType(networkInfo)
    const cell = this._parseServingCell(servingCell)

    // Prefer LTE band/EARFCN from the serving cell; fall back to QNWINFO.
    const band = cell.band ?? (net.band !== '-' ? net.band.replace(/[^0-9]/g, '') : '-')
    const earfcn = cell.earfcn ?? (net.channel !== '-' ? net.channel : '-')
    const freq = earfcnToDlMhz(band, earfcn)

    // Bar count: RSRP-based when available, else CSQ.
    const rsrpBars = barsFromRsrp(cell.rsrp)
    if (rsrpBars != null) csq.bars = rsrpBars

    this.state.info = {
      manufacturer: firstNonCommandLine(manufacturer) || '-',
      model: firstNonCommandLine(model) || '-',
      revision: firstNonCommandLine(revision) || '-',
      imei: firstNonCommandLine(imei) || '-',
      imsi: firstNonCommandLine(imsi) || '-',
      iccid: this._parseICCID(iccid),
      ownNumber: this._parseOwnNumber(ownNumber),
      simStatus: this._parsePrefixed(sim, '+CPIN:'),
      simInserted: this._parsePrefixed(simInserted, '+QSIMSTAT:'),
      operatorName: this._parseOperator(operatorName),
      signal: csq,
      ber: this._parseBER(signal),
      registration: this._parseRegistration(registration, '+CREG:'),
      gprsRegistration: this._parseRegistration(gprsRegistration, '+CGREG:'),
      epsRegistration: this._parseRegistration(epsRegistration, '+CEREG:'),
      packetAttached: this._parsePrefixed(packetAttached, '+CGATT:'),
      activePdp: this._compactLines(activePdp, '+CGACT:'),
      pdpAddress: this._compactLines(pdpAddress, '+CGPADDR:'),
      dataNetworkType: net.full,
      networkLabel: net.label,
      band: band && band !== '-' ? `Band ${band}` : '-',
      channel: earfcn ?? '-',
      tech: this._parseTech(operatorName, net.label),
      servingCell: this._compactLines(servingCell, '+QENG:'),
      carrierAggregation: this._compactLines(carrierAggregation, '+QCAINFO:'),
      usbNetworkMode: this._parseUSBNetworkMode(usbNetworkMode),
      apnProfiles: this._parseApnProfiles(apnProfiles),
      currentApn: this._currentApn(this._parseApnProfiles(apnProfiles)),
      // serving-cell metrics
      rsrp: cell.rsrp != null ? `${cell.rsrp} dBm` : '-',
      rsrq: cell.rsrq != null ? `${cell.rsrq} dB` : '-',
      rssiDbm: cell.rssi != null ? `${cell.rssi} dBm` : csq.text,
      sinr: cell.sinr != null ? `${cell.sinr}` : '-',
      cqi: cell.cqi != null ? `${cell.cqi}` : '-',
      modulation: cqiToModulation(cell.cqi),
      dlBandwidth: cell.dlBw ?? '-',
      ulBandwidth: cell.ulBw ?? '-',
      pci: cell.pci ?? '-',
      cellId: cell.cellId ?? '-',
      tac: cell.tac ?? '-',
      earfcn: earfcn ?? '-',
      freqMhz: freq != null ? `${freq} MHz` : '-',
      qos: this._parseQos(qosLines),
      temperature: this._parseTemperature(temperature)
    }
    this.emitUpdate()
  }

  // Read messages from both ME and SM storages (a modem may store SMS in
  // either), tagging each with its origin so deletes hit the right store.
  async _refreshMessages () {
    await this._send('AT+CMGF=1')
    await this._send('AT+CSCS="UCS2"')

    const all = []
    for (const storage of ['ME', 'SM']) {
      try {
        await this._send(`AT+CPMS="${storage}","${storage}","${storage}"`)
      } catch {
        continue
      }
      const lines = await this._send('AT+CMGL="ALL"', { timeout: 12000 }).catch(() => [])
      all.push(...this._parseMessageList(lines, storage))
    }

    all.push(...this._sentAsMessages())
    all.sort((a, b) => (a.date === b.date ? b.index - a.index : (a.date < b.date ? 1 : -1)))
    this.state.messages = all
    this.state.unreadCount = all.filter((m) => m.unread).length
    this.emitUpdate()
  }

  // Mark messages read on the modem by reading each (AT+CMGR flips UNREAD->READ).
  async _markRead (messages) {
    const targets = messages.filter((m) => m.unread && m.storage !== 'SENT')
    if (!targets.length) return
    const byStorage = {}
    for (const m of targets) (byStorage[m.storage] = byStorage[m.storage] || []).push(m.index)
    await this._send('AT+CMGF=1')
    for (const [storage, indices] of Object.entries(byStorage)) {
      await this._send(`AT+CPMS="${storage}","${storage}","${storage}"`).catch(() => {})
      for (const idx of indices) await this._send(`AT+CMGR=${idx}`, { timeout: 6000 }).catch(() => {})
    }
  }

  markAllRead () {
    return this._run(async () => {
      await this._markRead(this.state.messages)
      await this._refreshMessages()
      this.state.lastUpdated = Date.now()
      return { ok: true }
    })
  }

  markConversationRead (sender) {
    return this._run(async () => {
      const msgs = this.state.messages.filter((m) => (m.sender || '未知') === sender)
      if (!msgs.some((m) => m.unread)) return { ok: true }
      await this._markRead(msgs)
      await this._refreshMessages()
      this.state.lastUpdated = Date.now()
      return { ok: true }
    })
  }

  _parseMessageList (lines, storage) {
    const parsed = []
    let i = 0
    while (i < lines.length) {
      const line = lines[i]
      if (!line.startsWith('+CMGL:')) { i++; continue }
      const parts = csvParts(line.replace('+CMGL:', ''))
      const messageIndex = parseInt(trimmed(parts[0]) || '0', 10) || 0
      const status = MSG_STATUS[trimQuotes(parts[1] ?? '')] ?? trimQuotes(parts[1] ?? '-')
      const sender = UCS2.decode(trimQuotes(parts[2] ?? '-'))
      const date = trimQuotes(parts[4] ?? '-')
      const bodyLines = []
      i++
      while (i < lines.length && !lines[i].startsWith('+CMGL:')) {
        bodyLines.push(UCS2.decode(lines[i]))
        i++
      }
      const upper = (status || '').toUpperCase()
      const out = /STO|SENT/.test(upper)
      parsed.push({
        id: `${storage}-${messageIndex}`,
        storage,
        index: messageIndex,
        status,
        outgoing: out,
        unread: upper.includes('UNREAD'),
        sender,
        date,
        body: bodyLines.join('\n')
      })
    }
    return parsed
  }

  async _query (title, command, timeout = 5000) {
    try {
      const lines = await this._send(command, { timeout })
      this.state.commandRecords.push({ title, command, lines, error: null })
      return lines
    } catch (e) {
      this.state.commandRecords.push({ title, command, lines: [], error: String(e.message || e) })
      return []
    }
  }

  async _send (command, { payload, timeout = 4000 } = {}) {
    this._log('> ' + command)
    const res = await this.bridge.request('send', { command, payload, timeoutMs: timeout }, timeout + 5000)
    const lines = res.lines || []
    if (lines.length === 0) this._log('< OK')
    else lines.forEach((l) => this._log('< ' + l))
    return lines
  }

  _run (fn) {
    const task = this._chain.then(async () => {
      this.state.busy = true
      this.state.lastError = null
      this.emitUpdate()
      try {
        return await fn()
      } catch (e) {
        this.state.lastError = String(e.message || e)
        this._log('错误：' + this.state.lastError)
        return { ok: false, error: this.state.lastError }
      } finally {
        this.state.busy = false
        this.emitUpdate()
      }
    })
    this._chain = task.then(() => {}, () => {})
    return task
  }

  _log (line) {
    this.state.logLines.push(line)
    if (this.state.logLines.length > 600) this.state.logLines.splice(0, this.state.logLines.length - 600)
  }

  _appendTerminal (line) {
    this.state.terminalLines.push(line)
    if (this.state.terminalLines.length > 600) this.state.terminalLines.splice(0, this.state.terminalLines.length - 600)
  }

  _refreshNetworkHints () {
    const hints = []
    const ifaces = os.networkInterfaces()
    for (const [name, addrs] of Object.entries(ifaces)) {
      for (const addr of addrs || []) {
        if (addr.family === 'IPv4' && !addr.internal && addr.address.startsWith('192.168.225.')) {
          hints.push(`${name} · ${addr.address}`)
        }
      }
    }
    this.state.networkHints = hints.sort()
  }

  // ----- field parsers -----------------------------------------------------

  _parseSignal (lines) {
    const line = firstLine(lines, '+CSQ:')
    if (!line) return { dbm: null, bars: 0, percent: 0, text: '-' }
    const payload = line.replace('+CSQ:', '')
    const rssi = parseInt(trimmed(csvParts(payload)[0]) || '99', 10)
    return signalFromRssi(Number.isNaN(rssi) ? 99 : rssi)
  }

  _parseBER (lines) {
    const line = firstLine(lines, '+CSQ:')
    if (!line) return '-'
    return trimmed(csvParts(line.replace('+CSQ:', ''))[1]) || '-'
  }

  _parseOperator (lines) {
    const line = firstLine(lines, '+COPS:')
    if (!line) return '-'
    const parts = csvParts(line.replace('+COPS:', ''))
    return UCS2.decode(trimQuotes(parts[2] ?? line))
  }

  _parseTech (operatorLines, fallback) {
    const line = firstLine(operatorLines, '+COPS:')
    if (line) {
      const parts = csvParts(line.replace('+COPS:', ''))
      const act = parseInt(trimmed(parts[3] ?? ''), 10)
      if (!Number.isNaN(act) && ACT_TECH[act]) return ACT_TECH[act]
    }
    return fallback || '-'
  }

  _parseICCID (lines) {
    const prefixed = firstLine(lines, '+QCCID:')
    if (prefixed) return trimQuotes(prefixed.replace('+QCCID:', ''))
    return firstNonCommandLine(lines) || '-'
  }

  _parsePrefixed (lines, prefix) {
    const line = firstLine(lines, prefix)
    if (!line) return '-'
    return trimQuotes(line.replace(prefix, ''))
  }

  _parseOwnNumber (lines) {
    const line = firstLine(lines, '+CNUM:')
    if (!line) return '-'
    const parts = csvParts(line.replace('+CNUM:', ''))
    return UCS2.decode(trimQuotes(parts[1] ?? line))
  }

  _parseRegistration (lines, prefix) {
    const line = firstLine(lines, prefix)
    if (!line) return '-'
    const parts = csvParts(line.replace(prefix, ''))
    const stat = trimmed(parts[parts.length - 1])
    return REG_STATUS[stat] ?? stat
  }

  _parseNetworkType (lines) {
    const line = firstLine(lines, '+QNWINFO:')
    if (!line) return { full: '-', label: '-', band: '-', channel: '-' }
    const parts = csvParts(line.replace('+QNWINFO:', ''))
    const access = trimQuotes(parts[0] ?? '-')
    const band = trimQuotes(parts[2] ?? '-')
    const channel = trimmed(parts[3] ?? '-')
    if (access === '-' || access === '' || access.toUpperCase().includes('NONE') || access.toUpperCase().includes('NO SERVICE')) {
      return { full: '无服务', label: '无服务', band: '-', channel: '-' }
    }
    return { full: `${access} · ${band} · ${channel}`, label: shortNetworkLabel(access), band, channel }
  }

  // Parse AT+QENG="servingcell" for LTE metrics. Returns fields or nulls.
  _parseServingCell (lines) {
    const empty = { band: null, earfcn: null, rsrp: null, rsrq: null, rssi: null, sinr: null, cqi: null, dlBw: null, ulBw: null, pci: null, cellId: null, tac: null }
    const line = firstLine(lines, '+QENG:')
    if (!line) return empty
    const parts = csvParts(line.replace('+QENG:', '')).map(trimQuotes)
    // parts[0]="servingcell", parts[2]=rat
    const rat = (parts[2] || '').toUpperCase()
    if (rat !== 'LTE') return empty
    // "servingcell",state,"LTE",dup,MCC,MNC,cellID,PCID,EARFCN,band,ULbw,DLbw,TAC,RSRP,RSRQ,RSSI,SINR,CQI,...
    const num = (v) => { const n = Number(v); return Number.isFinite(n) ? n : null }
    return {
      cellId: parts[6] || null,
      pci: num(parts[7]),
      earfcn: num(parts[8]),
      band: num(parts[9]),
      ulBw: BW_INDEX[parts[10]] ?? null,
      dlBw: BW_INDEX[parts[11]] ?? null,
      tac: parts[12] || null,
      rsrp: num(parts[13]),
      rsrq: num(parts[14]),
      rssi: num(parts[15]),
      sinr: num(parts[16]),
      cqi: num(parts[17])
    }
  }

  // Parse AT+CGEQOSRDP -> the default bearer's QCI, if the network reports it.
  _parseQos (lines) {
    const entries = lines.filter((l) => l.includes('+CGEQOSRDP:'))
    for (const l of entries) {
      const parts = csvParts(l.replace('+CGEQOSRDP:', ''))
      const qci = parseInt(trimmed(parts[1] ?? ''), 10)
      if (Number.isFinite(qci) && qci > 0) {
        return `QCI ${qci}${QCI_DESC[qci] ? ' · ' + QCI_DESC[qci] : ''}`
      }
    }
    return '不可用'
  }

  // AT+QTEMP -> hottest sensor in °C. Handles both bare "37,34,34" and
  // "name",value pairs; ignores non-temperature tokens.
  _parseTemperature (lines) {
    const line = firstLine(lines, '+QTEMP:')
    if (!line) return '-'
    const nums = csvParts(line.replace('+QTEMP:', ''))
      .map((p) => trimQuotes(p).trim())
      .filter((p) => /^-?\d+$/.test(p))
      .map(Number)
      .filter((n) => n > -50 && n < 200)
    if (!nums.length) return '-'
    return `${Math.max(...nums)} °C`
  }

  _parseUSBNetworkMode (lines) {
    const line = firstLine(lines, '+QCFG:')
    if (!line) return '-'
    const parts = csvParts(line.replace('+QCFG:', ''))
    const mode = trimmed(parts[parts.length - 1])
    const name = USBNET_MODE[mode] ?? '未知'
    return `${name} (${mode})`
  }

  _parseApnProfiles (lines) {
    return lines
      .filter((l) => l.includes('+CGDCONT:'))
      .map((l) => {
        const parts = csvParts(l.replace('+CGDCONT:', ''))
        return {
          cid: trimmed(parts[0] ?? '-'),
          type: trimQuotes(parts[1] ?? '-'),
          apn: trimQuotes(parts[2] ?? '-')
        }
      })
  }

  // The current/default-bearer APN (cid 1), used prominently in the UI.
  _currentApn (profiles) {
    const def = (profiles || []).find((p) => p.cid === '1') || (profiles || [])[0]
    return def && def.apn && def.apn !== '-' ? `${def.apn} (${def.type})` : '-'
  }

  _compactLines (lines, prefix) {
    const matched = lines.filter((l) => l.includes(prefix))
    if (matched.length === 0) return '-'
    return matched.map((l) => trimmed(l.replace(prefix, ''))).join('\n')
  }
}

module.exports = { ModemManager }
