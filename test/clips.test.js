import { test } from 'node:test';
import assert from 'node:assert/strict';
import { PIXEL, ctx, call, signup } from './helpers.js';

// En-tête MP4 minimal (boîte « ftyp ») : suffisant pour la reconnaissance du format.
const MP4 = Buffer.concat([Buffer.from([0, 0, 0, 0x18]), Buffer.from('ftypisom'), Buffer.alloc(64, 1)]);

async function upload(token, buf, type = 'video/mp4') {
  const res = await fetch(`${ctx.base}/api/media/video`, { method: 'POST', headers: { 'content-type': type, authorization: `Bearer ${token}` }, body: buf });
  return { status: res.status, data: await res.json() };
}

test('clips : envoi de la vidéo, publication, fil Clips, vues', async () => {
  const a = (await signup('clipa')).data;
  const b = (await signup('clipb')).data;
  const priv = (await signup('clipc', { joinWorld: false })).data;

  assert.equal((await upload(priv.token, MP4)).status, 403); // présence World requise
  assert.equal((await upload(a.token, Buffer.from('pas une vidéo'))).status, 400);
  const up = await upload(a.token, MP4);
  assert.equal(up.status, 201);
  assert.match(up.data.url, /^\/uploads\/[a-f0-9]{32}\.mp4$/);

  // La vidéo d'un autre compte ne peut pas être publiée.
  assert.equal((await call('POST', '/posts', { video: up.data.url, duration: 5000 }, b.token)).status, 400);
  assert.equal((await call('POST', '/posts', { video: up.data.url, duration: 20 * 60 * 1000 }, a.token)).data.error, 'invalid_duration');

  const clip = await call('POST', '/posts', { video: up.data.url, duration: 12000, media: PIXEL, body: 'Mon premier clip #danse', allowDownload: false }, a.token);
  assert.equal(clip.status, 201);
  assert.equal(clip.data.kind, 'clip');
  assert.equal(clip.data.video, up.data.url);
  assert.equal(clip.data.allowDownload, false);
  assert.equal(clip.data.views, 0);
  // Une vidéo ne sert qu'une fois.
  assert.equal((await call('POST', '/posts', { video: up.data.url, duration: 5000 }, a.token)).status, 400);

  await call('POST', '/posts', { body: 'Publication texte' }, a.token);
  const feed = (await call('GET', '/feed/clips', undefined, b.token)).data;
  assert.deepEqual(feed.map((p) => p.kind), ['clip']);

  await call('POST', `/posts/${clip.data.id}/view`, undefined, b.token);
  await call('POST', `/posts/${clip.data.id}/view`, undefined, b.token);
  assert.equal((await call('GET', `/posts/${clip.data.id}`, undefined, a.token)).data.views, 1);

  // Mineur : téléchargement désactivé par défaut.
  const teen = (await signup('clipteen', { birthDate: `${new Date().getFullYear() - 16}-01-01` })).data;
  await call('POST', '/me/world', { enable: true, private: true }, teen.token);
  const tu = await upload(teen.token, MP4);
  const tclip = await call('POST', '/posts', { video: tu.data.url, duration: 4000 }, teen.token);
  assert.equal(tclip.data.allowDownload, false);
});
