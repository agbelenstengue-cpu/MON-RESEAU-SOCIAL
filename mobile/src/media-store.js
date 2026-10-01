// Fichiers téléversés (photos, vocaux, vidéos) : Cache Storage de l'application,
// lu par le service worker (sw.js) pour les URL /uploads/…
const CACHE = 'mic-media';
const TYPES = {
  png: 'image/png',
  jpg: 'image/jpeg',
  webp: 'image/webp',
  gif: 'image/gif',
  webm: 'video/webm',
  ogg: 'audio/ogg',
  m4a: 'audio/mp4',
  mp3: 'audio/mpeg',
  wav: 'audio/wav',
  mp4: 'video/mp4',
  mov: 'video/quicktime',
};
const pending = new Set();

function track(promise) {
  const p = promise.catch((err) => console.error('[MIC] média', err)).finally(() => pending.delete(p));
  pending.add(p);
}

export const typeOf = (name) => TYPES[String(name).split('.').pop().toLowerCase()] || 'application/octet-stream';

export const mediaStore = {
  put(name, data) {
    const type = typeOf(name);
    // Les vocaux .webm sont de l'audio : le type exact importe peu, le lecteur détecte le format.
    const blob = new Blob([data], { type });
    track(caches.open(CACHE).then((c) => c.put(`/uploads/${name}`, new Response(blob, { headers: { 'content-type': type, 'content-length': String(blob.size) } }))));
  },
  remove(name) {
    track(caches.open(CACHE).then((c) => c.delete(`/uploads/${name}`)));
  },
  // Attendre que les fichiers soient écrits avant de répondre à l'interface.
  flush: () => Promise.all([...pending]),
};
