import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ctx, call, signup, befriend } from './helpers.js';

test('téléchargement de mes données (24.2) : JSON et HTML', async () => {
  const a = (await signup('expa')).data;
  const b = (await signup('expb')).data;
  await befriend(a, b);
  await call('POST', '/posts', { body: 'Ma publication <script>alert(1)</script>' }, a.token);
  const conv = (await call('POST', '/conversations/direct', { userId: b.user.id }, a.token)).data;
  await call('POST', `/conversations/${conv.id}/messages`, { body: 'Salut !' }, b.token);

  const json = (await call('GET', '/me/export', undefined, a.token)).data;
  assert.equal(json.account.username, 'expa');
  assert.equal(json.friends[0].username, 'expb');
  assert.equal(json.posts.length, 1);
  assert.equal(json.conversations[0].messages[0].text, 'Salut !');
  assert.equal(json.privacy.lastSeen, 'friends');

  const res = await fetch(`${ctx.base}/api/me/export?format=html`, { headers: { authorization: `Bearer ${a.token}` } });
  const html = await res.text();
  assert.match(res.headers.get('content-disposition'), /attachment; filename="mic-expa-/);
  assert.match(html, /Mes données MIC — @expa/);
  assert.ok(!html.includes('<script>alert'));
  assert.ok(html.includes('&lt;script&gt;'));
});
