// Auto-update from GitHub Releases (configured under "publish" in package.json).
// Updates download in the background; they install on "Restart to update" or when the app quits.
const { app, ipcMain } = require('electron');
const { autoUpdater } = require('electron-updater');

const CHECK_EVERY_MS = 4 * 60 * 60 * 1000;

function setupUpdater({ send, log }) {
  let status = { state: 'idle', version: app.getVersion() };
  const emit = (patch) => {
    status = { ...status, ...patch };
    send('update:status', status);
  };

  // `npm start` runs unpackaged; updates only make sense for installed builds
  // (VC_TEST_UPDATE=1 forces a check against dev-app-update.yml for testing).
  const enabled = app.isPackaged || process.env.VC_TEST_UPDATE === '1';
  if (process.env.VC_TEST_UPDATE === '1') autoUpdater.forceDevUpdateConfig = true;

  autoUpdater.autoDownload = true;
  autoUpdater.autoInstallOnAppQuit = true;
  autoUpdater.logger = { info: (m) => log('[update]', m), warn: (m) => log('[update] warn', m), error: (m) => log('[update] error', m), debug: () => {} };

  autoUpdater.on('checking-for-update', () => emit({ state: 'checking', error: null }));
  autoUpdater.on('update-not-available', () => emit({ state: 'current', checkedAt: Date.now() }));
  autoUpdater.on('update-available', (info) => emit({ state: 'downloading', newVersion: info.version, percent: 0 }));
  autoUpdater.on('download-progress', (p) => emit({ state: 'downloading', percent: Math.round(p.percent) }));
  autoUpdater.on('update-downloaded', (info) => emit({ state: 'ready', newVersion: info.version }));
  autoUpdater.on('error', (e) => emit({ state: 'error', error: (e && e.message ? e.message : String(e)).split('\n')[0] }));

  const check = () => {
    if (!enabled) { emit({ state: 'disabled' }); return; }
    autoUpdater.checkForUpdates().catch(() => { /* reported via 'error' event */ });
  };

  ipcMain.handle('update:status', () => status);
  ipcMain.handle('update:check', () => { check(); return true; });
  ipcMain.handle('update:install', () => {
    if (status.state === 'ready') setImmediate(() => autoUpdater.quitAndInstall(false, true));
    return status.state === 'ready';
  });

  setTimeout(check, 5000);
  setInterval(check, CHECK_EVERY_MS);
}

module.exports = { setupUpdater };
