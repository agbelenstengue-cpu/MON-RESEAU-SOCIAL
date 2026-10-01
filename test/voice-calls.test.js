import { test } from 'node:test';
import assert from 'node:assert/strict';
import { call, signup, befriend, socket } from './helpers.js';

// Petit fichier audio factice (en-tête WebM + données) : seul le format de la data URL compte ici.
const AUDIO = 'data:audio/webm;codecs=opus;base64,' + Buffer.from('\x1aE\xdf\xa3 fake opus data').toString('base64');

test('messages vocaux : envoi, onde, statut « écouté »', async () => {
  const a = (await signup('vava')).data;
  const b = (await signup('vivi')).data;
  await befriend(a, b);
  const conv = (await call('POST', '/conversations/direct', { userId: b.user.id }, a.token)).data;

  const sent = await call('POST', `/conversations/${conv.id}/messages`, { kind: 'voice', media: AUDIO, duration: 4200, waveform: [0.1, 0.8, 2, -1] }, a.token);
  assert.equal(sent.status, 201);
  assert.equal(sent.data.kind, 'voice');
  assert.match(sent.data.media, /^\/uploads\/[a-f0-9]+\.webm$/);
  assert.deepEqual(sent.data.meta, { duration: 4200, waveform: [0.1, 0.8, 1, 0] });
  assert.equal(sent.data.played, false);

  // Un vocal n'accepte pas une image, et inversement.
  assert.equal((await call('POST', `/conversations/${conv.id}/messages`, { kind: 'voice', media: 'data:image/png;base64,AAAA' }, a.token)).status, 400);
  assert.equal((await call('POST', `/conversations/${conv.id}/messages`, { kind: 'image', media: AUDIO }, a.token)).status, 400);

  // Côté destinataire : non écouté, puis écouté.
  let mine = (await call('GET', `/conversations/${conv.id}/messages`, undefined, b.token)).data.find((m) => m.id === sent.data.id);
  assert.equal(mine.playedByMe, false);
  await call('POST', `/messages/${sent.data.id}/played`, undefined, b.token);
  mine = (await call('GET', `/conversations/${conv.id}/messages`, undefined, b.token)).data.find((m) => m.id === sent.data.id);
  assert.equal(mine.playedByMe, true);
  const forSender = (await call('GET', `/conversations/${conv.id}/messages`, undefined, a.token)).data.find((m) => m.id === sent.data.id);
  assert.equal(forSender.played, true);

  // Un vocal ne se modifie pas.
  assert.equal((await call('PATCH', `/messages/${sent.data.id}`, { body: 'x' }, a.token)).status, 403);
});

test('appel individuel : sonnerie, réponse, signalisation, fin et historique', async () => {
  const a = (await signup('calla')).data;
  const b = (await signup('callb')).data;
  const stranger = (await signup('callc')).data;
  await befriend(a, b);
  const conv = (await call('POST', '/conversations/direct', { userId: b.user.id }, a.token)).data;
  const wa = await socket(a.token);
  const wb = await socket(b.token);

  wa.send('call:start', { conversationId: conv.id, callType: 'video' });
  const started = await wa.wait('call:started');
  const incoming = await wb.wait('call:incoming');
  assert.equal(incoming.call.id, started.call.id);
  assert.equal(incoming.caller.id, a.user.id);
  assert.equal(incoming.call.type, 'video');

  // Le bandeau d'appel en cours apparaît dans la discussion.
  const summary = (await call('GET', `/conversations/${conv.id}`, undefined, b.token)).data;
  assert.equal(summary.activeCall.id, started.call.id);

  wb.send('call:join', { callId: started.call.id });
  const joined = await wb.wait('call:joined');
  assert.deepEqual(joined.peers.map((p) => p.id), [a.user.id]);
  await wa.wait('call:peer-joined', (d) => d.user.id === b.user.id);

  // Signalisation relayée uniquement entre participants.
  wb.send('call:signal', { callId: started.call.id, to: a.user.id, data: { description: { type: 'offer', sdp: 'v=0' } } });
  const sig = await wa.wait('call:signal');
  assert.equal(sig.from, b.user.id);
  assert.equal(sig.data.description.type, 'offer');

  wa.send('call:leave', { callId: started.call.id });
  await wb.wait('call:ended');
  const history = (await call('GET', '/calls', undefined, b.token)).data;
  assert.equal(history[0].direction, 'incoming');
  assert.equal(history[0].missed, false);
  assert.equal(history[0].answered, true);
  const msgs = (await call('GET', `/conversations/${conv.id}/messages`, undefined, a.token)).data;
  assert.equal(msgs.at(-1).kind, 'call');
  assert.equal(msgs.at(-1).meta.status, 'ended');

  // Un inconnu ne peut pas appeler (10.8) ; un bloqué non plus.
  const c2 = (await call('POST', '/conversations/direct', { userId: a.user.id }, stranger.token)).data;
  const ws = await socket(stranger.token);
  ws.send('call:start', { conversationId: c2.id, callType: 'audio' });
  assert.equal((await ws.wait('call:error')).error, 'cannot_call');

  // Refus → appel manqué.
  wa.send('call:start', { conversationId: conv.id, callType: 'audio' });
  const s2 = await wa.wait('call:started');
  await wb.wait('call:incoming', (d) => d.call.id === s2.call.id);
  wb.send('call:decline', { callId: s2.call.id });
  await wa.wait('call:ended', (d) => d.callId === s2.call.id);
  const h2 = (await call('GET', '/calls', undefined, b.token)).data;
  assert.equal(h2[0].missed, true);

  // Suppression de l'historique.
  await call('DELETE', '/calls/all', undefined, b.token);
  assert.equal((await call('GET', '/calls', undefined, b.token)).data.length, 0);

  [wa, wb, ws].forEach((w) => w.close());
});

test('appel de groupe : un retardataire rejoint, raccrocher en se déconnectant', async () => {
  const a = (await signup('grpa')).data;
  const b = (await signup('grpb')).data;
  const c = (await signup('grpc')).data;
  await befriend(a, b);
  await befriend(a, c);
  const g = (await call('POST', '/conversations/group', { title: 'Réunion', memberIds: [b.user.id, c.user.id] }, a.token)).data;
  const [wa, wb, wc] = await Promise.all([socket(a.token), socket(b.token), socket(c.token)]);

  wa.send('call:start', { conversationId: g.id, callType: 'audio' });
  const { call: started } = await wa.wait('call:started');
  await wb.wait('call:incoming');
  await wc.wait('call:incoming');
  wb.send('call:join', { callId: started.id });
  await wb.wait('call:joined');
  wc.send('call:decline', { callId: started.id });
  // L'appel continue à deux ; C peut encore rejoindre via le bandeau.
  wc.send('call:join', { callId: started.id });
  const joined = await wc.wait('call:joined');
  assert.deepEqual(joined.peers.map((p) => p.id).sort(), [a.user.id, b.user.id].sort());

  // Démarrer un appel alors qu'un appel est en cours dans le groupe = le rejoindre.
  wb.close();
  await wa.wait('call:peer-left', (d) => d.userId === b.user.id);
  const update = await wc.wait('call:update', (d) => d.call && d.call.participants.length === 2 && !d.call.participants.includes(b.user.id));
  assert.deepEqual(update.call.participants.sort(), [a.user.id, c.user.id].sort());
  wa.send('call:leave', { callId: started.id });
  await wc.wait('call:ended');
  [wa, wc].forEach((w) => w.close());
});
