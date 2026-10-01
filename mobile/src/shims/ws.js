// « ws » : connexions temps réel à l'intérieur de la page. Le client crée un
// WebSocket factice (backend.js) qui est relié ici à une socket côté serveur.
const servers = [];

class Emitter {
  constructor() {
    this.handlers = {};
  }
  on(event, fn) {
    (this.handlers[event] ||= []).push(fn);
    return this;
  }
  emit(event, ...args) {
    for (const fn of this.handlers[event] || []) fn(...args);
  }
}

export class ServerSocket extends Emitter {
  constructor(peer) {
    super();
    this.peer = peer; // { deliver(text), closed(code, reason) }
    this.readyState = 1;
  }
  send(text) {
    if (this.readyState !== 1) return;
    const data = String(text);
    setTimeout(() => this.peer.deliver(data), 0);
  }
  close(code = 1000, reason = '') {
    if (this.readyState !== 1) return;
    this.readyState = 3;
    setTimeout(() => {
      this.peer.closed(code, reason);
      this.emit('close', code, reason);
    }, 0);
  }
}

export class WebSocketServer extends Emitter {
  constructor({ path = '/ws' } = {}) {
    super();
    this.path = path;
    servers.push(this);
  }
}

// Appelé par le WebSocket factice de la page.
export function openLocalSocket(url, peer) {
  const u = new URL(url, 'http://localhost');
  const wss = servers.find((s) => s.path === u.pathname);
  if (!wss) return null;
  const socket = new ServerSocket(peer);
  setTimeout(() => wss.emit('connection', socket, { url: u.pathname + u.search }), 0);
  return socket;
}

export default { WebSocketServer };
