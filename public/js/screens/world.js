// Sections 14 (World), 16 (interactions), 17 (recherche, hashtags, tendances, recommandation).
import { t, compact, relTime } from '../i18n.js';
import { store, get, post, patch, del } from '../api.js';
import { html, raw, mount, $, $$, icon, avatar, richText, toast, showError, dialog, sheet, actionSheet, reportFlow, empty, skeleton, debounce } from '../ui.js';
import { layout, go, backButton, wireBack } from '../app.js';
import { ensureWorld } from './create.js';

const AUD_ICON = { everyone: '🌍', followers: '👥', friends: '🤝', only_me: '🔒' };

// ---------------- Carte de publication ----------------
function fmtDur(ms) {
  const s = Math.round((ms || 0) / 1000);
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}

// Lecture automatique des clips visibles (muets par défaut, 14.9 et 26.3),
// et une vue comptée après 2 secondes de lecture.
const viewed = new Set();
let clipObserver = null;
export function watchClips(container) {
  // Mode économie de données : pas de lecture automatique (26.3).
  if (document.documentElement.dataset.datasaver === 'on') {
    $$('video[data-clip-video]', container).forEach((v) => (v.preload = 'none'));
    return;
  }
  clipObserver ??= new IntersectionObserver(
    (entries) => {
      for (const e of entries) {
        const v = e.target;
        if (e.isIntersecting && e.intersectionRatio >= 0.6) {
          v.play().catch(() => {});
          const id = Number(v.dataset.clipVideo);
          if (!viewed.has(id)) {
            clearTimeout(v._viewTimer);
            v._viewTimer = setTimeout(() => {
              if (!v.paused && !viewed.has(id)) {
                viewed.add(id);
                post(`/posts/${id}/view`).catch(() => {});
              }
            }, 2000);
          }
        } else {
          v.pause();
          clearTimeout(v._viewTimer);
        }
      }
    },
    { threshold: [0, 0.6] }
  );
  $$('video[data-clip-video]', container).forEach((v) => clipObserver.observe(v));
}

export function postCardHtml(p) {
  return html`<article class="post" data-post="${p.id}">
    <div class="post-head">
      <a href="#/u/${p.author.username}">${avatar(p.author, 'sm')}</a>
      <div class="who">
        <a href="#/u/${p.author.username}" style="color:inherit"><span class="name">${p.author.name}</span></a>
        <div class="handle">@${p.author.username} · ${relTime(p.createdAt)} · <span title="${t(`aud.${p.audience}`)}">${AUD_ICON[p.audience]}</span>${p.editedAt ? html` · ${t('world.edited')}` : ''}</div>
      </div>
      <button class="icon-btn" data-act="menu" aria-label="${t('common.more')}">${icon('more')}</button>
    </div>
    ${p.body ? html`<div class="post-body">${richText(p.body)}</div>` : ''}
    ${p.kind === 'clip'
      ? html`<div class="post-media clip-media" data-act="media">
          <video data-clip-video="${p.id}" src="${p.video}" ${p.media ? raw(`poster="${p.media}"`) : ''} muted loop playsinline preload="metadata" ${p.allowDownload ? '' : raw('controlslist="nodownload"')}></video>
          <span class="clip-badge">${icon('video', 'width="14" height="14"')} ${fmtDur(p.duration)} · ${t('clip.views', { count: compact(p.views || 0) })}</span>
          <button class="clip-sound" data-act="sound" aria-label="${t('clip.sound')}">🔇</button>
        </div>`
      : p.media
        ? html`<div class="post-media" data-act="media"><img src="${p.media}" alt="" loading="lazy" /></div>`
        : ''}
    <div class="post-actions">
      <button data-act="like" class="${p.liked ? 'liked' : ''}" aria-pressed="${p.liked}" aria-label="${t('world.like')}">${icon('heart', p.liked ? 'fill="currentColor"' : '')}<span>${p.likes == null ? '' : compact(p.likes)}</span></button>
      <a href="#/post/${p.id}" class="btn-like" style="display:inline-flex;align-items:center;gap:6px;padding:6px 8px;color:var(--muted);font-size:13px" aria-label="${t('world.comment')}">${icon('comment', 'width="20" height="20"')}<span>${compact(p.comments)}</span></a>
      <button data-act="share" aria-label="${t('world.share')}">${icon('share')}<span>${p.shares ? compact(p.shares) : ''}</span></button>
      <span class="spacer"></span>
      <button data-act="save" class="${p.saved ? 'on' : ''}" aria-pressed="${p.saved}" aria-label="${t('world.save')}">${icon('bookmark', p.saved ? 'fill="currentColor"' : '')}</button>
    </div>
  </article>`;
}

// Branche les interactions sur une liste de cartes. `posts` est muté en place.
export function wirePosts(container, posts, { onRemove } = {}) {
  const find = (el) => posts.find((p) => p.id === Number(el.closest('[data-post]')?.dataset.post));
  const redraw = (p) => {
    const old = container.querySelector(`[data-post="${p.id}"]`);
    if (!old) return;
    const tmp = document.createElement('div');
    mount(tmp, postCardHtml(p));
    const fresh = tmp.firstElementChild;
    old.replaceWith(fresh);
    watchClips(fresh);
  };
  watchClips(container);
  const like = async (p, burstEl) => {
    try {
      const fresh = p.liked ? await del(`/posts/${p.id}/like`) : await post(`/posts/${p.id}/like`);
      Object.assign(p, fresh);
      redraw(p);
      if (burstEl && p.liked) burst(container.querySelector(`[data-post="${p.id}"] .post-media`));
    } catch (err) {
      showError(err);
    }
  };
  container.addEventListener('click', async (e) => {
    const btn = e.target.closest('[data-act]');
    if (!btn) return;
    const p = find(btn);
    if (!p) return;
    const act = btn.dataset.act;
    if (act === 'like') like(p);
    if (act === 'save') {
      try {
        if (p.saved) {
          await del(`/posts/${p.id}/save`);
          p.saved = false;
        } else Object.assign(p, await post(`/posts/${p.id}/save`));
        redraw(p);
        toast(p.saved ? t('world.saved') : t('common.done'));
      } catch (err) {
        showError(err);
      }
    }
    if (act === 'share') shareSheet(p);
    if (act === 'sound') {
      const v = btn.closest('.clip-media')?.querySelector('video');
      if (v) {
        v.muted = !v.muted;
        btn.textContent = v.muted ? '🔇' : '🔊';
        if (v.paused) v.play().catch(() => {});
      }
    }
    if (act === 'menu') postMenu(p, { redraw, remove: () => (container.querySelector(`[data-post="${p.id}"]`)?.remove(), onRemove?.(p)) });
  });
  // Double appui sur la photo = j'aime, avec l'animation du sourire MIC (16.1).
  container.addEventListener('dblclick', (e) => {
    const media = e.target.closest('[data-act="media"]');
    if (!media) return;
    const p = find(media);
    if (p && !p.liked) like(p, true);
    else if (p) burst(media);
  });
}

function burst(el) {
  if (!el) return;
  const b = document.createElement('div');
  b.className = 'like-burst';
  mount(
    b,
    raw(`<svg viewBox="0 0 64 64" fill="none" stroke-linecap="round" stroke-linejoin="round"><path d="M8 26c6-5 12-6 16-3 3 2 5 2 8 0 3-2 5-2 8 0 4-3 10-2 16 3-5 14-14 22-24 22S13 40 8 26z" fill="#FAF7F2" stroke="#3B2418" stroke-width="3"/><path d="M15 29c9 8 25 8 34 0" stroke="#1F6B4F" stroke-width="3"/></svg>`)
  );
  el.appendChild(b);
  setTimeout(() => b.remove(), 750);
}

// Partage World → Me : vers une discussion (4.4, 14.5).
export async function shareSheet(p) {
  const convs = (await get('/conversations').catch(() => [])).filter((c) => c.status === 'active' && !c.blocked);
  const chosen = new Set();
  sheet((box, close) => {
    mount(
      box,
      html`<div class="grabber"></div><h2>${t('world.share')}</h2>
        <button class="action" data-copy>${icon('link')}<span>${t('world.copyLink')}</span></button>
        <div class="section-title">${t('world.sendTo')}</div>
        ${convs.length
          ? html`<ul class="list">${convs.map(
              (c) => html`<li><label class="list-item">${c.type === 'direct' ? avatar(c.peer, 'sm') : avatar({ name: c.title }, 'sm')}<span class="grow title">${c.type === 'direct' ? c.peer?.name : c.title}</span><input type="checkbox" value="${c.id}" /></label></li>`
            )}</ul>`
          : html`<p class="muted center small">${t('share.noChats')}</p>`}
        <div class="sheet-actions"><button class="btn me block" data-send disabled>${t('share.send')}</button></div>`
    );
    $('[data-copy]', box).addEventListener('click', () => {
      navigator.clipboard?.writeText(`${location.origin}/#/post/${p.id}`);
      toast(t('world.linkCopied'));
      close();
    });
    const send = $('[data-send]', box);
    $$('input[type="checkbox"]', box).forEach((cb) =>
      cb.addEventListener('change', () => {
        if (cb.checked && chosen.size >= 5) return (cb.checked = false);
        cb.checked ? chosen.add(Number(cb.value)) : chosen.delete(Number(cb.value));
        send.disabled = !chosen.size;
      })
    );
    send.addEventListener('click', async () => {
      try {
        await post(`/posts/${p.id}/share`, { conversationIds: [...chosen] });
        p.shares++;
        toast(t('share.done'));
        close();
      } catch (err) {
        showError(err);
      }
    });
  });
}

function whySheet(p) {
  get(`/posts/${p.id}/why`)
    .then(({ reasons }) =>
      sheet((box) =>
        mount(
          box,
          html`<div class="grabber"></div><h2>${t('world.why')}</h2>
            <p class="muted" style="margin:0 16px 12px">${t('world.whyLead')}</p>
            <ul class="list">${reasons.map(
              (r) => html`<li class="list-item">${icon(r.type === 'hashtag' ? 'search' : r.type === 'following' || r.type === 'friend' ? 'users' : 'star')}<span>${t(`world.reason.${r.type}`, { tags: (r.tags || []).map((x) => '#' + x).join(', ') })}</span></li>`
            )}</ul>`
        )
      )
    )
    .catch(showError);
}

function postMenu(p, { redraw, remove }) {
  const items = [{ label: t('world.why'), icon: 'info', run: () => whySheet(p) }];
  // « Allow download » (14.4) : proposé seulement si l'auteur l'autorise.
  if (p.kind === 'clip' && (p.allowDownload || p.mine)) {
    items.push({
      label: t('clip.download'),
      icon: 'archive',
      run: () => {
        const a = document.createElement('a');
        a.href = p.video;
        a.download = `mic-clip-${p.id}`;
        a.click();
      },
    });
  }
  if (p.mine) {
    items.push({ label: t('world.editPost'), icon: 'edit', run: () => editPost(p, redraw) });
    items.push({
      label: t('world.deletePost'),
      icon: 'trash',
      danger: true,
      run: async () => {
        if (!(await dialog({ title: t('world.deletePost'), confirm: t('me.delete'), danger: true }))) return;
        try {
          await del(`/posts/${p.id}`);
          remove();
        } catch (err) {
          showError(err);
        }
      },
    });
  } else {
    items.push({
      label: t('world.notInterested'),
      icon: 'eyeOff',
      run: async () => {
        await post(`/posts/${p.id}/not-interested`).catch(showError);
        remove();
      },
    });
    items.push({ label: t('chat.report'), icon: 'flag', danger: true, run: () => reportFlow('post', p.id) });
  }
  actionSheet(items);
}

// Réglages par publication modifiables après coup (14.4).
function editPost(p, redraw) {
  sheet((box, close) => {
    const sel = (key, opts, value) => html`<select class="input" data-k="${key}">${opts.map((o) => html`<option value="${o}" ${o === value ? 'selected' : ''}>${t(`aud.${o}`)}</option>`)}</select>`;
    mount(
      box,
      html`<div class="grabber"></div><h2>${t('world.editPost')}</h2>
        <div class="section" style="padding-top:0">
          <div class="field"><textarea class="input" data-body maxlength="5000">${p.body}</textarea></div>
          <div class="field"><label>${t('share.whoView')}</label>${sel('audience', ['everyone', 'followers', 'friends', 'only_me'], p.audience)}</div>
          <div class="field"><label>${t('share.whoComment')}</label>${sel('whoCanComment', ['everyone', 'followers', 'friends', 'nobody'], p.whoCanComment)}</div>
          <label class="row" style="margin-bottom:16px"><span class="grow">${t('share.hideLikes')}</span><input type="checkbox" class="toggle" data-hide ${p.hideLikes ? 'checked' : ''} /></label>
          <button class="btn world block" data-save>${t('edit.save')}</button>
        </div>`
    );
    $('[data-save]', box).addEventListener('click', async () => {
      try {
        const fresh = await patch(`/posts/${p.id}`, {
          body: $('[data-body]', box).value,
          audience: $('[data-k="audience"]', box).value,
          whoCanComment: $('[data-k="whoCanComment"]', box).value,
          hideLikes: $('[data-hide]', box).checked,
        });
        Object.assign(p, fresh);
        redraw(p);
        close();
      } catch (err) {
        showError(err);
      }
    });
  });
}

export function renderPosts(container, posts, emptyTpl) {
  mount(container, posts.length ? html`${posts.map(postCardHtml)}` : emptyTpl);
  wirePosts(container, posts);
}

// ---------------- Onglet World ----------------
export async function worldScreen(root, { feed } = {}) {
  const notifs = await get('/notifications').catch(() => ({ unread: 0 }));
  const main = layout(root, {
    universe: 'world',
    title: 'World',
    tab: 'world',
    left: html`<span class="universe-tag">${t('universe.world')}</span>`,
    right: html`<a class="icon-btn" href="#/search" aria-label="${t('search.title')}">${icon('search')}</a>
      <a class="icon-btn" href="#/notifications" aria-label="${t('me.notifications')}">${icon('bell')}<span class="dot" data-notif-dot ${notifs.unread ? '' : 'hidden'}></span></a>
      <button class="icon-btn" data-create aria-label="${t('world.create')}">${icon('plus')}</button>`,
  });
  $('[data-create]', root).addEventListener('click', async () => {
    if (await ensureWorld()) go('create');
  });
  // Par défaut : Following si l'utilisateur suit déjà des comptes, sinon For You (7.6).
  if (!feed) {
    const following = await get('/feed/following').catch(() => []);
    feed = following.some((p) => p.author.id !== store.me.id) ? 'following' : 'for-you';
  }
  mount(
    main,
    html`<div class="chips" role="tablist">
        <a class="chip ${feed === 'for-you' ? 'active' : ''}" href="#/world/for-you">${t('world.forYou')}</a>
        <a class="chip ${feed === 'following' ? 'active' : ''}" href="#/world/following">${t('world.following')}</a>
        <a class="chip" href="#/clips">${icon('video', 'width="14" height="14" style="vertical-align:-2px"')} ${t('clip.feed')}</a>
        <a class="chip" href="#/communities">${icon('users', 'width="14" height="14" style="vertical-align:-2px"')} ${t('community.title')}</a>
        <a class="chip" href="#/events">${icon('star', 'width="14" height="14" style="vertical-align:-2px"')} ${t('event.title')}</a>
      </div>
      ${!store.me.world.enabled
        ? html`<div class="world-cta"><h3>${t('me.activateWorld')}</h3><p class="small muted">${t('me.activateWorldLead')}</p><button class="btn world" data-join>${t('me.activateWorld')}</button></div>`
        : ''}
      <div data-feed>${skeleton(4)}</div>`
  );
  $('[data-join]', main)?.addEventListener('click', async () => {
    if (await ensureWorld()) worldScreen(root, { feed });
  });
  const box = $('[data-feed]', main);
  try {
    const posts = await get(feed === 'following' ? '/feed/following' : '/feed/for-you');
    renderPosts(box, posts, empty(t('world.empty'), feed === 'following' ? t('world.emptyFollowing') : t('world.emptyForYou'), html`<a class="btn world" href="#/search">${t('search.title')}</a>`));
  } catch (err) {
    showError(err);
  }
}

// ---------------- Publication + commentaires ----------------
export async function postScreen(root, { id }) {
  const main = layout(root, { universe: 'world', title: t('world.post'), left: backButton() });
  wireBack(root, 'world');
  let p;
  try {
    p = await get(`/posts/${id}`);
  } catch {
    mount(main, empty(t('chat.postUnavailable')));
    return;
  }
  const posts = [p];
  mount(
    main,
    html`<div data-post-box>${postCardHtml(p)}</div>
      <div class="section-title">${t('world.comments')}</div>
      <div data-comments>${skeleton(2)}</div>
      ${p.canComment
        ? html`<form class="composer" data-form style="position:sticky;bottom:0">
            ${avatar({ name: store.me.displayName, avatar: store.me.avatar }, 'xs')}
            <textarea rows="1" data-input maxlength="500" placeholder="${t('world.addComment')}" aria-label="${t('world.addComment')}"></textarea>
            <button class="send" aria-label="${t('share.send')}">${icon('send')}</button>
          </form>`
        : html`<p class="muted small center" style="padding:16px">${t('world.commentsOff')}</p>`}`
  );
  wirePosts($('[data-post-box]', main), posts, { onRemove: () => go('world') });
  const cbox = $('[data-comments]', main);
  const loadComments = async () => {
    const comments = await get(`/posts/${id}/comments`).catch(() => []);
    mount(
      cbox,
      comments.length
        ? html`${comments.map(
            (c) => html`<div class="comment" data-c="${c.id}">
              <a href="#/u/${c.author.username}">${avatar(c.author, 'xs')}</a>
              <div class="c-body"><b>${c.author.name}</b>${richText(c.body)}<div class="small muted">${relTime(c.createdAt)}</div></div>
              <button class="icon-btn" data-cmenu="${c.id}" aria-label="${t('common.more')}">${icon('more')}</button>
            </div>`
          )}`
        : html`<p class="muted small center">${t('world.noComments')}</p>`
    );
    $$('[data-cmenu]', cbox).forEach((b) =>
      b.addEventListener('click', () => {
        const c = comments.find((x) => x.id === Number(b.dataset.cmenu));
        const items = [];
        if (c.canDelete) items.push({ label: t('me.delete'), icon: 'trash', danger: true, run: () => del(`/comments/${c.id}`).then(loadComments).catch(showError) });
        if (!c.mine) items.push({ label: t('chat.report'), icon: 'flag', danger: true, run: () => reportFlow('comment', c.id) });
        actionSheet(items);
      })
    );
  };
  await loadComments();
  $('[data-form]', main)?.addEventListener('submit', async (e) => {
    e.preventDefault();
    const input = $('[data-input]', main);
    const body = input.value.trim();
    if (!body) return;
    if (!(await ensureWorld())) return;
    try {
      await post(`/posts/${id}/comments`, { body });
      input.value = '';
      Object.assign(p, await get(`/posts/${id}`));
      const card = $(`[data-post="${p.id}"]`, main);
      if (card) {
        const tmp = document.createElement('div');
        mount(tmp, postCardHtml(p));
        card.replaceWith(tmp.firstElementChild);
      }
      await loadComments();
    } catch (err) {
      showError(err);
    }
  });
}

// ---------------- Hashtag ----------------
export async function tagScreen(root, { tag }) {
  const main = layout(root, { universe: 'world', title: `#${tag}`, left: backButton() });
  wireBack(root, 'world');
  mount(main, skeleton(3));
  try {
    const r = await get(`/hashtags/${encodeURIComponent(tag)}`);
    mount(main, html`<p class="muted section" style="padding-bottom:0">${t('search.postsCount', { count: compact(r.count) })}</p><div data-list></div>`);
    renderPosts($('[data-list]', main), r.posts, empty(t('world.empty')));
  } catch (err) {
    showError(err);
  }
}

// ---------------- Recherche globale (17.1) ----------------
export async function searchScreen(root) {
  const main = layout(root, { universe: 'world', title: t('search.title'), left: backButton() });
  wireBack(root, 'world');
  mount(
    main,
    html`<div class="searchbar"><input class="input" type="search" data-q placeholder="${t('search.placeholder')}" autofocus /></div>
      <div data-results>${skeleton(3)}</div>`
  );
  const results = $('[data-results]', main);

  const person = (u) => html`<li><a class="list-item" href="#/u/${u.username}">${avatar(u, 'sm')}<span class="grow"><span class="title" style="display:block">${u.name}</span><span class="preview">@${u.username}${u.mutual ? ` · ${t('search.mutual', { count: u.mutual })}` : ''}</span></span>${u.world ? html`<span class="small" style="color:var(--world)">World</span>` : ''}</a></li>`;

  const showDefault = async () => {
    const [trending, suggestions] = await Promise.all([get('/trending').catch(() => []), get('/users/suggestions').catch(() => [])]);
    mount(
      results,
      html`${suggestions.length ? html`<div class="section-title">${t('search.suggestions')}</div><ul class="list">${suggestions.map(person)}</ul>` : ''}
        <div class="section-title">${t('search.trending')}</div>
        ${trending.length
          ? trending.map(
              (tr, i) => html`<a class="trend" href="#/tag/${encodeURIComponent(tr.tag)}" style="color:inherit"><span class="rank">${i + 1}</span><span class="grow"><b>#${tr.tag}</b></span><span class="small muted">${t('search.postsCount', { count: compact(tr.posts) })}</span></a>`
            )
          : html`<p class="muted small center">${t('world.empty')}</p>`}`
    );
  };

  const search = debounce(async (q) => {
    if (!q) return showDefault();
    try {
      const [people, other, channels] = await Promise.all([
        get(`/users/search?q=${encodeURIComponent(q)}`),
        get(`/search?q=${encodeURIComponent(q)}`),
        get(`/channels/search?q=${encodeURIComponent(q)}`).catch(() => []),
      ]);
      if (!people.length && !other.hashtags.length && !other.posts.length && !channels.length) return mount(results, empty(t('search.noResults')));
      mount(
        results,
        html`${people.length ? html`<div class="section-title">${t('search.people')}</div><ul class="list">${people.map(person)}</ul>` : ''}
          ${channels.length
            ? html`<div class="section-title">${t('channel.channels')}</div><ul class="list">${channels.map(
                (c) => html`<li><a class="list-item" href="#/channel/${c.handle}">${avatar({ name: c.name, avatar: c.avatar }, 'sm')}<span class="grow"><span class="title" style="display:block">${c.name}</span><span class="preview">@${c.handle} · ${t('channel.subscribers', { count: compact(c.subscribers) })}</span></span></a></li>`
              )}</ul>`
            : ''}
          ${other.hashtags.length
            ? html`<div class="section-title">${t('search.hashtags')}</div>${other.hashtags.map(
                (h) => html`<a class="trend" href="#/tag/${encodeURIComponent(h.tag)}" style="color:inherit"><b>#${h.tag}</b><span class="small muted">${t('search.postsCount', { count: compact(h.posts) })}</span></a>`
              )}`
            : ''}
          ${other.posts.length ? html`<div class="section-title">${t('search.posts')}</div><div data-posts></div>` : ''}`
      );
      if (other.posts.length) renderPosts($('[data-posts]', results), other.posts, '');
    } catch (err) {
      showError(err);
    }
  }, 250);

  $('[data-q]', main).addEventListener('input', (e) => search(e.target.value.trim()));
  await showDefault();
}

// ---------------- Fil Clips plein écran vertical (14.2) ----------------
export async function clipsScreen(root) {
  layout(root, { universe: 'world', topbar: false, tab: 'world', flush: true });
  const main = $('main', root);
  mount(main, html`<div class="clips-feed" data-feed>${skeleton(1)}</div>`);
  const feed = $('[data-feed]', main);
  let clips = [];
  try {
    clips = await get('/feed/clips');
  } catch (err) {
    showError(err);
  }
  let muted = true;
  const item = (p) => html`<section class="clip-item" data-post="${p.id}">
    <video data-clip-video="${p.id}" src="${p.video}" ${p.media ? raw(`poster="${p.media}"`) : ''} loop playsinline preload="metadata" ${muted ? raw('muted') : ''} ${p.allowDownload ? '' : raw('controlslist="nodownload"')}></video>
    <div class="clip-side">
      <a href="#/u/${p.author.username}" class="clip-author">${avatar(p.author, 'sm')}</a>
      <button data-act="like" class="${p.liked ? 'liked' : ''}" aria-label="${t('world.like')}">${icon('heart', p.liked ? 'fill="currentColor"' : '')}<span>${p.likes == null ? '' : compact(p.likes)}</span></button>
      <a href="#/post/${p.id}" aria-label="${t('world.comment')}">${icon('comment')}<span>${compact(p.comments)}</span></a>
      <button data-act="share" aria-label="${t('world.share')}">${icon('share')}<span>${p.shares ? compact(p.shares) : ''}</span></button>
      <button data-act="save" class="${p.saved ? 'on' : ''}" aria-label="${t('world.save')}">${icon('bookmark', p.saved ? 'fill="currentColor"' : '')}</button>
      <button data-act="menu" aria-label="${t('common.more')}">${icon('more')}</button>
    </div>
    <div class="clip-caption">
      <a href="#/u/${p.author.username}"><b>@${p.author.username}</b></a>
      ${p.body ? html`<div class="clip-text">${richText(p.body)}</div>` : ''}
      <div class="small" style="opacity:.8">${t('clip.views', { count: compact(p.views || 0) })} · ${relTime(p.createdAt)}</div>
    </div>
    <button class="clip-mute" data-mute aria-label="${t('clip.sound')}">${muted ? '🔇' : '🔊'}</button>
  </section>`;
  const draw = () => {
    mount(
      feed,
      clips.length
        ? html`${clips.map(item)}`
        : html`<div class="clip-empty">${empty(t('clip.empty'), t('clip.emptyLead'), html`<a class="btn world" href="#/create/clip">${t('clip.create')}</a>`)}</div>`
    );
    watchClips(feed);
  };
  draw();
  // Actions (j'aime, partage, enregistrer, menu) partagées avec les cartes.
  const sync = (p) => {
    const old = feed.querySelector(`[data-post="${p.id}"] .clip-side`);
    if (!old) return;
    const tmp = document.createElement('div');
    mount(tmp, item(p));
    old.replaceWith(tmp.querySelector('.clip-side'));
  };
  feed.addEventListener('click', async (e) => {
    const sec = e.target.closest('[data-post]');
    if (!sec) return;
    const p = clips.find((c) => c.id === Number(sec.dataset.post));
    const btn = e.target.closest('[data-act]');
    if (e.target.closest('[data-mute]')) {
      muted = !muted;
      $$('video', feed).forEach((v) => (v.muted = muted));
      $$('[data-mute]', feed).forEach((b) => (b.textContent = muted ? '🔇' : '🔊'));
      return;
    }
    if (!btn) {
      // Appui = pause / lecture (14.2).
      if (e.target.closest('a')) return;
      const v = $('video', sec);
      if (v.paused) v.play().catch(() => {});
      else v.pause();
      return;
    }
    const act = btn.dataset.act;
    try {
      if (act === 'like') Object.assign(p, p.liked ? await del(`/posts/${p.id}/like`) : await post(`/posts/${p.id}/like`));
      if (act === 'save') {
        if (p.saved) {
          await del(`/posts/${p.id}/save`);
          p.saved = false;
        } else Object.assign(p, await post(`/posts/${p.id}/save`));
      }
      if (act === 'share') return shareSheet(p);
      if (act === 'menu') return postMenu(p, { redraw: sync, remove: () => sec.remove() });
      sync(p);
    } catch (err) {
      showError(err);
    }
  });
  // Double appui = j'aime avec le sourire MIC.
  feed.addEventListener('dblclick', async (e) => {
    const sec = e.target.closest('[data-post]');
    if (!sec || e.target.closest('.clip-side')) return;
    const p = clips.find((c) => c.id === Number(sec.dataset.post));
    burst(sec);
    if (!p.liked) {
      Object.assign(p, await post(`/posts/${p.id}/like`).catch(() => p));
      sync(p);
    }
  });
  return () => $$('video', feed).forEach((v) => v.pause());
}
