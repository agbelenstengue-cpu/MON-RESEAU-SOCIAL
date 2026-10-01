// Temps réel : messages, accusés, « écrit… », présence (8.3, 8.4).
// En production : serveurs de connexions persistantes dédiés (27.1).
import { WebSocketServer } from 'ws';

export function createHub() {
  const sockets = new Map(); // userId -> Set<WebSocket>
  const listeners = { connect: [], disconnect: [], message: [] };

  const hub = {
    isOnline: (userId) => (sockets.get(userId)?.size ?? 0) > 0,
    send(userId, type, data) {
      const set = sockets.get(userId);
      if (!set) return;
      const payload = JSON.stringify({ type, data });
      for (const ws of set) if (ws.readyState === 1) ws.send(payload);
    },
    sendMany(userIds, type, data) {
      for (const id of new Set(userIds)) hub.send(id, type, data);
    },
    on(event, fn) {
      listeners[event].push(fn);
    },

    attach(server, authenticate) {
      const wss = new WebSocketServer({ server, path: '/ws' });
      wss.on('connection', (ws, req) => {
        const url = new URL(req.url, 'http://localhost');
        const user = authenticate(url.searchParams.get('token'));
        if (!user) {
          ws.close(4001, 'unauthorized');
          return;
        }
        const first = !hub.isOnline(user.id);
        if (!sockets.has(user.id)) sockets.set(user.id, new Set());
        sockets.get(user.id).add(ws);
        if (first) listeners.connect.forEach((fn) => fn(user.id));

        ws.on('message', (raw) => {
          let msg;
          try {
            msg = JSON.parse(raw.toString());
          } catch {
            return;
          }
          listeners.message.forEach((fn) => fn(user.id, msg));
        });
        ws.on('close', () => {
          const set = sockets.get(user.id);
          set?.delete(ws);
          if (set && set.size === 0) {
            sockets.delete(user.id);
            listeners.disconnect.forEach((fn) => fn(user.id));
          }
        });
      });
      return wss;
    },
  };
  return hub;
}
