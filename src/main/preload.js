const { contextBridge, ipcRenderer } = require('electron');

function subscribe(channel, cb) {
  const listener = (_e, payload) => cb(payload);
  ipcRenderer.on(channel, listener);
  return () => ipcRenderer.removeListener(channel, listener);
}

contextBridge.exposeInMainWorld('api', {
  dev: process.argv.includes('--vc-dev'),
  update: {
    status: () => ipcRenderer.invoke('update:status'),
    check: () => ipcRenderer.invoke('update:check'),
    install: () => ipcRenderer.invoke('update:install'),
  },
  auth: {
    restore: () => ipcRenderer.invoke('auth:restore'),
    login: (token) => ipcRenderer.invoke('auth:login', token),
    logout: () => ipcRenderer.invoke('auth:logout'),
    openTokenPage: () => ipcRenderer.invoke('auth:createTokenPage'),
  },
  game: {
    watch: (id) => ipcRenderer.invoke('game:watch', id),
    move: (id, uci) => ipcRenderer.invoke('game:move', id, uci),
    resign: (id) => ipcRenderer.invoke('game:resign', id),
    abort: (id) => ipcRenderer.invoke('game:abort', id),
    draw: (id, accept) => ipcRenderer.invoke('game:draw', id, accept),
    exportGame: (id) => ipcRenderer.invoke('game:export', id),
    challengeAi: (opts) => ipcRenderer.invoke('game:challengeAi', opts),
    seek: (opts) => ipcRenderer.invoke('game:seek', opts),
    cancelSeek: () => ipcRenderer.invoke('game:cancelSeek'),
    openInBrowser: (id) => ipcRenderer.invoke('open:game', id),
  },
  settings: {
    get: () => ipcRenderer.invoke('settings:get'),
    set: (patch) => ipcRenderer.invoke('settings:set', patch),
  },
  speech: {
    say: (text, interrupt = false) => ipcRenderer.send('speech:say', text, interrupt),
    setGrammar: (items) => ipcRenderer.send('speech:grammar', items),
    listen: (on) => ipcRenderer.send('speech:listen', on),
  },
  on: {
    lichessEvent: (cb) => subscribe('lichess:event', cb),
    lichessStatus: (cb) => subscribe('lichess:status', cb),
    gameEvent: (cb) => subscribe('game:event', cb),
    seekStatus: (cb) => subscribe('seek:status', cb),
    speechEvent: (cb) => subscribe('speech:event', cb),
    updateStatus: (cb) => subscribe('update:status', cb),
  },
});
