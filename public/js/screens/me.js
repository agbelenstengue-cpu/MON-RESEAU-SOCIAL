// Section 7.7 (onglet Me), 6 (relations), 15 (profils), 19 (notifications), 20 (paramètres).
import { t, getLang, setLang, compact, relTime } from '../i18n.js';
import { store, get, post, patch, put, del, readImage } from '../api.js';
import { html, mount, $, $$, icon, logo, avatar, toast, showError, dialog, actionSheet, reportFlow, empty, skeleton } from '../ui.js';
import { layout, go, backButton, wireBack, signOut } from '../app.js';
import { renderPosts } from './world.js';
import { openViewer } from './stories.js';
import { ensureWorld } from './create.js';

const meCard = () => ({ id: store.me.id, name: store.me.displayName, avatar: store.me.avatar, username: store.me.username });

// ---------------- Onglet Me ----------------
export async function meScreen(root) {
  let face = 'me';
  const main = layout(root, {
    universe: 'me',
    title: t('nav.me'),
    tab: 'me',
    right: html`<a class="icon-btn" href="#/notifications" aria-label="${t('me.notifications')}">${icon('bell')}</a>
      <a class="icon-btn" href="#/settings" aria-label="${t('me.settings')}">${icon('settings')}</a>`,
  });
  mount(main, skeleton(4));
  const [profile, requests, followReqs] = await Promise.all([
    get(`/users/${store.me.username}`),
    get('/friend-requests').catch(() => ({ received: [] })),
    get('/follow-requests').catch(() => []),
  ]);

  const draw = () => {
    const w = store.me.world;
    const isWorld = face === 'world';
    document.body.dataset.universe = isWorld ? 'world' : 'me';
    const shown = isWorld
      ? { name: w.publicName || store.me.displayName, avatar: w.publicAvatar || store.me.avatar }
      : { name: store.me.displayName, avatar: store.me.avatar };
    mount(
      main,
      html`<div class="profile-head">
          ${avatar(shown, 'lg')}
          <h2>${shown.name}</h2>
          <div class="handle">@${store.me.username}</div>
          <p class="about">${isWorld ? w.bio || '' : store.me.about}</p>
          <div class="face-toggle" role="tablist">
            <button class="me ${!isWorld ? 'active' : ''}" data-face="me">${t('profile.private')}</button>
            <button class="world ${isWorld ? 'active' : ''}" data-face="world">${t('profile.world')}</button>
          </div>
          <div class="counters">
            <div><b>${compact(profile.counts.friends ?? 0)}</b><span>${t('profile.friends')}</span></div>
            ${w.enabled
              ? html`<div><b>${compact(profile.counts.followers ?? 0)}</b><span>${t('profile.followers')}</span></div>
                  <div><b>${compact(profile.counts.posts ?? 0)}</b><span>${t('profile.posts')}</span></div>`
              : ''}
          </div>
          <div class="profile-actions"><a class="btn ghost small" href="#/edit-profile">${t('profile.editProfile')}</a>
            <button class="btn ghost small" data-invite>${icon('link', 'width="16" height="16"')} ${t('me.invite')}</button></div>
        </div>
        ${isWorld
          ? w.enabled
            ? html`<div class="section-title">${t('me.worldPresence')}</div>
                <div class="menu-group">
                  ${followReqs.length ? html`<a class="list-item" href="#/requests">${icon('userPlus')}<span class="grow">${t('me.followRequests')}</span><span class="badge">${followReqs.length}</span></a>` : ''}
                  <a class="list-item" href="#/u/${store.me.username}">${icon('world')}<span class="grow">${t('me.myPosts')}</span></a>
                  <a class="list-item" href="#/settings">${icon('lock')}<span class="grow">${w.private ? t('me.privateAccount') : t('me.publicAccount')}</span></a>
                </div>
                <div data-posts></div>`
            : html`<div class="world-cta"><h3>${t('me.activateWorld')}</h3><p class="small muted">${t('me.activateWorldLead')}</p><button class="btn world" data-join>${t('me.activateWorld')}</button></div>`
          : html`<div class="section-title">${t('me.privateSpaces')}</div>
              <div class="menu-group">
                <a class="list-item" href="#/requests">${icon('userPlus')}<span class="grow">${t('me.friendRequests')}</span>${requests.received.length + followReqs.length ? html`<span class="badge">${requests.received.length + followReqs.length}</span>` : ''}</a>
                <a class="list-item" href="#/friends">${icon('users')}<span class="grow">${t('me.friendsList')}</span></a>
                <a class="list-item" href="#/saved">${icon('bookmark')}<span class="grow">${t('me.saved')}</span></a>
                <a class="list-item" href="#/archive">${icon('archive')}<span class="grow">${t('stories.archive')}</span></a>
              </div>
              <div class="menu-group">
                <a class="list-item" href="#/notifications">${icon('bell')}<span class="grow">${t('me.notifications')}</span></a>
                <a class="list-item" href="#/settings">${icon('settings')}<span class="grow">${t('me.settings')}</span></a>
              </div>
              <div class="section-title">${t('safety.title')}</div>
              <div class="menu-group">
                <a class="list-item" href="#/account-status">${icon('info')}<span class="grow">${t('safety.status')}</span></a>
                <a class="list-item" href="#/my-reports">${icon('flag')}<span class="grow">${t('safety.myReports')}</span></a>
                ${store.me.role === 'moderator' ? html`<a class="list-item" href="#/moderation">${icon('lock')}<span class="grow">${t('mod.title')}</span></a>` : ''}
              </div>`}`
    );
    $$('[data-face]', main).forEach((b) =>
      b.addEventListener('click', () => {
        face = b.dataset.face;
        draw();
      })
    );
    $('[data-invite]', main).addEventListener('click', () => {
      navigator.clipboard?.writeText(`${location.origin}/#/u/${store.me.username}`);
      toast(t('me.inviteCopied'));
    });
    $('[data-join]', main)?.addEventListener('click', async () => {
      if (await ensureWorld()) draw();
    });
    const postsBox = $('[data-posts]', main);
    if (postsBox) renderPosts(postsBox, profile.posts, empty(t('profile.noPosts'), '', html`<a class="btn world" href="#/create">${t('world.create')}</a>`));
  };
  draw();
}

// ---------------- Profil d'une autre personne ----------------
export async function profileScreen(root, { username }) {
  let p;
  const main = layout(root, { universe: 'world', title: `@${username}`, left: backButton() });
  wireBack(root, 'world');
  mount(main, skeleton(4));
  try {
    p = await get(`/users/${encodeURIComponent(username)}`);
  } catch {
    mount(main, empty(t('search.noResults')));
    return;
  }

  const draw = () => {
    const r = p.relationship;
    const intimate = r.self || r.friend;
    document.body.dataset.universe = intimate ? 'me' : 'world';
    const friendBtn = r.self
      ? ''
      : r.friend
        ? html`<button class="btn soft small" data-friend-menu>${icon('check', 'width="16" height="16"')} ${t('profile.isFriend')}</button>`
        : r.requestReceived
          ? html`<button class="btn me small" data-accept>${t('profile.respond')}</button>`
          : r.requestSent
            ? html`<button class="btn ghost small" data-cancel>${t('profile.requested')}</button>`
            : html`<button class="btn me small" data-add>${icon('userPlus', 'width="16" height="16"')} ${t('profile.addFriend')}</button>`;
    const followBtn =
      r.self || !p.world
        ? ''
        : r.following === 'active'
          ? html`<button class="btn soft small" data-unfollow>${t('profile.unfollow')}</button>`
          : r.following === 'pending'
            ? html`<button class="btn ghost small" data-unfollow>${t('profile.followPending')}</button>`
            : html`<button class="btn world small" data-follow>${t('profile.follow')}</button>`;
    mount(
      main,
      html`<div class="profile-head">
          ${avatar(p, 'lg')}
          <h2>${p.name}</h2>
          <div class="handle">@${p.username}${p.world ? html` · <span style="color:var(--world)">World</span>` : ''}</div>
          ${p.about ? html`<p class="about">${p.about}</p>` : ''} ${p.bio ? html`<p class="about">${p.bio}</p>` : ''}
          ${r.blocked
            ? html`<p class="muted">${t('profile.blocked')}</p><button class="btn soft small" data-unblock>${t('profile.unblock')}</button>`
            : html`<div class="counters">
                  ${p.counts.mutualFriends != null ? html`<div><b>${compact(p.counts.mutualFriends)}</b><span>${t('profile.mutual')}</span></div>` : ''}
                  ${p.world ? html`<div><b>${compact(p.counts.followers ?? 0)}</b><span>${t('profile.followers')}</span></div><div><b>${compact(p.counts.posts ?? 0)}</b><span>${t('profile.posts')}</span></div>` : ''}
                </div>
                <div class="profile-actions">
                  ${friendBtn} ${followBtn}
                  ${r.self ? html`<a class="btn ghost small" href="#/edit-profile">${t('profile.editProfile')}</a>` : html`<button class="btn ghost small" data-message>${icon('chats', 'width="16" height="16"')} ${t('profile.message')}</button>`}
                  ${r.self ? '' : html`<button class="icon-btn" data-more aria-label="${t('common.more')}">${icon('more')}</button>`}
                </div>`}
        </div>
        ${r.blocked
          ? ''
          : !p.world
            ? html`<p class="muted center small">${t('profile.noWorld')}</p>`
            : !p.canSeeWorld
              ? empty(t('profile.privateWorld'))
              : html`<div class="section-title">${t('profile.posts')}</div><div data-posts></div>`}`
    );
    const act = (sel, fn) =>
      $(sel, main)?.addEventListener('click', async () => {
        try {
          await fn();
          p = await get(`/users/${encodeURIComponent(username)}`);
          draw();
        } catch (err) {
          showError(err);
        }
      });
    act('[data-add]', () => post(`/users/${p.id}/friend-request`));
    act('[data-cancel]', () => del(`/users/${p.id}/friend-request`));
    act('[data-accept]', () => post(`/friend-requests/${p.id}/accept`));
    act('[data-follow]', () => post(`/users/${p.id}/follow`));
    act('[data-unfollow]', () => del(`/users/${p.id}/follow`));
    act('[data-unblock]', () => del(`/users/${p.id}/block`));
    $('[data-message]', main)?.addEventListener('click', async () => {
      try {
        const c = await post('/conversations/direct', { userId: p.id });
        go(`chat/${c.id}`);
      } catch (err) {
        showError(err);
      }
    });
    const refresh = async () => {
      p = await get(`/users/${encodeURIComponent(username)}`);
      draw();
    };
    $('[data-friend-menu]', main)?.addEventListener('click', async () => {
      const friends = await get('/friends');
      const close = friends.find((f) => f.id === p.id)?.closeFriend;
      actionSheet([
        { label: close ? t('profile.removeClose') : t('profile.addClose'), icon: 'star', run: () => (close ? del(`/close-friends/${p.id}`) : put(`/close-friends/${p.id}`)).then(() => toast(t('common.done'))).catch(showError) },
        { label: t('profile.removeFriend'), icon: 'trash', danger: true, run: () => del(`/friends/${p.id}`).then(refresh).catch(showError) },
      ]);
    });
    $('[data-more]', main)?.addEventListener('click', () =>
      actionSheet([
        {
          label: t('profile.block'),
          icon: 'block',
          danger: true,
          run: async () => {
            if (!(await dialog({ title: t('block.confirm', { name: p.name }), body: t('block.lead'), confirm: t('block.title'), danger: true }))) return;
            await post(`/users/${p.id}/block`).catch(showError);
            refresh();
          },
        },
        { label: t('profile.report'), icon: 'flag', danger: true, run: () => reportFlow('user', p.id) },
      ])
    );
    const box = $('[data-posts]', main);
    if (box) renderPosts(box, p.posts, empty(t('profile.noPosts')));
  };
  draw();
}

// ---------------- Demandes d'ami et d'abonnement (6.5) ----------------
export async function requestsScreen(root) {
  const main = layout(root, { universe: 'me', title: t('me.friendRequests'), left: backButton() });
  wireBack(root, 'me');
  const load = async () => {
    const [fr, follows] = await Promise.all([get('/friend-requests'), get('/follow-requests').catch(() => [])]);
    const row = (r, kind) => html`<li class="list-item">
      <a href="#/u/${r.user.username}">${avatar(r.user, 'sm')}</a>
      <a class="grow" href="#/u/${r.user.username}" style="color:inherit"><span class="title" style="display:block">${r.user.name}</span><span class="preview">@${r.user.username}${r.mutual ? ` · ${t('search.mutual', { count: r.mutual })}` : ''}</span></a>
      <button class="btn small ${kind === 'follow' ? 'world' : 'me'}" data-ok="${kind}:${r.user.id}">${t('chat.accept')}</button>
      <button class="btn small ghost" data-no="${kind}:${r.user.id}">${t('me.delete')}</button>
    </li>`;
    mount(
      main,
      html`<div class="section-title">${t('me.friendRequests')}</div>
        ${fr.received.length ? html`<ul class="list">${fr.received.map((r) => row(r, 'friend'))}</ul>` : html`<p class="muted small" style="padding:0 16px">${t('me.noRequests')}</p>`}
        ${follows.length ? html`<div class="section-title" style="color:var(--world)">${t('me.followRequests')}</div><ul class="list">${follows.map((r) => row(r, 'follow'))}</ul>` : ''}
        ${fr.sent.length
          ? html`<div class="section-title">${t('profile.requested')}</div><ul class="list">${fr.sent.map(
              (r) => html`<li class="list-item">${avatar(r.user, 'sm')}<span class="grow title">${r.user.name}</span><button class="btn small ghost" data-cancel="${r.user.id}">${t('common.cancel')}</button></li>`
            )}</ul>`
          : ''}
        <div class="section"><a class="btn ghost block" href="#/search">${t('me.findFriends')}</a></div>`
    );
    $$('[data-ok]', main).forEach((b) =>
      b.addEventListener('click', async () => {
        const [kind, id] = b.dataset.ok.split(':');
        await post(kind === 'follow' ? `/follow-requests/${id}/accept` : `/friend-requests/${id}/accept`).catch(showError);
        load();
      })
    );
    $$('[data-no]', main).forEach((b) =>
      b.addEventListener('click', async () => {
        const [kind, id] = b.dataset.no.split(':');
        await post(kind === 'follow' ? `/follow-requests/${id}/delete` : `/friend-requests/${id}/delete`).catch(showError);
        load();
      })
    );
    $$('[data-cancel]', main).forEach((b) =>
      b.addEventListener('click', async () => {
        await del(`/users/${b.dataset.cancel}/friend-request`).catch(showError);
        load();
      })
    );
  };
  await load();
}

// ---------------- Amis et proches ----------------
export async function friendsScreen(root) {
  const main = layout(root, { universe: 'me', title: t('me.friendsList'), left: backButton() });
  wireBack(root, 'me');
  const load = async () => {
    const friends = await get('/friends');
    mount(
      main,
      friends.length
        ? html`<p class="muted small section" style="padding-bottom:0">${icon('star', 'width="14" height="14" style="vertical-align:-2px;color:var(--sage)"')} ${t('me.closeFriendsHint')}</p>
            <ul class="list">${friends.map(
              (f) => html`<li class="list-item">
                <a href="#/u/${f.username}">${avatar(f, 'sm')}</a>
                <a class="grow" href="#/u/${f.username}" style="color:inherit"><span class="title" style="display:block">${f.name}</span><span class="preview">@${f.username}</span></a>
                <button class="btn small ${f.closeFriend ? 'soft' : 'ghost'}" data-close="${f.id}" aria-pressed="${f.closeFriend}">${icon('star', `width="14" height="14" ${f.closeFriend ? 'fill="currentColor"' : ''}`)} ${t('stories.audience.close_friends')}</button>
              </li>`
            )}</ul>`
        : empty(t('me.noFriends'), '', html`<a class="btn" href="#/search">${t('me.findFriends')}</a>`)
    );
    $$('[data-close]', main).forEach((b) =>
      b.addEventListener('click', async () => {
        const f = friends.find((x) => x.id === Number(b.dataset.close));
        await (f.closeFriend ? del(`/close-friends/${f.id}`) : put(`/close-friends/${f.id}`)).catch(showError);
        load();
      })
    );
  };
  await load();
}

export async function savedScreen(root) {
  const main = layout(root, { universe: 'me', title: t('me.saved'), left: backButton() });
  wireBack(root, 'me');
  mount(main, skeleton(3));
  renderPosts(main, await get('/saved'), empty(t('world.empty')));
}

export async function archiveScreen(root) {
  const main = layout(root, { universe: 'me', title: t('stories.archive'), left: backButton() });
  wireBack(root, 'me');
  const stories = await get('/stories/archive');
  mount(
    main,
    stories.length
      ? html`<ul class="list">${stories.map(
          (s, i) => html`<li><button class="list-item" data-i="${i}">
            <span class="avatar ${s.kind === 'text' ? 'bg-' + s.bg : ''}" style="border-radius:12px">${s.kind === 'image' ? html`<img src="${s.media}" alt="" />` : 'Aa'}</span>
            <span class="grow"><span class="title" style="display:block">${s.body || t('chat.photo')}</span><span class="preview">${t(`stories.audience.${s.audience}`)} · ${relTime(s.createdAt)}</span></span>
            <span class="small muted">${icon('eye', 'width="14" height="14" style="vertical-align:-2px"')} ${s.views ?? 0}</span>
          </button></li>`
        )}</ul>`
      : empty(t('stories.empty'))
  );
  $$('[data-i]', main).forEach((b) =>
    b.addEventListener('click', () => {
      const s = stories[Number(b.dataset.i)];
      openViewer([{ universe: 'me', author: meCard(), stories: [{ ...s, seen: true }] }], 0);
    })
  );
}

// ---------------- Notifications (19) ----------------
export async function notificationsScreen(root) {
  const main = layout(root, { universe: 'world', title: t('notif.title'), left: backButton() });
  wireBack(root, 'world');
  mount(main, skeleton(4));
  const { items } = await get('/notifications');
  post('/notifications/read').catch(() => {});
  const target = (n) => {
    if (['like', 'comment', 'mention'].includes(n.type) && n.refId) return `#/post/${n.refId}`;
    if (n.type === 'friend_request' || n.type === 'follow_request') return '#/requests';
    if (n.type === 'moderation_strike' || n.type.startsWith('appeal_')) return '#/account-status';
    if (n.type === 'report_update') return '#/my-reports';
    return n.actor ? `#/u/${n.actor.username}` : '#/me';
  };
  mount(
    main,
    items.length
      ? html`<ul class="list">${items.map(
          (n) => html`<li><a class="list-item" href="${target(n)}" style="${n.read ? '' : 'background:var(--accent-soft)'}">
            ${n.actor ? avatar(n.actor, 'sm') : html`<span class="system-avatar" aria-label="MIC">${logo(24)}</span>`}
            <span class="grow" style="white-space:normal">${t(`notif.${n.type}`, { name: n.actor?.name || '' })}<span class="small muted" style="display:block">${relTime(n.createdAt)}</span></span>
          </a></li>`
        )}</ul>`
      : empty(t('notif.empty'))
  );
}

// ---------------- Modifier le profil : deux visages (4.3) ----------------
export async function editProfileScreen(root) {
  const main = layout(root, { universe: 'me', title: t('edit.title'), left: backButton() });
  wireBack(root, 'me');
  const me = store.me;
  const pending = { avatar: undefined, publicAvatar: undefined };
  mount(
    main,
    html`<form class="section" data-form>
      <div class="section-title" style="margin-left:0;color:var(--me)">${icon('lock', 'width="12" height="12"')} ${t('edit.privateFace')}</div>
      <div class="row" style="margin-bottom:16px">
        <span data-av>${avatar({ name: me.displayName, avatar: me.avatar }, 'lg')}</span>
        <label class="btn ghost small">${t('edit.photo')}<input type="file" accept="image/*" data-file="avatar" hidden /></label>
      </div>
      <div class="field"><label>${t('auth.displayName')}</label><input class="input" data-k="displayName" maxlength="50" value="${me.displayName}" required /></div>
      <div class="field"><label>${t('auth.username')}</label><input class="input" data-k="username" maxlength="30" value="${me.username}" autocapitalize="none" required /></div>
      <div class="field"><label>${t('edit.about')}</label><input class="input" data-k="about" maxlength="140" value="${me.about}" /></div>
      ${me.world.enabled
        ? html`<div class="section-title" style="margin-left:0;color:var(--world)">${icon('world', 'width="12" height="12"')} ${t('edit.publicFace')}</div>
            <div class="row" style="margin-bottom:16px">
              <span data-pav>${avatar({ name: me.world.publicName || me.displayName, avatar: me.world.publicAvatar || me.avatar }, 'lg')}</span>
              <label class="btn ghost small">${t('edit.photo')}<input type="file" accept="image/*" data-file="publicAvatar" hidden /></label>
            </div>
            <div class="field"><label>${t('edit.publicName')}</label><input class="input" data-k="publicName" maxlength="50" value="${me.world.publicName || ''}" placeholder="${me.displayName}" /></div>
            <div class="field"><label>${t('edit.bio')}</label><textarea class="input" data-k="bio" maxlength="300">${me.world.bio}</textarea></div>`
        : ''}
      <button class="btn block" type="submit">${t('edit.save')}</button>
    </form>`
  );
  $$('[data-file]', main).forEach((input) =>
    input.addEventListener('change', async () => {
      try {
        const data = await readImage(input.files[0], 800);
        pending[input.dataset.file] = data;
        const slot = $(input.dataset.file === 'avatar' ? '[data-av]' : '[data-pav]', main);
        mount(slot, avatar({ name: '', avatar: data }, 'lg'));
      } catch (err) {
        showError(err);
      }
    })
  );
  $('[data-form]', main).addEventListener('submit', async (e) => {
    e.preventDefault();
    const body = {};
    $$('[data-k]', main).forEach((el) => (body[el.dataset.k] = el.value));
    if (pending.avatar) body.avatar = pending.avatar;
    if (pending.publicAvatar) body.publicAvatar = pending.publicAvatar;
    try {
      store.me = await patch('/me', body);
      toast(t('edit.saved'));
      go('me');
    } catch (err) {
      showError(err);
    }
  });
}

// ---------------- Paramètres et confidentialité (20) ----------------
export async function settingsScreen(root) {
  const main = layout(root, { universe: 'me', title: t('me.settings'), left: backButton() });
  wireBack(root, 'me');
  const draw = async () => {
    const [blocked, privacy] = await Promise.all([get('/blocked').catch(() => []), get('/me/privacy').catch(() => null)]);
    let theme = 'auto';
    try {
      theme = localStorage.getItem('mic.theme') || 'auto';
    } catch {
      /* ignore */
    }
    const w = store.me.world;
    mount(
      main,
      html`<div class="section-title">${t('settings.account')}</div>
        <div class="menu-group">
          <label class="list-item">${icon('world')}<span class="grow">${t('settings.language')}</span>
            <select class="lang-select" data-lang><option value="en" ${getLang() === 'en' ? 'selected' : ''}>English</option><option value="fr" ${getLang() === 'fr' ? 'selected' : ''}>Français</option></select></label>
          <label class="list-item">${icon('eye')}<span class="grow">${t('settings.theme')}</span>
            <select class="lang-select" data-theme>
              <option value="auto" ${theme === 'auto' ? 'selected' : ''}>${t('settings.themeAuto')}</option>
              <option value="light" ${theme === 'light' ? 'selected' : ''}>${t('settings.themeLight')}</option>
              <option value="dark" ${theme === 'dark' ? 'selected' : ''}>${t('settings.themeDark')}</option>
            </select></label>
          <a class="list-item" href="#/edit-profile">${icon('edit')}<span class="grow">${t('profile.editProfile')}</span></a>
        </div>
        <div class="section-title">${t('settings.privacy')}</div>
        ${privacy ? privacyGroup(privacy) : ''}
        <div class="menu-group">
          ${w.enabled
            ? html`<label class="list-item">${icon('lock')}<span class="grow">${t('settings.worldPrivate')}<span class="preview" style="display:block;white-space:normal">${t('settings.worldPrivateHint')}</span></span><input type="checkbox" class="toggle" data-wprivate ${w.private ? 'checked' : ''} /></label>
                <button class="list-item" data-leave-world>${icon('world')}<span class="grow">${t('settings.leaveWorld')}</span></button>`
            : html`<button class="list-item" data-join>${icon('world')}<span class="grow">${t('me.activateWorld')}</span></button>`}
        </div>
        <div class="section-title">${t('settings.blocked')}</div>
        <div class="menu-group">
          ${blocked.length
            ? blocked.map((u) => html`<div class="list-item">${avatar(u, 'xs')}<span class="grow title">${u.name}</span><button class="btn small ghost" data-unblock="${u.id}">${t('profile.unblock')}</button></div>`)
            : html`<div class="list-item muted small">${t('settings.noBlocked')}</div>`}
        </div>
        <div class="menu-group">
          <button class="list-item" data-logout>${icon('logout')}<span class="grow">${t('settings.logout')}</span></button>
          <button class="list-item" data-delete style="color:var(--garnet)">${icon('trash')}<span class="grow">${t('account.delete')}</span></button>
        </div>
        <p class="center muted small" style="padding:16px">MIC — Interconnected World · v0.1 (prototype)</p>`
    );
    $('[data-lang]', main).addEventListener('change', async (e) => {
      setLang(e.target.value);
      store.me = await patch('/me', { language: e.target.value }).catch(() => store.me);
      settingsScreen(root);
    });
    $('[data-theme]', main).addEventListener('change', (e) => {
      const v = e.target.value;
      try {
        if (v === 'auto') localStorage.removeItem('mic.theme');
        else localStorage.setItem('mic.theme', v);
      } catch {
        /* ignore */
      }
      if (v === 'auto') delete document.documentElement.dataset.theme;
      else document.documentElement.dataset.theme = v;
    });
    // Réglages de confidentialité (20.2) : enregistrés à chaque changement.
    $$('[data-priv]', main).forEach((el) =>
      el.addEventListener('change', async () => {
        const key = el.dataset.priv;
        const raw = el.type === 'checkbox' ? el.checked : el.value;
        const value = key === 'defaultTimer' ? Number(raw) : raw;
        try {
          await patch('/me/privacy', { [key]: value });
          toast(t('common.done'));
        } catch (err) {
          showError(err);
          draw();
        }
      })
    );
    $('[data-wprivate]', main)?.addEventListener('change', async (e) => {
      try {
        store.me = await patch('/me', { worldPrivate: e.target.checked });
      } catch (err) {
        showError(err);
      }
    });
    $('[data-leave-world]', main)?.addEventListener('click', async () => {
      if (!(await dialog({ title: t('settings.leaveWorld'), danger: true }))) return;
      store.me = await post('/me/world', { enable: false });
      draw();
    });
    $('[data-join]', main)?.addEventListener('click', async () => {
      if (await ensureWorld()) draw();
    });
    $$('[data-unblock]', main).forEach((b) =>
      b.addEventListener('click', async () => {
        await del(`/users/${b.dataset.unblock}/block`).catch(showError);
        draw();
      })
    );
    $('[data-logout]', main).addEventListener('click', async () => {
      await post('/auth/logout').catch(() => {});
      signOut();
    });
    $('[data-delete]', main).addEventListener('click', async () => {
      const typed = await dialog({ title: t('account.delete'), body: t('account.deleteLead'), confirm: t('me.delete'), danger: true, input: { placeholder: store.me.username } });
      if (typed == null) return;
      try {
        await del('/me', { confirm: typed.replace(/^@/, '').trim() });
        signOut();
      } catch (err) {
        showError(err);
      }
    });
  };
  await draw();
}

const PRIV_ROWS = [
  ['lastSeen', 'eye'],
  ['profilePhoto', 'me'],
  ['about', 'info'],
  ['whoCanMessage', 'chats'],
  ['whoCanCall', 'phone'],
  ['whoCanMention', 'world'],
  ['defaultTimer', 'archive'],
];
const PRIV_TOGGLES = [
  ['readReceipts', 'checks'],
  ['typingIndicator', 'edit'],
  ['suggestAccount', 'userPlus'],
];

function privacyGroup({ settings, options, locked }) {
  const label = (key, v) => (key === 'defaultTimer' ? t(`timer.${v}`) : t(`privacy.opt.${v}`));
  return html`<div class="menu-group">
      ${PRIV_ROWS.map(
        ([key, ic]) => html`<label class="list-item">${icon(ic)}<span class="grow">${t(`privacy.${key}`)}${locked.includes(key) ? html`<span class="preview" style="display:block">${t('privacy.lockedMinor')}</span>` : ''}</span>
          <select class="lang-select" data-priv="${key}" ${locked.includes(key) ? 'disabled' : ''}>${options[key].map(
            (v) => html`<option value="${v}" ${settings[key] === v ? 'selected' : ''}>${label(key, v)}</option>`
          )}</select></label>`
      )}
    </div>
    <div class="menu-group">
      ${PRIV_TOGGLES.map(
        ([key, ic]) => html`<label class="list-item">${icon(ic)}<span class="grow">${t(`privacy.${key}`)}<span class="preview" style="display:block;white-space:normal">${t(`privacy.${key}Hint`)}</span></span>
          <input type="checkbox" class="toggle" data-priv="${key}" ${settings[key] ? 'checked' : ''} /></label>`
      )}
    </div>`;
}
