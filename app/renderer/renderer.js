'use strict'

const el = (id) => document.getElementById(id)
const $ = (sel) => document.querySelector(sel)

let lastState = null
let settings = null
const sms = { view: 'list', activeSender: null }

// ---------- field catalog (#9 selectable status fields) ----------
const FIELD_CATALOG = [
  { key: 'dataNetworkType', label: '数据网络类型', wide: true, get: (i) => i.dataNetworkType },
  { key: 'operator', label: '运营商', get: (i) => i.operatorName },
  { key: 'tech', label: '网络制式', get: (i) => i.tech },
  { key: 'regCS', label: 'CS 注册', get: (i) => i.registration },
  { key: 'regPS', label: 'PS 注册', get: (i) => i.gprsRegistration },
  { key: 'regEPS', label: 'EPS 注册', get: (i) => i.epsRegistration },
  { key: 'attach', label: '分组附着', get: (i) => (i.packetAttached === '1' ? '已附着' : i.packetAttached === '0' ? '未附着' : i.packetAttached) },
  { key: 'imei', label: 'IMEI', mono: true, get: (i) => i.imei },
  { key: 'imsi', label: 'IMSI', mono: true, get: (i) => i.imsi },
  { key: 'iccid', label: 'ICCID', wide: true, mono: true, get: (i) => i.iccid },
  { key: 'simStatus', label: 'SIM 状态', get: (i) => i.simStatus },
  { key: 'simInserted', label: 'SIM 插入', get: (i) => i.simInserted },
  { key: 'ownNumber', label: '本机号码', get: (i) => i.ownNumber },
  { key: 'pdp', label: 'PDP 地址', wide: true, mono: true, get: (i) => i.pdpAddress },
  { key: 'band', label: '频段', get: (i) => i.band },
  { key: 'earfcn', label: '信道 (EARFCN)', get: (i) => i.earfcn },
  { key: 'freq', label: '下行频率', get: (i) => i.freqMhz },
  { key: 'rsrp', label: 'RSRP', get: (i) => i.rsrp },
  { key: 'rsrq', label: 'RSRQ', get: (i) => i.rsrq },
  { key: 'rssi', label: 'RSSI', get: (i) => i.rssiDbm },
  { key: 'sinr', label: 'SINR', get: (i) => i.sinr },
  { key: 'cqi', label: 'CQI', get: (i) => i.cqi },
  { key: 'modulation', label: '调制状态', get: (i) => i.modulation },
  { key: 'dlbw', label: '下行带宽', get: (i) => i.dlBandwidth },
  { key: 'ulbw', label: '上行带宽', get: (i) => i.ulBandwidth },
  { key: 'pci', label: 'PCI', get: (i) => i.pci },
  { key: 'cellId', label: 'Cell ID', mono: true, get: (i) => i.cellId },
  { key: 'tac', label: 'TAC', get: (i) => i.tac },
  { key: 'qos', label: 'QoS 级别', wide: true, get: (i) => i.qos },
  { key: 'temp', label: '模组温度', get: (i) => i.temperature },
  { key: 'ber', label: 'BER', get: (i) => i.ber },
  { key: 'usbnet', label: 'USB 模式', get: (i) => i.usbNetworkMode }
]
const FIELD_MAP = Object.fromEntries(FIELD_CATALOG.map((f) => [f.key, f]))

// ---------- toast ----------
let toastTimer = null
function toast (msg, isError = false) {
  const t = el('toast')
  t.textContent = msg
  t.classList.toggle('error', isError)
  t.classList.add('show')
  clearTimeout(toastTimer)
  toastTimer = setTimeout(() => t.classList.remove('show'), 2200)
}

async function action (promise, okMsg) {
  try {
    const res = await promise
    if (res && res.ok === false) { toast(res.error || '操作失败', true); return res }
    if (okMsg) toast(okMsg)
    return res
  } catch (e) {
    toast(String(e.message || e), true)
  }
}

function escapeHtml (s) {
  return String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]))
}
function isTyping (node) { return document.activeElement === node }

// ---------- tabs ----------
document.querySelectorAll('.tab').forEach((tab) => {
  tab.addEventListener('click', () => {
    document.querySelectorAll('.tab').forEach((t) => t.classList.remove('active'))
    document.querySelectorAll('.panel').forEach((p) => p.classList.remove('active'))
    tab.classList.add('active')
    $(`.panel[data-panel="${tab.dataset.tab}"]`).classList.add('active')
  })
})

// ---------- render: modem state ----------
function render (state) {
  lastState = state
  const info = state.info

  const dot = el('statusDot')
  dot.className = 'dot ' + (state.connected ? 'online' : state.busy ? 'busy' : 'offline')
  el('statusText').textContent = state.connected ? (state.busy ? '执行中' : '在线') : (state.busy ? '连接中' : '离线')
  el('usbDesc').textContent = state.connected ? state.usbDescription : '设备未连接'
  el('btnRefresh').classList.toggle('spin', state.busy)

  const bars = el('signalBars')
  bars.className = 'bars q' + (info.signal.bars || 0)
  el('heroDbm').textContent = info.rsrp && info.rsrp !== '-' ? info.rsrp : (info.signal.dbm != null ? `${info.signal.dbm} dBm` : (state.connected ? '未知' : '-- dBm'))
  el('netBadge').textContent = info.networkLabel || '--'
  el('heroOperator').textContent = info.operatorName || '--'
  el('regValue').textContent = info.epsRegistration !== '-' ? info.epsRegistration : info.registration

  renderGrid(info)

  const ca = [info.carrierAggregation, info.servingCell].filter((x) => x && x !== '-').join('\n')
  el('caText').textContent = ca || '暂无载波聚合信息'

  const unread = state.unreadCount || 0
  el('smsTabDot').classList.toggle('hidden', unread === 0)
  el('btnMarkRead').classList.toggle('hidden', unread === 0)
  renderSms(state.messages)

  const out = el('terminalOut')
  const atBottom = out.scrollHeight - out.scrollTop - out.clientHeight < 40
  out.textContent = state.terminalLines.join('\n')
  if (atBottom) out.scrollTop = out.scrollHeight

  // settings device panel
  el('usbCurrent').textContent = '当前：' + info.usbNetworkMode
  el('apnCurrentMain').textContent = info.currentApn || '-'
  if (info.currentApn && info.currentApn !== '-') el('apnInput').placeholder = info.currentApn.replace(/\s*\(.*\)$/, '')
  const apnText = (info.apnProfiles || []).map((p) => `cid${p.cid}: ${p.apn} (${p.type})`).join('\n') || '-'
  el('apnCurrent').textContent = '全部配置：\n' + apnText
  el('ecmHint').textContent = 'ECM 网络：' + (state.networkHints.length ? state.networkHints.join('\n') : '未检测到 192.168.225.x')
  el('sManu').textContent = info.manufacturer
  el('sModel').textContent = info.model
  el('sRev').textContent = info.revision
  if (!isTyping(el('usbMode'))) {
    const m = String(info.usbNetworkMode).match(/\((\d)\)/)
    if (m) el('usbMode').value = m[1]
  }
}

function renderGrid (info) {
  const keys = (settings && settings.visibleFields) || FIELD_CATALOG.map((f) => f.key)
  const tiles = keys
    .map((k) => FIELD_MAP[k])
    .filter(Boolean)
    .map((f) => {
      const cls = 'tile' + (f.wide ? ' wide' : '')
      const vcls = 't-value' + (f.mono ? ' small' : '')
      const val = f.get(info)
      return `<div class="${cls}"><div class="t-label">${f.label}</div><div class="${vcls}">${escapeHtml(val || '-')}</div></div>`
    })
  el('infoGrid').innerHTML = tiles.join('') || '<div class="empty">未选择任何状态字段（在设置中开启）</div>'
}

// ---------- SMS conversations (#11) ----------
function cmpDate (a, b) { return a === b ? 0 : (a < b ? -1 : 1) }

function groupConversations (messages) {
  const map = new Map()
  for (const m of messages) {
    const key = m.sender && m.sender !== '-' ? m.sender : '未知'
    if (!map.has(key)) map.set(key, [])
    map.get(key).push(m)
  }
  const convs = []
  for (const [key, msgs] of map) {
    msgs.sort((a, b) => (a.date === b.date ? a.index - b.index : cmpDate(a.date, b.date)))
    convs.push({ key, messages: msgs, last: msgs[msgs.length - 1], count: msgs.length, unread: msgs.filter((m) => m.unread).length })
  }
  convs.sort((a, b) => cmpDate(b.last.date, a.last.date))
  return convs
}

function avatarText (name) {
  const digits = String(name).replace(/\D/g, '')
  if (digits.length >= 2) return digits.slice(-2)
  return String(name).slice(0, 2).toUpperCase()
}

function renderSms (messages) {
  const convs = groupConversations(messages)
  if (sms.view === 'thread') {
    el('smsListView').classList.add('hidden')
    el('smsThreadView').classList.remove('hidden')
    renderThread(convs)
  } else {
    el('smsThreadView').classList.add('hidden')
    el('smsListView').classList.remove('hidden')
    renderConvList(convs)
  }
}

function renderConvList (convs) {
  const totalUnread = convs.reduce((n, c) => n + c.unread, 0)
  el('smsCount').textContent = `${convs.length} 个会话` + (totalUnread ? ` · ${totalUnread} 未读` : '')
  const list = el('convList')
  if (!convs.length) { list.innerHTML = '<div class="empty">暂无短信</div>'; return }
  list.innerHTML = convs.map((c) => {
    const preview = (c.last.body || '').replace(/\n/g, ' ').slice(0, 40)
    const time = (c.last.date || '').split(',')[0]
    const badge = c.unread
      ? `<div class="conv-badge unread">${c.unread}</div>`
      : `<div class="conv-badge">${c.count}</div>`
    return `<div class="conv-item ${c.unread ? 'has-unread' : ''}" data-sender="${escapeHtml(c.key)}">
      <div class="conv-avatar">${escapeHtml(avatarText(c.key))}</div>
      <div class="conv-main">
        <div class="conv-top"><span class="conv-name">${escapeHtml(c.key)}</span><span class="conv-time">${escapeHtml(time)}</span></div>
        <div class="conv-preview">${escapeHtml(preview)}</div>
      </div>
      ${badge}
    </div>`
  }).join('')
  list.querySelectorAll('.conv-item').forEach((item) => {
    item.addEventListener('click', () => openThread(item.dataset.sender))
  })
}

function renderThread (convs) {
  const conv = convs.find((c) => c.key === sms.activeSender)
  el('threadTitle').textContent = sms.activeSender || '新短信'
  el('btnDeleteConv').classList.toggle('hidden', !conv)
  const box = el('bubbles')
  const atBottom = box.scrollHeight - box.scrollTop - box.clientHeight < 60
  if (!conv) {
    box.innerHTML = sms.activeSender ? '<div class="empty">该会话已无短信</div>' : '<div class="empty">输入收件人与内容，开始新会话</div>'
    return
  }
  box.innerHTML = conv.messages.map((m) => {
    const time = m.date || ''
    return `<div class="bubble ${m.outgoing ? 'out' : 'in'}">
      <button class="b-del" data-index="${m.index}" data-storage="${escapeHtml(m.storage)}" title="删除">✕</button>
      <div class="b-text">${escapeHtml(m.body)}</div>
      <div class="b-time">${escapeHtml(time)}</div>
    </div>`
  }).join('')
  box.querySelectorAll('.b-del').forEach((btn) => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation()
      action(window.api.deleteSMS(parseInt(btn.dataset.index, 10), btn.dataset.storage), '已删除')
    })
  })
  if (atBottom) box.scrollTop = box.scrollHeight
}

function openThread (sender) {
  sms.view = 'thread'
  sms.activeSender = sender
  el('smsTo').value = sender || ''
  el('smsTo').readOnly = !!sender
  if (lastState) renderSms(lastState.messages)
  if (!sender) setTimeout(() => el('smsTo').focus(), 50)
  // Opening a conversation marks its messages read (like a chat app).
  if (sender && lastState && lastState.messages.some((m) => (m.sender || '未知') === sender && m.unread)) {
    window.api.markConversationRead(sender)
  }
}

function backToList () {
  sms.view = 'list'
  sms.activeSender = null
  el('smsTo').readOnly = false
  if (lastState) renderSms(lastState.messages)
}

el('btnNewSms').addEventListener('click', () => { el('smsTo').value = ''; el('smsBody').value = ''; openThread(null) })
el('btnBackSms').addEventListener('click', backToList)
el('btnRefreshSms').addEventListener('click', () => window.api.refreshMessages())
el('btnMarkRead').addEventListener('click', () => action(window.api.markAllRead(), '已全部标记为已读'))
el('btnDeleteConv').addEventListener('click', async () => {
  if (!lastState || !sms.activeSender) return
  const msgs = lastState.messages.filter((m) => (m.sender || '未知') === sms.activeSender)
  for (const m of msgs) await window.api.deleteSMS(m.index, m.storage)
  toast('会话已清空')
  backToList()
})

el('btnSendSms').addEventListener('click', async () => {
  const to = el('smsTo').value
  const body = el('smsBody').value
  if (!to.trim() || !body.trim()) { toast('请填写收件人和内容', true); return }
  const res = await action(window.api.sendSMS(to, body), '短信已发送')
  if (res && res.ok !== false) {
    el('smsBody').value = ''
    if (!sms.activeSender) openThread(to.trim())
  }
})

// ---------- terminal ----------
function submitAt () {
  const cmd = el('atInput').value.trim()
  if (!cmd) return
  el('atInput').value = ''
  window.api.sendAT(cmd)
}
el('btnSendAt').addEventListener('click', submitAt)
el('atInput').addEventListener('keydown', (e) => { if (e.key === 'Enter') submitAt() })

const QUICK = ['ATI', 'AT+CSQ', 'AT+QNWINFO', 'AT+COPS?', 'AT+CGDCONT?', 'AT+QENG="servingcell"', 'AT+CGPADDR', 'AT+QCAINFO']
el('quickCmds').innerHTML = QUICK.map((c) => `<span class="chip">${escapeHtml(c)}</span>`).join('')
el('quickCmds').querySelectorAll('.chip').forEach((chip) => {
  chip.addEventListener('click', () => { el('atInput').value = chip.textContent; submitAt() })
})

// ---------- settings ----------
el('btnRefresh').addEventListener('click', () => window.api.refresh())

el('btnApplyUsb').addEventListener('click', () => {
  const mode = parseInt(el('usbMode').value, 10)
  action(window.api.setUsbMode(mode), '已切换 USB 模式，可能需要重启模块')
})
el('btnApplyApn').addEventListener('click', () => {
  const apn = el('apnInput').value.trim()
  if (!apn) { toast('请输入 APN', true); return }
  action(window.api.setApn(apn), 'APN 已设置')
})
el('btnResearch').addEventListener('click', () => action(window.api.researchNetwork(), '正在重新搜索网络…'))
el('btnReconnect').addEventListener('click', () => action(window.api.reconnect(), '正在重连…'))
el('btnRestart').addEventListener('click', () => action(window.api.restartModule(), '模块重启中…'))
el('btnQuit').addEventListener('click', () => window.api.quit())

el('setLogin').addEventListener('change', () => saveSettings({ openAtLogin: el('setLogin').checked }))
el('setInfoPoll').addEventListener('change', () => saveSettings({ infoPollSeconds: parseInt(el('setInfoPoll').value, 10) }))
el('setSmsPoll').addEventListener('change', () => saveSettings({ smsPollSeconds: parseInt(el('setSmsPoll').value, 10) }))
el('setRestartWake').addEventListener('change', () => saveSettings({ restartOnWake: el('setRestartWake').checked }))

async function saveSettings (partial) {
  settings = await window.api.setSettings(partial)
  applySettings(settings)
}

function applySettings (s) {
  settings = s
  el('setLogin').checked = !!s.openAtLogin
  el('setInfoPoll').value = String(s.infoPollSeconds)
  el('setSmsPoll').value = String(s.smsPollSeconds)
  el('setRestartWake').checked = !!s.restartOnWake
  renderFieldToggles(s)
  if (lastState) renderGrid(lastState.info)
}

function renderFieldToggles (s) {
  const enabled = new Set(s.visibleFields || [])
  el('fieldToggles').innerHTML = FIELD_CATALOG.map((f) => `
    <label class="field-toggle">
      <input type="checkbox" data-key="${f.key}" ${enabled.has(f.key) ? 'checked' : ''} />
      <span>${escapeHtml(f.label)}</span>
    </label>`).join('')
  el('fieldToggles').querySelectorAll('input[data-key]').forEach((cb) => {
    cb.addEventListener('change', () => {
      const key = cb.dataset.key
      let fields = (settings.visibleFields || []).slice()
      if (cb.checked) {
        if (!fields.includes(key)) {
          // insert in catalog order
          fields.push(key)
          fields = FIELD_CATALOG.map((f) => f.key).filter((k) => fields.includes(k))
        }
      } else {
        fields = fields.filter((k) => k !== key)
      }
      saveSettings({ visibleFields: fields })
    })
  })
}

// ---------- boot ----------
window.api.onState((state) => render(state))
window.api.onSettings((s) => applySettings(s))
window.api.getSettings().then((s) => { if (s) applySettings(s) })
window.api.getState().then((state) => { if (state) render(state) })
