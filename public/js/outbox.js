// File d'envoi hors ligne (26.4) : les messages texte écrits sans réseau partent
// automatiquement au retour de la connexion (icône horloge en attendant).
import { post, emit, on } from './api.js';

const KEY = 'mic.outbox';
let flushing = false;

function read() {
  try {
    return JSON.parse(localStorage.getItem(KEY) || '[]');
  } catch {
    return [];
  }
}
function write(items) {
  try {
    localStorage.setItem(KEY, JSON.stringify(items));
  } catch {
    /* stockage plein ou indisponible */
  }
  emit('outbox', items);
}

export function pending(convId) {
  return read().filter((x) => x.convId === convId);
}

export function enqueue(convId, body, replyTo) {
  const item = { id: `tmp-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`, convId, body, replyTo: replyTo ?? null, createdAt: Date.now() };
  write([...read(), item]);
  return item;
}

export function clearOutbox() {
  write([]);
}

export async function flush() {
  if (flushing || !navigator.onLine) return;
  flushing = true;
  try {
    for (const item of read()) {
      try {
        await post(`/conversations/${item.convId}/messages`, { body: item.body, replyTo: item.replyTo });
        write(read().filter((x) => x.id !== item.id));
      } catch (err) {
        if (err.code === 'network') break; // toujours hors ligne : on réessaiera
        write(read().filter((x) => x.id !== item.id)); // refusé par le serveur : abandon
        emit('outbox:failed', { item, error: err.code });
      }
    }
  } finally {
    flushing = false;
  }
}

window.addEventListener('online', flush);
on('online', (ok) => ok && flush());
