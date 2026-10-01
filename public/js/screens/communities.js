// Section 18 : communautés et événements.
import { t, compact, relTime, getLang } from '../i18n.js';
import { store, get, post, patch, del, readImage, getToken } from '../api.js';
import { html, mount, $, $$, icon, avatar, toast, showError, dialog, actionSheet, empty, skeleton, debounce } from '../ui.js';
import { layout, go, backButton, wireBack } from '../app.js';
import { renderPosts } from './world.js';
import { ensureWorld } from './create.js';
import { pickPeople } from './chats.js';
import { saveFile } from '../download.js';

const CATEGORIES = ['education', 'business', 'culture', 'sport', 'faith', 'tech', 'food', 'local', 'other'];
const cAvatar = (c, size = '') => avatar({ name: c.name, avatar: c.avatar }, size);

function fmtEventDate(ev) {
  const opts = { weekday: 'long', day: 'numeric', month: 'long', hour: '2-digit', minute: '2-digit' };
  const local = new Intl.DateTimeFormat(getLang(), opts).format(ev.startsAt);
  // 3.6 : heure locale de l'événement si elle diffère de celle de l'appareil.
  const deviceTz = Intl.DateTimeFormat().resolvedOptions().timeZone;
  if (ev.timezone && ev.timezone !== deviceTz) {
    try {
      const there = new Intl.DateTimeFormat(getLang(), { hour: '2-digit', minute: '2-digit', timeZone: ev.timezone }).format(ev.startsAt);
      return `${local} (${there} ${ev.timezone})`;
    } catch {
      return local;
    }
  }
  return local;
}

function eventCard(ev) {
  const d = new Date(ev.startsAt);
  return html`<a class="event-card ${ev.cancelled ? 'cancelled' : ''}" href="#/event/${ev.id}">
    <span class="event-date"><b>${d.getDate()}</b><small>${new Intl.DateTimeFormat(getLang(), { month: 'short' }).format(d)}</small></span>
    <span class="grow" style="min-width:0">
      <span class="title" style="display:block">${ev.title}</span>
      <span class="preview">${ev.cancelled ? t('event.cancelled') : fmtEventDate(ev)}</span>
      <span class="preview">${ev.community ? `${ev.community.name} · ` : ''}${t('event.goingCount', { count: compact(ev.going) })}</span>
    </span>
    ${ev.myRsvp ? html`<span class="small" style="color:var(--world)">${t(`event.rsvp.${ev.myRsvp}`)}</span>` : ''}
  </a>`;
}

// ---------------- Liste des communautés ----------------
export async function communitiesScreen(root) {
  const main = layout(root, {
    universe: 'world',
    title: t('community.title'),
    left: backButton(),
    right: html`<a class="icon-btn" href="#/new-community" aria-label="${t('community.new')}">${icon('plus')}</a>`,
    tab: 'world',
  });
  wireBack(root, 'world');
  mount(main, skeleton(4));
  const [data, feed] = await Promise.all([get('/communities'), get('/feed/communities').catch(() => [])]);
  const row = (c) => html`<li><a class="list-item" href="#/community/${c.handle}">${cAvatar(c)}
    <span class="grow"><span class="title" style="display:block">${c.name}</span>
      <span class="preview">${t(`community.type.${c.type}`)} · ${t('community.members', { count: compact(c.members) })} · ${t(`community.cat.${c.category}`)}</span></span>
    ${c.status === 'pending' ? html`<span class="small muted">${t('community.pending')}</span>` : ''}
  </a></li>`;
  mount(
    main,
    html`<div class="chips">
        <a class="chip" href="#/events">${icon('star', 'width="14" height="14" style="vertical-align:-2px"')} ${t('event.title')}</a>
      </div>
      ${data.mine.length ? html`<div class="section-title">${t('community.mine')}</div><ul class="list">${data.mine.map(row)}</ul>` : ''}
      <div class="section-title">${t('community.discover')}</div>
      <div class="searchbar"><input class="input" type="search" data-q placeholder="${t('community.search')}" /></div>
      <ul class="list" data-discover>${data.discover.filter((c) => !c.role).map(row)}</ul>
      ${feed.length ? html`<div class="section-title">${t('community.feed')}</div><div data-feed></div>` : ''}
      ${!data.mine.length && !data.discover.length ? empty(t('community.empty'), t('community.emptyLead'), html`<a class="btn world" href="#/new-community">${t('community.new')}</a>`) : ''}`
  );
  if (feed.length) renderPosts($('[data-feed]', main), feed, '');
  $('[data-q]', main).addEventListener(
    'input',
    debounce(async (e) => {
      const r = await get(`/communities?q=${encodeURIComponent(e.target.value.trim())}`).catch(() => null);
      if (r) mount($('[data-discover]', main), html`${r.discover.map(row)}`);
    })
  );
}

// ---------------- Créer une communauté ----------------
export async function newCommunityScreen(root) {
  if (!(await ensureWorld())) return go('world');
  const main = layout(root, { universe: 'world', title: t('community.new'), left: backButton() });
  wireBack(root, 'communities');
  mount(
    main,
    html`<form class="section" data-form>
      <div class="field"><label>${t('channel.name')}</label><input class="input" data-name maxlength="80" required /></div>
      <div class="field"><label>${t('channel.handle')}</label><div class="row"><span class="muted">@</span><input class="input" data-handle maxlength="30" autocapitalize="none" required /></div></div>
      <div class="field"><label>${t('channel.description')}</label><textarea class="input" data-desc maxlength="1000"></textarea></div>
      <div class="field"><label>${t('community.category')}</label><select class="input" data-cat>${CATEGORIES.map((c) => html`<option value="${c}">${t(`community.cat.${c}`)}</option>`)}</select></div>
      ${['public', 'private', 'hidden'].map(
        (ty, i) => html`<label class="choice ${i === 0 ? 'selected' : ''}"><input type="radio" name="type" value="${ty}" ${i === 0 ? 'checked' : ''} /><div><h4>${t(`community.type.${ty}`)}</h4><p>${t(`community.typeDesc.${ty}`)}</p></div></label>`
      )}
      <div class="field"><label>${t('community.rules')}</label><textarea class="input" data-rules placeholder="${t('community.rulesHint')}">${t('community.defaultRules')}</textarea></div>
      <button class="btn world block" type="submit">${t('chat.create')}</button>
    </form>`
  );
  const name = $('[data-name]', main);
  const handle = $('[data-handle]', main);
  let edited = false;
  handle.addEventListener('input', () => ((edited = true), (handle.value = handle.value.toLowerCase().replace(/[^a-z0-9._]/g, ''))));
  name.addEventListener('input', () => !edited && (handle.value = name.value.toLowerCase().normalize('NFD').replace(/[^a-z0-9._]/g, '').slice(0, 30)));
  $$('input[name="type"]', main).forEach((r) => r.addEventListener('change', () => $$('.choice', main).forEach((ch) => ch.classList.toggle('selected', ch.contains(r) && r.checked))));
  $('[data-form]', main).addEventListener('submit', async (e) => {
    e.preventDefault();
    try {
      const c = await post('/communities', {
        name: name.value,
        handle: handle.value,
        description: $('[data-desc]', main).value,
        category: $('[data-cat]', main).value,
        type: $('input[name="type"]:checked', main).value,
        rules: $('[data-rules]', main).value.split('\n'),
      });
      go(`community/${c.handle}`);
    } catch (err) {
      showError(err);
    }
  });
}

// ---------------- Page d'une communauté ----------------
export async function communityScreen(root, { handle, tab = 'posts' }) {
  let c;
  try {
    c = await get(`/communities/${encodeURIComponent(handle)}`);
  } catch {
    const m = layout(root, { universe: 'world', title: t('community.title'), left: backButton() });
    wireBack(root, 'communities');
    return mount(m, empty(t('community.notFound')));
  }
  const main = layout(root, {
    universe: 'world',
    title: c.name,
    sub: `${t(`community.type.${c.type}`)} · ${t('community.members', { count: compact(c.members) })}`,
    left: backButton(),
    right: c.role ? html`<button class="icon-btn" data-menu aria-label="${t('common.more')}">${icon('more')}</button>` : '',
  });
  wireBack(root, 'communities');
  const isAdmin = ['owner', 'admin'].includes(c.role);
  const isMod = isAdmin || c.role === 'moderator';
  const tabLink = (k, label) => html`<a class="chip ${tab === k ? 'active' : ''}" href="#/community/${c.handle}/${k}">${label}</a>`;

  mount(
    main,
    html`<div class="ch-head">
        ${cAvatar(c, 'lg')}
        <h2>${c.name}</h2>
        <div class="muted">@${c.handle} · ${t(`community.cat.${c.category}`)}</div>
        ${c.description ? html`<p>${c.description}</p>` : ''}
        ${c.role
          ? html`<span class="small" style="color:var(--world)">${t(`community.role.${c.role}`)}</span>`
          : c.status === 'pending'
            ? html`<button class="btn ghost" disabled>${t('community.pending')}</button>`
            : html`<button class="btn world" data-join>${c.type === 'private' && c.status !== 'invited' ? t('community.request') : t('community.join')}</button>`}
      </div>
      ${c.rules.length ? html`<details class="rules"><summary>${t('community.rules')} (${c.rules.length})</summary><ol>${c.rules.map((r) => html`<li>${r}</li>`)}</ol></details>` : ''}
      <div class="chips">
        ${tabLink('posts', t('profile.posts'))} ${tabLink('events', t('event.title'))} ${tabLink('members', t('community.membersTab') + (c.pendingCount ? ` · ${c.pendingCount}` : ''))}
        ${isAdmin ? tabLink('log', t('community.log')) : ''}
      </div>
      <div data-pane></div>`
  );
  const pane = $('[data-pane]', main);
  $('[data-join]', main)?.addEventListener('click', async () => {
    if (!(await ensureWorld())) return;
    try {
      await post(`/communities/${c.id}/join`);
      communityScreen(root, { handle, tab });
    } catch (err) {
      showError(err);
    }
  });
  $('[data-menu]', root)?.addEventListener('click', () => {
    const items = [];
    if (isAdmin)
      items.push({
        label: t('community.invite'),
        icon: 'userPlus',
        run: async () => {
          const friends = await get('/friends').catch(() => []);
          pickPeople(friends, t('community.invite'), async (ids) => {
            for (const id of ids) await post(`/communities/${c.id}/members/${id}`, { action: 'invite' });
            toast(t('common.done'));
          });
        },
      });
    items.push({ label: t('world.copyLink'), icon: 'link', run: () => (navigator.clipboard?.writeText(`${location.origin}/#/community/${c.handle}`), toast(t('world.linkCopied'))) });
    if (c.role && c.role !== 'owner')
      items.push({
        label: t('community.leave'),
        icon: 'logout',
        danger: true,
        run: async () => {
          await post(`/communities/${c.id}/leave`).catch(showError);
          go('communities');
        },
      });
    actionSheet(items);
  });

  if (!c.canSeeContent && tab !== 'events') {
    mount(pane, empty(t('community.membersOnly'), t(`community.typeDesc.${c.type}`)));
    return;
  }

  if (tab === 'posts') {
    mount(
      pane,
      html`${c.role
          ? html`<form class="composer card-composer" data-form>
              <label class="icon-btn" aria-label="${t('chat.photo')}">${icon('image')}<input type="file" accept="image/*" data-file hidden /></label>
              <textarea rows="2" data-input maxlength="5000" placeholder="${t('community.placeholder')}"></textarea>
              <button class="send" aria-label="${t('share.publish')}">${icon('send')}</button>
            </form>`
          : ''}
        <div data-posts>${skeleton(2)}</div>`
    );
    const loadPosts = async () => {
      const posts = await get(`/communities/${c.id}/posts`).catch(() => []);
      const box = $('[data-posts]', pane);
      renderPosts(box, posts, empty(t('community.noPosts')));
      // Outils des modérateurs et admins sur chaque publication.
      if (isMod)
        $$('[data-post]', box).forEach((card) => {
          const p = posts.find((x) => x.id === Number(card.dataset.post));
          const bar = document.createElement('div');
          bar.className = 'mod-tools';
          mount(
            bar,
            html`${p.pinned ? html`<span class="small" style="color:var(--world)">📌 ${t('community.pinned')}</span>` : ''}
              ${isAdmin ? html`<button class="chip" data-pin>${p.pinned ? t('community.unpin') : t('community.pin')}</button>` : ''}
              <button class="chip" data-remove style="color:var(--garnet)">${t('community.removePost')}</button>`
          );
          card.prepend(bar);
          $('[data-pin]', bar)?.addEventListener('click', async () => (await post(`/communities/${c.id}/pin`, { postId: p.pinned ? null : p.id }).catch(showError), loadPosts()));
          $('[data-remove]', bar).addEventListener('click', async () => {
            if (!(await dialog({ title: t('community.removePost'), danger: true, confirm: t('me.delete') }))) return;
            await del(`/communities/${c.id}/posts/${p.id}`).catch(showError);
            loadPosts();
          });
        });
    };
    const form = $('[data-form]', pane);
    if (form) {
      const input = $('[data-input]', form);
      const send = async (payload) => {
        if (!(await ensureWorld())) return;
        try {
          await post(`/communities/${c.id}/posts`, payload);
          input.value = '';
          loadPosts();
        } catch (err) {
          showError(err);
        }
      };
      form.addEventListener('submit', (e) => (e.preventDefault(), input.value.trim() && send({ body: input.value.trim() })));
      $('[data-file]', form).addEventListener('change', async (e) => {
        try {
          send({ media: await readImage(e.target.files[0]), body: input.value.trim() });
        } catch (err) {
          showError(err);
        }
      });
    }
    await loadPosts();
  }

  if (tab === 'events') {
    const events = await get(`/communities/${c.id}/events`).catch(() => []);
    mount(
      pane,
      html`${c.role ? html`<div class="section"><a class="btn world block" href="#/new-event/${c.id}">${t('event.new')}</a></div>` : ''}
        ${events.length ? html`<div class="event-list">${events.map(eventCard)}</div>` : empty(t('event.empty'))}`
    );
  }

  if (tab === 'members') {
    const draw = async () => {
      const m = await get(`/communities/${c.id}/members`).catch(() => ({ members: [] }));
      mount(
        pane,
        html`${m.pending?.length
            ? html`<div class="section-title">${t('community.requests')}</div><ul class="list">${m.pending.map(
                (u) => html`<li class="list-item">${avatar(u, 'sm')}<span class="grow title">${u.name}</span>
                  <button class="btn small world" data-act="approve:${u.id}">${t('chat.accept')}</button>
                  <button class="btn small ghost" data-act="decline:${u.id}">${t('me.delete')}</button></li>`
              )}</ul>`
            : ''}
          <div class="section-title">${t('community.members', { count: compact(m.members.length) })}</div>
          <ul class="list">${m.members.map(
            (u) => html`<li class="list-item"><a href="#/u/${u.username}">${avatar(u, 'sm')}</a>
              <a class="grow" href="#/u/${u.username}" style="color:inherit"><span class="title" style="display:block">${u.name}</span><span class="preview">${t(`community.role.${u.role}`)}</span></a>
              ${isAdmin && u.role !== 'owner' && u.id !== store.me.id ? html`<button class="icon-btn" data-manage="${u.id}" aria-label="${t('common.more')}">${icon('more')}</button>` : ''}
            </li>`
          )}</ul>`
      );
      $$('[data-act]', pane).forEach((b) =>
        b.addEventListener('click', async () => {
          const [action, id] = b.dataset.act.split(':');
          await post(`/communities/${c.id}/members/${id}`, { action }).catch(showError);
          draw();
        })
      );
      $$('[data-manage]', pane).forEach((b) =>
        b.addEventListener('click', () => {
          const id = b.dataset.manage;
          const set = (role) => async () => (await post(`/communities/${c.id}/members/${id}`, { action: 'role', role }).catch(showError), draw());
          actionSheet([
            { label: t('community.makeAdmin'), icon: 'star', run: set('admin') },
            { label: t('community.makeModerator'), icon: 'lock', run: set('moderator') },
            { label: t('community.makeMember'), icon: 'me', run: set('member') },
            { label: t('community.removeMember'), icon: 'trash', danger: true, run: async () => (await post(`/communities/${c.id}/members/${id}`, { action: 'remove' }).catch(showError), draw()) },
          ]);
        })
      );
    };
    await draw();
  }

  if (tab === 'log' && isAdmin) {
    const log = await get(`/communities/${c.id}/log`).catch(() => []);
    mount(
      pane,
      log.length
        ? html`<ul class="list">${log.map((l) => html`<li class="list-item" style="cursor:default">${icon('archive')}<span class="grow"><span class="title" style="display:block">${l.actor?.name || ''} · ${t(`community.action.${l.action}`)}</span><span class="preview">${relTime(l.createdAt)}</span></span></li>`)}</ul>`
        : empty(t('community.noLog'))
    );
  }
}

// ---------------- Événements ----------------
export async function eventsScreen(root) {
  const main = layout(root, {
    universe: 'world',
    title: t('event.title'),
    left: backButton(),
    right: html`<a class="icon-btn" href="#/new-event" aria-label="${t('event.new')}">${icon('plus')}</a>`,
    tab: 'world',
  });
  wireBack(root, 'world');
  mount(main, skeleton(3));
  const data = await get('/events').catch(() => ({ mine: [], discover: [] }));
  mount(
    main,
    html`${data.mine.length ? html`<div class="section-title">${t('event.mine')}</div><div class="event-list">${data.mine.map(eventCard)}</div>` : ''}
      ${data.discover.length ? html`<div class="section-title">${t('event.discover')}</div><div class="event-list">${data.discover.map(eventCard)}</div>` : ''}
      ${!data.mine.length && !data.discover.length ? empty(t('event.empty'), t('event.emptyLead'), html`<a class="btn world" href="#/new-event">${t('event.new')}</a>`) : ''}`
  );
}

export async function eventScreen(root, { id }) {
  const main = layout(root, { universe: 'world', title: t('event.title'), left: backButton() });
  wireBack(root, 'events');
  const draw = async () => {
    let ev;
    try {
      ev = await get(`/events/${id}`);
    } catch {
      return mount(main, empty(t('event.notFound')));
    }
    mount(
      main,
      html`${ev.cover ? html`<img class="event-cover" src="${ev.cover}" alt="" />` : ''}
        <div class="section">
          ${ev.cancelled ? html`<p class="error"><b>${t('event.cancelled')}</b></p>` : ''}
          <h2 class="event-title">${ev.title}</h2>
          <p class="row small">${icon('timer', 'width="16" height="16"')} ${fmtEventDate(ev)}</p>
          ${ev.location ? html`<p class="row small">${icon('world', 'width="16" height="16"')} ${ev.location}</p>` : ''}
          ${ev.locationHidden ? html`<p class="row small muted">${icon('lock', 'width="16" height="16"')} ${t('event.addressHidden')}</p>` : ''}
          ${ev.onlineUrl ? html`<p class="row small">${icon('link', 'width="16" height="16"')} <a href="${ev.onlineUrl}" target="_blank" rel="noopener noreferrer">${ev.onlineUrl}</a></p>` : ''}
          <p class="row small">${avatar(ev.host, 'xs')} ${t('event.hostedBy', { name: ev.host.name })}${ev.community ? html` · <a href="#/community/${ev.community.handle}">${ev.community.name}</a>` : ''}</p>
          <p class="small muted">${t(`event.visibility.${ev.visibility}`)} · ${t('event.goingCount', { count: compact(ev.going) })} · ${t('event.interestedCount', { count: compact(ev.interested) })}</p>
          ${ev.description ? html`<p style="white-space:pre-wrap">${ev.description}</p>` : ''}
          ${ev.cancelled
            ? ''
            : html`<div class="rsvp">${['going', 'interested', 'cant'].map(
                (s) => html`<button class="btn small ${ev.myRsvp === s ? 'world' : 'ghost'}" data-rsvp="${s}">${t(`event.rsvp.${s}`)}</button>`
              )}</div>`}
          <div class="row" style="margin-top:12px;flex-wrap:wrap">
            <button class="btn small ghost" data-ics>${icon('archive', 'width="16" height="16"')} ${t('event.addCalendar')}</button>
            ${ev.isHost && !ev.cancelled ? html`<button class="btn small ghost" data-cancel style="color:var(--garnet)">${t('event.cancel')}</button>` : ''}
          </div>
        </div>
        ${ev.attendees.length
          ? html`<div class="section-title">${t('event.attendees')}</div><ul class="list">${ev.attendees.map(
              (u) => html`<li><a class="list-item" href="#/u/${u.username}">${avatar(u, 'sm')}<span class="grow title">${u.name}</span><span class="small muted">${t(`event.rsvp.${u.status}`)}</span></a></li>`
            )}</ul>`
          : ''}`
    );
    $$('[data-rsvp]', main).forEach((b) =>
      b.addEventListener('click', async () => {
        try {
          await post(`/events/${id}/rsvp`, { status: ev.myRsvp === b.dataset.rsvp ? null : b.dataset.rsvp });
          draw();
        } catch (err) {
          showError(err);
        }
      })
    );
    $('[data-ics]', main).addEventListener('click', async () => {
      const res = await fetch(`/api/events/${id}/ics`, { headers: { authorization: `Bearer ${getToken()}` } });
      await saveFile(await res.blob(), `mic-event-${id}.ics`).catch(showError);
    });
    $('[data-cancel]', main)?.addEventListener('click', async () => {
      if (!(await dialog({ title: t('event.cancel'), body: t('event.cancelLead'), danger: true, confirm: t('event.cancel') }))) return;
      await patch(`/events/${id}`, { cancelled: true }).catch(showError);
      draw();
    });
  };
  await draw();
}

export async function newEventScreen(root, { communityId } = {}) {
  const main = layout(root, { universe: 'world', title: t('event.new'), left: backButton() });
  wireBack(root, 'events');
  const tz = Intl.DateTimeFormat().resolvedOptions().timeZone;
  const pad = (n) => String(n).padStart(2, '0');
  const d = new Date(Date.now() + 24 * 3600 * 1000);
  const local = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T18:00`;
  let cover;
  mount(
    main,
    html`<form class="section" data-form>
      <div class="field"><label>${t('event.titleField')}</label><input class="input" data-title maxlength="120" required /></div>
      <div class="field"><label>${t('event.start')}</label><input class="input" type="datetime-local" data-start value="${local}" required /></div>
      <div class="field"><label>${t('event.end')}</label><input class="input" type="datetime-local" data-end /></div>
      <p class="hint">${t('event.timezone', { tz })}</p>
      <div class="field"><label>${t('event.location')}</label><input class="input" data-location maxlength="300" placeholder="${t('event.locationHint')}" /></div>
      <div class="field"><label>${t('event.online')}</label><input class="input" type="url" data-online maxlength="300" placeholder="https://" /></div>
      <div class="field"><label>${t('event.visibilityField')}</label><select class="input" data-vis>
        ${(communityId ? ['community', 'public'] : ['public', 'followers', 'friends']).map((v) => html`<option value="${v}">${t(`event.visibility.${v}`)}</option>`)}
      </select></div>
      <div class="field"><label>${t('channel.description')}</label><textarea class="input" data-desc maxlength="3000"></textarea></div>
      <label class="btn ghost small" style="margin-bottom:16px">${icon('image', 'width="16" height="16"')} ${t('event.cover')}<input type="file" accept="image/*" data-cover hidden /></label>
      <button class="btn world block" type="submit">${t('chat.create')}</button>
    </form>`
  );
  $('[data-cover]', main).addEventListener('change', async (e) => {
    try {
      cover = await readImage(e.target.files[0], 1200);
      toast(t('common.done'));
    } catch (err) {
      showError(err);
    }
  });
  $('[data-form]', main).addEventListener('submit', async (e) => {
    e.preventDefault();
    const end = $('[data-end]', main).value;
    try {
      const ev = await post('/events', {
        title: $('[data-title]', main).value,
        startsAt: new Date($('[data-start]', main).value).getTime(),
        endsAt: end ? new Date(end).getTime() : null,
        timezone: tz,
        location: $('[data-location]', main).value,
        onlineUrl: $('[data-online]', main).value,
        visibility: $('[data-vis]', main).value,
        description: $('[data-desc]', main).value,
        cover,
        communityId: communityId ? Number(communityId) : undefined,
      });
      go(`event/${ev.id}`);
    } catch (err) {
      showError(err);
    }
  });
}
