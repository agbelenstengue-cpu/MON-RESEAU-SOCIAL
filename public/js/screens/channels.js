// Section 11.8 (canaux) et 11.9 (listes de diffusion).
import { t, compact, relTime, clock } from '../i18n.js';
import { get, post, put, patch, del, on, readImage } from '../api.js';
import { html, mount, $, $$, icon, avatar, richText, toast, showError, dialog, actionSheet, empty } from '../ui.js';
import { layout, go, backButton, wireBack } from '../app.js';
import { pickPeople } from './chats.js';
import { ensureWorld } from './create.js';

const channelAvatar = (c, size = '') => avatar({ name: c.name, avatar: c.avatar }, size);

// ---------------- Canal ----------------
export async function channelScreen(root, { handle, code }) {
  let c;
  try {
    c = await get(`/channels/${encodeURIComponent(handle)}${code ? `?code=${encodeURIComponent(code)}` : ''}`);
  } catch {
    const main = layout(root, { universe: 'world', title: t('channel.title'), left: backButton() });
    wireBack(root, 'stories');
    return mount(main, empty(t('channel.notFound')));
  }
  let posts = [];
  const main = layout(root, {
    universe: 'world',
    title: c.name,
    sub: t('channel.subscribers', { count: compact(c.subscribers) }),
    left: backButton(),
    right: html`<button class="icon-btn" data-menu aria-label="${t('common.more')}">${icon('more')}</button>`,
    flush: true,
  });
  wireBack(root, 'stories');

  const postHtml = (p) => html`<article class="ch-post" data-p="${p.id}">
    ${p.media ? html`<img src="${p.media}" alt="" loading="lazy" />` : ''}
    ${p.body ? html`<div class="text">${richText(p.body)}</div>` : ''}
    <div class="ch-meta">
      <span class="ch-reactions">${c.reactions.map((e) => {
        const n = p.reactions.find((r) => r.emoji === e)?.count || 0;
        return html`<button class="${p.myReaction === e ? 'on' : ''}" data-react="${e}">${e}${n ? html` <span>${compact(n)}</span>` : ''}</button>`;
      })}</span>
      <span class="small muted">${p.views != null ? html`${icon('eye', 'width="13" height="13" style="vertical-align:-2px"')} ${compact(p.views)} · ` : ''}${clock(p.createdAt)}</span>
    </div>
  </article>`;

  const draw = () => {
    mount(
      main,
      html`<div class="ch-head">
          ${channelAvatar(c, 'lg')}
          <h2>${c.name}</h2>
          <div class="muted">@${c.handle} · ${t(c.visibility === 'private' ? 'channel.private' : 'channel.public')}</div>
          ${c.description ? html`<p>${c.description}</p>` : ''}
          <p class="small muted">${icon('world', 'width="12" height="12" style="vertical-align:-1px"')} ${t('channel.notEncrypted')}</p>
          ${c.isAdmin ? '' : html`<button class="btn ${c.subscribed ? 'ghost' : 'world'}" data-sub>${c.subscribed ? t('channel.subscribed') : t('channel.subscribe')}</button>`}
        </div>
        <div class="ch-posts" data-posts>
          ${!c.canRead ? '' : posts.length ? posts.map(postHtml) : empty(t('channel.empty'))}
        </div>
        ${c.isAdmin
          ? html`<form class="composer" data-form style="position:sticky;bottom:0">
              <label class="icon-btn" aria-label="${t('chat.photo')}">${icon('image')}<input type="file" accept="image/*" data-file hidden /></label>
              <textarea rows="1" data-input maxlength="4096" placeholder="${t('channel.placeholder')}"></textarea>
              <button class="send" aria-label="${t('share.publish')}">${icon('send')}</button>
            </form>`
          : ''}`
    );
    const list = $('[data-posts]', main);
    list.scrollIntoView({ block: 'end' });
    $('[data-sub]', main)?.addEventListener('click', async () => {
      try {
        c = { ...c, ...(c.subscribed ? await del(`/channels/${c.id}/subscribe`) : await post(`/channels/${c.id}/subscribe`, { code })) };
        c.canRead = c.subscribed || c.visibility === 'public' || c.isAdmin;
        await loadPosts();
      } catch (err) {
        showError(err);
      }
    });
    list.addEventListener('click', async (e) => {
      const b = e.target.closest('[data-react]');
      if (!b) return;
      const p = posts.find((x) => x.id === Number(b.closest('[data-p]').dataset.p));
      const emoji = p.myReaction === b.dataset.react ? null : b.dataset.react;
      try {
        Object.assign(p, await put(`/channel-posts/${p.id}/reaction`, { emoji }));
        draw();
      } catch (err) {
        showError(err);
      }
    });
    const form = $('[data-form]', main);
    if (form) {
      const input = $('[data-input]', form);
      const send = async (payload) => {
        try {
          posts.push(await post(`/channels/${c.id}/posts`, payload));
          draw();
        } catch (err) {
          showError(err);
        }
      };
      form.addEventListener('submit', (e) => {
        e.preventDefault();
        if (input.value.trim()) send({ body: input.value.trim() });
      });
      $('[data-file]', form).addEventListener('change', async (e) => {
        try {
          send({ media: await readImage(e.target.files[0]), body: input.value.trim() });
        } catch (err) {
          showError(err);
        }
      });
    }
  };

  const loadPosts = async () => {
    posts = c.canRead ? await get(`/channels/${c.id}/posts`).catch(() => []) : [];
    draw();
    const last = posts.at(-1);
    if (last && (c.subscribed || c.isAdmin)) post(`/channels/${c.id}/read`, { upTo: last.id }).catch(() => {});
  };

  $('[data-menu]', root).addEventListener('click', () => {
    const items = [
      {
        label: t('channel.copyLink'),
        icon: 'link',
        run: () => {
          const link = `${location.origin}/#/channel/${c.handle}${c.visibility === 'private' && c.inviteCode ? `/${c.inviteCode}` : ''}`;
          navigator.clipboard?.writeText(link);
          toast(t('world.linkCopied'));
        },
      },
    ];
    if (c.subscribed && !c.isAdmin) items.push({ label: t('channel.unsubscribe'), icon: 'close', run: () => $('[data-sub]', main)?.click() });
    actionSheet(items);
  });

  await loadPosts();
  return on('channel:post', ({ channelId, post: p }) => {
    if (channelId !== c.id || posts.some((x) => x.id === p.id)) return;
    posts.push(p);
    draw();
    post(`/channels/${c.id}/read`, { upTo: p.id }).catch(() => {});
  });
}

export async function newChannelScreen(root) {
  if (!(await ensureWorld())) return go('chats');
  const main = layout(root, { universe: 'world', title: t('channel.new'), left: backButton() });
  wireBack(root, 'chats');
  mount(
    main,
    html`<form class="section" data-form>
      <p class="muted small">${t('channel.newLead')}</p>
      <div class="field"><label for="cn">${t('channel.name')}</label><input class="input" id="cn" data-name maxlength="80" required /></div>
      <div class="field"><label for="ch">${t('channel.handle')}</label><div class="row"><span class="muted">@</span><input class="input" id="ch" data-handle maxlength="30" autocapitalize="none" required /></div><span class="hint">${t('auth.usernameHint')}</span></div>
      <div class="field"><label for="cd">${t('channel.description')}</label><textarea class="input" id="cd" data-desc maxlength="500"></textarea></div>
      <label class="choice selected"><input type="radio" name="vis" value="public" checked /><div><h4>${t('channel.public')}</h4><p>${t('channel.publicDesc')}</p></div></label>
      <label class="choice"><input type="radio" name="vis" value="private" /><div><h4>${t('channel.private')}</h4><p>${t('channel.privateDesc')}</p></div></label>
      <button class="btn world block" type="submit">${t('chat.create')}</button>
    </form>`
  );
  const name = $('[data-name]', main);
  const handle = $('[data-handle]', main);
  let edited = false;
  handle.addEventListener('input', () => {
    edited = true;
    handle.value = handle.value.toLowerCase().replace(/[^a-z0-9._]/g, '');
  });
  name.addEventListener('input', () => {
    if (!edited) handle.value = name.value.toLowerCase().normalize('NFD').replace(/[^a-z0-9._]/g, '').slice(0, 30);
  });
  $$('input[name="vis"]', main).forEach((r) => r.addEventListener('change', () => $$('.choice', main).forEach((ch) => ch.classList.toggle('selected', ch.contains(r) && r.checked))));
  $('[data-form]', main).addEventListener('submit', async (e) => {
    e.preventDefault();
    try {
      const c = await post('/channels', { name: name.value, handle: handle.value, description: $('[data-desc]', main).value, visibility: $('input[name="vis"]:checked', main).value });
      go(`channel/${c.handle}`);
    } catch (err) {
      showError(err);
    }
  });
}

// Liste compacte des canaux suivis (onglet Stories, 7.4).
export function channelsRail(channels) {
  if (!channels.length) return '';
  return html`<div class="section-title" style="color:var(--world)">${t('channel.channels')}</div>
    <ul class="list">${channels.map(
      (c) => html`<li><a class="list-item" href="#/channel/${c.handle}">
        ${channelAvatar(c)}
        <span class="grow"><span class="title" style="display:block">${c.name}</span>
          <span class="preview">${c.lastPost ? (c.lastPost.media ? '📷 ' : '') + c.lastPost.body : t('channel.empty')}</span></span>
        <span class="meta">${c.lastPost ? relTime(c.lastPost.createdAt) : ''}${c.unread ? html`<span class="badge">${c.unread}</span>` : ''}</span>
      </a></li>`
    )}</ul>`;
}

// ---------------- Listes de diffusion ----------------
export async function broadcastsScreen(root) {
  const main = layout(root, {
    universe: 'me',
    title: t('broadcast.title'),
    left: backButton(),
    right: html`<button class="icon-btn" data-new aria-label="${t('broadcast.new')}">${icon('plus')}</button>`,
  });
  wireBack(root, 'chats');
  const draw = async () => {
    const lists = await get('/broadcasts').catch(() => []);
    mount(
      main,
      html`<p class="muted small section" style="padding-bottom:0">${t('broadcast.lead')}</p>
        ${lists.length
          ? html`<ul class="list">${lists.map(
              (l) => html`<li><a class="list-item" href="#/broadcast/${l.id}">
                <span class="avatar">${icon('users', 'width="22" height="22"')}</span>
                <span class="grow"><span class="title" style="display:block">${l.name}</span><span class="preview">${t('broadcast.recipients', { count: l.members.length })}</span></span>
              </a></li>`
            )}</ul>`
          : empty(t('broadcast.empty'), '', html`<button class="btn" data-new2>${t('broadcast.new')}</button>`)}`
    );
    $('[data-new2]', main)?.addEventListener('click', create);
  };
  const create = async () => {
    const name = await dialog({ title: t('broadcast.new'), input: { placeholder: t('broadcast.namePlaceholder') } });
    if (!name?.trim()) return;
    const friends = await get('/friends').catch(() => []);
    pickPeople(friends, t('chat.chooseFriends'), async (ids) => {
      const l = await post('/broadcasts', { name, memberIds: ids });
      go(`broadcast/${l.id}`);
    });
  };
  $('[data-new]', root).addEventListener('click', create);
  await draw();
}

export async function broadcastScreen(root, { id }) {
  const lists = await get('/broadcasts').catch(() => []);
  let l = lists.find((x) => x.id === Number(id));
  if (!l) return go('broadcasts');
  const main = layout(root, {
    universe: 'me',
    title: l.name,
    sub: t('broadcast.recipients', { count: l.members.length }),
    left: backButton(),
    right: html`<button class="icon-btn" data-menu aria-label="${t('common.more')}">${icon('more')}</button>`,
    flush: true,
  });
  wireBack(root, 'broadcasts');
  const draw = () => {
    mount(
      main,
      html`<div class="messages" style="min-height:calc(100dvh - 140px)">
          <div class="e2ee-note">${t('broadcast.note')}</div>
          ${[...l.sent].reverse().map(
            (s) => html`<div class="bubble-row mine"><div class="bubble">
              ${s.media ? html`<img class="media" src="${s.media}" alt="" />` : ''}${s.body ? html`<div class="text">${richText(s.body)}</div>` : ''}
              <div class="meta"><span>${t('broadcast.delivered', { count: s.delivered })}</span><span>${clock(s.createdAt)}</span></div>
            </div></div>`
          )}
        </div>
        <form class="composer" data-form style="position:sticky;bottom:0">
          <label class="icon-btn" aria-label="${t('chat.photo')}">${icon('image')}<input type="file" accept="image/*" data-file hidden /></label>
          <textarea rows="1" data-input maxlength="4096" placeholder="${t('chat.placeholder')}"></textarea>
          <button class="send" aria-label="${t('share.send')}">${icon('send')}</button>
        </form>`
    );
    const input = $('[data-input]', main);
    const send = async (payload) => {
      try {
        const r = await post(`/broadcasts/${l.id}/send`, payload);
        toast(t('broadcast.delivered', { count: r.delivered }));
        l = (await get('/broadcasts')).find((x) => x.id === l.id);
        draw();
      } catch (err) {
        showError(err);
      }
    };
    $('[data-form]', main).addEventListener('submit', (e) => {
      e.preventDefault();
      if (input.value.trim()) send({ body: input.value.trim() });
    });
    $('[data-file]', main).addEventListener('change', async (e) => {
      try {
        send({ media: await readImage(e.target.files[0]), body: input.value.trim() });
      } catch (err) {
        showError(err);
      }
    });
    window.scrollTo(0, document.body.scrollHeight);
  };
  $('[data-menu]', root).addEventListener('click', () =>
    actionSheet([
      {
        label: t('broadcast.editRecipients'),
        icon: 'users',
        run: async () => {
          const friends = await get('/friends').catch(() => []);
          pickPeople(friends, t('broadcast.editRecipients'), async (ids) => {
            l = await patch(`/broadcasts/${l.id}`, { memberIds: ids });
            draw();
          });
        },
      },
      {
        label: t('broadcast.delete'),
        icon: 'trash',
        danger: true,
        run: async () => {
          if (!(await dialog({ title: t('broadcast.delete'), danger: true, confirm: t('me.delete') }))) return;
          await del(`/broadcasts/${l.id}`).catch(showError);
          go('broadcasts');
        },
      },
    ])
  );
  draw();
}
