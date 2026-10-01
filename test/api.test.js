import { test } from 'node:test';
import assert from 'node:assert/strict';
import { WebSocket } from 'ws';
import { PIXEL, ctx, call, signup, befriend } from './helpers.js';

test('inscription, connexion et règles du compte', async () => {
  const s = await signup('angele');
  assert.equal(s.status, 201);
  assert.equal(s.data.user.username, 'angele');
  assert.equal(s.data.user.world.enabled, true);

  // Mauvais code puis connexion d'un compte existant.
  const otp = await call('POST', '/auth/request-otp', { phone: s.phone });
  assert.equal((await call('POST', '/auth/verify', { phone: s.phone, code: '000000' === otp.data.devCode ? '111111' : '000000' })).status, 400);
  const otp2 = await call('POST', '/auth/request-otp', { phone: s.phone });
  const login = await call('POST', '/auth/verify', { phone: s.phone, code: otp2.data.devCode });
  assert.ok(login.data.token);

  // Nom d'utilisateur pris → suggestions.
  const u = await call('GET', '/auth/username?u=angele');
  assert.equal(u.data.available, false);
  assert.ok(u.data.suggestions.length > 0);

  // Trop jeune : inscription refusée.
  const phone = '+237699999999';
  const o = await call('POST', '/auth/request-otp', { phone });
  const v = await call('POST', '/auth/verify', { phone, code: o.data.devCode });
  const young = await call('POST', '/auth/signup', { ticket: v.data.ticket, birthDate: '2020-01-01', displayName: 'Kid', username: 'kid01' });
  assert.equal(young.status, 403);
  assert.equal(young.data.error, 'too_young');

  // Mineur : présence World désactivée même s'il la demande.
  const teen = await signup('teen', { birthDate: `${new Date().getFullYear() - 15}-01-01`, joinWorld: true });
  assert.equal(teen.data.user.world.enabled, false);

  assert.equal((await call('POST', '/auth/request-otp', { phone: '12' })).status, 400);
});

test('amis, demandes de message, messagerie et accusés', async () => {
  const a = (await signup('bruno')).data;
  const b = (await signup('chloe')).data;
  const c = (await signup('david')).data;

  // Non-ami → « Message requests ».
  const conv = (await call('POST', '/conversations/direct', { userId: c.user.id }, a.token)).data;
  await call('POST', `/conversations/${conv.id}/messages`, { body: 'Bonjour !' }, a.token);
  const cList = (await call('GET', '/conversations', undefined, c.token)).data;
  assert.equal(cList.find((x) => x.id === conv.id).status, 'request');

  // Amis → discussion normale.
  await befriend(a, b);
  const ab = (await call('POST', '/conversations/direct', { userId: b.user.id }, a.token)).data;
  assert.equal(ab.peer.username, 'chloe');
  const sent = await call('POST', `/conversations/${ab.id}/messages`, { body: 'Salut #mic' }, a.token);
  assert.equal(sent.status, 201);
  assert.equal(sent.data.status, 'sent');

  const bList = (await call('GET', '/conversations', undefined, b.token)).data;
  const bConv = bList.find((x) => x.id === ab.id);
  assert.equal(bConv.status, 'active');
  assert.equal(bConv.unread, 1);

  // Réponse, réaction, lecture.
  const reply = await call('POST', `/conversations/${ab.id}/messages`, { body: 'Coucou', replyTo: sent.data.id }, b.token);
  assert.equal(reply.data.replyTo.id, sent.data.id);
  await call('PUT', `/messages/${sent.data.id}/reaction`, { emoji: '❤️' }, b.token);
  await call('POST', `/conversations/${ab.id}/read`, { upTo: reply.data.id }, b.token);
  const msgs = (await call('GET', `/conversations/${ab.id}/messages`, undefined, a.token)).data;
  const first = msgs.find((m) => m.id === sent.data.id);
  assert.equal(first.status, 'read');
  assert.deepEqual(first.reactions, [{ userId: b.user.id, emoji: '❤️' }]);

  // Modifier / supprimer : seulement l'auteur.
  assert.equal((await call('PATCH', `/messages/${sent.data.id}`, { body: 'x' }, b.token)).status, 403);
  assert.equal((await call('PATCH', `/messages/${sent.data.id}`, { body: 'Salut !' }, a.token)).status, 200);
  assert.equal((await call('DELETE', `/messages/${sent.data.id}`, undefined, a.token)).status, 200);
  const after = (await call('GET', `/conversations/${ab.id}/messages`, undefined, b.token)).data;
  assert.equal(after.find((m) => m.id === sent.data.id).deleted, true);
  assert.equal(after.find((m) => m.id === sent.data.id).body, '');

  // Un tiers ne lit pas la conversation.
  assert.equal((await call('GET', `/conversations/${ab.id}/messages`, undefined, c.token)).status, 404);

  // Image.
  const img = await call('POST', `/conversations/${ab.id}/messages`, { kind: 'image', media: PIXEL }, a.token);
  assert.match(img.data.media, /^\/uploads\/[a-f0-9]+\.png$/);

  // Groupe : seulement des amis.
  assert.equal((await call('POST', '/conversations/group', { title: 'Famille', memberIds: [c.user.id] }, a.token)).status, 403);
  const g = await call('POST', '/conversations/group', { title: 'Famille', memberIds: [b.user.id] }, a.token);
  assert.equal(g.status, 201);
  assert.equal(g.data.role, 'admin');
  await call('PATCH', `/conversations/${g.data.id}`, { announceOnly: true }, a.token);
  assert.equal((await call('POST', `/conversations/${g.data.id}/messages`, { body: 'hey' }, b.token)).status, 403);
});

test('stories : audiences Me et World', async () => {
  const a = (await signup('emma')).data;
  const friend = (await signup('fabrice')).data;
  const close = (await signup('grace')).data;
  const stranger = (await signup('hugo')).data;
  await befriend(a, friend);
  await befriend(a, close);
  await call('PUT', `/close-friends/${close.user.id}`, undefined, a.token);

  await call('POST', '/stories', { audience: 'friends', body: 'Pour mes amis' }, a.token);
  await call('POST', '/stories', { audience: 'close_friends', body: 'Pour mes proches' }, a.token);
  await call('POST', '/stories', { audience: 'only_me', body: 'Souvenir' }, a.token);
  const w = await call('POST', '/stories', { audience: 'world', kind: 'image', media: PIXEL }, a.token);
  assert.equal(w.status, 201);

  const count = async (who) => {
    const s = (await call('GET', '/stories', undefined, who.token)).data;
    const mine = s.friends.find((g) => g.author.id === a.user.id);
    return mine ? mine.stories.map((x) => x.body).sort() : [];
  };
  assert.deepEqual(await count(friend), ['Pour mes amis']);
  assert.deepEqual(await count(close), ['Pour mes amis', 'Pour mes proches']);
  assert.deepEqual(await count(stranger), []);

  // World story visible par un abonné, dans la section World.
  await call('POST', `/users/${a.user.id}/follow`, undefined, stranger.token);
  const s = (await call('GET', '/stories', undefined, stranger.token)).data;
  assert.equal(s.world.length, 1);

  // Vues.
  const storyId = s.world[0].stories[0].id;
  await call('POST', `/stories/${storyId}/view`, undefined, stranger.token);
  const viewers = (await call('GET', `/stories/${storyId}/viewers`, undefined, a.token)).data;
  assert.equal(viewers[0].user.id, stranger.user.id);

  // Sans présence World : pas de World story.
  const priv = (await signup('ines', { joinWorld: false })).data;
  assert.equal((await call('POST', '/stories', { audience: 'world', body: 'x' }, priv.token)).status, 403);
});

test('World : publications, visibilité, fils, commentaires, partage', async () => {
  const a = (await signup('jules')).data;
  const b = (await signup('karine')).data;
  const c = (await signup('leo')).data;

  const p1 = await call('POST', '/posts', { body: 'Bienvenue sur MIC #Douala #mic @karine' }, a.token);
  assert.equal(p1.status, 201);
  assert.deepEqual(p1.data.hashtags.sort(), ['douala', 'mic']);
  const p2 = (await call('POST', '/posts', { body: 'Réservé à mes abonnés', audience: 'followers', whoCanComment: 'nobody', hideLikes: true }, a.token)).data;

  // Mention → notification.
  const notifs = (await call('GET', '/notifications', undefined, b.token)).data;
  assert.ok(notifs.items.some((n) => n.type === 'mention'));

  // Visibilité.
  assert.equal((await call('GET', `/posts/${p2.id}`, undefined, b.token)).status, 404);
  await call('POST', `/users/${a.user.id}/follow`, undefined, b.token);
  const seen = await call('GET', `/posts/${p2.id}`, undefined, b.token);
  assert.equal(seen.status, 200);
  assert.equal(seen.data.likes, null); // « Hide like count »
  assert.equal(seen.data.canComment, false);
  assert.equal((await call('POST', `/posts/${p2.id}/comments`, { body: 'hello' }, b.token)).status, 403);

  // Fils.
  const following = (await call('GET', '/feed/following', undefined, b.token)).data;
  assert.equal(following.length, 2);
  const forYou = (await call('GET', '/feed/for-you', undefined, c.token)).data;
  assert.ok(forYou.some((p) => p.id === p1.data.id));
  assert.ok(!forYou.some((p) => p.id === p2.id));

  // Like, commentaire, enregistrement, pourquoi.
  const liked = await call('POST', `/posts/${p1.data.id}/like`, undefined, c.token);
  assert.equal(liked.data.likes, 1);
  assert.equal((await call('POST', `/posts/${p1.data.id}/comments`, { body: 'Super !' }, c.token)).status, 201);
  await call('POST', `/posts/${p1.data.id}/save`, undefined, c.token);
  assert.equal((await call('GET', '/saved', undefined, c.token)).data.length, 1);
  const why = (await call('GET', `/posts/${p1.data.id}/why`, undefined, b.token)).data;
  assert.ok(why.reasons.some((r) => r.type === 'following'));

  // Hashtags et tendances.
  const tag = (await call('GET', '/hashtags/douala', undefined, c.token)).data;
  assert.equal(tag.posts.length, 1);
  const trending = (await call('GET', '/trending', undefined, c.token)).data;
  assert.ok(trending.some((t) => t.tag === 'mic'));

  // Partage World → Me.
  const conv = (await call('POST', '/conversations/direct', { userId: b.user.id }, c.token)).data;
  assert.equal((await call('POST', `/posts/${p1.data.id}/share`, { conversationIds: [conv.id] }, c.token)).data.shared, 1);
  const msgs = (await call('GET', `/conversations/${conv.id}/messages`, undefined, c.token)).data;
  assert.equal(msgs.at(-1).post.id, p1.data.id);

  // Sans présence World : impossible de publier.
  const priv = (await signup('mila', { joinWorld: false })).data;
  assert.equal((await call('POST', '/posts', { body: 'x' }, priv.token)).data.error, 'world_presence_required');

  // « Not interested » retire du fil For You.
  await call('POST', `/posts/${p1.data.id}/not-interested`, undefined, c.token);
  const forYou2 = (await call('GET', '/feed/for-you', undefined, c.token)).data;
  assert.ok(!forYou2.some((p) => p.id === p1.data.id));
});

test('blocage et compte World privé', async () => {
  const a = (await signup('nadia')).data;
  const b = (await signup('omar')).data;
  await befriend(a, b);
  await call('POST', `/users/${a.user.id}/follow`, undefined, b.token);
  const post = (await call('POST', '/posts', { body: 'public' }, a.token)).data;

  await call('POST', `/users/${b.user.id}/block`, undefined, a.token);
  assert.equal((await call('GET', `/posts/${post.id}`, undefined, b.token)).status, 404);
  assert.equal((await call('GET', '/users/nadia', undefined, b.token)).status, 404);
  assert.equal((await call('POST', '/conversations/direct', { userId: a.user.id }, b.token)).status, 403);
  const search = (await call('GET', '/users/search?q=nadia', undefined, b.token)).data;
  assert.equal(search.length, 0);
  const prof = (await call('GET', '/users/omar', undefined, a.token)).data;
  assert.equal(prof.relationship.friend, false);
  assert.equal(prof.relationship.blocked, true);

  // Compte World privé : abonnement en attente.
  const c = (await signup('pauline')).data;
  await call('PATCH', '/me', { worldPrivate: true }, c.token);
  const f = await call('POST', `/users/${c.user.id}/follow`, undefined, a.token);
  assert.equal(f.data.following, 'pending');
  const reqs = (await call('GET', '/follow-requests', undefined, c.token)).data;
  assert.equal(reqs[0].user.id, a.user.id);
  await call('POST', `/follow-requests/${a.user.id}/accept`, undefined, c.token);
  assert.equal((await call('GET', '/users/pauline', undefined, a.token)).data.relationship.following, 'active');

  // Signalement.
  // Signalement : seulement ce que l'on peut voir (la personne bloquée ne voit plus la publication).
  assert.equal((await call('POST', '/reports', { targetType: 'post', targetId: post.id, reason: 'spam' }, b.token)).status, 404);
  assert.equal((await call('POST', '/reports', { targetType: 'user', targetId: b.user.id, reason: 'harassment' }, a.token)).status, 201);
  assert.equal((await call('POST', '/reports', { targetType: 'user', targetId: b.user.id, reason: 'nope' }, a.token)).status, 400);
});

test('deux visages : nom privé pour les amis, nom public pour les autres', async () => {
  const a = (await signup('quentin')).data;
  const friend = (await signup('rose')).data;
  const stranger = (await signup('sami')).data;
  await befriend(a, friend);
  await call('PATCH', '/me', { displayName: 'Quentin (maison)', publicName: 'Q. Créateur' }, a.token);
  assert.equal((await call('GET', '/users/quentin', undefined, friend.token)).data.name, 'Quentin (maison)');
  assert.equal((await call('GET', '/users/quentin', undefined, stranger.token)).data.name, 'Q. Créateur');
  assert.equal((await call('GET', '/users/quentin', undefined, stranger.token)).data.online, undefined);
});

test('temps réel : nouveau message poussé par WebSocket', async () => {
  const a = (await signup('theo')).data;
  const b = (await signup('ursula')).data;
  await befriend(a, b);
  const conv = (await call('POST', '/conversations/direct', { userId: b.user.id }, a.token)).data;
  const ws = new WebSocket(`${ctx.base.replace('http', 'ws')}/ws?token=${b.token}`);
  await new Promise((r) => ws.once('open', r));
  const got = new Promise((resolve) => {
    ws.on('message', (raw) => {
      const m = JSON.parse(raw.toString());
      if (m.type === 'message') resolve(m.data);
    });
  });
  const sent = await call('POST', `/conversations/${conv.id}/messages`, { body: 'en direct' }, a.token);
  const pushed = await got;
  assert.equal(pushed.body, 'en direct');
  assert.equal(sent.data.status, 'delivered');
  ws.close();
});
