// Accès à l'API et connexion temps réel.

const listeners = new Map(); // type -> Set<fn>
let token = null;
let ws = null;
let retry = 0;
let wsTimer = null;

try {
  token = localStorage.getItem('mic.token');
} catch {
  /* stockage indisponible : session limitée à l'onglet */
}

export const store = { me: null };

export class ApiError extends Error {
  constructor(code, status) {
    super(code);
    this.code = code;
    this.status = status;
  }
}

export function getToken() {
  return token;
}

export function setToken(next) {
  token = next;
  try {
    if (next) localStorage.setItem('mic.token', next);
    else localStorage.removeItem('mic.token');
  } catch {
    /* ignore */
  }
}

export async function api(method, url, body) {
  let res;
  try {
    res = await fetch('/api' + url, {
      method,
      headers: {
        ...(body !== undefined ? { 'content-type': 'application/json' } : {}),
        ...(token ? { authorization: `Bearer ${token}` } : {}),
      },
      body: body !== undefined ? JSON.stringify(body) : undefined,
    });
  } catch {
    throw new ApiError('network', 0);
  }
  let data = null;
  try {
    data = await res.json();
  } catch {
    /* réponse vide */
  }
  if (!res.ok) {
    if (res.status === 401 && token) emit('logout', {});
    throw new ApiError(data?.error || 'generic', res.status);
  }
  return data;
}

export const get = (url) => api('GET', url);
export const post = (url, body = {}) => api('POST', url, body);
export const patch = (url, body = {}) => api('PATCH', url, body);
export const put = (url, body = {}) => api('PUT', url, body);
export const del = (url, body) => api('DELETE', url, body);

// --- Événements ---
export function on(type, fn) {
  if (!listeners.has(type)) listeners.set(type, new Set());
  listeners.get(type).add(fn);
  return () => listeners.get(type)?.delete(fn);
}

export function emit(type, data) {
  listeners.get(type)?.forEach((fn) => fn(data));
  listeners.get('*')?.forEach((fn) => fn({ type, data }));
}

// --- WebSocket ---
export function connect() {
  if (!token || (ws && ws.readyState <= 1)) return;
  const proto = location.protocol === 'https:' ? 'wss' : 'ws';
  ws = new WebSocket(`${proto}://${location.host}/ws?token=${encodeURIComponent(token)}`);
  ws.onopen = () => {
    retry = 0;
    emit('online', true);
  };
  ws.onmessage = (e) => {
    try {
      const { type, data } = JSON.parse(e.data);
      emit(type, data);
    } catch {
      /* message illisible ignoré */
    }
  };
  ws.onclose = (e) => {
    ws = null;
    emit('online', false);
    if (e.code === 4001 || !token) return;
    clearTimeout(wsTimer);
    wsTimer = setTimeout(connect, Math.min(1000 * 2 ** retry++, 15000));
  };
}

export function disconnect() {
  clearTimeout(wsTimer);
  if (ws) {
    const s = ws;
    ws = null;
    s.onclose = null;
    s.close();
  }
}

export function sendWs(type, data) {
  if (ws?.readyState === 1) ws.send(JSON.stringify({ type, ...data }));
}

// Lecture d'un fichier image en data URL, redimensionnée pour économiser
// les données (26.3).
export function readImage(file, max = 1600) {
  return new Promise((resolve, reject) => {
    if (!file || !file.type.startsWith('image/')) return reject(new ApiError('invalid_media'));
    const img = new Image();
    const url = URL.createObjectURL(file);
    img.onload = () => {
      const scale = Math.min(1, max / Math.max(img.width, img.height));
      const c = document.createElement('canvas');
      c.width = Math.round(img.width * scale);
      c.height = Math.round(img.height * scale);
      c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
      URL.revokeObjectURL(url);
      resolve(c.toDataURL('image/jpeg', 0.86));
    };
    img.onerror = () => reject(new ApiError('invalid_media'));
    img.src = url;
  });
}
