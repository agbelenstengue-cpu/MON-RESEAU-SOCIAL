// Section 13 (caméra MIC, filtres) et 4.5 (sélecteur d'audience).
import { t } from '../i18n.js';
import { store, get, post, patch, readImage } from '../api.js';
import { html, mount, $, $$, icon, avatar, sheet, dialog, toast, showError, errorText } from '../ui.js';
import { layout, go } from '../app.js';

// Filtres MIC (13.5) : réglages de couleur aux tons de la marque.
const FILTERS = {
  none: 'none',
  ivory: 'brightness(1.08) contrast(0.94) saturate(0.85) sepia(0.12)',
  cognac: 'sepia(0.35) saturate(1.25) contrast(1.05)',
  emerald: 'hue-rotate(-12deg) saturate(1.2) contrast(1.06) brightness(0.98)',
  noir: 'grayscale(1) contrast(1.18)',
  brass: 'sepia(0.5) brightness(1.04) saturate(1.35)',
};
const BACKGROUNDS = ['espresso', 'cognac', 'emerald', 'sage', 'brass', 'ebony'];

export async function createScreen(root, { mode = 'photo' } = {}) {
  const state = { mode: mode === 'text' ? 'text' : 'photo', facing: 'environment', source: null, filter: 'none', caption: '', text: '', bg: 'espresso' };
  let stream = null;

  const stopStream = () => {
    stream?.getTracks().forEach((tr) => tr.stop());
    stream = null;
  };

  const main = layout(root, {
    universe: 'me',
    title: t('nav.camera'),
    tab: 'create',
    flush: true,
  });
  document.body.dataset.universe = 'me';

  const draw = async () => {
    stopStream();
    const modes = html`<div class="modes" role="tablist">
      <button data-mode="photo" class="${state.mode === 'photo' ? 'active' : ''}">${t('camera.photo')}</button>
      <button data-mode="text" class="${state.mode === 'text' ? 'active' : ''}">${t('camera.text')}</button>
    </div>`;

    if (state.mode === 'text') {
      mount(
        main,
        html`<div class="camera">
          ${modes}
          <div class="text-canvas bg-${state.bg}" data-canvas>
            <textarea data-text maxlength="500" placeholder="${t('camera.typeSomething')}" aria-label="${t('camera.text')}">${state.text}</textarea>
          </div>
          <div class="bg-picker">${BACKGROUNDS.map((b) => html`<button class="bg-${b} ${state.bg === b ? 'active' : ''}" data-bg="${b}" aria-label="${b}"></button>`)}</div>
          <div class="shutter-row"><button class="btn world" data-next disabled style="--world:var(--brass);min-width:160px">${t('camera.next')}</button></div>
        </div>`
      );
      const ta = $('[data-text]', main);
      const next = $('[data-next]', main);
      ta.focus();
      const sync = () => {
        state.text = ta.value;
        next.disabled = !ta.value.trim();
      };
      sync();
      ta.addEventListener('input', sync);
      $$('[data-bg]', main).forEach((b) =>
        b.addEventListener('click', () => {
          state.bg = b.dataset.bg;
          $('[data-canvas]', main).className = `text-canvas bg-${state.bg}`;
          $$('[data-bg]', main).forEach((x) => x.classList.toggle('active', x === b));
        })
      );
      next.addEventListener('click', () => openAudience({ kind: 'text', body: state.text.trim(), bg: state.bg }));
    } else if (!state.source) {
      mount(
        main,
        html`<div class="camera">
          ${modes}
          <div class="viewport"><video data-video autoplay playsinline muted></video><p data-nocam class="center" style="padding:24px;opacity:.8" hidden>${t('camera.noCamera')}</p></div>
          <div class="shutter-row">
            <label class="icon-btn" aria-label="${t('camera.gallery')}">${icon('image')}<input type="file" accept="image/*" data-file hidden /></label>
            <button class="shutter" data-shutter aria-label="${t('camera.photo')}"></button>
            <button class="icon-btn" data-flip aria-label="${t('camera.flip')}">${icon('flip')}</button>
          </div>
        </div>`
      );
      const video = $('[data-video]', main);
      try {
        if (!navigator.mediaDevices?.getUserMedia) throw new Error('no camera');
        stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: state.facing }, audio: false });
        if (!main.isConnected) return stopStream();
        video.srcObject = stream;
      } catch {
        video.hidden = true;
        $('[data-nocam]', main).hidden = false;
        $('[data-shutter]', main).disabled = true;
      }
      $('[data-shutter]', main).addEventListener('click', () => {
        if (!video.videoWidth) return;
        const c = document.createElement('canvas');
        const scale = Math.min(1, 1600 / Math.max(video.videoWidth, video.videoHeight));
        c.width = video.videoWidth * scale;
        c.height = video.videoHeight * scale;
        c.getContext('2d').drawImage(video, 0, 0, c.width, c.height);
        state.source = c.toDataURL('image/jpeg', 0.9);
        draw();
      });
      $('[data-flip]', main).addEventListener('click', () => {
        state.facing = state.facing === 'environment' ? 'user' : 'environment';
        draw();
      });
      $('[data-file]', main).addEventListener('change', async (e) => {
        try {
          state.source = await readImage(e.target.files[0]);
          draw();
        } catch (err) {
          showError(err);
        }
      });
    } else {
      mount(
        main,
        html`<div class="camera">
          <div class="viewport"><img class="preview-img" data-preview src="${state.source}" alt="" style="filter:${FILTERS[state.filter]}" /></div>
          <div class="filters">${Object.keys(FILTERS).map((f) => html`<button data-filter="${f}" class="${state.filter === f ? 'active' : ''}">${t(`filter.${f}`)}</button>`)}</div>
          <div class="caption-bar"><textarea class="input" data-caption maxlength="2200" placeholder="${t('camera.caption')}">${state.caption}</textarea></div>
          <div class="shutter-row">
            <button class="btn ghost" data-retake style="color:#fff;border-color:rgba(255,255,255,.3)">${t('camera.retake')}</button>
            <button class="btn" data-next style="background:var(--brass);color:#1c1a19;min-width:140px">${t('camera.next')}</button>
          </div>
        </div>`
      );
      $$('[data-filter]', main).forEach((b) =>
        b.addEventListener('click', () => {
          state.filter = b.dataset.filter;
          $('[data-preview]', main).style.filter = FILTERS[state.filter];
          $$('[data-filter]', main).forEach((x) => x.classList.toggle('active', x === b));
        })
      );
      $('[data-caption]', main).addEventListener('input', (e) => (state.caption = e.target.value));
      $('[data-retake]', main).addEventListener('click', () => {
        state.source = null;
        state.filter = 'none';
        draw();
      });
      $('[data-next]', main).addEventListener('click', async () => {
        const media = await applyFilter(state.source, FILTERS[state.filter]);
        openAudience({ kind: 'image', media, body: state.caption.trim() });
      });
    }
    $$('[data-mode]', main).forEach((b) =>
      b.addEventListener('click', () => {
        state.mode = b.dataset.mode;
        draw();
      })
    );
  };

  await draw();
  return stopStream;
}

function applyFilter(src, filter) {
  if (filter === 'none') return Promise.resolve(src);
  return new Promise((resolve) => {
    const img = new Image();
    img.onload = () => {
      const c = document.createElement('canvas');
      c.width = img.width;
      c.height = img.height;
      const ctx = c.getContext('2d');
      ctx.filter = filter;
      ctx.drawImage(img, 0, 0);
      resolve(c.toDataURL('image/jpeg', 0.88));
    };
    img.onerror = () => resolve(src);
    img.src = src;
  });
}

// ---------------- Sélecteur d'audience « Share with… » (4.5) ----------------
const PRIVATE_KEYS = ['only_me', 'story_friends', 'story_close'];

function lastPrivate() {
  try {
    return JSON.parse(localStorage.getItem('mic.lastPrivate') || '[]').filter((k) => PRIVATE_KEYS.includes(k));
  } catch {
    return [];
  }
}

export async function openAudience(content, { onDone } = {}) {
  const convs = (await get('/conversations').catch(() => [])).filter((c) => c.status === 'active' && !c.blocked && !(c.type === 'group' && c.announceOnly && c.role !== 'admin'));
  // Les destinations privées sont pré-cochées selon le dernier choix ; jamais les publiques.
  const sel = new Set(lastPrivate());
  const chats = new Set();
  const settings = { audience: 'everyone', whoCanComment: 'everyone', hideLikes: false };
  let showChats = false;

  sheet((box, close) => {
    const draw = () => {
      const pub = ['post_world', 'world_story'].filter((k) => sel.has(k)).length;
      const priv = PRIVATE_KEYS.filter((k) => sel.has(k)).length + chats.size;
      const opt = (key, label, desc = '') => html`<label class="aud-option">
        <input type="checkbox" data-key="${key}" ${sel.has(key) ? 'checked' : ''} />
        <span class="grow">${label}${desc ? html`<small>${desc}</small>` : ''}</span>
      </label>`;
      const select = (key, options, value) => html`<select class="input" data-setting="${key}">${options.map((o) => html`<option value="${o}" ${o === value ? 'selected' : ''}>${t(`aud.${o}`)}</option>`)}</select>`;
      mount(
        box,
        html`<div class="grabber"></div>
          <h2>${t('share.title')}</h2>
          <div class="aud-block private">
            <div class="aud-title">${icon('lock', 'width="12" height="12" style="vertical-align:-1px"')} ${t('share.private')} · Me</div>
            ${opt('only_me', t('share.onlyMe'), t('share.onlyMeDesc'))}
            ${opt('story_friends', t('share.storyFriends'))}
            ${opt('story_close', t('share.storyClose'))}
            <label class="aud-option"><input type="checkbox" data-sendto ${showChats || chats.size ? 'checked' : ''} /><span class="grow">${t('share.sendTo')}<small>${chats.size ? `${chats.size} ✓` : t('share.sendToDesc')}</small></span></label>
            ${showChats
              ? html`<div class="dest-list">${convs.length
                  ? convs.map(
                      (c) => html`<label class="list-item">${c.type === 'direct' ? avatar(c.peer, 'xs') : avatar({ name: c.title }, 'xs')}<span class="grow title">${c.type === 'direct' ? c.peer?.name : c.title}</span><input type="checkbox" data-chat="${c.id}" ${chats.has(c.id) ? 'checked' : ''} /></label>`
                    )
                  : html`<p class="muted small center">${t('share.noChats')}</p>`}</div>`
              : ''}
          </div>
          <div class="aud-block public">
            <div class="aud-title">${icon('world', 'width="12" height="12" style="vertical-align:-1px"')} ${t('share.publicBlock')} · World</div>
            ${opt('post_world', t('share.postWorld'))}
            ${opt('world_story', t('share.worldStory'))}
            ${sel.has('post_world')
              ? html`<div class="post-settings">
                  <div class="row"><label>${t('share.whoView')}</label>${select('audience', ['everyone', 'followers', 'friends', 'only_me'], settings.audience)}</div>
                  <div class="row"><label>${t('share.whoComment')}</label>${select('whoCanComment', ['everyone', 'followers', 'friends', 'nobody'], settings.whoCanComment)}</div>
                  <label class="row"><span class="grow">${t('share.hideLikes')}</span><input type="checkbox" class="toggle" data-hidelikes ${settings.hideLikes ? 'checked' : ''} /></label>
                </div>`
              : ''}
          </div>
          ${pub ? html`<div class="public-banner">${icon('world', 'width="14" height="14" style="vertical-align:-2px"')} ${t('share.public')}</div>` : ''}
          <div class="aud-summary">${t('share.summary', { p: priv, w: pub })}</div>
          <div class="sheet-actions">
            <button class="btn block ${pub ? 'world' : 'me'}" data-submit ${priv + pub ? '' : 'disabled'}>${pub ? t('share.publish') : t('share.send')}</button>
          </div>`
      );
      $$('[data-key]', box).forEach((cb) =>
        cb.addEventListener('change', () => {
          cb.checked ? sel.add(cb.dataset.key) : sel.delete(cb.dataset.key);
          draw();
        })
      );
      $('[data-sendto]', box).addEventListener('change', (e) => {
        showChats = e.target.checked;
        if (!showChats) chats.clear();
        draw();
      });
      $$('[data-chat]', box).forEach((cb) =>
        cb.addEventListener('change', () => {
          const id = Number(cb.dataset.chat);
          if (cb.checked && chats.size >= 5) {
            cb.checked = false;
            return;
          }
          cb.checked ? chats.add(id) : chats.delete(id);
          draw();
        })
      );
      $$('[data-setting]', box).forEach((s) => s.addEventListener('change', () => (settings[s.dataset.setting] = s.value)));
      $('[data-hidelikes]', box)?.addEventListener('change', (e) => (settings.hideLikes = e.target.checked));
      $('[data-submit]', box).addEventListener('click', async (e) => {
        e.target.disabled = true;
        const ok = await submit();
        if (ok) close();
        else if (e.target.isConnected) e.target.disabled = false;
      });
    };

    const submit = async () => {
      const isPublic = sel.has('post_world') || sel.has('world_story');
      if (isPublic && !(await ensureWorld())) return false;
      // Confirmation pédagogique de la première publication publique (une seule fois).
      if (isPublic && !store.me.firstPublicDone) {
        const okFirst = await dialog({ title: t('share.firstTitle'), body: t('share.firstBody'), confirm: t('share.understand') });
        if (!okFirst) return false;
        store.me = await patch('/me', { firstPublicDone: true });
      }
      try {
        localStorage.setItem('mic.lastPrivate', JSON.stringify(PRIVATE_KEYS.filter((k) => sel.has(k))));
      } catch {
        /* ignore */
      }
      const story = (audience) =>
        post('/stories', content.kind === 'image' ? { audience, kind: 'image', media: content.media, body: content.body } : { audience, kind: 'text', body: content.body, bg: content.bg });
      const jobs = [];
      if (sel.has('only_me')) jobs.push(story('only_me'));
      if (sel.has('story_friends')) jobs.push(story('friends'));
      if (sel.has('story_close')) jobs.push(story('close_friends'));
      if (sel.has('world_story')) jobs.push(story('world'));
      if (sel.has('post_world')) jobs.push(post('/posts', { body: content.body, media: content.kind === 'image' ? content.media : undefined, ...settings }));
      for (const id of chats) {
        jobs.push(
          post(`/conversations/${id}/messages`, content.kind === 'image' ? { kind: 'image', media: content.media, body: content.body } : { body: content.body })
        );
      }
      const results = await Promise.allSettled(jobs);
      const failed = results.find((r) => r.status === 'rejected');
      if (failed) {
        toast(errorText(failed.reason));
        if (results.every((r) => r.status === 'rejected')) return false;
      } else toast(t('share.done'));
      if (onDone) onDone();
      else if (isPublic) go('world/following');
      else if (chats.size === 1 && sel.size === 0) go(`chat/${[...chats][0]}`);
      else if (chats.size && sel.size === 0) go('chats');
      else go('stories');
      return true;
    };
    draw();
  });
}

// Présence World requise pour publier (4.2) : écran d'explication unique.
export async function ensureWorld() {
  if (store.me.world.enabled) return true;
  const ok = await dialog({ title: t('me.activateWorld'), body: t('me.activateWorldLead'), confirm: t('me.activateWorld') });
  if (!ok) return false;
  try {
    store.me = await post('/me/world', { enable: true });
  } catch (err) {
    if (err.code !== 'minor_world_private_only') {
      showError(err);
      return false;
    }
    store.me = await post('/me/world', { enable: true, private: true });
  }
  return true;
}
