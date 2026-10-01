// Service worker MIC (26.4) : l'application s'ouvre hors ligne et les discussions
// déjà téléchargées restent lisibles. Rien n'est mis en cache pour les envois.
const VERSION = 'mic-v1';
const SHELL = ['/', '/index.html', '/css/styles.css', '/js/app.js', '/favicon.svg', '/manifest.webmanifest'];
// Lectures d'API utiles hors ligne : réseau d'abord, cache en secours.
const OFFLINE_API = [/^\/api\/me$/, /^\/api\/conversations(\/\d+(\/messages)?)?$/, /^\/api\/friends$/, /^\/api\/stories$/, /^\/api\/channels$/, /^\/api\/calls$/];

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(VERSION).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== VERSION).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

// À la déconnexion, les données en cache de la personne sont effacées.
self.addEventListener('message', (event) => {
  if (event.data === 'clear-user-data') {
    event.waitUntil(
      caches.open(VERSION).then(async (c) => {
        for (const req of await c.keys()) if (new URL(req.url).pathname.startsWith('/api/')) await c.delete(req);
      })
    );
  }
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== location.origin || url.pathname === '/ws') return;

  if (url.pathname.startsWith('/api/')) {
    if (!OFFLINE_API.some((re) => re.test(url.pathname))) return;
    event.respondWith(
      fetch(req)
        .then((res) => {
          if (res.ok) caches.open(VERSION).then((c) => c.put(req, res.clone()));
          return res;
        })
        .catch(() => caches.match(req).then((hit) => hit || new Response(JSON.stringify({ error: 'network' }), { status: 503, headers: { 'content-type': 'application/json' } })))
    );
    return;
  }

  // Médias : jamais mis en cache (vue unique, économie d'espace) — réseau direct.
  if (url.pathname.startsWith('/uploads/')) return;

  // Application : servie du cache et mise à jour en arrière-plan.
  if (req.mode === 'navigate') {
    event.respondWith(fetch(req).catch(() => caches.match('/index.html')));
    return;
  }
  event.respondWith(
    caches.match(req).then((hit) => {
      const network = fetch(req)
        .then((res) => {
          if (res.ok) caches.open(VERSION).then((c) => c.put(req, res.clone()));
          return res;
        })
        .catch(() => hit);
      return hit || network;
    })
  );
});
