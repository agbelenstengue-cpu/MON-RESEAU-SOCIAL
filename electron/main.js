// Application de bureau MIC (Windows, macOS, Linux) : le serveur MIC tourne dans
// le processus principal d'Electron, sur cet ordinateur uniquement (127.0.0.1),
// et l'interface s'ouvre dans une fenêtre dédiée.
import { app, BrowserWindow, Menu, shell, dialog } from 'electron';
import fs from 'node:fs';
import path from 'node:path';

const HOST = '127.0.0.1';
// Port fixe : l'origine reste la même d'un lancement à l'autre, donc la session
// (stockée par le navigateur intégré) est conservée.
const PREFERRED_PORT = 37237;

if (!app.requestSingleInstanceLock()) app.quit();

let win = null;
let baseUrl = null;

function listen(server, port) {
  return new Promise((resolve, reject) => {
    const onError = (err) => {
      server.off('listening', onListening);
      reject(err);
    };
    const onListening = () => {
      server.off('error', onError);
      resolve(server.address().port);
    };
    server.once('error', onError);
    server.once('listening', onListening);
    server.listen(port, HOST);
  });
}

async function startServer() {
  const dataDir = path.join(app.getPath('userData'), 'data');
  fs.mkdirSync(dataDir, { recursive: true });
  const dbFile = path.join(dataDir, 'mic.db');
  process.env.MIC_DB = dbFile;

  // Premier lancement : comptes de démonstration pour découvrir MIC tout de suite.
  if (!fs.existsSync(dbFile)) await import('../server/seed.js');

  const { createServer } = await import('../server/app.js');
  const { server } = createServer({ dbFile, uploadsDir: path.join(dataDir, 'uploads'), devOtp: true });
  let port;
  try {
    port = await listen(server, PREFERRED_PORT);
  } catch (err) {
    if (err.code !== 'EADDRINUSE') throw err;
    port = await listen(server, 0);
  }
  return `http://localhost:${port}`;
}

function createWindow() {
  win = new BrowserWindow({
    width: 1200,
    height: 820,
    minWidth: 360,
    minHeight: 560,
    title: 'MIC',
    backgroundColor: '#1c1410',
    icon: path.join(import.meta.dirname, '..', 'public', 'img', 'icon-512.png'),
    autoHideMenuBar: true,
    webPreferences: { contextIsolation: true, sandbox: true },
  });

  const ses = win.webContents.session;
  const local = (url) => {
    try {
      const u = new URL(url);
      return u.origin === baseUrl;
    } catch {
      return false;
    }
  };
  // Micro et caméra (vocaux, appels, Clips), notifications : autorisés pour MIC seulement.
  const allowed = new Set(['media', 'notifications', 'clipboard-sanitized-write', 'fullscreen']);
  ses.setPermissionRequestHandler((wc, permission, cb, details) => cb(allowed.has(permission) && local(details.requestingUrl)));
  ses.setPermissionCheckHandler((wc, permission, origin) => allowed.has(permission) && local(origin));

  // Les liens externes s'ouvrent dans le navigateur ; les téléchargements MIC restent ici.
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (!local(url)) shell.openExternal(url);
    return { action: 'deny' };
  });
  win.webContents.on('will-navigate', (event, url) => {
    if (!local(url)) {
      event.preventDefault();
      shell.openExternal(url);
    }
  });

  win.loadURL(baseUrl);
  win.on('closed', () => {
    win = null;
  });
}

app.on('second-instance', () => {
  if (!win) return;
  if (win.isMinimized()) win.restore();
  win.focus();
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

app.on('activate', () => {
  if (!win && baseUrl) createWindow();
});

app.whenReady().then(async () => {
  Menu.setApplicationMenu(null);
  try {
    baseUrl = await startServer();
  } catch (err) {
    dialog.showErrorBox('MIC', `MIC n'a pas pu démarrer.\n\n${err?.stack || err}`);
    app.quit();
    return;
  }
  createWindow();
});
