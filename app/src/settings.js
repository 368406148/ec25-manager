'use strict'

const fs = require('fs')
const path = require('path')

const DEFAULTS = {
  openAtLogin: true,       // auto-launch into the menu bar at login
  infoPollSeconds: 12,     // status/signal polling cadence (gentler on the modem)
  smsPollSeconds: 30,      // SMS polling cadence (0 = off)
  restartOnWake: true,     // after sleep, restart the module to restore the ECM network
  // #9 which overview fields to show, in order
  visibleFields: [
    'dataNetworkType', 'operator', 'regEPS', 'imei', 'imsi', 'iccid',
    'simStatus', 'ownNumber', 'rsrp', 'rsrq', 'sinr', 'modulation',
    'temp', 'tempAvg', 'band', 'freq', 'usbnet'
  ]
}

class Settings {
  constructor (filePath) {
    this.filePath = filePath
    this.values = { ...DEFAULTS }
    this._load()
  }

  _load () {
    try {
      const raw = JSON.parse(fs.readFileSync(this.filePath, 'utf8'))
      this.values = { ...DEFAULTS, ...raw }
      // arrays: fall back to defaults if malformed
      if (!Array.isArray(this.values.visibleFields) || this.values.visibleFields.length === 0) {
        this.values.visibleFields = [...DEFAULTS.visibleFields]
      }
    } catch {
      this.values = { ...DEFAULTS }
    }
  }

  get () {
    return this.values
  }

  update (partial) {
    this.values = { ...this.values, ...partial }
    try {
      fs.mkdirSync(path.dirname(this.filePath), { recursive: true })
      fs.writeFileSync(this.filePath, JSON.stringify(this.values, null, 2))
    } catch {
      /* best-effort persistence */
    }
    return this.values
  }
}

module.exports = { Settings, DEFAULTS }
