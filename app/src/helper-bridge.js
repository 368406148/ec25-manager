'use strict'

const { spawn } = require('child_process')
const readline = require('readline')
const { EventEmitter } = require('events')

// Spawns the Swift EC25Helper process and speaks the line-delimited JSON
// protocol. Requests are matched to responses by an incrementing id.
class HelperBridge extends EventEmitter {
  constructor (binaryPath, env = {}) {
    super()
    this.binaryPath = binaryPath
    this.env = env
    this.proc = null
    this.nextId = 1
    this.pending = new Map()
  }

  get running () {
    return this.proc != null
  }

  start () {
    if (this.running) return
    const child = spawn(this.binaryPath, [], {
      env: { ...process.env, ...this.env },
      stdio: ['pipe', 'pipe', 'pipe']
    })
    this.proc = child

    const rl = readline.createInterface({ input: child.stdout })
    rl.on('line', (line) => this._onLine(line))

    child.stderr.on('data', (chunk) => this.emit('stderr', chunk.toString()))
    const onDead = (info) => {
      // Clear proc so `running` is false and the next start() respawns.
      // Guard against a late event from an already-replaced child.
      if (this.proc === child) this.proc = null
      this._failAll(typeof info === 'string' ? info : `helper exited (code ${info})`)
    }
    child.on('exit', (code) => { onDead(code); this.emit('exit', code) })
    child.on('error', (err) => { onDead(err.message); this.emit('error', err) })
  }

  _onLine (line) {
    let msg
    try {
      msg = JSON.parse(line)
    } catch {
      return
    }
    const entry = this.pending.get(msg.id)
    if (!entry) return
    this.pending.delete(msg.id)
    if (msg.ok) entry.resolve(msg)
    else entry.reject(new Error(msg.error || 'helper error'))
  }

  _failAll (reason) {
    for (const entry of this.pending.values()) entry.reject(new Error(reason))
    this.pending.clear()
  }

  request (op, params = {}, timeoutMs = 30000) {
    return new Promise((resolve, reject) => {
      if (!this.running) {
        reject(new Error('helper 未运行'))
        return
      }
      const id = this.nextId++
      const timer = setTimeout(() => {
        if (this.pending.has(id)) {
          this.pending.delete(id)
          reject(new Error('helper 请求超时'))
        }
      }, timeoutMs)
      this.pending.set(id, {
        resolve: (v) => { clearTimeout(timer); resolve(v) },
        reject: (e) => { clearTimeout(timer); reject(e) }
      })
      try {
        this.proc.stdin.write(JSON.stringify({ id, op, ...params }) + '\n')
      } catch (e) {
        clearTimeout(timer)
        this.pending.delete(id)
        reject(e)
      }
    })
  }

  stop () {
    if (this.proc) {
      try { this.proc.stdin.end() } catch {}
      try { this.proc.kill() } catch {}
      this.proc = null
    }
  }
}

module.exports = { HelperBridge }
