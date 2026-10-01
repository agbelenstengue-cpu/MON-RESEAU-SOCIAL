// node:http : pas de port réseau, l'application Express est appelée directement.
export function createServer(app) {
  return { app, on() {}, listen() {}, close() {} };
}
export default { createServer };
