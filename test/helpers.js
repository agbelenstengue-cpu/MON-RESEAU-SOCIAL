// Outils partagés par les tests d'intégration : serveur éphémère, inscription, amitié.
import { before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { WebSocket } from 'ws';
import { createServer } from '../server/app.js';

// Comptes modérateurs des tests (désignés par configuration, comme en production).
process.env.MIC_MODERATORS = 'modone,modtwo';

export const PIXEL = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
export const ctx = { base: '' };
let server;
let tmp;

before(async () => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'mic-test-'));
  ({ server } = createServer({ dbFile: ':memory:', uploadsDir: path.join(tmp, 'uploads'), devOtp: true }));
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  ctx.base = `http://127.0.0.1:${server.address().port}`;
});

const sockets = [];
after(() => {
  sockets.forEach((ws) => ws.terminate());
  server.closeAllConnections();
  server.close();
  fs.rmSync(tmp, { recursive: true, force: true });
});

export async function call(method, url, body, token) {
  const res = await fetch(ctx.base + '/api' + url, {
    method,
    headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const data = await res.json();
  return { status: res.status, data };
}

let phoneSeq = 100000 + Math.floor(Math.random() * 1000) * 100;
export async function signup(username, { birthDate = '1995-04-12', joinWorld = true } = {}) {
  const phone = `+2376${phoneSeq++}00`;
  const otp = await call('POST', '/auth/request-otp', { phone });
  assert.equal(otp.status, 200);
  const v = await call('POST', '/auth/verify', { phone, code: otp.data.devCode });
  assert.equal(v.data.needsSignup, true);
  const s = await call('POST', '/auth/signup', {
    ticket: v.data.ticket, birthDate, displayName: username.toUpperCase(), username, joinWorld,
  });
  return { ...s, phone };
}

export async function befriend(a, b) {
  await call('POST', `/users/${b.user.id}/friend-request`, {}, a.token);
  const r = await call('POST', `/friend-requests/${a.user.id}/accept`, {}, b.token);
  assert.equal(r.data.status, 'friends');
}

// Client WebSocket qui mémorise les événements reçus et permet de les attendre.
export async function socket(token) {
  const ws = new WebSocket(`${ctx.base.replace('http', 'ws')}/ws?token=${token}`);
  sockets.push(ws);
  const events = [];
  const waiters = [];
  ws.on('message', (raw) => {
    const m = JSON.parse(raw.toString());
    const w = waiters.find((x) => x.match(m));
    if (!w) return events.push(m);
    waiters.splice(waiters.indexOf(w), 1);
    w.resolve(m.data);
  });
  await new Promise((r) => ws.once('open', r));
  return {
    events,
    send: (type, data = {}) => ws.send(JSON.stringify({ type, ...data })),
    wait(type, pred = () => true, timeout = 3000) {
      const found = events.find((m) => m.type === type && pred(m.data));
      if (found) {
        events.splice(events.indexOf(found), 1);
        return Promise.resolve(found.data);
      }
      return new Promise((resolve, reject) => {
        const w = { match: (m) => m.type === type && pred(m.data), resolve };
        waiters.push(w);
        setTimeout(() => reject(new Error(`timeout waiting for ${type} (reçus : ${events.map((e) => e.type).join(', ')})`)), timeout);
      });
    },
    close: () => ws.close(),
  };
}
