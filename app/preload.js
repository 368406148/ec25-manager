'use strict'

const { contextBridge, ipcRenderer } = require('electron')

contextBridge.exposeInMainWorld('api', {
  onState: (cb) => {
    const listener = (_e, state) => cb(state)
    ipcRenderer.on('state', listener)
    return () => ipcRenderer.removeListener('state', listener)
  },
  onSettings: (cb) => {
    const listener = (_e, s) => cb(s)
    ipcRenderer.on('settings', listener)
    return () => ipcRenderer.removeListener('settings', listener)
  },
  getState: () => ipcRenderer.invoke('getState'),
  getSettings: () => ipcRenderer.invoke('getSettings'),
  setSettings: (partial) => ipcRenderer.invoke('setSettings', partial),
  refresh: () => ipcRenderer.invoke('refresh'),
  refreshMessages: () => ipcRenderer.invoke('refreshMessages'),
  sendAT: (cmd) => ipcRenderer.invoke('sendAT', cmd),
  sendSMS: (to, body) => ipcRenderer.invoke('sendSMS', { to, body }),
  deleteSMS: (index, storage) => ipcRenderer.invoke('deleteSMS', { index, storage }),
  markAllRead: () => ipcRenderer.invoke('markAllRead'),
  markConversationRead: (sender) => ipcRenderer.invoke('markConversationRead', sender),
  setUsbMode: (mode) => ipcRenderer.invoke('setUsbMode', mode),
  setApn: (apn) => ipcRenderer.invoke('setApn', apn),
  restartModule: () => ipcRenderer.invoke('restartModule'),
  researchNetwork: () => ipcRenderer.invoke('researchNetwork'),
  reconnect: () => ipcRenderer.invoke('reconnect'),
  quit: () => ipcRenderer.invoke('quit'),
  openExternal: (url) => ipcRenderer.invoke('openExternal', url)
})
