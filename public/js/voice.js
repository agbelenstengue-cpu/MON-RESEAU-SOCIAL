// Section 9 : enregistrement et lecture des messages vocaux.
import { t } from './i18n.js';
import { post, emit, on } from './api.js';
import { html, mount, icon } from './ui.js';

const MAX_MS = 60 * 60 * 1000; // 9.1 : 60 minutes
const BARS = 48;

export function fmtDuration(ms) {
  const s = Math.max(0, Math.round((ms || 0) / 1000));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = String(s % 60).padStart(2, '0');
  return h ? `${h}:${String(m).padStart(2, '0')}:${sec}` : `${m}:${sec}`;
}

function pickMime() {
  const types = ['audio/webm;codecs=opus', 'audio/ogg;codecs=opus', 'audio/mp4', 'audio/webm'];
  return types.find((x) => window.MediaRecorder?.isTypeSupported?.(x)) || '';
}

// Réduit une suite de niveaux à BARS valeurs normalisées entre 0 et 1.
export function compress(levels, n = BARS) {
  if (!levels.length) return Array(n).fill(0.05);
  const out = [];
  for (let i = 0; i < n; i++) {
    const a = Math.floor((i * levels.length) / n);
    const b = Math.max(a + 1, Math.floor(((i + 1) * levels.length) / n));
    const slice = levels.slice(a, b);
    out.push(slice.reduce((x, y) => Math.max(x, y), 0));
  }
  const max = Math.max(...out, 0.01);
  return out.map((v) => Math.round(Math.max(0.05, v / max) * 100) / 100);
}

export function waveformHtml(waveform, progress = 0) {
  const bars = waveform?.length ? waveform : Array(BARS).fill(0.3);
  return html`${bars.map((v, i) => html`<i class="${i / bars.length < progress ? 'on' : ''}" style="height:${Math.round(15 + v * 85)}%"></i>`)}`;
}

// ---------------- Enregistreur ----------------
// Cycle : enregistrement → (pause / reprise) → arrêt → écoute avant envoi → envoi.
export class VoiceRecorder {
  constructor({ onLevel } = {}) {
    this.onLevel = onLevel;
    this.levels = [];
    this.chunks = [];
    this.elapsed = 0;
    this.startedAt = 0;
    this.state = 'idle';
  }

  async start() {
    if (!navigator.mediaDevices?.getUserMedia || !window.MediaRecorder) throw Object.assign(new Error('mic'), { code: 'mic_unavailable' });
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true } });
    } catch {
      throw Object.assign(new Error('mic'), { code: 'mic_denied' });
    }
    const mimeType = pickMime();
    // Opus ~32 kbit/s mono (9.2).
    this.rec = new MediaRecorder(this.stream, { ...(mimeType ? { mimeType } : {}), audioBitsPerSecond: 32000 });
    this.rec.ondataavailable = (e) => e.data.size && this.chunks.push(e.data);
    this.rec.start(250);
    this.ctx = new (window.AudioContext || window.webkitAudioContext)();
    const src = this.ctx.createMediaStreamSource(this.stream);
    this.analyser = this.ctx.createAnalyser();
    this.analyser.fftSize = 512;
    src.connect(this.analyser);
    this.buf = new Uint8Array(this.analyser.fftSize);
    this.startedAt = performance.now();
    this.state = 'recording';
    this.timer = setInterval(() => this.sample(), 100);
  }

  sample() {
    if (this.state !== 'recording') return;
    this.analyser.getByteTimeDomainData(this.buf);
    let sum = 0;
    for (const v of this.buf) sum += ((v - 128) / 128) ** 2;
    const rms = Math.min(1, Math.sqrt(sum / this.buf.length) * 4);
    this.levels.push(rms);
    this.onLevel?.(rms, this.duration());
    if (this.duration() >= MAX_MS) this.stop();
  }

  duration() {
    return this.elapsed + (this.state === 'recording' ? performance.now() - this.startedAt : 0);
  }

  pause() {
    if (this.state !== 'recording') return;
    this.elapsed = this.duration();
    this.rec.pause();
    this.state = 'paused';
  }

  resume() {
    if (this.state !== 'paused') return;
    this.rec.resume();
    this.startedAt = performance.now();
    this.state = 'recording';
  }

  // Arrête et renvoie { blob, url, duration, waveform }.
  stop() {
    if (this.result) return Promise.resolve(this.result);
    if (this.stopping) return this.stopping;
    const duration = this.duration();
    this.state = 'stopped';
    this.stopping = new Promise((resolve) => {
      this.rec.onstop = () => {
        const blob = new Blob(this.chunks, { type: this.rec.mimeType || 'audio/webm' });
        this.release();
        this.result = { blob, url: URL.createObjectURL(blob), duration, waveform: compress(this.levels) };
        resolve(this.result);
      };
      if (this.rec.state !== 'inactive') this.rec.stop();
      else this.rec.onstop();
    });
    return this.stopping;
  }

  cancel() {
    this.state = 'stopped';
    try {
      if (this.rec && this.rec.state !== 'inactive') this.rec.stop();
    } catch {
      /* ignore */
    }
    this.release();
    if (this.result) URL.revokeObjectURL(this.result.url);
  }

  release() {
    clearInterval(this.timer);
    this.stream?.getTracks().forEach((tr) => tr.stop());
    this.ctx?.close().catch(() => {});
  }
}

export function blobToDataUrl(blob) {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(String(r.result));
    r.onerror = reject;
    r.readAsDataURL(blob);
  });
}

// ---------------- Lecteur (unique dans l'application) ----------------
// Vitesses 1× · 1,5× · 2× (9.3), lecture continue, mini-lecteur flottant.
const RATES = [1, 1.5, 2];
const audio = new Audio();
audio.preload = 'auto';
let current = null; // { message, title, convId, next }
let rate = 1;
try {
  rate = Number(localStorage.getItem('mic.voiceRate')) || 1;
} catch {
  /* ignore */
}

function durationOf(m) {
  return m?.meta?.duration || (Number.isFinite(audio.duration) ? audio.duration * 1000 : 0);
}

function state() {
  if (!current) return null;
  const d = durationOf(current.message);
  return {
    id: current.message.id,
    convId: current.convId,
    title: current.title,
    playing: !audio.paused,
    current: audio.currentTime * 1000,
    duration: d,
    progress: d ? Math.min(1, (audio.currentTime * 1000) / d) : 0,
    rate,
  };
}

const notify = () => emit('voice:progress', state());
audio.addEventListener('timeupdate', notify);
audio.addEventListener('play', notify);
audio.addEventListener('pause', notify);
audio.addEventListener('ended', () => {
  const next = current?.next?.(current.message);
  if (next) play(next.message, next);
  else {
    current = null;
    emit('voice:progress', null);
  }
});

export const player = {
  state,
  isCurrent: (id) => current?.message.id === id,
  rate: () => rate,
  toggle(message, opts) {
    if (current?.message.id === message.id) {
      if (audio.paused) audio.play().catch(() => {});
      else audio.pause();
      return;
    }
    play(message, opts);
  },
  seek(message, ratio, opts) {
    if (current?.message.id !== message.id) play(message, opts);
    const d = durationOf(message) / 1000;
    if (d) audio.currentTime = Math.max(0, Math.min(d, ratio * d));
  },
  cycleRate() {
    rate = RATES[(RATES.indexOf(rate) + 1) % RATES.length];
    audio.playbackRate = rate;
    try {
      localStorage.setItem('mic.voiceRate', String(rate));
    } catch {
      /* ignore */
    }
    notify();
    return rate;
  },
  stop() {
    audio.pause();
    current = null;
    emit('voice:progress', null);
  },
};

function play(message, { title = '', convId = null, next = null, mine = false } = {}) {
  current = { message, title, convId, next };
  audio.src = message.media;
  audio.playbackRate = rate;
  audio.play().catch(() => {});
  // Statut « écouté » : uniquement pour les vocaux reçus (9.4).
  if (!mine && !message.playedByMe) {
    message.playedByMe = true;
    post(`/messages/${message.id}/played`).catch(() => {});
  }
  notify();
}

// Mini-lecteur flottant quand on quitte la conversation (9.3).
let bar = null;
export function updateMiniPlayer(currentRoute = location.hash) {
  const s = state();
  const hidden = !s || currentRoute === `#/chat/${s.convId}`;
  if (hidden) {
    bar?.remove();
    bar = null;
    return;
  }
  if (!bar) {
    bar = document.createElement('div');
    bar.className = 'mini-player';
    document.body.appendChild(bar);
    bar.addEventListener('click', (e) => {
      const act = e.target.closest('[data-mp]')?.dataset.mp;
      if (act === 'toggle') audio.paused ? audio.play() : audio.pause();
      else if (act === 'rate') player.cycleRate();
      else if (act === 'close') player.stop();
      else if (state()) location.hash = `#/chat/${state().convId}`;
    });
  }
  mount(
    bar,
    html`<button class="icon-btn" data-mp="toggle" aria-label="${s.playing ? t('voice.pause') : t('voice.play')}">${icon(s.playing ? 'pause' : 'play')}</button>
      <span class="grow"><b>${s.title}</b><span class="small muted"> · ${fmtDuration(s.current)} / ${fmtDuration(s.duration)}</span>
        <span class="mp-progress"><i style="width:${Math.round(s.progress * 100)}%"></i></span></span>
      <button class="chip" data-mp="rate">${s.rate}×</button>
      <button class="icon-btn" data-mp="close" aria-label="${t('common.close')}">${icon('close')}</button>`
  );
}
on('voice:progress', () => updateMiniPlayer());
window.addEventListener('hashchange', () => updateMiniPlayer());

