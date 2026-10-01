// Section 12 : stories Me (amis, proches) et World, visibles 24 h.
import { t, relTime } from '../i18n.js';
import { store, get, post, del, on } from '../api.js';
import { html, mount, $, $$, icon, avatar, empty, skeleton, sheet, dialog, showError, reportFlow } from '../ui.js';
import { layout } from '../app.js';
import { channelsRail } from './channels.js';

const DURATION = 5000;

function ring(group, label) {
  const cls = group.universe === 'world' ? 'world' : group.closeFriends ? 'close' : '';
  return html`<button class="story-bubble" data-author="${group.universe}:${group.author.id}">
    <span class="ring ${cls} ${group.allSeen ? 'seen' : ''}">${avatar({ ...group.author, online: false })}</span>
    <span>${label || group.author.name}</span>
  </button>`;
}

export async function storiesScreen(root) {
  const main = layout(root, {
    universe: 'me',
    title: t('nav.stories'),
    tab: 'stories',
    right: html`<a class="icon-btn" href="#/create/text" aria-label="${t('stories.add')}">${icon('plus')}</a>`,
  });
  mount(main, skeleton(3));
  let data;

  const draw = () => {
    const mine = data.mine;
    const me = { id: store.me.id, name: store.me.displayName, avatar: store.me.avatar };
    mount(
      main,
      html`<div class="section-title">${t('stories.friends')}</div>
        <div class="story-rail">
          ${mine.length
            ? mine.map((g) => ring(g, g.universe === 'world' ? `${t('stories.my')} · World` : t('stories.my')))
            : html`<a class="story-bubble" href="#/create/text"><span class="ring add">${avatar(me)}</span><span>${t('stories.add')}</span></a>`}
          ${data.friends.map((g) => ring(g))}
        </div>
        ${!data.friends.length ? html`<p class="muted small" style="padding:0 16px">${t('stories.emptyLead')}</p>` : ''}
        ${data.world.length
          ? html`<div class="section-title" style="color:var(--world)">${t('stories.fromWorld')}</div><div class="story-rail">${data.world.map((g) => ring(g))}</div>`
          : ''}
        ${channelsRail(data.channels || [])}
        ${!mine.length && !data.friends.length && !data.world.length && !(data.channels || []).length ? empty(t('stories.empty'), '', html`<a class="btn" href="#/create/text">${t('stories.add')}</a>`) : ''}
        <div class="menu-group" style="margin-top:24px">
          <a class="list-item" href="#/archive">${icon('archive')}<span class="grow">${t('stories.archive')}</span></a>
        </div>`
    );
    const all = [...data.mine, ...data.friends, ...data.world];
    $$('[data-author]', main).forEach((b) =>
      b.addEventListener('click', () => {
        const idx = all.findIndex((g) => `${g.universe}:${g.author.id}` === b.dataset.author);
        openViewer(all, idx, load);
      })
    );
  };

  const load = async () => {
    try {
      const [stories, channels] = await Promise.all([get('/stories'), get('/channels').catch(() => [])]);
      data = { ...stories, channels };
      draw();
    } catch (err) {
      showError(err);
    }
  };
  await load();
  const off = on('stories:changed', load);
  return off;
}

// Lecteur plein écran : barre de progression, appui gauche/droite, pause.
export function openViewer(groups, startGroup, onClose) {
  let gi = startGroup;
  let si = Math.max(0, groups[gi].stories.findIndex((s) => !s.seen));
  let start = 0;
  let elapsed = 0;
  let raf = null;
  let paused = false;

  const el = document.createElement('div');
  el.className = 'viewer';
  el.setAttribute('role', 'dialog');
  el.setAttribute('aria-modal', 'true');
  document.body.appendChild(el);

  const close = () => {
    cancelAnimationFrame(raf);
    el.remove();
    document.removeEventListener('keydown', onKey);
    onClose?.();
  };
  const onKey = (e) => {
    if (e.key === 'Escape') close();
    if (e.key === 'ArrowRight') next();
    if (e.key === 'ArrowLeft') prev();
  };
  document.addEventListener('keydown', onKey);

  const next = () => {
    const g = groups[gi];
    if (si < g.stories.length - 1) si++;
    else if (gi < groups.length - 1) {
      gi++;
      si = 0;
    } else return close();
    show();
  };
  const prev = () => {
    if (si > 0) si--;
    else if (gi > 0) {
      gi--;
      si = groups[gi].stories.length - 1;
    }
    show();
  };

  const tick = (now) => {
    if (!start) start = now - elapsed;
    if (!paused) elapsed = now - start;
    else start = now - elapsed;
    const bar = $('[data-current] i', el);
    if (bar) bar.style.width = Math.min(100, (elapsed / DURATION) * 100) + '%';
    if (elapsed >= DURATION) return next();
    raf = requestAnimationFrame(tick);
  };

  const show = () => {
    cancelAnimationFrame(raf);
    start = 0;
    elapsed = 0;
    const g = groups[gi];
    const s = g.stories[si];
    const mine = g.author.id === store.me.id;
    mount(
      el,
      html`<div class="stage ${s.kind === 'text' ? 'bg-' + (s.bg || 'espresso') : ''}">
        <div class="bars">${g.stories.map((x, i) => html`<div ${i === si ? 'data-current' : ''}><i style="width:${i < si ? '100%' : '0'}"></i></div>`)}</div>
        <div class="head">
          ${avatar(g.author, 'xs')}
          <b>${mine ? t('stories.my') : g.author.name}</b>
          <span style="opacity:.8;font-size:13px">${relTime(s.createdAt)} · ${t(`stories.audience.${s.audience}`)}</span>
          <span class="grow"></span>
          ${mine ? '' : html`<button class="icon-btn" data-report aria-label="${t('chat.report')}">${icon('flag')}</button>`}
          <button class="icon-btn" data-close aria-label="${t('common.close')}">${icon('close')}</button>
        </div>
        ${s.kind === 'image' ? html`<img src="${s.media}" alt="" />` : html`<div class="text-story">${s.body}</div>`}
        <div class="nav prev" data-prev></div><div class="nav next" data-next></div>
        ${mine
          ? html`<div class="foot"><button class="btn small ghost" style="color:#fff;border-color:rgba(255,255,255,.4)" data-viewers>${icon('eye', 'width="16" height="16"')} ${t('stories.views', { count: s.views ?? 0 })}</button>
              <button class="btn small ghost" style="color:#fff;border-color:rgba(255,255,255,.4)" data-delete>${icon('trash', 'width="16" height="16"')}</button></div>`
          : ''}
      </div>`
    );
    $('[data-close]', el).addEventListener('click', close);
    $('[data-next]', el).addEventListener('click', next);
    $('[data-prev]', el).addEventListener('click', prev);
    // Appui long = pause.
    const stage = $('.stage', el);
    stage.addEventListener('pointerdown', () => (paused = true));
    stage.addEventListener('pointerup', () => (paused = false));
    stage.addEventListener('pointerleave', () => (paused = false));
    $('[data-report]', el)?.addEventListener('click', (e) => {
      e.stopPropagation();
      paused = true;
      reportFlow('story', s.id);
    });
    $('[data-viewers]', el)?.addEventListener('click', async (e) => {
      e.stopPropagation();
      paused = true;
      const viewers = await get(`/stories/${s.id}/viewers`).catch(() => []);
      sheet(
        (box) =>
          mount(
            box,
            html`<div class="grabber"></div><h2>${t('stories.viewers')}</h2>
              ${viewers.length
                ? html`<ul class="list">${viewers.map((v) => html`<li class="list-item">${avatar(v.user, 'sm')}<span class="grow title">${v.user.name}</span><span class="small muted">${relTime(v.viewedAt)}</span></li>`)}</ul>`
                : empty(t('stories.noViewers'))}`
          ),
        { onClose: () => (paused = false) }
      );
    });
    $('[data-delete]', el)?.addEventListener('click', async (e) => {
      e.stopPropagation();
      paused = true;
      if (!(await dialog({ title: t('stories.delete'), confirm: t('me.delete'), danger: true }))) return (paused = false);
      await del(`/stories/${s.id}`).catch(showError);
      g.stories.splice(si, 1);
      if (!g.stories.length) {
        groups.splice(gi, 1);
        if (!groups.length) return close();
        gi = Math.min(gi, groups.length - 1);
        si = 0;
      } else si = Math.min(si, g.stories.length - 1);
      show();
    });
    if (!s.seen && !mine) {
      s.seen = true;
      post(`/stories/${s.id}/view`).catch(() => {});
    }
    g.allSeen = g.stories.every((x) => x.seen);
    raf = requestAnimationFrame(tick);
  };
  show();
}
