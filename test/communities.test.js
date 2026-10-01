import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ctx, call, signup, befriend } from './helpers.js';

const DAY = 24 * 3600 * 1000;

test('communautés : types, adhésion, rôles, publications, journal', async () => {
  const owner = (await signup('cmowner')).data;
  const bob = (await signup('cmbob')).data;
  const eve = (await signup('cmeve')).data;
  const teen = (await signup('cmteen', { birthDate: `${new Date().getFullYear() - 15}-01-01` })).data;
  await call('POST', '/me/world', { enable: true, private: true }, teen.token);
  assert.equal((await call('POST', '/communities', { name: 'Ados', handle: 'ados_x' }, teen.token)).data.error, 'adults_only');

  const pub = (await call('POST', '/communities', { name: 'Étudiants de Yaoundé', handle: 'etudiants.yde', category: 'education', rules: ['Respect', 'Pas de spam'] }, owner.token)).data;
  assert.equal(pub.role, 'owner');
  assert.deepEqual(pub.rules, ['Respect', 'Pas de spam']);

  // Publique : on rejoint directement, le contenu est lisible par tous.
  assert.equal((await call('POST', `/communities/${pub.id}/join`, {}, bob.token)).data.role, 'member');
  const p = (await call('POST', `/communities/${pub.id}/posts`, { body: 'Partiels reportés ? #fac' }, bob.token)).data;
  assert.equal((await call('GET', `/posts/${p.id}`, undefined, eve.token)).status, 200);
  assert.equal((await call('POST', `/communities/${pub.id}/posts`, { body: 'x' }, eve.token)).status, 403);
  const feed = (await call('GET', '/feed/communities', undefined, owner.token)).data;
  assert.equal(feed[0].community.handle, 'etudiants.yde');

  // Modérateur : retire une publication ; journal visible des admins.
  await call('POST', `/communities/${pub.id}/members/${bob.user.id}`, { action: 'role', role: 'moderator' }, owner.token);
  const p2 = (await call('POST', `/communities/${pub.id}/posts`, { body: 'Annonce' }, owner.token)).data;
  await call('POST', `/communities/${pub.id}/pin`, { postId: p2.id }, owner.token);
  const posts = (await call('GET', `/communities/${pub.id}/posts`, undefined, eve.token)).data;
  assert.equal(posts[0].pinned, true);
  assert.equal((await call('DELETE', `/communities/${pub.id}/posts/${p.id}`, undefined, bob.token)).status, 200);
  const log = (await call('GET', `/communities/${pub.id}/log`, undefined, owner.token)).data;
  assert.ok(log.some((l) => l.action === 'post_removed'));
  assert.equal((await call('GET', `/communities/${pub.id}/log`, undefined, bob.token)).status, 403);

  // Privée : demande approuvée ; contenu réservé aux membres.
  const priv = (await call('POST', '/communities', { name: 'Entrepreneurs', handle: 'entrepreneurs.cm', type: 'private' }, owner.token)).data;
  const pp = (await call('POST', `/communities/${priv.id}/posts`, { body: 'secret' }, owner.token)).data;
  assert.equal((await call('GET', `/posts/${pp.id}`, undefined, eve.token)).status, 404);
  assert.equal((await call('POST', `/communities/${priv.id}/join`, {}, eve.token)).data.status, 'pending');
  const members = (await call('GET', `/communities/${priv.id}/members`, undefined, owner.token)).data;
  assert.equal(members.pending[0].id, eve.user.id);
  await call('POST', `/communities/${priv.id}/members/${eve.user.id}`, { action: 'approve' }, owner.token);
  assert.equal((await call('GET', `/posts/${pp.id}`, undefined, eve.token)).status, 200);

  // Cachée : introuvable, accessible sur invitation d'un ami.
  const hid = (await call('POST', '/communities', { name: 'Famille élargie', handle: 'famille.cachee', type: 'hidden' }, owner.token)).data;
  assert.equal((await call('GET', `/communities/${hid.id}`, undefined, bob.token)).status, 404);
  assert.ok(!(await call('GET', '/communities?q=famille', undefined, bob.token)).data.discover.length);
  await befriend(owner, bob);
  await call('POST', `/communities/${hid.id}/members/${bob.user.id}`, { action: 'invite' }, owner.token);
  assert.equal((await call('POST', `/communities/${hid.id}/join`, {}, bob.token)).data.role, 'member');
});

test('événements : visibilité, participation, adresse protégée, rappels, iCalendar', async () => {
  const host = (await signup('evhost')).data;
  const friend = (await signup('evfriend')).data;
  const stranger = (await signup('evstranger')).data;
  await befriend(host, friend);
  const start = Date.now() + 3 * DAY;
  assert.equal((await call('POST', '/events', { title: 'Passé', startsAt: Date.now() - 5 * DAY }, host.token)).status, 400);

  const ev = (await call('POST', '/events', { title: 'Anniversaire de Kofi', startsAt: start, endsAt: start + 4 * 3600000, location: '12 rue des Palmiers, Bonapriso', visibility: 'friends', timezone: 'Africa/Douala' }, host.token)).data;
  assert.equal(ev.going, 1);
  assert.equal(ev.location, '12 rue des Palmiers, Bonapriso');
  assert.equal((await call('GET', `/events/${ev.id}`, undefined, stranger.token)).status, 404);

  // L'ami voit l'événement mais pas l'adresse tant qu'il n'a pas confirmé.
  const seen = (await call('GET', `/events/${ev.id}`, undefined, friend.token)).data;
  assert.equal(seen.location, null);
  assert.equal(seen.locationHidden, true);
  const going = (await call('POST', `/events/${ev.id}/rsvp`, { status: 'going' }, friend.token)).data;
  assert.equal(going.location, '12 rue des Palmiers, Bonapriso');
  assert.equal(going.going, 2);
  assert.equal((await call('GET', '/events', undefined, friend.token)).data.mine[0].id, ev.id);

  // Annulation : les participants sont prévenus.
  await call('PATCH', `/events/${ev.id}`, { cancelled: true }, host.token);
  const notifs = (await call('GET', '/notifications', undefined, friend.token)).data.items;
  assert.ok(notifs.some((n) => n.type === 'event_cancelled'));

  // Événement public : visible de tous, fichier iCalendar.
  const pubEv = (await call('POST', '/events', { title: 'Concert MIC', startsAt: Date.now() + 30 * 60000, onlineUrl: 'https://mic.example/live', visibility: 'public' }, host.token)).data;
  const ics = await fetch(`${ctx.base}/api/events/${pubEv.id}/ics`, { headers: { authorization: `Bearer ${stranger.token}` } });
  const text = await ics.text();
  assert.match(text, /BEGIN:VEVENT/);
  assert.match(text, /SUMMARY:Concert MIC/);
  assert.equal((await call('POST', '/events', { title: 'x', startsAt: Date.now() + DAY, onlineUrl: 'javascript:alert(1)' }, host.token)).data.error, 'invalid_url');
});
