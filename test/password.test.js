// Serveur en ligne (MIC_AUTH=password) : inscription et connexion par numéro + mot de passe.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createServer } from '../server/app.js';

let server;
let base;
let tmp;

before(async () => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'mic-pw-'));
  ({ server } = createServer({ dbFile: ':memory:', uploadsDir: path.join(tmp, 'uploads'), devOtp: false, authMode: 'password' }));
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  base = `http://127.0.0.1:${server.address().port}`;
});

after(() => {
  server.closeAllConnections();
  server.close();
  fs.rmSync(tmp, { recursive: true, force: true });
});

async function call(method, url, body, token) {
  const res = await fetch(base + '/api' + url, {
    method,
    headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  return { status: res.status, data: await res.json() };
}

test('inscription, connexion et changement de mot de passe', async () => {
  const phone = '+237699000111';
  let r = await call('POST', '/auth/request-otp', { phone });
  assert.deepEqual([r.status, r.data.mode, r.data.exists, r.data.devCode], [200, 'password', false, undefined]);
  // Pas de code OTP en mode mot de passe.
  r = await call('POST', '/auth/verify', { phone, code: '000000' });
  assert.equal(r.status, 404);

  r = await call('POST', '/auth/password', { phone, password: 'court', create: true });
  assert.equal(r.data.error, 'password_too_short');
  r = await call('POST', '/auth/password', { phone, password: 'motdepasse-solide', create: true });
  assert.equal(r.data.needsSignup, true);
  r = await call('POST', '/auth/signup', { ticket: r.data.ticket, birthDate: '1990-01-01', displayName: 'Awa', username: 'awa', joinWorld: true });
  assert.equal(r.status, 201);
  assert.equal(r.data.user.hasPassword, true);
  assert.equal(JSON.stringify(r.data).includes('scrypt'), false);
  const first = r.data.token;

  r = await call('POST', '/auth/request-otp', { phone });
  assert.equal(r.data.exists, true);
  r = await call('POST', '/auth/password', { phone, password: 'motdepasse-solide', create: true });
  assert.equal(r.data.error, 'phone_taken');
  r = await call('POST', '/auth/password', { phone, password: 'mauvais-mot' });
  assert.equal(r.data.error, 'wrong_password');
  r = await call('POST', '/auth/password', { phone: '+237699000999', password: 'peu-importe' });
  assert.equal(r.data.error, 'wrong_password');
  r = await call('POST', '/auth/password', { phone, password: 'motdepasse-solide' });
  assert.equal(r.status, 200);
  const second = r.data.token;
  assert.notEqual(first, second);

  // Changement : les autres sessions sont fermées, l'ancien mot de passe ne marche plus.
  r = await call('POST', '/me/password', { current: 'faux', next: 'nouveau-secret' }, second);
  assert.equal(r.data.error, 'wrong_password');
  r = await call('POST', '/me/password', { current: 'motdepasse-solide', next: 'nouveau-secret' }, second);
  assert.equal(r.status, 200);
  assert.equal((await call('GET', '/me', undefined, first)).status, 401);
  assert.equal((await call('GET', '/me', undefined, second)).status, 200);
  assert.equal((await call('POST', '/auth/password', { phone, password: 'motdepasse-solide' })).data.error, 'wrong_password');
  assert.equal((await call('POST', '/auth/password', { phone, password: 'nouveau-secret' })).status, 200);
});

test('trop d’essais : blocage temporaire', async () => {
  const phone = '+237699000222';
  let r = await call('POST', '/auth/password', { phone, password: 'secret-123', create: true });
  await call('POST', '/auth/signup', { ticket: r.data.ticket, birthDate: '1990-01-01', displayName: 'Bob', username: 'bobby', joinWorld: false });
  for (let i = 0; i < 5; i++) assert.equal((await call('POST', '/auth/password', { phone, password: 'faux-' + i })).data.error, 'wrong_password');
  r = await call('POST', '/auth/password', { phone, password: 'secret-123' });
  assert.equal(r.status, 429);
  assert.equal(r.data.error, 'too_many_logins');
});

test('santé du serveur', async () => {
  const r = await call('GET', '/health');
  assert.deepEqual(r.data, { ok: true });
});
