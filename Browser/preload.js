const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('vmsb', {
  env: () => ipcRenderer.invoke('env'),
  list: () => ipcRenderer.invoke('list'),
  prefs: () => ipcRenderer.invoke('prefs'),
  setAutoAdd: (on) => ipcRenderer.invoke('set-auto-add', on),
  action: (id, act) => ipcRenderer.invoke('action', id, act),
  ready: () => ipcRenderer.send('ui-ready'),
  on: (channel, fn) => {
    const allowed = ['downloads', 'download-started', 'open-url', 'focus-address', 'reload',
      'toggle-downloads', 'show-downloads', 'prefs', 'back', 'forward', 'home'];
    if (allowed.includes(channel)) ipcRenderer.on(channel, (_e, data) => fn(data));
  },
});
