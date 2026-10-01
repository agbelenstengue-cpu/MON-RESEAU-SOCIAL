// Service worker de l'application Android : sert les fichiers téléversés
// (/uploads/…) depuis le stockage de l'application, avec les plages d'octets
// demandées par les lecteurs audio et vidéo.
const CACHE = 'mic-media';

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

async function serveMedia(request, pathname) {
  const cache = await caches.open(CACHE);
  const hit = await cache.match(pathname);
  if (!hit) return new Response('', { status: 404 });
  const type = hit.headers.get('content-type') || 'application/octet-stream';
  const range = /^bytes=(\d*)-(\d*)$/.exec(request.headers.get('range') || '');
  const blob = await hit.blob();
  if (!range) {
    return new Response(blob, { headers: { 'content-type': type, 'content-length': String(blob.size), 'accept-ranges': 'bytes' } });
  }
  const size = blob.size;
  let start = range[1] === '' ? size - Number(range[2]) : Number(range[1]);
  let end = range[1] !== '' && range[2] !== '' ? Number(range[2]) : size - 1;
  start = Math.max(0, start);
  end = Math.min(end, size - 1);
  if (start > end) return new Response('', { status: 416, headers: { 'content-range': `bytes */${size}` } });
  return new Response(blob.slice(start, end + 1, type), {
    status: 206,
    headers: { 'content-type': type, 'content-length': String(end - start + 1), 'content-range': `bytes ${start}-${end}/${size}`, 'accept-ranges': 'bytes' },
  });
}

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  if (url.origin === location.origin && event.request.method === 'GET' && url.pathname.startsWith('/uploads/')) {
    event.respondWith(serveMedia(event.request, url.pathname));
  }
});
