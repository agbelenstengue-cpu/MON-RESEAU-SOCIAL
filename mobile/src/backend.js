// MIC sur Android : le serveur MIC (dossier server/, le même code que sur PC)
// tourne dans l'application. Les appels /api et la connexion temps réel /ws de
// l'interface lui sont remis directement, sans réseau ; la base SQLite (sql.js)
// et les médias sont enregistrés sur le téléphone.
import initSqlJs from 'sql.js/dist/sql-wasm-browser.js';
import sqlWasm from 'sql.js/dist/sql-wasm-browser.wasm';
import { Buffer } from 'buffer';
import { configureSqlite } from './shims/sqlite.js';
import { openLocalSocket } from './shims/ws.js';
import { mediaStore } from './media-store.js';
import { installDownloads } from './downloads.js';
import { createServer } from '../../server/app.js';
import { seedDemo } from '../../server/demo.js';

const JSON_LIMIT = 16 * 1024 * 1024;
const VIDEO_LIMIT = 50 * 1024 * 1024;

// ---------- Stockage de la base (IndexedDB) ----------
const idb = (() => {
  let dbp = null;
  const open = () =>
    (dbp ||= new Promise((resolve, reject) => {
      const r = indexedDB.open('mic', 1);
      r.onupgradeneeded = () => r.result.createObjectStore('files');
      r.onsuccess = () => resolve(r.result);
      r.onerror = () => reject(r.error);
    }));
  const run = (mode, fn) =>
    open().then(
      (db) =>
        new Promise((resolve, reject) => {
          const t = db.transaction('files', mode);
          const req = fn(t.objectStore('files'));
          t.oncomplete = () => resolve(req.result);
          t.onerror = () => reject(t.error);
        })
    );
  return {
    get: (key) => run('readonly', (s) => s.get(key)),
    set: (key, value) => run('readwrite', (s) => s.put(value, key)),
  };
})();

// ---------- Démarrage du serveur local ----------
let server = null;
let saveTimer = null;
let saving = Promise.resolve();

function saveNow() {
  clearTimeout(saveTimer);
  saveTimer = null;
  if (!server) return saving;
  const bytes = server.db.serialize();
  saving = saving.then(() => idb.set('mic.db', bytes)).catch((err) => console.error('[MIC] enregistrement', err));
  return saving;
}
const scheduleSave = () => {
  if (!saveTimer) saveTimer = setTimeout(saveNow, 300);
};

async function waitForServiceWorker() {
  if (!('serviceWorker' in navigator)) return;
  try {
    await navigator.serviceWorker.register('/sw.js');
    if (navigator.serviceWorker.controller) return;
    await Promise.race([
      new Promise((r) => navigator.serviceWorker.addEventListener('controllerchange', r, { once: true })),
      new Promise((r) => setTimeout(r, 4000)),
    ]);
  } catch (err) {
    console.error('[MIC] service worker', err);
  }
}

const ready = (async () => {
  navigator.storage?.persist?.().catch(() => {});
  const [SQL, bytes] = await Promise.all([initSqlJs({ wasmBinary: sqlWasm }), idb.get('mic.db').catch(() => null), waitForServiceWorker()]);
  configureSqlite({ sql: SQL, bytes, onChange: scheduleSave });
  server = createServer({ dbFile: ':memory:', uploadsDir: '/uploads', devOtp: true });
  // Premier lancement : comptes de démonstration, comme sur PC.
  if (!bytes) seedDemo(server.db);
  await saveNow();
  return server;
})();
ready.catch((err) => console.error('[MIC] démarrage', err));

addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'hidden' && saveTimer) saveNow();
});
addEventListener('pagehide', () => saveTimer && saveNow());

// ---------- fetch('/api/…') → serveur local ----------
const json = (status, data) => new Response(JSON.stringify(data), { status, headers: { 'content-type': 'application/json' } });
const nativeFetch = window.fetch.bind(window);

async function readBody(input, init, headers) {
  const raw = init.body !== undefined ? init.body : input instanceof Request && !['GET', 'HEAD'].includes(input.method) ? await input.blob() : undefined;
  if (raw == null) return { body: {} };
  const type = (headers['content-type'] || '').toLowerCase();
  if (type.startsWith('video/')) {
    const blob = raw instanceof Blob ? raw : new Blob([raw]);
    if (blob.size > VIDEO_LIMIT) return { error: json(413, { error: 'media_too_large' }) };
    return { body: Buffer.from(await blob.arrayBuffer()) };
  }
  const text = typeof raw === 'string' ? raw : await new Response(raw).text();
  if (text.length > JSON_LIMIT) return { error: json(413, { error: 'media_too_large' }) };
  if (!text) return { body: {} };
  if (!type.includes('json')) return { body: {} };
  try {
    return { body: JSON.parse(text) };
  } catch {
    return { error: json(400, { error: 'bad_json' }) };
  }
}

window.fetch = async function micFetch(input, init = {}) {
  const url = new URL(input instanceof Request ? input.url : String(input), location.href);
  if (url.origin !== location.origin || !url.pathname.startsWith('/api/')) return nativeFetch(input, init);
  const srv = await ready;
  const method = (init.method || (input instanceof Request ? input.method : 'GET')).toUpperCase();
  const headers = Object.fromEntries(new Headers(init.headers || (input instanceof Request ? input.headers : undefined)));
  const { body, error } = await readBody(input, init, headers);
  if (error) return error;
  const out = await srv.app.dispatch({ method, url: url.pathname + url.search, headers, body });
  // Écriture enregistrée sur le téléphone avant que l'interface ne la voie.
  await Promise.all([mediaStore.flush(), saveTimer ? saveNow() : saving]);
  return new Response(out.status === 204 ? null : out.body, { status: out.status, headers: out.headers });
};

// ---------- WebSocket('/ws') → hub temps réel local ----------
const NativeWebSocket = window.WebSocket;

class LocalWebSocket extends EventTarget {
  static CONNECTING = 0;
  static OPEN = 1;
  static CLOSING = 2;
  static CLOSED = 3;

  constructor(url, protocols) {
    const u = new URL(url, location.href);
    if (u.host !== location.host || u.pathname !== '/ws') return new NativeWebSocket(url, protocols);
    super();
    this.url = u.href;
    this.readyState = 0;
    this.onopen = this.onmessage = this.onclose = this.onerror = null;
    this.server = null;
    ready.then(() => {
      if (this.readyState !== 0) return;
      this.server = openLocalSocket(u.pathname + u.search, {
        deliver: (data) => this.readyState === 1 && this.fire('message', new MessageEvent('message', { data })),
        closed: (code, reason) => this.finish(code, reason),
      });
      this.readyState = 1;
      // Laisser le serveur enregistrer la connexion avant de prévenir l'interface.
      setTimeout(() => this.readyState === 1 && this.fire('open', new Event('open')), 0);
    });
  }

  fire(type, event) {
    this[`on${type}`]?.(event);
    this.dispatchEvent(event);
  }

  finish(code = 1000, reason = '') {
    if (this.readyState === 3) return;
    this.readyState = 3;
    this.fire('close', new CloseEvent('close', { code, reason, wasClean: true }));
  }

  send(data) {
    if (this.readyState !== 1) throw new DOMException('WebSocket is not open', 'InvalidStateError');
    const text = String(data);
    setTimeout(() => this.server?.emit('message', text), 0);
  }

  close(code = 1000, reason = '') {
    if (this.readyState >= 2) return;
    const srv = this.server;
    this.readyState = 2;
    setTimeout(() => {
      if (srv && srv.readyState === 1) {
        srv.readyState = 3;
        srv.emit('close', code, reason);
      }
      this.finish(code, reason);
    }, 0);
  }
}
window.WebSocket = LocalWebSocket;

// ---------- Toujours « en ligne » : le serveur est dans le téléphone ----------
try {
  Object.defineProperty(Navigator.prototype, 'onLine', { configurable: true, get: () => true });
} catch {
  /* ignore */
}
addEventListener('offline', (e) => e.stopImmediatePropagation(), true);

installDownloads();

window.__micLocal = { ready, save: saveNow };
