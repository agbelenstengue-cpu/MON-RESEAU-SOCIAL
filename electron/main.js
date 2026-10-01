// Application de bureau MIC (Windows, macOS, Linux) : le serveur MIC tourne dans
// le processus principal d'Electron, sur cet ordinateur uniquement (127.0.0.1),
// et l'interface s'ouvre dans une fenêtre dédiée. Sur demande (menu « Partage »),
// il est aussi ouvert aux navigateurs des appareils du réseau local.
import { app, BrowserWindow, Menu, shell, dialog } from 'electron';
import fs from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';

const HOST = '127.0.0.1';
// Port fixe : l'origine reste la même d'un lancement à l'autre, donc la session
// (stockée par le navigateur intégré) est conservée.
const PREFERRED_PORT = 37237;
const LAN_PORT = 37238;

// Adresse du serveur MIC en ligne (mic.config.json). Vide : MIC tourne sur ce PC.
const CONFIG = (() => {
  try {
    return JSON.parse(fs.readFileSync(path.join(import.meta.dirname, '..', 'mic.config.json'), 'utf8'));
  } catch {
    return {};
  }
})();
const ONLINE = /^https?:\/\//.test(CONFIG.server || '') ? new URL(CONFIG.server).origin : null;

if (!app.requestSingleInstanceLock()) app.quit();

let win = null;
let baseUrl = null;
let httpServer = null;
let lanServer = null;

// ---------- Réglages de l'application de bureau ----------
const settingsFile = () => path.join(app.getPath('userData'), 'settings.json');
function readSettings() {
  try {
    return JSON.parse(fs.readFileSync(settingsFile(), 'utf8'));
  } catch {
    return {};
  }
}
function writeSettings(patch) {
  fs.writeFileSync(settingsFile(), JSON.stringify({ ...readSettings(), ...patch }, null, 2));
}

// ---------- Partage sur le réseau local (navigateurs des autres appareils) ----------
function lanAddresses() {
  const out = [];
  for (const list of Object.values(os.networkInterfaces())) {
    for (const a of list ?? []) {
      if (a.family === 'IPv4' && !a.internal) out.push(`http://${a.address}:${LAN_PORT}`);
    }
  }
  return out;
}

// Second point d'écoute sur toutes les interfaces : les connexions sont remises
// au serveur MIC (HTTP et WebSocket), qui reste seul à les traiter.
function startLan() {
  if (lanServer) return Promise.resolve();
  return new Promise((resolve, reject) => {
    const srv = net.createServer((socket) => httpServer.emit('connection', socket));
    srv.once('error', reject);
    srv.listen(LAN_PORT, '0.0.0.0', () => {
      srv.off('error', reject);
      lanServer = srv;
      resolve();
    });
  });
}
function stopLan() {
  lanServer?.close();
  lanServer = null;
}

function updateTitle() {
  if (!win || ONLINE) return;
  const [first] = lanAddresses();
  win.setTitle(lanServer && first ? `MIC — partagé : ${first}` : 'MIC');
}

function showLanAddress() {
  const addresses = lanAddresses();
  if (!lanServer) {
    dialog.showMessageBox(win, {
      type: 'info',
      title: 'MIC',
      message: 'Le partage sur le réseau local est désactivé.',
      detail: 'Activez « Partager sur le réseau local » dans le menu Partage, puis ouvrez l’adresse affichée dans le navigateur d’un téléphone ou d’un autre ordinateur.',
    });
    return;
  }
  dialog.showMessageBox(win, {
    type: 'info',
    title: 'MIC',
    message: addresses.length ? 'Adresse à ouvrir dans le navigateur des autres appareils :' : 'Aucun réseau détecté.',
    detail: addresses.length
      ? `${addresses.join('\n')}\n\nLes appareils doivent être connectés au même réseau Wi-Fi que ce PC. Si Windows demande l’autorisation du pare-feu, acceptez pour les réseaux privés.\n\nTout le monde partage alors le MIC de ce PC : messages en temps réel entre les appareils. Dans un navigateur, le micro et la caméra ne sont autorisés qu’en https : les vocaux, les appels et les Clips filmés restent réservés à ce PC.`
      : 'Connectez ce PC à un réseau Wi-Fi ou filaire.',
  });
}

async function setLan(enabled) {
  if (enabled) {
    const { response } = await dialog.showMessageBox(win, {
      type: 'warning',
      title: 'MIC',
      buttons: ['Partager', 'Annuler'],
      defaultId: 0,
      cancelId: 1,
      message: 'Partager MIC sur le réseau local ?',
      detail: 'Les appareils du même réseau pourront ouvrir MIC sur ce PC. Comme aucun SMS n’est envoyé dans ce prototype, le code de connexion s’affiche sur l’appareil qui le demande : ne partagez que sur un réseau de confiance (votre Wi-Fi à la maison), jamais sur un Wi-Fi public.',
    });
    if (response !== 0) return buildMenu();
    try {
      await startLan();
    } catch (err) {
      dialog.showErrorBox('MIC', `Impossible d’ouvrir le port ${LAN_PORT}.\n\n${err.message}`);
      return buildMenu();
    }
    writeSettings({ lan: true });
    buildMenu();
    updateTitle();
    showLanAddress();
  } else {
    stopLan();
    writeSettings({ lan: false });
    buildMenu();
    updateTitle();
  }
}

function buildMenu() {
  Menu.setApplicationMenu(
    Menu.buildFromTemplate([
      ...(ONLINE ? [] : [{
        label: 'Partage',
        submenu: [
          { label: 'Partager sur le réseau local', type: 'checkbox', checked: !!lanServer, click: (item) => setLan(item.checked) },
          { label: 'Adresse à ouvrir sur les autres appareils…', click: showLanAddress },
        ],
      }]),
      {
        label: 'Affichage',
        submenu: [
          { role: 'reload', label: 'Recharger' },
          { type: 'separator' },
          { role: 'resetZoom', label: 'Taille réelle' },
          { role: 'zoomIn', label: 'Zoom avant' },
          { role: 'zoomOut', label: 'Zoom arrière' },
          { type: 'separator' },
          { role: 'togglefullscreen', label: 'Plein écran' },
        ],
      },
    ])
  );
}

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
  if (!fs.existsSync(dbFile)) {
    const { openDatabase } = await import('../server/db.js');
    const { seedDemo } = await import('../server/demo.js');
    const db = openDatabase(dbFile);
    seedDemo(db);
    db.close();
  }

  const { createServer } = await import('../server/app.js');
  const { server } = createServer({ dbFile, uploadsDir: path.join(dataDir, 'uploads'), devOtp: true });
  httpServer = server;
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

  // Le titre de la fenêtre affiche l'adresse de partage quand il est actif.
  win.on('page-title-updated', (event) => event.preventDefault());
  win.webContents.on('did-finish-load', updateTitle);

  // En ligne : sans connexion Internet, proposer de réessayer.
  win.webContents.on('did-fail-load', (event, code, description, url, isMainFrame) => {
    if (!isMainFrame || code === -3) return;
    dialog
      .showMessageBox(win, {
        type: 'warning',
        title: 'MIC',
        buttons: ['Réessayer', 'Quitter'],
        defaultId: 0,
        message: 'MIC ne parvient pas à joindre le serveur.',
        detail: 'Vérifiez votre connexion Internet, puis réessayez.',
      })
      .then(({ response }) => (response === 0 ? win?.loadURL(baseUrl) : app.quit()));
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
  if (ONLINE) baseUrl = ONLINE;
  else {
    try {
      baseUrl = await startServer();
    } catch (err) {
      dialog.showErrorBox('MIC', `MIC n'a pas pu démarrer.\n\n${err?.stack || err}`);
      app.quit();
      return;
    }
    if (readSettings().lan) await startLan().catch(() => {});
  }
  buildMenu();
  createWindow();
});
