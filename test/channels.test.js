import { test } from 'node:test';
import assert from 'node:assert/strict';
import { call, signup, befriend, socket } from './helpers.js';

test('canaux : création, abonnement, publication, réactions, vues, canal privé', async () => {
  const owner = (await signup('chowner')).data;
  const fan = (await signup('chfan')).data;
  const other = (await signup('chother')).data;
  const priv = (await signup('chpriv', { joinWorld: false })).data;
  assert.equal((await call('POST', '/channels', { name: 'X', handle: 'xx_test' }, priv.token)).data.error, 'world_presence_required');

  const ch = await call('POST', '/channels', { name: 'Mairie de Douala', handle: 'mairie.douala', description: 'Infos officielles' }, owner.token);
  assert.equal(ch.status, 201);
  assert.equal(ch.data.isAdmin, true);
  assert.equal((await call('POST', '/channels', { name: 'Doublon', handle: 'mairie.douala' }, owner.token)).status, 409);

  const found = (await call('GET', '/channels/search?q=mairie', undefined, fan.token)).data;
  assert.equal(found[0].handle, 'mairie.douala');
  await call('POST', `/channels/${ch.data.id}/subscribe`, {}, fan.token);
  const ws = await socket(fan.token);

  // Seuls les admins publient ; les abonnés reçoivent en temps réel.
  assert.equal((await call('POST', `/channels/${ch.data.id}/posts`, { body: 'x' }, fan.token)).status, 403);
  const post = (await call('POST', `/channels/${ch.data.id}/posts`, { body: 'Coupure d’eau demain à Akwa' }, owner.token)).data;
  const pushed = await ws.wait('channel:post');
  assert.equal(pushed.post.body, 'Coupure d’eau demain à Akwa');
  assert.equal(pushed.post.views, undefined); // statistiques réservées aux admins

  const mine = (await call('GET', '/channels', undefined, fan.token)).data;
  assert.equal(mine[0].unread, 1);
  await call('PUT', `/channel-posts/${post.id}/reaction`, { emoji: '🙏' }, fan.token);
  assert.equal((await call('PUT', `/channel-posts/${post.id}/reaction`, { emoji: '🍕' }, fan.token)).status, 400);
  await call('POST', `/channels/${ch.data.id}/read`, { upTo: post.id }, fan.token);
  assert.equal((await call('GET', '/channels', undefined, fan.token)).data[0].unread, 0);
  const forOwner = (await call('GET', `/channels/${ch.data.id}/posts`, undefined, owner.token)).data[0];
  assert.equal(forOwner.views, 1);
  assert.deepEqual(forOwner.reactions, [{ emoji: '🙏', count: 1 }]);
  // Les abonnés ne voient pas la liste des abonnés, seulement le nombre.
  const info = (await call('GET', `/channels/${ch.data.id}`, undefined, fan.token)).data;
  assert.equal(info.subscribers, 1);
  assert.equal(info.admins, undefined);

  // Canal privé : accessible seulement avec le lien d'invitation.
  const pc = (await call('POST', '/channels', { name: 'Équipe', handle: 'equipe.privee', visibility: 'private' }, owner.token)).data;
  assert.equal((await call('GET', `/channels/${pc.id}`, undefined, other.token)).status, 404);
  assert.equal((await call('GET', '/channels/search?q=equipe', undefined, other.token)).data.length, 0);
  assert.equal((await call('POST', `/channels/${pc.id}/subscribe`, {}, other.token)).status, 403);
  assert.equal((await call('GET', `/channels/${pc.id}?code=${pc.inviteCode}`, undefined, other.token)).status, 200);
  assert.equal((await call('POST', `/channels/${pc.id}/subscribe`, { code: pc.inviteCode }, other.token)).data.subscribed, true);
  ws.close();
});

test('listes de diffusion : envoi individuel, réponses privées', async () => {
  const a = (await signup('blA')).data;
  const b = (await signup('blB')).data;
  const c = (await signup('blC')).data;
  const stranger = (await signup('blD')).data;
  await befriend(a, b);
  await befriend(a, c);
  assert.equal((await call('POST', '/broadcasts', { name: 'Famille', memberIds: [stranger.user.id] }, a.token)).data.error, 'not_friend');
  const list = (await call('POST', '/broadcasts', { name: 'Famille', memberIds: [b.user.id, c.user.id] }, a.token)).data;
  assert.equal(list.members.length, 2);
  const sent = (await call('POST', `/broadcasts/${list.id}/send`, { body: 'Réunion dimanche à 15 h' }, a.token)).data;
  assert.equal(sent.delivered, 2);
  // Chacun le reçoit dans sa discussion privée, sans voir les autres destinataires.
  for (const u of [b, c]) {
    const convs = (await call('GET', '/conversations', undefined, u.token)).data;
    const direct = convs.find((x) => x.type === 'direct' && x.peer.id === a.user.id);
    assert.equal(direct.lastMessage.body, 'Réunion dimanche à 15 h');
    assert.equal(direct.memberCount, 2);
  }
  assert.equal((await call('GET', '/broadcasts', undefined, a.token)).data[0].sent.length, 1);
  assert.equal((await call('GET', '/broadcasts', undefined, b.token)).data.length, 0);
});
