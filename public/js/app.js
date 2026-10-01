// Point d'entrée : routeur, coquille (barre supérieure + barre de navigation) et état global.
import { t } from './i18n.js';
import { store, getToken, setToken, get, on, connect, disconnect } from './api.js';
import { html, mount, icon, $, $$, toast } from './ui.js';
import { welcomeScreen, authScreen } from './screens/auth.js';
import { chatsScreen, chatScreen, newChatScreen, newGroupScreen, callsScreen } from './screens/chats.js';
import { initCalls, hangUp } from './calls.js';
import { flush as flushOutbox, clearOutbox } from './outbox.js';
import { applyDataSaver } from './datasaver.js';
import { myReportsScreen, accountStatusScreen, moderationScreen } from './screens/safety.js';
import { channelScreen, newChannelScreen, broadcastsScreen, broadcastScreen } from './screens/channels.js';
import { communitiesScreen, newCommunityScreen, communityScreen, eventsScreen, eventScreen, newEventScreen } from './screens/communities.js';
import './voice.js';
import { storiesScreen } from './screens/stories.js';
import { createScreen } from './screens/create.js';
import { worldScreen, postScreen, tagScreen, searchScreen, clipsScreen } from './screens/world.js';
import { meScreen, profileScreen, requestsScreen, friendsScreen, savedScreen, archiveScreen, settingsScreen, editProfileScreen, notificationsScreen } from './screens/me.js';

const app = document.getElementById('app');

const ROUTES = [
  ['welcome', welcomeScreen, { public: true }],
  ['auth/:mode', authScreen, { public: true }],
  ['chats', chatsScreen],
  ['chats/:filter', chatsScreen],
  ['chat/:id', chatScreen],
  ['calls', callsScreen],
  ['calls/:filter', callsScreen],
  ['new-chat', newChatScreen],
  ['new-group', newGroupScreen],
  ['stories', storiesScreen],
  ['create', createScreen],
  ['create/:mode', createScreen],
  ['world', worldScreen],
  ['world/:feed', worldScreen],
  ['clips', clipsScreen],
  ['post/:id', postScreen],
  ['tag/:tag', tagScreen],
  ['search', searchScreen],
  ['me', meScreen],
  ['u/:username', profileScreen],
  ['requests', requestsScreen],
  ['friends', friendsScreen],
  ['saved', savedScreen],
  ['archive', archiveScreen],
  ['settings', settingsScreen],
  ['edit-profile', editProfileScreen],
  ['notifications', notificationsScreen],
  ['communities', communitiesScreen],
  ['new-community', newCommunityScreen],
  ['community/:handle', communityScreen],
  ['community/:handle/:tab', communityScreen],
  ['events', eventsScreen],
  ['event/:id', eventScreen],
  ['new-event', newEventScreen],
  ['new-event/:communityId', newEventScreen],
  ['channel/:handle', channelScreen],
  ['channel/:handle/:code', channelScreen],
  ['new-channel', newChannelScreen],
  ['broadcasts', broadcastsScreen],
  ['broadcast/:id', broadcastScreen],
  ['my-reports', myReportsScreen],
  ['account-status', accountStatusScreen],
  ['moderation', moderationScreen],
  ['moderation/:tab', moderationScreen],
];

function match(path) {
  const parts = path.split('/').filter(Boolean);
  for (const [pattern, screen, opts = {}] of ROUTES) {
    const pp = pattern.split('/');
    if (pp.length !== parts.length) continue;
    const params = {};
    if (pp.every((p, i) => (p.startsWith(':') ? ((params[p.slice(1)] = decodeURIComponent(parts[i])), true) : p === parts[i]))) {
      return { screen, params, opts };
    }
  }
  return null;
}

export function go(path) {
  location.hash = '#/' + path.replace(/^#?\//, '');
}

let cleanup = null;
let renderSeq = 0;

async function render() {
  const path = location.hash.replace(/^#\/?/, '');
  const m = match(path);
  if (!m) return go(getToken() ? 'chats' : 'welcome');
  if (!m.opts.public && !store.me) return go('welcome');
  if (m.opts.public && store.me) return go('chats');
  const seq = ++renderSeq;
  if (typeof cleanup === 'function') cleanup();
  cleanup = null;
  window.scrollTo(0, 0);
  try {
    const c = await m.screen(app, m.params);
    if (seq === renderSeq) cleanup = c;
    else if (typeof c === 'function') c();
  } catch (err) {
    console.error(err);
    toast(t('err.generic'));
  }
}

// --- Coquille commune ---
const TABS = [
  ['chats', 'chats', 'nav.chats', 'me'],
  ['stories', 'stories', 'nav.stories', 'me'],
  ['create', 'camera', 'nav.camera', 'camera'],
  ['world', 'world', 'nav.world', 'world'],
  ['me', 'me', 'nav.me', 'me'],
];

export function setUniverse(u) {
  document.body.dataset.universe = u;
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content', u === 'world' ? '#1F6B4F' : '#3B2418');
}

// layout({ universe, title, sub, left, right, tab, flush }) → <main>
export function layout(root, { universe = 'me', title = '', sub = '', left = '', right = '', tab = null, flush = false, topbar = true }) {
  setUniverse(universe);
  mount(
    root,
    html`${topbar
        ? html`<header class="topbar">
            ${left}
            <h1>${title}${sub ? html`<span class="sub">${sub}</span>` : ''}</h1>
            ${right}
          </header>`
        : ''}
      <main class="${flush ? 'flush' : ''}"></main>
      ${tab
        ? html`<nav class="tabbar" aria-label="MIC">
            ${TABS.map(
              ([path, ic, label]) => html`<a class="tab ${path === 'create' ? 'tab-camera' : ''} ${tab === path ? 'active' : ''}" href="#/${path}" aria-label="${t(label)}">
                ${path === 'create' ? html`<span class="lens">${icon('camera')}</span>` : icon(ic)}
                ${path === 'create' ? '' : html`<span>${t(label)}</span>`}
                ${path === 'chats' ? html`<span class="dot" data-unread hidden></span>` : ''}
              </a>`
            )}
          </nav>`
        : ''}`
  );
  if (tab) refreshBadges();
  return $('main', root);
}

export function backButton(fallback = 'chats') {
  return html`<button class="icon-btn" data-back aria-label="${t('common.back')}">${icon('back')}</button>`;
}

export function wireBack(root, fallback = 'chats') {
  $$('[data-back]', root).forEach((b) =>
    b.addEventListener('click', () => {
      if (history.length > 1) history.back();
      else go(fallback);
    })
  );
}

// Compteur de discussions non lues sur l'onglet Chats.
export async function refreshBadges() {
  if (!store.me) return;
  try {
    const convs = await get('/conversations');
    const unread = convs.filter((c) => c.status === 'active').reduce((n, c) => n + c.unread, 0);
    $$('[data-unread]').forEach((el) => {
      el.hidden = !unread;
      el.textContent = unread > 99 ? '99+' : unread;
    });
  } catch {
    /* hors ligne */
  }
}

// --- Démarrage ---
async function boot() {
  if (!navigator.onLine) setTimeout(() => setOffline(true), 0);
  if (getToken()) {
    try {
      store.me = await get('/me');
      connect();
    } catch (err) {
      if (err.status === 401) setToken(null);
    }
  }
  window.addEventListener('hashchange', render);
  render();
}

export async function signedIn(token, me) {
  setToken(token);
  store.me = me;
  connect();
  go('chats');
}

export function signOut() {
  hangUp();
  clearOutbox();
  navigator.serviceWorker?.controller?.postMessage('clear-user-data');
  disconnect();
  setToken(null);
  store.me = null;
  go('welcome');
}

on('logout', () => signOut());
on('banned', () => {
  toast(t('err.account_banned'));
  signOut();
});
on('suspended', () => location.hash !== '#/account-status' && go('account-status'));
initCalls();
on('message', () => refreshBadges());
on('receipts', () => refreshBadges());
on('notification', () => $$('[data-notif-dot]').forEach((el) => (el.hidden = false)));

// Bandeau hors ligne (7.9).
let offlineEl = null;
function setOffline(off) {
  if (off && !offlineEl) {
    offlineEl = document.createElement('div');
    offlineEl.className = 'offline';
    offlineEl.textContent = t('common.offline');
    document.body.appendChild(offlineEl);
  } else if (!off && offlineEl) {
    offlineEl.remove();
    offlineEl = null;
  }
}
window.addEventListener('offline', () => setOffline(true));
window.addEventListener('online', () => {
  setOffline(false);
  connect();
});

// Thème mémorisé (préférence locale).
try {
  const theme = localStorage.getItem('mic.theme');
  if (theme) document.documentElement.dataset.theme = theme;
} catch {
  /* ignore */
}

// Application installable et hors ligne (26.4).
if ('serviceWorker' in navigator && (location.protocol === 'https:' || location.hostname === 'localhost' || location.hostname === '127.0.0.1')) {
  window.addEventListener('load', () => navigator.serviceWorker.register('/sw.js').catch(() => {}));
}
applyDataSaver();
boot().then(() => store.me && flushOutbox());
