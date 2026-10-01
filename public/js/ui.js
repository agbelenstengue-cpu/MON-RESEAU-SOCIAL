// Composants d'interface partagés : gabarits HTML sûrs, icônes, feuilles, dialogues.
import { t } from './i18n.js';
import { post } from './api.js';

// --- Gabarits HTML avec échappement automatique ---
class Raw {
  constructor(s) {
    this.s = s;
  }
  toString() {
    return this.s;
  }
}
export const raw = (s) => new Raw(s);

export function esc(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
}

function fmt(v) {
  if (v == null || v === false) return '';
  if (v instanceof Raw) return v.s;
  if (Array.isArray(v)) return v.map(fmt).join('');
  return esc(v);
}

export function html(strings, ...vals) {
  let out = '';
  strings.forEach((s, i) => {
    out += s + (i < vals.length ? fmt(vals[i]) : '');
  });
  return new Raw(out);
}

export function mount(el, tpl) {
  el.innerHTML = fmt(tpl);
  return el;
}

export const $ = (sel, root = document) => root.querySelector(sel);
export const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

// Texte enrichi : #hashtags et @mentions cliquables (après échappement).
export function richText(text) {
  const safe = esc(text ?? '');
  return raw(
    safe
      .replace(/(^|[^\w&])#([\p{L}\p{N}_]{1,50})/gu, (m, pre, tag) => `${pre}<a class="tag" href="#/tag/${encodeURIComponent(tag.toLowerCase())}">#${tag}</a>`)
      .replace(/(^|[^\w])@([a-z0-9._]{3,30})/g, (m, pre, name) => `${pre}<a class="mention" href="#/u/${name}">@${name}</a>`)
  );
}

// --- Icônes au trait fin (2.4) ---
const P = {
  chats: '<path d="M4 5.5A2.5 2.5 0 0 1 6.5 3h11A2.5 2.5 0 0 1 20 5.5v8a2.5 2.5 0 0 1-2.5 2.5H9l-5 4V5.5z"/>',
  stories: '<circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="12" r="4.5"/>',
  camera: '<path d="M4 8.5A2.5 2.5 0 0 1 6.5 6h1.8l1.4-2h4.6l1.4 2h1.8A2.5 2.5 0 0 1 20 8.5v8a2.5 2.5 0 0 1-2.5 2.5h-11A2.5 2.5 0 0 1 4 16.5v-8z"/><circle cx="12" cy="12.5" r="3.5"/>',
  world: '<circle cx="12" cy="12" r="8.5"/><path d="M3.5 12h17M12 3.5c2.5 2.6 3.7 5.4 3.7 8.5s-1.2 5.9-3.7 8.5c-2.5-2.6-3.7-5.4-3.7-8.5S9.5 6.1 12 3.5z"/>',
  me: '<circle cx="12" cy="8.5" r="4"/><path d="M4.5 20c1.2-3.6 4-5.5 7.5-5.5s6.3 1.9 7.5 5.5"/>',
  search: '<circle cx="11" cy="11" r="6.5"/><path d="M16 16l4 4"/>',
  bell: '<path d="M6 16V11a6 6 0 1 1 12 0v5l1.5 2h-15L6 16z"/><path d="M10 20.5a2 2 0 0 0 4 0"/>',
  edit: '<path d="M4 20h4L19 9l-4-4L4 16v4z"/><path d="M13.5 6.5l4 4"/>',
  back: '<path d="M15 5l-7 7 7 7"/>',
  close: '<path d="M6 6l12 12M18 6L6 18"/>',
  more: '<circle cx="5.5" cy="12" r="1.2"/><circle cx="12" cy="12" r="1.2"/><circle cx="18.5" cy="12" r="1.2"/>',
  send: '<path d="M4 12l16-8-6 16-2.5-6.5L4 12z"/>',
  image: '<rect x="3.5" y="5" width="17" height="14" rx="2.5"/><circle cx="9" cy="10" r="1.8"/><path d="M20.5 16l-5-5-8 8"/>',
  heart: '<path d="M12 20s-7.5-4.6-7.5-10A4.3 4.3 0 0 1 12 7.4 4.3 4.3 0 0 1 19.5 10c0 5.4-7.5 10-7.5 10z"/>',
  comment: '<path d="M4 6.5A2.5 2.5 0 0 1 6.5 4h11A2.5 2.5 0 0 1 20 6.5v8a2.5 2.5 0 0 1-2.5 2.5H10l-4.5 3.5V17H6.5A2.5 2.5 0 0 1 4 14.5v-8z"/>',
  share: '<path d="M14 5l6 6-6 6M20 11H10a6 6 0 0 0-6 6v1"/>',
  bookmark: '<path d="M6.5 4h11v16l-5.5-4-5.5 4V4z"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  users: '<circle cx="9" cy="8.5" r="3.5"/><path d="M2.5 19c.9-3 3.4-4.8 6.5-4.8s5.6 1.8 6.5 4.8"/><path d="M15.5 5.2a3.5 3.5 0 0 1 0 6.6M17.5 14.5c2 .6 3.4 2.2 4 4.5"/>',
  star: '<path d="M12 3.8l2.5 5.2 5.7.8-4.1 4 1 5.6-5.1-2.7-5.1 2.7 1-5.6-4.1-4 5.7-.8L12 3.8z"/>',
  settings: '<circle cx="12" cy="12" r="3"/><path d="M19 12a7 7 0 0 0-.1-1.2l2-1.5-2-3.4-2.3.9a7 7 0 0 0-2-1.2L14.2 3h-4l-.4 2.6a7 7 0 0 0-2 1.2l-2.4-.9-2 3.4 2 1.5a7 7 0 0 0 0 2.4l-2 1.5 2 3.4 2.4-.9a7 7 0 0 0 2 1.2l.4 2.6h4l.4-2.6a7 7 0 0 0 2-1.2l2.3.9 2-3.4-2-1.5c.1-.4.1-.8.1-1.2z"/>',
  archive: '<rect x="3.5" y="4" width="17" height="4" rx="1"/><path d="M5 8v10.5A1.5 1.5 0 0 0 6.5 20h11a1.5 1.5 0 0 0 1.5-1.5V8M10 12h4"/>',
  userPlus: '<circle cx="10" cy="8.5" r="3.8"/><path d="M3 19.5c1-3.4 3.8-5.2 7-5.2 1.4 0 2.7.3 3.8 1M18 13v6M15 16h6"/>',
  lock: '<rect x="5" y="10.5" width="14" height="9.5" rx="2"/><path d="M8 10.5V8a4 4 0 0 1 8 0v2.5"/>',
  link: '<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>',
  flip: '<path d="M4 9a8 8 0 0 1 14-3l2 2M20 15a8 8 0 0 1-14 3l-2-2"/><path d="M20 4v4h-4M4 20v-4h4"/>',
  check: '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
  checks: '<path d="M2.5 12.5L7 17l9.5-9.5M11 16.5l.5.5L21 7.5"/>',
  logout: '<path d="M14 4h4.5A1.5 1.5 0 0 1 20 5.5v13a1.5 1.5 0 0 1-1.5 1.5H14M10 16l-4-4 4-4M6 12h10"/>',
  flag: '<path d="M5 21V4M5 4h11l-2 4 2 4H5"/>',
  block: '<circle cx="12" cy="12" r="8.5"/><path d="M6 6l12 12"/>',
  info: '<circle cx="12" cy="12" r="8.5"/><path d="M12 11v5M12 8h.01"/>',
  trash: '<path d="M4.5 7h15M9.5 7V4.5h5V7M6.5 7l1 13h9l1-13"/>',
  copy: '<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V5.5A1.5 1.5 0 0 0 14.5 4h-9A1.5 1.5 0 0 0 4 5.5v9A1.5 1.5 0 0 0 5.5 16H8"/>',
  reply: '<path d="M10 5L4 11l6 6M4 11h10a6 6 0 0 1 6 6v1"/>',
  eye: '<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z"/><circle cx="12" cy="12" r="3"/>',
  eyeOff: '<path d="M4 4l16 16M10 6c.6-.3 1.3-.5 2-.5 6 0 9.5 6.5 9.5 6.5a17 17 0 0 1-3 3.6M6.4 7.6A17 17 0 0 0 2.5 12S6 18.5 12 18.5c1.4 0 2.6-.3 3.7-.9"/>',
  play: '<path d="M8 5.5v13l10.5-6.5L8 5.5z" fill="currentColor"/>',
  pause: '<path d="M8 5.5v13M16 5.5v13" stroke-width="3"/>',
  mic: '<rect x="9" y="3.5" width="6" height="11" rx="3"/><path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v2.5"/>',
  micOff: '<path d="M4 4l16 16M9 9v2.5a3 3 0 0 0 5.1 2.1M15 10.5V6.5a3 3 0 0 0-5.8-1M5.5 11.5a6.5 6.5 0 0 0 10.4 5.2M18.5 11.5c0 .8-.1 1.5-.4 2.2M12 18v2.5"/>',
  phone: '<path d="M6.5 3.5h3l1.5 4-2 1.5a11 11 0 0 0 6 6l1.5-2 4 1.5v3a2 2 0 0 1-2 2A16 16 0 0 1 4.5 5.5a2 2 0 0 1 2-2z"/>',
  hangup: '<path d="M3 13.5c5-4.7 13-4.7 18 0l-2.2 2.6-3.6-1.4v-2.4a12 12 0 0 0-6.4 0v2.4l-3.6 1.4L3 13.5z" fill="currentColor"/>',
  video: '<rect x="3" y="6.5" width="12.5" height="11" rx="2.5"/><path d="M15.5 10.5l5-3v9l-5-3"/>',
  videoOff: '<path d="M4 4l16 16M8 6.5h5a2.5 2.5 0 0 1 2.5 2.5v5M15.5 17.5H5.5A2.5 2.5 0 0 1 3 15V9a2.5 2.5 0 0 1 1.5-2.3M15.5 10.5l5-3v9l-2-1.2"/>',
  minimize: '<path d="M9 4v5H4M15 20v-5h5M4 9l6-6M20 15l-6 6"/>',
  timer: '<circle cx="12" cy="13" r="7.5"/><path d="M12 9v4l2.5 2M9.5 3h5"/>',
  smile: '<path d="M4 10c2-1.7 4-2 5.3-1 1 .7 1.7.7 2.7 0 1-.7 1.7-.7 2.7 0 1.3-1 3.3-.7 5.3 1-1.7 4.7-4.7 7.3-8 7.3S5.7 14.7 4 10z"/>',
};

export function icon(name, extra = '') {
  return raw(
    `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" ${extra}>${P[name] || ''}</svg>`
  );
}

export function logo(size = 40) {
  return raw(`<svg class="logo" width="${size}" height="${size}" viewBox="0 0 64 64" fill="none" stroke-linecap="round" stroke-linejoin="round" role="img" aria-label="MIC">
    <path d="M8 26c6-5 12-6 16-3 3 2 5 2 8 0 3-2 5-2 8 0 4-3 10-2 16 3-5 14-14 22-24 22S13 40 8 26z" stroke="var(--me)" stroke-width="3.5"/>
    <path d="M15 29c9 8 25 8 34 0" stroke="var(--world)" stroke-width="3"/></svg>`);
}

// --- Avatars ---
export function initials(name) {
  return (
    (name || '?')
      .trim()
      .split(/\s+/)
      .slice(0, 2)
      .map((w) => [...w][0] || '')
      .join('')
      .toUpperCase() || '?'
  );
}

export function avatar(user, size = '') {
  const cls = `avatar ${size}`;
  const inner = user?.avatar ? html`<img src="${user.avatar}" alt="" loading="lazy" />` : initials(user?.name);
  const dot = user?.online ? raw('<span class="online" aria-label="online"></span>') : '';
  return html`<span class="avatar-wrap"><span class="${cls}">${inner}</span>${dot}</span>`;
}

// --- Toast, dialogues, feuilles ---
let toastTimer;
export function toast(message) {
  document.querySelector('.toast')?.remove();
  const el = document.createElement('div');
  el.className = 'toast';
  el.setAttribute('role', 'status');
  el.textContent = message;
  document.body.appendChild(el);
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.remove(), 2600);
}

export function errorText(err) {
  const key = `err.${err?.code || 'generic'}`;
  const msg = t(key);
  return msg === key ? t('err.generic') : msg;
}

export function showError(err) {
  toast(errorText(err));
}

export function dialog({ title, body = '', confirm = t('common.confirm'), cancel = t('common.cancel'), danger = false, input = null }) {
  return new Promise((resolve) => {
    const el = document.createElement('div');
    el.className = 'dialog';
    el.setAttribute('role', 'dialog');
    el.setAttribute('aria-modal', 'true');
    mount(
      el,
      html`<div class="box">
        <h3>${title}</h3>
        ${body ? html`<p class="muted">${body}</p>` : ''}
        ${input ? html`<input class="input" data-input type="${input.type || 'text'}" placeholder="${input.placeholder || ''}" value="${input.value || ''}" ${input.type === 'password' ? 'autocomplete="current-password"' : ''} />` : ''}
        <div class="buttons">
          ${cancel ? html`<button class="btn ghost" data-no>${cancel}</button>` : ''}
          <button class="btn ${danger ? 'danger' : ''}" data-yes>${confirm}</button>
        </div>
      </div>`
    );
    const done = (v) => {
      el.remove();
      document.removeEventListener('keydown', onKey);
      resolve(v);
    };
    const onKey = (e) => e.key === 'Escape' && done(input ? null : false);
    document.addEventListener('keydown', onKey);
    el.addEventListener('click', (e) => e.target === el && done(input ? null : false));
    $('[data-no]', el)?.addEventListener('click', () => done(input ? null : false));
    $('[data-yes]', el).addEventListener('click', () => done(input ? $('[data-input]', el).value : true));
    document.body.appendChild(el);
    ($('[data-input]', el) || $('[data-yes]', el)).focus();
  });
}

// Feuille modale montante. `render(sheetEl, close)` remplit le contenu.
export function sheet(render, { onClose } = {}) {
  const overlay = document.createElement('div');
  overlay.className = 'overlay';
  const box = document.createElement('div');
  box.className = 'sheet';
  box.setAttribute('role', 'dialog');
  box.setAttribute('aria-modal', 'true');
  overlay.appendChild(box);
  let closed = false;
  const close = (value) => {
    if (closed) return;
    closed = true;
    overlay.remove();
    document.removeEventListener('keydown', onKey);
    onClose?.(value);
  };
  const onKey = (e) => e.key === 'Escape' && close();
  document.addEventListener('keydown', onKey);
  overlay.addEventListener('click', (e) => e.target === overlay && close());
  document.body.appendChild(overlay);
  render(box, close);
  return close;
}

// Menu d'actions simple : [{ label, icon, danger, run }]
export function actionSheet(items, { title, header } = {}) {
  return sheet((box, close) => {
    mount(
      box,
      html`<div class="grabber"></div>
        ${title ? html`<h2>${title}</h2>` : ''} ${header || ''}
        ${items.map(
          (it, i) => html`<button class="action ${it.danger ? 'danger' : ''}" data-i="${i}">${it.icon ? icon(it.icon) : ''}<span>${it.label}</span></button>`
        )}`
    );
    $$('[data-i]', box).forEach((b) =>
      b.addEventListener('click', () => {
        close();
        items[Number(b.dataset.i)].run();
      })
    );
  });
}

// Signalement (22.2).
const REASONS = ['harassment', 'violence', 'nudity', 'scam', 'impersonation', 'hate', 'false_info', 'spam', 'minor_safety', 'self_harm', 'other'];
export function reportFlow(targetType, targetId) {
  actionSheet(
    REASONS.map((r) => ({
      label: t(`report.${r}`),
      run: async () => {
        try {
          await post('/reports', { targetType, targetId, reason: r });
          toast(t('report.thanks'));
        } catch (err) {
          showError(err);
        }
      },
    })),
    {
      title: t('report.title'),
      header: html`<p class="muted small" style="margin:0 16px 8px">${t('report.lead')}${targetType === 'message' ? html`<br /><b>${t('report.messageNote')}</b>` : ''}</p>`,
    }
  );
}

export function empty(title, lead = '', action = '') {
  return html`<div class="empty">
    <svg class="art" viewBox="0 0 64 64" fill="none" stroke-linecap="round" stroke-linejoin="round">
      <path d="M8 26c6-5 12-6 16-3 3 2 5 2 8 0 3-2 5-2 8 0 4-3 10-2 16 3-5 14-14 22-24 22S13 40 8 26z" stroke="var(--line)" stroke-width="2.5"/>
      <path d="M15 29c9 8 25 8 34 0" stroke="var(--accent)" stroke-width="2.5"/></svg>
    <h3>${title}</h3>
    ${lead ? html`<p>${lead}</p>` : ''} ${action}
  </div>`;
}

export function skeleton(n = 5) {
  return html`<div class="skeleton" aria-label="${t('common.loading')}">${Array.from({ length: n }, () => raw('<div></div>'))}</div>`;
}

export function debounce(fn, ms = 250) {
  let timer;
  return (...args) => {
    clearTimeout(timer);
    timer = setTimeout(() => fn(...args), ms);
  };
}
