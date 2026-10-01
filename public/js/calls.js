// Section 10 : appels audio et vidéo (WebRTC, maillage pair-à-pair).
// Le serveur ne fait que relayer la signalisation ; le son et l'image passent
// directement entre les appareils, chiffrés par DTLS-SRTP.
import { t } from './i18n.js';
import { store, get, post, on, sendWs } from './api.js';
import { html, raw, mount, $, $$, icon, avatar, toast } from './ui.js';
import { fmtDuration, player } from './voice.js';

let iceServers = null;
let active = null; // appel en cours
let incoming = null; // appel qui sonne

async function config() {
  if (!iceServers) iceServers = (await get('/calls/config').catch(() => ({ iceServers: [] }))).iceServers;
  return iceServers;
}

// ---------------- Sonnerie (Web Audio, sans fichier) ----------------
let ring = null;
function startRing(outgoing = false) {
  stopRing();
  try {
    const ctx = new (window.AudioContext || window.webkitAudioContext)();
    const gain = ctx.createGain();
    gain.gain.value = 0;
    gain.connect(ctx.destination);
    const osc = ctx.createOscillator();
    osc.frequency.value = outgoing ? 425 : 660;
    osc.connect(gain);
    osc.start();
    let on = false;
    const timer = setInterval(() => {
      on = !on;
      gain.gain.setTargetAtTime(on ? 0.06 : 0, ctx.currentTime, 0.02);
    }, outgoing ? 1000 : 500);
    ring = { ctx, timer };
  } catch {
    ring = null;
  }
}
function stopRing() {
  if (!ring) return;
  clearInterval(ring.timer);
  ring.ctx.close().catch(() => {});
  ring = null;
}

// ---------------- Médias locaux ----------------
async function getMedia(video, facingMode = 'user') {
  try {
    return await navigator.mediaDevices.getUserMedia({
      audio: { echoCancellation: true, noiseSuppression: true },
      video: video ? { facingMode, width: { ideal: 1280 }, height: { ideal: 720 } } : false,
    });
  } catch {
    if (video) {
      // Pas de caméra : on bascule en audio plutôt que d'échouer.
      try {
        return await navigator.mediaDevices.getUserMedia({ audio: true });
      } catch {
        /* rien */
      }
    }
    throw Object.assign(new Error('mic'), { code: 'call_media_denied' });
  }
}

// ---------------- Connexions pair-à-pair (« perfect negotiation ») ----------------
function createPeer(user) {
  const pc = new RTCPeerConnection({ iceServers });
  const peer = { user, pc, stream: new MediaStream(), makingOffer: false, ignoreOffer: false, polite: store.me.id > user.id, audio: true, video: undefined };
  active.peers.set(user.id, peer);
  for (const track of active.local.getTracks()) pc.addTrack(track, active.local);
  pc.ontrack = (e) => {
    peer.stream.addTrack(e.track);
    e.track.onunmute = () => draw();
    draw();
  };
  pc.onicecandidate = (e) => e.candidate && signal(user.id, { candidate: e.candidate.toJSON() });
  pc.onnegotiationneeded = async () => {
    try {
      peer.makingOffer = true;
      await pc.setLocalDescription();
      signal(user.id, { description: pc.localDescription.toJSON() });
    } catch {
      /* nouvelle tentative au prochain besoin */
    } finally {
      peer.makingOffer = false;
    }
  };
  pc.onconnectionstatechange = () => {
    if (pc.connectionState === 'connected' && !active.connectedAt) active.connectedAt = Date.now();
    draw();
  };
  return peer;
}

function signal(to, data) {
  sendWs('call:signal', { callId: active.id, to, data });
}

async function onSignal({ callId, from, data }) {
  if (!active || active.id !== callId) return;
  const peer = active.peers.get(from) || createPeer(active.names.get(from) || { id: from, name: '' });
  if (!peer.mediaSent) {
    peer.mediaSent = true;
    sendWs('call:media', { callId: active.id, audio: active.audio, video: active.video });
  }
  const { pc } = peer;
  try {
    if (data.description) {
      const collision = data.description.type === 'offer' && (peer.makingOffer || pc.signalingState !== 'stable');
      peer.ignoreOffer = !peer.polite && collision;
      if (peer.ignoreOffer) return;
      await pc.setRemoteDescription(data.description);
      if (data.description.type === 'offer') {
        await pc.setLocalDescription();
        signal(from, { description: pc.localDescription.toJSON() });
      }
    } else if (data.candidate) {
      try {
        await pc.addIceCandidate(data.candidate);
      } catch (err) {
        if (!peer.ignoreOffer) throw err;
      }
    }
  } catch (err) {
    console.warn('signal', err);
  }
}

// ---------------- Cycle de vie ----------------
export async function startCall(conversation, type = 'audio') {
  if (active) return toast(t('call.alreadyIn'));
  await config();
  let local;
  try {
    local = await getMedia(type === 'video');
  } catch (err) {
    return toast(t(`err.${err.code}`));
  }
  player.stop();
  active = newCall({ id: null, conversation, type, local, outgoing: true });
  sendWs('call:start', { conversationId: conversation.id, callType: type });
  startRing(true);
  draw();
}

function newCall({ id, conversation, type, local, outgoing }) {
  return {
    id,
    conversation,
    type,
    local,
    outgoing,
    peers: new Map(),
    names: new Map(),
    audio: true,
    video: local.getVideoTracks().length > 0,
    facing: 'user',
    minimized: false,
    startedAt: Date.now(),
    connectedAt: null,
    timer: setInterval(() => updateTimer(), 1000),
  };
}

export async function acceptCall() {
  if (!incoming) return;
  const inc = incoming;
  closeIncoming();
  if (active) hangUp();
  await config();
  let local;
  try {
    local = await getMedia(inc.call.type === 'video');
  } catch (err) {
    sendWs('call:decline', { callId: inc.call.id });
    return toast(t(`err.${err.code}`));
  }
  player.stop();
  active = newCall({ id: inc.call.id, conversation: inc.conversation, type: inc.call.type, local, outgoing: false });
  active.names.set(inc.caller.id, inc.caller);
  sendWs('call:join', { callId: inc.call.id });
  draw();
}

// Rejoindre un appel de groupe déjà en cours (bandeau « Rejoindre »).
export async function joinCall(conversation, call) {
  if (active?.id === call.id) return expand();
  if (active) hangUp();
  await config();
  let local;
  try {
    local = await getMedia(call.type === 'video');
  } catch (err) {
    return toast(t(`err.${err.code}`));
  }
  player.stop();
  active = newCall({ id: call.id, conversation, type: call.type, local, outgoing: false });
  sendWs('call:join', { callId: call.id });
  draw();
}

export function declineCall(message) {
  if (!incoming) return;
  const inc = incoming;
  sendWs('call:decline', { callId: inc.call.id });
  closeIncoming();
  // « Reply with message » (10.3) : le message part dans la discussion.
  if (message) post(`/conversations/${inc.conversation.id}/messages`, { body: message }).catch(() => {});
}

export function hangUp() {
  if (!active) return;
  if (active.id) sendWs('call:leave', { callId: active.id });
  cleanup();
}

function cleanup(message) {
  if (!active) return;
  stopRing();
  clearInterval(active.timer);
  for (const p of active.peers.values()) p.pc.close();
  active.local.getTracks().forEach((tr) => tr.stop());
  active = null;
  document.querySelector('.call-screen')?.remove();
  document.querySelector('.call-pill')?.remove();
  if (message) toast(message);
}

export function inCall() {
  return active;
}

// ---------------- Commandes pendant l'appel (10.4) ----------------
function toggleMic() {
  active.audio = !active.audio;
  active.local.getAudioTracks().forEach((tr) => (tr.enabled = active.audio));
  sendWs('call:media', { callId: active.id, audio: active.audio, video: active.video });
  draw();
}

async function toggleCamera() {
  const track = active.local.getVideoTracks()[0];
  if (track) {
    active.video = !active.video;
    track.enabled = active.video;
  } else {
    // Passer d'un appel audio à la vidéo : nouvelle piste, renégociation automatique.
    try {
      const cam = await navigator.mediaDevices.getUserMedia({ video: { facingMode: active.facing } });
      const vt = cam.getVideoTracks()[0];
      active.local.addTrack(vt);
      for (const p of active.peers.values()) p.pc.addTrack(vt, active.local);
      active.video = true;
    } catch {
      return toast(t('err.call_media_denied'));
    }
  }
  sendWs('call:media', { callId: active.id, audio: active.audio, video: active.video });
  draw();
}

async function flipCamera() {
  const old = active.local.getVideoTracks()[0];
  if (!old) return;
  active.facing = active.facing === 'user' ? 'environment' : 'user';
  try {
    const cam = await navigator.mediaDevices.getUserMedia({ video: { facingMode: active.facing } });
    const vt = cam.getVideoTracks()[0];
    for (const p of active.peers.values()) {
      const sender = p.pc.getSenders().find((s) => s.track === old);
      await sender?.replaceTrack(vt);
    }
    active.local.removeTrack(old);
    old.stop();
    active.local.addTrack(vt);
    draw();
  } catch {
    toast(t('err.call_media_denied'));
  }
}

function minimize() {
  active.minimized = true;
  draw();
}
function expand() {
  if (!active) return;
  active.minimized = false;
  draw();
}

function floatReaction(userId, emoji) {
  const screen = document.querySelector('.call-screen');
  if (!screen) return;
  const el = document.createElement('div');
  el.className = 'call-reaction';
  el.textContent = emoji;
  el.style.left = `${15 + Math.random() * 70}%`;
  screen.appendChild(el);
  setTimeout(() => el.remove(), 2500);
}

// ---------------- Interface ----------------
function peerName(id) {
  return active.peers.get(id)?.user?.name || active.names.get(id)?.name || '';
}

function title() {
  const c = active.conversation;
  if (c?.type === 'group') return c.title;
  const first = [...active.peers.values()][0]?.user || [...active.names.values()][0];
  return first?.name || c?.peer?.name || c?.title || '';
}

function statusText() {
  if (active.connectedAt) return fmtDuration(Date.now() - active.connectedAt);
  if (active.peers.size) return t('call.connecting');
  return active.outgoing ? t('call.ringing') : t('call.connecting');
}

function updateTimer() {
  if (!active) return;
  $$('[data-call-status]').forEach((el) => (el.textContent = statusText()));
}

function draw() {
  if (!active) return;
  let screen = document.querySelector('.call-screen');
  let pill = document.querySelector('.call-pill');
  if (active.minimized) {
    screen?.classList.add('hidden');
    if (!pill) {
      pill = document.createElement('button');
      pill.className = 'call-pill';
      pill.addEventListener('click', expand);
      document.body.appendChild(pill);
    }
    mount(pill, html`${icon(active.type === 'video' ? 'video' : 'phone')}<span>${title()}</span><span data-call-status>${statusText()}</span>`);
    return;
  }
  pill?.remove();
  if (!screen) {
    screen = document.createElement('div');
    screen.className = 'call-screen';
    screen.setAttribute('role', 'dialog');
    screen.setAttribute('aria-modal', 'true');
    document.body.appendChild(screen);
    screen.addEventListener('click', onScreenClick);
  }
  screen.classList.remove('hidden');
  const peers = [...active.peers.values()];
  const hasVideo = active.video || peers.some((p) => p.stream.getVideoTracks().some((tr) => !tr.muted) && p.video !== false);
  // Les éléments <video> existants sont conservés pour ne pas couper le flux.
  const keep = new Map($$('video[data-peer]', screen).map((v) => [v.dataset.peer, v]));
  mount(
    screen,
    html`<div class="call-head">
        <button class="icon-btn" data-c="min" aria-label="${t('call.minimize')}">${icon('minimize')}</button>
        <div class="grow center"><b>${title()}</b><div class="small" data-call-status>${statusText()}</div></div>
        <span class="small call-lock">${icon('lock', 'width="12" height="12"')} ${t('call.p2p')}</span>
      </div>
      <div class="call-grid n${Math.min(peers.length, 4)} ${hasVideo ? 'video' : ''}">
        ${peers.length
          ? peers.map(
              (p) => html`<div class="tile" data-tile="${p.user.id}">
                <div class="tile-avatar">${avatar(p.user, 'lg')}</div>
                <div class="tile-name">${p.user.name}${p.audio === false ? raw(' 🔇') : ''}</div>
              </div>`
            )
          : html`<div class="tile waiting"><div class="tile-avatar">${avatar({ name: title(), avatar: active.conversation?.peer?.avatar }, 'lg')}</div><div class="tile-name">${title()}</div></div>`}
      </div>
      ${active.video ? html`<div class="self-view" data-self></div>` : ''}
      <div class="call-reactions">${['❤️', '😂', '👏', '🙏', '👍'].map((e) => html`<button data-react="${e}">${e}</button>`)}</div>
      <div class="call-controls">
        <button class="ctl ${active.audio ? '' : 'off'}" data-c="mic" aria-pressed="${!active.audio}" aria-label="${t('call.mic')}">${icon(active.audio ? 'mic' : 'micOff')}</button>
        <button class="ctl ${active.video ? '' : 'off'}" data-c="cam" aria-pressed="${!active.video}" aria-label="${t('call.camera')}">${icon(active.video ? 'video' : 'videoOff')}</button>
        ${active.local.getVideoTracks().length ? html`<button class="ctl" data-c="flip" aria-label="${t('camera.flip')}">${icon('flip')}</button>` : ''}
        <button class="ctl end" data-c="end" aria-label="${t('call.hangUp')}">${icon('hangup')}</button>
      </div>`
  );
  for (const p of peers) {
    const tile = $(`[data-tile="${p.user.id}"]`, screen);
    let v = keep.get(String(p.user.id));
    if (!v) {
      v = document.createElement('video');
      v.dataset.peer = p.user.id;
      v.autoplay = true;
      v.playsInline = true;
    }
    if (v.srcObject !== p.stream) v.srcObject = p.stream;
    const showVideo = p.video !== false && p.stream.getVideoTracks().some((tr) => tr.readyState === 'live' && !tr.muted);
    v.className = showVideo ? '' : 'audio-only';
    tile.classList.toggle('has-video', showVideo);
    tile.prepend(v);
    v.play?.().catch(() => {});
  }
  const self = $('[data-self]', screen);
  if (self) {
    const v = document.createElement('video');
    v.autoplay = true;
    v.muted = true;
    v.playsInline = true;
    v.srcObject = active.local;
    if (active.facing === 'user') v.style.transform = 'scaleX(-1)';
    self.appendChild(v);
  }
}

function onScreenClick(e) {
  const c = e.target.closest('[data-c]')?.dataset.c;
  const react = e.target.closest('[data-react]')?.dataset.react;
  if (react && active?.id) sendWs('call:reaction', { callId: active.id, emoji: react });
  if (c === 'mic') toggleMic();
  if (c === 'cam') toggleCamera();
  if (c === 'flip') flipCamera();
  if (c === 'end') hangUp();
  if (c === 'min') minimize();
}

// Écran d'appel entrant (10.3).
function showIncoming(data) {
  closeIncoming(false);
  incoming = data;
  const el = document.createElement('div');
  el.className = 'call-incoming';
  el.setAttribute('role', 'alertdialog');
  const isGroup = data.conversation.type === 'group';
  mount(
    el,
    html`<div class="box">
      ${avatar(data.caller, 'lg')}
      <h3>${isGroup ? data.conversation.title : data.caller.name}</h3>
      <p class="muted">${isGroup ? t('call.groupFrom', { name: data.caller.name }) + ' · ' : ''}${t(data.call.type === 'video' ? 'call.incomingVideo' : 'call.incomingAudio')}</p>
      <div class="row" style="justify-content:center;gap:40px;margin:20px 0 12px">
        <button class="ctl end" data-i="decline" aria-label="${t('call.decline')}">${icon('hangup')}</button>
        <button class="ctl accept" data-i="accept" aria-label="${t('call.accept')}">${icon(data.call.type === 'video' ? 'video' : 'phone')}</button>
      </div>
      <div class="row" style="justify-content:center;gap:8px;flex-wrap:wrap">
        <button class="chip" data-i="msg1">${t('call.decline.msg')}</button>
        <button class="chip" data-i="msg2">${t('call.decline.msg2')}</button>
      </div>
    </div>`
  );
  el.addEventListener('click', (e) => {
    const a = e.target.closest('[data-i]')?.dataset.i;
    if (a === 'accept') acceptCall();
    if (a === 'decline') declineCall();
    if (a === 'msg1') declineCall(t('call.decline.msg'));
    if (a === 'msg2') declineCall(t('call.decline.msg2'));
  });
  document.body.appendChild(el);
  startRing(false);
  if (document.hidden && 'Notification' in window && Notification.permission === 'granted') {
    new Notification('MIC', { body: `${data.caller.name} — ${t(data.call.type === 'video' ? 'call.incomingVideo' : 'call.incomingAudio')}` });
  }
}

function closeIncoming(stop = true) {
  incoming = null;
  document.querySelector('.call-incoming')?.remove();
  // La tonalité d'appel sortant continue tant que personne n'a décroché.
  const outgoingRinging = active?.outgoing && !active.peers.size;
  if (stop && !outgoingRinging) stopRing();
}

// ---------------- Événements temps réel ----------------
export function initCalls() {
  on('call:incoming', (d) => {
    // Déjà en appel : on refuse automatiquement (occupé).
    if (active) return sendWs('call:decline', { callId: d.call.id });
    showIncoming(d);
  });
  on('call:started', ({ call, busy }) => {
    if (!active || active.id) return;
    active.id = call.id;
    if (busy?.length && active.conversation?.type === 'group') toast(t('call.someBusy'));
  });
  on('call:joined', ({ call, peers }) => {
    if (!active || active.id !== call.id) return;
    stopRing();
    // Le nouvel arrivant ouvre une connexion vers chaque participant présent.
    for (const user of peers) if (!active.peers.has(user.id)) createPeer(user);
    sendWs('call:media', { callId: active.id, audio: active.audio, video: active.video });
    draw();
  });
  on('call:peer-joined', ({ callId, user }) => {
    if (!active || active.id !== callId) return;
    stopRing();
    // Pas d'offre de notre côté : c'est le nouvel arrivant qui la fait (aucune collision).
    active.names.set(user.id, user);
    const existing = active.peers.get(user.id);
    if (existing) existing.user = user;
    draw();
  });
  on('call:peer-left', ({ callId, userId }) => {
    if (!active || active.id !== callId) return;
    const p = active.peers.get(userId);
    p?.pc.close();
    active.peers.delete(userId);
    draw();
  });
  on('call:peer-media', ({ callId, userId, audio, video }) => {
    const p = active?.id === callId && active.peers.get(userId);
    if (!p) return;
    p.audio = audio;
    p.video = video;
    draw();
  });
  on('call:declined', ({ callId, userId }) => {
    if (active?.id === callId && active.conversation?.type === 'group') toast(t('call.declinedBy', { name: peerName(userId) || '' }));
  });
  on('call:busy', ({ callId }) => {
    if (active?.id === callId) cleanup(t('call.busy'));
  });
  on('call:ended', ({ callId }) => {
    if (incoming?.call.id === callId) closeIncoming();
    if (active?.id === callId) cleanup(active.connectedAt ? t('call.ended') : active.outgoing ? t('call.noAnswer') : t('call.ended'));
  });
  on('call:answered-elsewhere', ({ callId }) => {
    if (incoming?.call.id === callId) closeIncoming();
  });
  on('call:error', ({ error }) => {
    if (active && !active.peers.size) cleanup();
    toast(t(`err.${error}`));
  });
  on('call:signal', onSignal);
  on('call:reaction', ({ callId, userId, emoji }) => active?.id === callId && floatReaction(userId, emoji));
  on('logout', () => cleanup());
  window.addEventListener('beforeunload', () => active && hangUp());
}
