import { test } from 'node:test';
import assert from 'node:assert/strict';
import { PIXEL, call, signup, befriend, socket } from './helpers.js';

test('réglages de confidentialité : valeurs par défaut, modification, mineurs', async () => {
  const a = (await signup('privA')).data;
  const r = (await call('GET', '/me/privacy', undefined, a.token)).data;
  assert.equal(r.settings.lastSeen, 'friends');
  assert.equal(r.settings.whoCanCall, 'friends');
  assert.equal(r.settings.readReceipts, true);
  const upd = await call('PATCH', '/me/privacy', { lastSeen: 'nobody', readReceipts: false }, a.token);
  assert.equal(upd.data.settings.lastSeen, 'nobody');
  assert.equal((await call('PATCH', '/me/privacy', { lastSeen: 'sometimes' }, a.token)).status, 400);
  assert.equal((await call('PATCH', '/me/privacy', { unknown: true }, a.token)).status, 400);

  const teen = (await signup('privteen', { birthDate: `${new Date().getFullYear() - 15}-01-01` })).data;
  const tp = (await call('GET', '/me/privacy', undefined, teen.token)).data;
  assert.equal(tp.settings.whoCanMessage, 'friends');
  assert.deepEqual(tp.locked.sort(), ['whoCanCall', 'whoCanMessage']);
  assert.equal((await call('PATCH', '/me/privacy', { whoCanMessage: 'everyone' }, teen.token)).data.error, 'locked_for_minors');
});

test('confidentialité appliquée : photo, vu à, messages, accusés de lecture', async () => {
  const a = (await signup('privB')).data;
  const friend = (await signup('privC')).data;
  const stranger = (await signup('privD')).data;
  await befriend(a, friend);
  await call('PATCH', '/me', { avatar: PIXEL }, a.token);

  // Par défaut : photo privée et « vu à » pour les amis seulement.
  assert.ok((await call('GET', '/users/privb', undefined, friend.token)).data.avatar);
  assert.equal((await call('GET', '/users/privb', undefined, stranger.token)).data.avatar, null);
  assert.ok('lastSeen' in (await call('GET', '/users/privb', undefined, friend.token)).data);
  await call('PATCH', '/me/privacy', { lastSeen: 'nobody', profilePhoto: 'everyone' }, a.token);
  assert.ok(!('lastSeen' in (await call('GET', '/users/privb', undefined, friend.token)).data));
  assert.ok((await call('GET', '/users/privb', undefined, stranger.token)).data.avatar);

  // « Who can message me : friends » → un inconnu ne peut pas ouvrir de discussion.
  await call('PATCH', '/me/privacy', { whoCanMessage: 'friends' }, a.token);
  assert.equal((await call('POST', '/conversations/direct', { userId: a.user.id }, stranger.token)).data.error, 'cannot_message');

  // Accusés de lecture coupés : les messages de l'ami ne passent jamais en « lu ».
  await call('PATCH', '/me/privacy', { readReceipts: false }, a.token);
  const conv = (await call('POST', '/conversations/direct', { userId: a.user.id }, friend.token)).data;
  const m = (await call('POST', `/conversations/${conv.id}/messages`, { body: 'coucou' }, friend.token)).data;
  await call('POST', `/conversations/${conv.id}/read`, { upTo: m.id }, a.token);
  const seen = (await call('GET', `/conversations/${conv.id}/messages`, undefined, friend.token)).data.at(-1);
  assert.notEqual(seen.status, 'read');

  // « Who can call me : nobody ».
  await call('PATCH', '/me/privacy', { whoCanCall: 'nobody' }, a.token);
  const ws = await socket(friend.token);
  ws.send('call:start', { conversationId: conv.id, callType: 'audio' });
  assert.equal((await ws.wait('call:error')).error, 'cannot_call');
  ws.close();
});

test('messages éphémères : minuteur, message système, expiration', async () => {
  const a = (await signup('ephA')).data;
  const b = (await signup('ephB')).data;
  await befriend(a, b);
  const conv = (await call('POST', '/conversations/direct', { userId: b.user.id }, a.token)).data;
  assert.equal(conv.messageTimer, 0);
  assert.equal((await call('PUT', `/conversations/${conv.id}/timer`, { timer: 1234 }, a.token)).status, 400);
  const set = await call('PUT', `/conversations/${conv.id}/timer`, { timer: 86400000 }, a.token);
  assert.equal(set.data.messageTimer, 86400000);
  const msgs = (await call('GET', `/conversations/${conv.id}/messages`, undefined, b.token)).data;
  assert.equal(msgs.at(-1).body, 'timer_set');
  assert.equal(msgs.at(-1).meta.timer, 86400000);
  const m = (await call('POST', `/conversations/${conv.id}/messages`, { body: 'éphémère' }, a.token)).data;
  assert.ok(m.expiresAt > Date.now() + 86000000);

  // Minuteur par défaut appliqué aux nouvelles discussions.
  const c = (await signup('ephC')).data;
  await befriend(a, c);
  await call('PATCH', '/me/privacy', { defaultTimer: 604800000 }, a.token);
  const conv2 = (await call('POST', '/conversations/direct', { userId: c.user.id }, a.token)).data;
  assert.equal(conv2.messageTimer, 604800000);
});

test('vue unique : une seule ouverture, puis plus de fichier', async () => {
  const a = (await signup('voA')).data;
  const b = (await signup('voB')).data;
  await befriend(a, b);
  const conv = (await call('POST', '/conversations/direct', { userId: b.user.id }, a.token)).data;
  const sent = (await call('POST', `/conversations/${conv.id}/messages`, { kind: 'image', media: PIXEL, viewOnce: true }, a.token)).data;
  assert.equal(sent.viewOnce, true);
  assert.equal(sent.media, null);
  assert.equal(sent.opened, false);
  const listed = (await call('GET', `/conversations/${conv.id}/messages`, undefined, b.token)).data.at(-1);
  assert.equal(listed.media, null);
  assert.equal((await call('POST', `/messages/${sent.id}/open`, undefined, a.token)).status, 403);
  const opened = await call('POST', `/messages/${sent.id}/open`, undefined, b.token);
  assert.match(opened.data.media, /^\/uploads\//);
  assert.equal((await call('POST', `/messages/${sent.id}/open`, undefined, b.token)).status, 410);
  const forSender = (await call('GET', `/conversations/${conv.id}/messages`, undefined, a.token)).data.at(-1);
  assert.equal(forSender.opened, true);
  // Un texte ne peut pas être en vue unique.
  const txt = (await call('POST', `/conversations/${conv.id}/messages`, { body: 'x', viewOnce: true }, a.token)).data;
  assert.equal(txt.viewOnce, undefined);
});
