import { test } from 'node:test';
import assert from 'node:assert/strict';
import { call, signup, befriend } from './helpers.js';
import { sanctionFor } from '../server/routes/moderation.js';

test('échelle des sanctions (22.5)', () => {
  assert.equal(sanctionFor(1).kind, 'warning');
  assert.deepEqual(sanctionFor(2), { kind: 'restrict', ms: 86400000 });
  assert.equal(sanctionFor(3).ms, 7 * 86400000);
  assert.equal(sanctionFor(4).kind, 'suspend');
  assert.equal(sanctionFor(5).kind, 'ban');
});

test('signalement, file de modération, avertissements, restriction, appel, bannissement', async () => {
  const author = (await signup('modauthor')).data;
  const reporter = (await signup('modreporter')).data;
  const other = (await signup('modother')).data;
  const mod1 = (await signup('modone')).data;
  const mod2 = (await signup('modtwo')).data;
  assert.equal(mod1.user.role, 'moderator');
  assert.equal((await call('GET', '/mod/reports', undefined, reporter.token)).data.error, 'moderators_only');

  // On ne peut signaler que ce que l'on peut voir : pas un message d'une autre discussion.
  await befriend(author, other);
  const conv = (await call('POST', '/conversations/direct', { userId: other.user.id }, author.token)).data;
  const msg = (await call('POST', `/conversations/${conv.id}/messages`, { body: 'privé' }, author.token)).data;
  assert.equal((await call('POST', '/reports', { targetType: 'message', targetId: msg.id, reason: 'spam' }, reporter.token)).status, 404);

  const p1 = (await call('POST', '/posts', { body: 'contenu haineux' }, author.token)).data;
  const p2 = (await call('POST', '/posts', { body: 'arnaque' }, author.token)).data;
  await call('POST', '/reports', { targetType: 'post', targetId: p1.id, reason: 'hate', details: 'insultes' }, reporter.token);
  await call('POST', '/reports', { targetType: 'post', targetId: p1.id, reason: 'hate' }, other.token);
  await call('POST', '/reports', { targetType: 'post', targetId: p2.id, reason: 'minor_safety' }, reporter.token);

  // File triée par gravité, signalements regroupés par contenu.
  const queue = (await call('GET', '/mod/reports', undefined, mod1.token)).data;
  assert.equal(queue.length, 2);
  assert.equal(queue[0].targetId, p2.id); // sécurité des enfants en premier
  const hateItem = queue.find((x) => x.targetId === p1.id);
  assert.equal(hateItem.count, 2);
  assert.equal(hateItem.preview.body, 'contenu haineux');

  // 1er avertissement : contenu supprimé, simple avertissement.
  const d1 = (await call('POST', `/mod/reports/${hateItem.id}/decide`, { action: 'remove' }, mod1.token)).data;
  assert.equal(d1.sanction.kind, 'warning');
  assert.equal((await call('GET', `/posts/${p1.id}`, undefined, reporter.token)).status, 404);
  const mine = (await call('GET', '/me/reports', undefined, reporter.token)).data;
  assert.ok(mine.some((r) => r.status === 'closed' && r.decision === 'remove'));

  // 2e avertissement : restriction 24 h (publication impossible).
  const d2 = (await call('POST', `/mod/reports/${queue[0].id}/decide`, { action: 'remove' }, mod1.token)).data;
  assert.equal(d2.sanction.kind, 'restrict');
  assert.equal((await call('POST', '/posts', { body: 'encore' }, author.token)).data.error, 'account_restricted');
  const status = (await call('GET', '/me/status', undefined, author.token)).data;
  assert.equal(status.strikes.length, 2);
  assert.ok(status.restrictedUntil > Date.now());

  // Appel : revu par un autre modérateur ; annulé → restriction levée.
  await call('POST', `/me/strikes/${status.strikes[0].id}/appeal`, { text: 'Erreur' }, author.token);
  assert.equal((await call('POST', `/me/strikes/${status.strikes[0].id}/appeal`, { text: 'bis' }, author.token)).status, 409);
  assert.equal((await call('POST', `/mod/appeals/${status.strikes[0].id}`, { decision: 'overturn' }, mod1.token)).data.error, 'different_moderator_required');
  const appeals = (await call('GET', '/mod/appeals', undefined, mod2.token)).data;
  assert.equal(appeals.length, 1);
  await call('POST', `/mod/appeals/${status.strikes[0].id}`, { decision: 'overturn' }, mod2.token);
  const after = (await call('GET', '/me/status', undefined, author.token)).data;
  assert.equal(after.strikes.length, 1);
  assert.equal(after.restrictedUntil, null);
  assert.equal((await call('POST', '/posts', { body: 'de retour' }, author.token)).status, 201);

  // Bannissement : plus d'accès, même en se reconnectant.
  const p3 = (await call('POST', '/posts', { body: 'grave' }, author.token)).data;
  await call('POST', '/reports', { targetType: 'post', targetId: p3.id, reason: 'violence' }, reporter.token);
  const q2 = (await call('GET', '/mod/reports', undefined, mod1.token)).data;
  await call('POST', `/mod/reports/${q2[0].id}/decide`, { action: 'ban' }, mod1.token);
  assert.equal((await call('GET', '/me', undefined, author.token)).status, 401); // sessions fermées
});
