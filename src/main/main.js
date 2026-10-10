const { app, BrowserWindow, ipcMain, shell, safeStorage, screen } = require('electron');
const path = require('path');
const fs = require('fs');
const { Lichess } = require('./lichess');
const { SpeechHost } = require('./speech');
const { setupUpdater } = require('./updater');

const APP_ROOT = path.join(__dirname, '..', '..');
const userDir = app.getPath('userData');
const settingsFile = path.join(userDir, 'settings.json');
const logDir = path.join(userDir, 'logs');

// ---------- logging / crash handling ----------
function log(...args) {
  try {
    fs.mkdirSync(logDir, { recursive: true });
    fs.appendFileSync(path.join(logDir, 'main.log'), `[${new Date().toISOString()}] ${args.join(' ')}\n`);
  } catch { /* ignore */ }
}
process.on('uncaughtException', (e) => { log('uncaught', e.stack || e); });
process.on('unhandledRejection', (e) => { log('unhandled', (e && e.stack) || e); });

// ---------- settings ----------
const DEFAULT_SETTINGS = {
  voice: '',
  rate: 0,
  volume: 100,
  threshold: 0.6,
  micMode: 'toggle', // 'toggle' | 'ptt'
  confirmMoves: false,
  echoMyMoves: true,
  announceOpponent: true,
  clockWarnings: true,
  detailedCaptures: true,
  threatWarnings: true,
  boardTheme: 'brown',
  pieceSet: 'cburnett',
  window: null,
};

function loadSettings() {
  try { return { ...DEFAULT_SETTINGS, ...JSON.parse(fs.readFileSync(settingsFile, 'utf8')) }; }
  catch { return { ...DEFAULT_SETTINGS }; }
}
let settings = loadSettings();
function saveSettings() {
  fs.mkdirSync(userDir, { recursive: true });
  fs.writeFileSync(settingsFile, JSON.stringify(settings, null, 2));
}

function loadToken() {
  if (!settings.tokenEnc) return null;
  try { return safeStorage.decryptString(Buffer.from(settings.tokenEnc, 'base64')); }
  catch { return null; }
}
function storeToken(token) {
  if (token) settings.tokenEnc = safeStorage.encryptString(token).toString('base64');
  else delete settings.tokenEnc;
  saveSettings();
}

// ---------- state ----------
let win = null;
let client = null;
let account = null;
let eventAbort = null;
let gameAbort = null;
let seekAbort = null;
const speech = new SpeechHost(
  path.join(APP_ROOT, 'speech', 'speech-host.ps1').replace('app.asar', 'app.asar.unpacked'),
);

function send(channel, payload) {
  if (win && !win.isDestroyed()) win.webContents.send(channel, payload);
}

speech.on('message', (msg) => send('speech:event', msg));

function applySpeechSettings() {
  speech.send({ type: 'voice', name: settings.voice || '', rate: settings.rate, volume: settings.volume });
  speech.send({ type: 'threshold', value: settings.threshold });
}

// ---------- lichess streams ----------
async function runEventStream() {
  if (eventAbort) eventAbort.abort();
  const abort = new AbortController();
  eventAbort = abort;
  let delay = 1000;
  while (!abort.signal.aborted && client) {
    try {
      send('lichess:status', { connected: true });
      await client.stream('/api/stream/event', {
        signal: abort.signal,
        onMessage: (ev) => { delay = 1000; send('lichess:event', ev); },
      });
    } catch (e) {
      if (abort.signal.aborted) return;
      log('event stream error', e.message);
      if (e.status === 401) { send('lichess:status', { connected: false, error: 'Token rejected (401). Please log in again.' }); return; }
    }
    if (abort.signal.aborted) return;
    send('lichess:status', { connected: false, reconnecting: true });
    await new Promise((r) => setTimeout(r, delay));
    delay = Math.min(delay * 2, 30000);
  }
}

async function watchGame(gameId) {
  if (gameAbort) gameAbort.abort();
  const abort = new AbortController();
  gameAbort = abort;
  let delay = 1000;
  while (!abort.signal.aborted) {
    try {
      await client.stream(`/api/board/game/stream/${gameId}`, {
        signal: abort.signal,
        onMessage: (ev) => { delay = 1000; send('game:event', { gameId, ...ev }); },
      });
      // Stream ends when the game is over.
      return;
    } catch (e) {
      if (abort.signal.aborted) return;
      log('game stream error', gameId, e.message);
      send('game:event', { gameId, type: 'streamError', message: e.message });
      if (e.status && e.status < 500 && e.status !== 429) return;
    }
    await new Promise((r) => setTimeout(r, delay));
    delay = Math.min(delay * 2, 15000);
  }
}

async function connect(token) {
  const c = new Lichess(token);
  const acc = await c.account();
  client = c;
  account = { id: acc.id, username: acc.username };
  let scopes = null;
  try { scopes = await c.tokenScopes(); } catch { /* not fatal */ }
  runEventStream();
  return { ...account, scopes };
}

function disconnect() {
  for (const a of [eventAbort, gameAbort, seekAbort]) if (a) a.abort();
  eventAbort = gameAbort = seekAbort = null;
  client = null;
  account = null;
}

// Wrap lichess calls so the renderer gets {ok, error} rather than a thrown IPC error.
function wrap(fn) {
  return async (_e, ...args) => {
    try { return { ok: true, data: await fn(...args) }; }
    catch (e) { log('ipc error', e.message); return { ok: false, error: e.message }; }
  };
}

function needClient() {
  if (!client) throw new Error('Not logged in');
  return client;
}

// ---------- IPC ----------
ipcMain.handle('auth:restore', wrap(async () => {
  const token = loadToken();
  if (!token) return null;
  return connect(token);
}));
ipcMain.handle('auth:login', wrap(async (token) => {
  token = String(token || '').trim();
  if (!token) throw new Error('Paste a token first');
  const info = await connect(token);
  storeToken(token);
  return info;
}));
ipcMain.handle('auth:logout', wrap(async () => { disconnect(); storeToken(null); }));
ipcMain.handle('auth:createTokenPage', () => shell.openExternal(
  'https://lichess.org/account/oauth/token/create?scopes[]=board:play&scopes[]=challenge:write&description=Voice+Chess+Desktop',
));
ipcMain.handle('open:game', (_e, gameId) => shell.openExternal(`https://lichess.org/${encodeURIComponent(gameId)}`));

ipcMain.handle('game:watch', wrap(async (gameId) => { needClient(); watchGame(gameId); }));
ipcMain.handle('game:move', wrap((gameId, uci) => needClient().move(gameId, uci)));
ipcMain.handle('game:resign', wrap((gameId) => needClient().resign(gameId)));
ipcMain.handle('game:abort', wrap((gameId) => needClient().abort(gameId)));
ipcMain.handle('game:draw', wrap((gameId, accept) => needClient().draw(gameId, accept)));
ipcMain.handle('game:export', wrap((gameId) => needClient().exportGame(gameId)));
ipcMain.handle('game:challengeAi', wrap((opts) => needClient().challengeAi(opts)));
ipcMain.handle('game:seek', wrap(async (opts) => {
  const c = needClient();
  if (seekAbort) seekAbort.abort();
  const abort = new AbortController();
  seekAbort = abort;
  c.seek({ ...opts, signal: abort.signal })
    .then(() => send('seek:status', { active: false }))
    .catch((e) => send('seek:status', { active: false, error: abort.signal.aborted ? null : e.message }));
  send('seek:status', { active: true });
}));
ipcMain.handle('game:cancelSeek', wrap(async () => {
  if (seekAbort) seekAbort.abort();
  seekAbort = null;
  send('seek:status', { active: false });
}));

ipcMain.handle('settings:get', () => {
  const { tokenEnc, window: _w, ...rest } = settings;
  return { ...rest, speechReady: speech.lastReady };
});
ipcMain.handle('settings:set', (_e, patch) => {
  const allowed = Object.keys(DEFAULT_SETTINGS).filter((k) => k !== 'window');
  for (const k of allowed) if (k in patch) settings[k] = patch[k];
  saveSettings();
  applySpeechSettings();
  return true;
});

ipcMain.on('speech:say', (_e, text, interrupt) => speech.send({ type: 'say', text, interrupt: !!interrupt }));
ipcMain.on('speech:grammar', (_e, items) => speech.send({ type: 'grammar', items }));
ipcMain.on('speech:listen', (_e, on) => speech.send({ type: 'listen', on: !!on }));

// ---------- window ----------
function validBounds(b) {
  if (!b) return null;
  const area = screen.getDisplayMatching(b).workArea;
  const visible = b.x < area.x + area.width - 50 && b.x + b.width > area.x + 50
    && b.y >= area.y - 10 && b.y < area.y + area.height - 50;
  return visible ? b : null;
}

function createWindow() {
  const bounds = validBounds(settings.window) || { width: 1180, height: 820 };
  win = new BrowserWindow({
    ...bounds,
    minWidth: 820,
    minHeight: 600,
    title: 'Voice Chess for Lichess',
    backgroundColor: '#1f1d1a',
    icon: path.join(APP_ROOT, 'assets', 'icon.png'),
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      additionalArguments: app.isPackaged ? [] : ['--vc-dev'],
    },
  });
  win.loadFile(path.join(APP_ROOT, 'src', 'renderer', 'index.html'));
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (url.startsWith('https://lichess.org/')) shell.openExternal(url);
    return { action: 'deny' };
  });
  win.webContents.on('will-navigate', (e) => e.preventDefault());
  win.on('close', () => {
    settings.window = win.getNormalBounds();
    saveSettings();
  });
}

app.whenReady().then(() => {
  speech.start();
  applySpeechSettings();
  createWindow();
  setupUpdater({ send, log });
});

app.on('window-all-closed', () => {
  disconnect();
  speech.stop();
  app.quit();
});
