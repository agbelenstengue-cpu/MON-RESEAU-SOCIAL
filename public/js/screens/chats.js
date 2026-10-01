// Section 7.3 (onglet Chats), 8 (messagerie) et 11 (groupes).
import { t, clock, dayLabel, listTime } from '../i18n.js';
import { store, get, post, patch, put, del, on, sendWs, readImage } from '../api.js';
import { html, raw, mount, $, $$, icon, avatar, richText, toast, showError, dialog, sheet, actionSheet, reportFlow, empty, skeleton, debounce } from '../ui.js';
import { layout, go, backButton, wireBack, refreshBadges } from '../app.js';
import { VoiceRecorder, blobToDataUrl, fmtDuration, waveformHtml, player } from '../voice.js';
import { startCall, joinCall, inCall } from '../calls.js';

const QUICK = ['❤️', '😂', '😮', '😢', '🙏', '👍'];
const EDIT_WINDOW = 15 * 60 * 1000;
const DELETE_WINDOW = 48 * 3600 * 1000;

function convName(c) {
  return c.type === 'direct' ? c.peer?.name || '—' : c.title;
}
function convAvatar(c, size = '') {
  return c.type === 'direct' ? avatar(c.peer, size) : avatar({ name: c.title }, size);
}

export function presenceText(user) {
  if (!user) return '';
  if (user.online) return t('chat.online');
  if (user.lastSeen) return t('chat.lastSeen', { time: `${dayLabel(user.lastSeen).toLowerCase()} ${clock(user.lastSeen)}` });
  return '';
}

function previewText(m, c) {
  if (!m) return '';
  const who = c.type === 'group' && m.sender && m.sender.id !== store.me.id ? `${m.sender.name}: ` : '';
  if (m.deleted) return t('chat.deleted');
  if (m.kind === 'system') return systemText(m);
  if (m.kind === 'image') return `${who}📷 ${t('chat.photo')}`;
  if (m.kind === 'voice') return `${who}🎤 ${t('voice.message')} (${fmtDuration(m.meta?.duration)})`;
  if (m.kind === 'call') return callText(m);
  if (m.kind === 'post') return `${who}🌍 ${t('chat.sharedPost')}`;
  return who + m.body;
}

function callText(m) {
  const video = m.meta?.type === 'video';
  if (m.meta?.status === 'missed') return `${video ? '📹' : '📞'} ${t(m.sender?.id === store.me.id ? 'call.noAnswerMsg' : 'call.missed')}`;
  return `${video ? '📹' : '📞'} ${t(video ? 'call.videoCall' : 'call.audioCall')} · ${fmtDuration(m.meta?.duration)}`;
}

function systemText(m) {
  return t(`chat.sys.${m.body}`, { name: m.sender?.name || '' });
}

// ---------------- Liste des discussions ----------------
export async function chatsScreen(root, { filter = 'all' } = {}) {
  const main = layout(root, {
    universe: 'me',
    title: t('nav.chats'),
    tab: 'chats',
    left: html`<a href="#/me" aria-label="${t('nav.me')}">${avatar({ name: store.me.displayName, avatar: store.me.avatar }, 'sm')}</a>`,
    right: html`<a class="icon-btn" href="#/search" aria-label="${t('search.title')}">${icon('search')}</a>
      <button class="icon-btn" data-new aria-label="${t('chats.newChat')}">${icon('edit')}</button>`,
  });
  $('[data-new]', root).addEventListener('click', () =>
    actionSheet([
      { label: t('chats.newChat'), icon: 'chats', run: () => go('new-chat') },
      { label: t('chats.newGroup'), icon: 'users', run: () => go('new-group') },
    ])
  );
  mount(main, skeleton(6));

  let convs = [];
  const draw = () => {
    const requests = convs.filter((c) => c.status === 'request');
    const active = convs.filter((c) => c.status === 'active');
    let list = filter === 'requests' ? requests : active;
    if (filter === 'unread') list = list.filter((c) => c.unread > 0);
    if (filter === 'groups') list = list.filter((c) => c.type === 'group');
    const chip = (key, label, extra = '') => html`<a class="chip ${filter === key ? 'active' : ''}" href="#/chats/${key}">${label}${extra}</a>`;
    mount(
      main,
      html`<div class="chips" role="tablist">
          ${chip('all', t('chats.all'))} ${chip('unread', t('chats.unread'))} ${chip('groups', t('chats.groups'))}
          ${chip('requests', t('chats.requests'), requests.length ? html` · ${requests.length}` : '')}
          <a class="chip" href="#/calls">${t('call.history')}</a>
        </div>
        ${list.length
          ? html`<ul class="list">
              ${list.map(
                (c) => html`<li>
                  <a class="list-item" href="#/chat/${c.id}">
                    ${convAvatar(c)}
                    <div class="grow">
                      <div class="title">${convName(c)}</div>
                      <div class="preview">${previewText(c.lastMessage, c)}</div>
                    </div>
                    <div class="meta">
                      <span>${listTime(c.updatedAt)}</span>
                      ${c.unread && c.status === 'active' ? html`<span class="badge">${c.unread}</span>` : ''}
                    </div>
                  </a>
                </li>`
              )}
            </ul>`
          : filter === 'requests'
            ? empty(t('chats.requestsEmpty'))
            : empty(t('chats.empty'), t('chats.emptyLead'), html`<a class="btn" href="#/new-chat">${t('chats.newChat')}</a>`)}`
    );
  };

  const load = async () => {
    try {
      convs = await get('/conversations');
      draw();
    } catch (err) {
      showError(err);
    }
  };
  await load();
  const reload = debounce(load, 150);
  const offs = ['message', 'message:update', 'receipts', 'conversation:new', 'conversation:update', 'presence'].map((ev) => on(ev, reload));
  return () => offs.forEach((off) => off());
}

// ---------------- Conversation ----------------
export async function chatScreen(root, { id }) {
  const convId = Number(id);
  let conv;
  try {
    conv = await get(`/conversations/${convId}`);
  } catch (err) {
    showError(err);
    return go('chats');
  }
  let messages = [];
  let replyTo = null;
  let editing = null;
  let typingTimer = null;
  let typingUntil = 0;
  let lastTypingSent = 0;
  let loadingOlder = false;
  let noMore = false;

  const header = () => html`${backButton()}
    <a class="row grow" style="color:inherit" ${conv.type === 'direct' && conv.peer ? raw(`href="#/u/${encodeURIComponent(conv.peer.username)}"`) : raw('href="#" data-info')}>
      ${convAvatar(conv, 'sm')}
      <span class="grow" style="min-width:0">
        <span style="display:block;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${convName(conv)}</span>
        <span class="small muted" data-presence>${subtitle()}</span>
      </span>
    </a>
    ${canCall() ? html`<button class="icon-btn" data-call="audio" aria-label="${t('call.audioCall')}">${icon('phone')}</button>
      <button class="icon-btn" data-call="video" aria-label="${t('call.videoCall')}">${icon('video')}</button>` : ''}
    <button class="icon-btn" data-menu aria-label="${t('common.more')}">${icon('more')}</button>`;

  const canCall = () => conv.status === 'active' && !(conv.type === 'direct' && (conv.blocked || !conv.peer));
  let typingActivity = 'typing';

  const subtitle = () => {
    if (typingUntil > Date.now()) return html`<span class="typing">${t(typingActivity === 'recording' ? 'chat.recording' : 'chat.typing')}</span>`;
    if (conv.type === 'group') return t('chat.members', { count: conv.memberCount });
    return presenceText(conv.peer);
  };

  setUniverseMe();
  mount(
    root,
    html`<div class="chat-screen">
      <header class="topbar" data-head></header>
      <div data-callbar></div>
      <div class="messages" data-list role="log" aria-live="polite"></div>
      <div data-bottom></div>
    </div>`
  );
  const list = $('[data-list]', root);
  const head = $('[data-head]', root);
  const bottom = $('[data-bottom]', root);
  const callbar = $('[data-callbar]', root);

  // Bandeau « Appel en cours · Rejoindre » (10.2).
  const drawCallbar = () => {
    const c = conv.activeCall;
    const mineActive = inCall()?.id && c && inCall().id === c.id;
    if (!c || mineActive || !c.participants.length || c.participants.includes(store.me.id)) return mount(callbar, '');
    mount(
      callbar,
      html`<div class="call-banner">${icon(c.type === 'video' ? 'video' : 'phone')}<span class="grow">${t('call.ongoing', { count: c.participants.length })}</span>
        <button class="btn small world" data-joincall>${t('call.join')}</button></div>`
    );
    $('[data-joincall]', callbar).addEventListener('click', () => joinCall(conv, c));
  };

  const drawHead = () => {
    mount(head, header());
    wireBack(head, 'chats');
    $('[data-menu]', head).addEventListener('click', openMenu);
    $$('[data-call]', head).forEach((b) => b.addEventListener('click', () => startCall(conv, b.dataset.call)));
    $('[data-info]', head)?.addEventListener('click', (e) => {
      e.preventDefault();
      openGroupInfo();
    });
  };

  const bubble = (m) => {
    if (m.kind === 'system') return html`<div class="system-msg">${systemText(m)}</div>`;
    if (m.kind === 'call') {
      const missed = m.meta?.status === 'missed';
      return html`<div class="system-msg call-msg ${missed && m.sender?.id !== store.me.id ? 'missed' : ''}">${callText(m)} · ${clock(m.createdAt)}
        ${canCall() ? html`<button class="chip" data-callback="${m.meta?.type || 'audio'}">${t('call.callBack')}</button>` : ''}</div>`;
    }
    const mine = m.sender?.id === store.me.id;
    const showSender = conv.type === 'group' && !mine;
    const ticks =
      mine && !m.deleted
        ? html`<span class="ticks ${m.status === 'read' ? 'read' : ''}" aria-label="${m.status}">${icon(m.status === 'sent' ? 'check' : 'checks', 'width="15" height="15"')}</span>`
        : '';
    let content;
    if (m.deleted) content = html`<span class="deleted">${t('chat.deleted')}</span>`;
    else if (m.kind === 'image') content = html`<img class="media" src="${m.media}" alt="${t('chat.photo')}" loading="lazy" />${m.body ? html`<div class="text">${richText(m.body)}</div>` : ''}`;
    else if (m.kind === 'voice') content = voiceBubble(m, mine);
    else if (m.kind === 'post') content = html`${postCard(m.post)}${m.body ? html`<div class="text">${richText(m.body)}</div>` : ''}`;
    else content = html`<div class="text">${richText(m.body)}</div>`;
    const counts = {};
    m.reactions.forEach((r) => (counts[r.emoji] = (counts[r.emoji] || 0) + 1));
    return html`<div class="bubble-row ${mine ? 'mine' : ''}" data-mid="${m.id}">
      <div class="bubble" tabindex="0">
        ${showSender ? html`<div class="sender">${m.sender?.name}</div>` : ''}
        ${m.replyTo ? html`<div class="quote"><b>${m.replyTo.senderName}</b><br />${m.replyTo.deleted ? t('chat.deleted') : m.replyTo.kind === 'image' ? '📷 ' + t('chat.photo') : m.replyTo.kind === 'voice' ? '🎤 ' + t('voice.message') : m.replyTo.body}</div>` : ''}
        ${content}
        <div class="meta">${m.editedAt && !m.deleted ? html`<span>${t('chat.edited')}</span>` : ''}<span>${clock(m.createdAt)}</span>${ticks}</div>
      </div>
      ${Object.keys(counts).length ? html`<div class="reactions">${Object.entries(counts).map(([e, n]) => html`<span>${e}${n > 1 ? n : ''}</span>`)}</div>` : ''}
    </div>`;
  };

  // Bulle vocale (9.3) : lecture, onde cliquable, durée, vitesse, statut écouté.
  const voiceBubble = (m, mine) => {
    const s = player.state();
    const playing = s && s.id === m.id;
    const d = m.meta?.duration || 0;
    return html`<div class="voice" data-voice="${m.id}">
      <button class="vplay" data-v="play" aria-label="${playing && s.playing ? t('voice.pause') : t('voice.play')}">${icon(playing && s.playing ? 'pause' : 'play')}</button>
      <div class="wave" data-v="seek" role="slider" aria-label="${t('voice.message')}" aria-valuemin="0" aria-valuemax="${Math.round(d / 1000)}">${waveformHtml(m.meta?.waveform, playing ? s.progress : 0)}</div>
      <div class="vmeta">
        <span data-vtime>${fmtDuration(playing ? s.current : d)}</span>
        <button class="vrate" data-v="rate">${player.rate()}×</button>
        ${mine
          ? html`<span class="vstate ${m.played ? 'played' : ''}" title="${m.played ? t('voice.played') : ''}">${icon('mic', 'width="14" height="14"')}</span>`
          : m.playedByMe
            ? ''
            : html`<span class="vdot" title="${t('voice.unplayed')}"></span>`}
      </div>
    </div>`;
  };

  const voiceOpts = (m) => ({
    title: m.sender?.id === store.me.id ? t('stories.my') : m.sender?.name || '',
    convId,
    mine: m.sender?.id === store.me.id,
    // Lecture continue : le vocal reçu non écouté suivant démarre automatiquement.
    next: (cur) => {
      const nm = messages.find((x) => x.id > cur.id && x.kind === 'voice' && !x.deleted && !x.playedByMe && x.sender?.id !== store.me.id);
      return nm ? { message: nm, ...voiceOpts(nm) } : null;
    },
  });

  const updateVoice = (s) => {
    $$('[data-voice]', list).forEach((el) => {
      const m = messages.find((x) => x.id === Number(el.dataset.voice));
      if (!m) return;
      const playing = s && s.id === m.id;
      const btn = $('[data-v="play"]', el);
      mount(btn, icon(playing && s.playing ? 'pause' : 'play'));
      const bars = $$('.wave i', el);
      bars.forEach((b, i) => b.classList.toggle('on', !!playing && i / bars.length < s.progress));
      $('[data-vtime]', el).textContent = fmtDuration(playing ? s.current : m.meta?.duration);
      $('[data-v="rate"]', el).textContent = `${player.rate()}×`;
      if (playing && m.playedByMe) $('.vdot', el)?.remove();
    });
  };

  const drawList = (keepBottom = true) => {
    const nearBottom = list.scrollHeight - list.scrollTop - list.clientHeight < 120;
    const prevHeight = list.scrollHeight;
    const prevTop = list.scrollTop;
    let lastDay = '';
    const items = [html`<div class="e2ee-note">${icon('lock', 'width="12" height="12" style="vertical-align:-2px"')} ${t('chat.e2ee')}</div>`];
    for (const m of messages) {
      const day = new Date(m.createdAt).toDateString();
      if (day !== lastDay) {
        items.push(html`<div class="day-sep">${dayLabel(m.createdAt)}</div>`);
        lastDay = day;
      }
      items.push(bubble(m));
    }
    mount(list, html`${items}`);
    if (keepBottom === 'top') list.scrollTop = list.scrollHeight - prevHeight + prevTop;
    else if (keepBottom === 'force' || nearBottom) list.scrollTop = list.scrollHeight;
    else list.scrollTop = prevTop;
  };

  const drawBottom = () => {
    if (conv.status === 'request') {
      mount(
        bottom,
        html`<div class="request-banner">
          <b>${t('chat.requestTitle', { name: convName(conv) })}</b>
          <p class="small muted" style="margin:4px 0 0">${t('chat.requestLead')}</p>
          <div class="row">
            <button class="btn ghost" data-block>${t('chat.block')}</button>
            <button class="btn" data-accept>${t('chat.accept')}</button>
          </div>
        </div>`
      );
      $('[data-accept]', bottom).addEventListener('click', async () => {
        conv = await post(`/conversations/${convId}/accept`);
        drawBottom();
        markRead();
      });
      $('[data-block]', bottom).addEventListener('click', () => blockPeer());
      return;
    }
    if (conv.type === 'direct' && conv.blocked) {
      mount(bottom, html`<div class="request-banner"><span class="muted">${t('chat.blockedBanner')}</span><div class="row"><button class="btn soft" data-unblock>${t('chat.unblock')}</button></div></div>`);
      $('[data-unblock]', bottom).addEventListener('click', async () => {
        await del(`/users/${conv.peer.id}/block`);
        conv = await get(`/conversations/${convId}`);
        drawBottom();
      });
      return;
    }
    if (conv.type === 'group' && conv.announceOnly && conv.role !== 'admin') {
      mount(bottom, html`<div class="request-banner muted small">${t('chat.announceOnly')}</div>`);
      return;
    }
    const bar = replyTo
      ? html`<div class="reply-bar"><span class="grow">${t('chat.replyingTo', { name: replyTo.sender?.name || '' })} — <span class="muted">${(replyTo.body || (replyTo.kind === 'voice' ? '🎤' : '📷')).slice(0, 80)}</span></span><button class="icon-btn" data-cancel aria-label="${t('common.cancel')}">${icon('close')}</button></div>`
      : editing
        ? html`<div class="reply-bar"><span class="grow">${t('chat.editing')}</span><button class="icon-btn" data-cancel aria-label="${t('common.cancel')}">${icon('close')}</button></div>`
        : '';
    mount(
      bottom,
      html`${bar}
        <form class="composer" data-composer>
          <label class="icon-btn" aria-label="${t('chat.photo')}">${icon('image')}<input type="file" accept="image/*" data-file hidden /></label>
          <textarea rows="1" data-input placeholder="${t('chat.placeholder')}" aria-label="${t('chat.placeholder')}">${editing ? editing.body : ''}</textarea>
          <button class="send" type="submit" data-send aria-label="${t('share.send')}" ${editing ? '' : 'hidden'}>${icon('send')}</button>
          ${editing ? '' : html`<button class="send mic" type="button" data-mic aria-label="${t('voice.record')}" title="${t('voice.holdHint')}">${icon('mic')}</button>`}
        </form>`
    );
    const input = $('[data-input]', bottom);
    const form = $('[data-composer]', bottom);
    const syncButtons = () => {
      if (editing) return;
      const hasText = !!input.value.trim();
      $('[data-send]', bottom).hidden = !hasText;
      $('[data-mic]', bottom).hidden = hasText;
    };
    input.addEventListener('input', syncButtons);
    $('[data-mic]', bottom)?.addEventListener('pointerdown', (e) => beginRecording(e));
    $('[data-cancel]', bottom)?.addEventListener('click', () => {
      replyTo = null;
      editing = null;
      drawBottom();
    });
    const autosize = () => {
      input.style.height = 'auto';
      input.style.height = Math.min(input.scrollHeight, 140) + 'px';
    };
    input.addEventListener('input', () => {
      autosize();
      if (Date.now() - lastTypingSent > 2500) {
        lastTypingSent = Date.now();
        sendWs('typing', { conversationId: convId });
      }
    });
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) {
        e.preventDefault();
        form.requestSubmit();
      }
    });
    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      const body = input.value.trim();
      if (!body) return;
      try {
        if (editing) {
          await patch(`/messages/${editing.id}`, { body });
          editing = null;
        } else {
          const m = await post(`/conversations/${convId}/messages`, { body, replyTo: replyTo?.id });
          upsert(m);
          replyTo = null;
        }
        if (conv.status !== 'active') conv.status = 'active';
        drawBottom();
        drawList('force');
        $('[data-input]', bottom)?.focus();
      } catch (err) {
        showError(err);
      }
    });
    $('[data-file]', bottom).addEventListener('change', async (e) => {
      const file = e.target.files[0];
      if (!file) return;
      try {
        const media = await readImage(file);
        const m = await post(`/conversations/${convId}/messages`, { kind: 'image', media, body: input.value.trim(), replyTo: replyTo?.id });
        replyTo = null;
        upsert(m);
        drawBottom();
        drawList('force');
      } catch (err) {
        showError(err);
      }
    });
    if (editing) {
      autosize();
      input.focus();
    }
  };

  const upsert = (m) => {
    const i = messages.findIndex((x) => x.id === m.id);
    if (i >= 0) messages[i] = m;
    else {
      messages.push(m);
      messages.sort((a, b) => a.id - b.id);
    }
  };

  // ---------- Enregistrement d'un vocal (9.1) ----------
  let rec = null; // { recorder, locked, levels, preview, startX, startY, startT }
  let lastRecordingSent = 0;

  const beginRecording = async (e) => {
    if (rec) return;
    e.preventDefault();
    const recorder = new VoiceRecorder({
      onLevel: (lvl, dur) => {
        if (!rec) return;
        rec.levels.push(lvl);
        if (rec.levels.length > 40) rec.levels.shift();
        const time = $('[data-rtime]', bottom);
        if (time) time.textContent = fmtDuration(dur);
        const meter = $('[data-rlevel]', bottom);
        if (meter) mount(meter, html`${rec.levels.map((v) => html`<i style="height:${Math.round(10 + v * 90)}%"></i>`)}`);
        if (Date.now() - lastRecordingSent > 2500) {
          lastRecordingSent = Date.now();
          sendWs('typing', { conversationId: convId, activity: 'recording' });
        }
        if (dur > 59 * 60 * 1000 && !rec.warned) {
          rec.warned = true;
          toast(t('voice.oneMinuteLeft'));
        }
      },
    });
    rec = { recorder, locked: false, levels: [], startX: e.clientX, startY: e.clientY, startT: Date.now(), pointerId: e.pointerId };
    drawRecorder();
    window.addEventListener('pointermove', onRecMove);
    window.addEventListener('pointerup', onRecUp);
    try {
      await recorder.start();
      if (!rec) recorder.cancel();
    } catch (err) {
      stopListening();
      rec = null;
      drawBottom();
      toast(t(`err.${err.code || 'mic_denied'}`));
    }
  };

  const stopListening = () => {
    window.removeEventListener('pointermove', onRecMove);
    window.removeEventListener('pointerup', onRecUp);
  };

  // Glisser à gauche = annuler ; glisser vers le haut = verrouiller.
  const onRecMove = (e) => {
    if (!rec || rec.locked) return;
    const dx = e.clientX - rec.startX;
    const dy = e.clientY - rec.startY;
    const hint = $('[data-rhint]', bottom);
    if (hint) hint.style.transform = `translateX(${Math.min(0, dx)}px)`;
    if (dx < -90) cancelRecording();
    else if (dy < -70) lockRecording();
  };

  const onRecUp = () => {
    if (!rec || rec.locked) return;
    stopListening();
    // Un simple appui verrouille (« Tap to record ») ; un appui maintenu envoie au relâchement.
    if (Date.now() - rec.startT < 400) lockRecording();
    else sendRecording();
  };

  const lockRecording = () => {
    if (!rec) return;
    stopListening();
    rec.locked = true;
    drawRecorder();
  };

  const cancelRecording = () => {
    if (!rec) return;
    stopListening();
    rec.recorder.cancel();
    rec = null;
    drawBottom();
  };

  const sendRecording = async () => {
    if (!rec) return;
    const r = rec;
    rec = null;
    drawBottom();
    const result = await r.recorder.stop();
    if (result.duration < 700) return toast(t('voice.tooShort'));
    try {
      const media = await blobToDataUrl(result.blob);
      const m = await post(`/conversations/${convId}/messages`, { kind: 'voice', media, duration: Math.round(result.duration), waveform: result.waveform, replyTo: replyTo?.id });
      URL.revokeObjectURL(result.url);
      replyTo = null;
      upsert(m);
      drawBottom();
      drawList('force');
    } catch (err) {
      showError(err);
    }
  };

  const drawRecorder = () => {
    if (!rec) return drawBottom();
    const st = rec.recorder.state;
    if (rec.preview) {
      // Écoute avant envoi.
      mount(
        bottom,
        html`<div class="rec-bar">
          <button class="icon-btn" data-r="delete" aria-label="${t('voice.delete')}" style="color:var(--garnet)">${icon('trash')}</button>
          <button class="icon-btn" data-r="listen" aria-label="${t('voice.play')}">${icon('play')}</button>
          <div class="wave grow">${waveformHtml(rec.preview.waveform)}</div>
          <span class="small" data-rtime>${fmtDuration(rec.preview.duration)}</span>
          <button class="send" data-r="send" aria-label="${t('share.send')}">${icon('send')}</button>
        </div>`
      );
    } else if (rec.locked) {
      mount(
        bottom,
        html`<div class="rec-bar">
          <button class="icon-btn" data-r="delete" aria-label="${t('voice.delete')}" style="color:var(--garnet)">${icon('trash')}</button>
          <span class="rec-dot ${st === 'paused' ? 'paused' : ''}"></span>
          <span class="small" data-rtime>${fmtDuration(rec.recorder.duration())}</span>
          <div class="rec-level grow" data-rlevel></div>
          <button class="icon-btn" data-r="${st === 'paused' ? 'resume' : 'pause'}" aria-label="${st === 'paused' ? t('voice.resume') : t('voice.pause')}">${icon(st === 'paused' ? 'mic' : 'pause')}</button>
          <button class="icon-btn" data-r="stop" aria-label="${t('voice.preview')}"><span class="stop-square"></span></button>
          <button class="send" data-r="send" aria-label="${t('share.send')}">${icon('send')}</button>
        </div>`
      );
    } else {
      mount(
        bottom,
        html`<div class="rec-bar holding">
          <span class="rec-dot"></span>
          <span class="small" data-rtime>0:00</span>
          <div class="rec-level grow" data-rlevel></div>
          <span class="small muted" data-rhint>‹ ${t('voice.slideCancel')}</span>
          <span class="rec-lock" aria-hidden="true">${icon('lock', 'width="16" height="16"')}<br />▲</span>
          <span class="send mic recording">${icon('mic')}</span>
        </div>`
      );
    }
    $$('[data-r]', bottom).forEach((b) =>
      b.addEventListener('click', async () => {
        const a = b.dataset.r;
        if (a === 'delete') {
          if (rec.preview) URL.revokeObjectURL(rec.preview.url);
          cancelRecording();
        }
        if (a === 'pause') rec.recorder.pause(), drawRecorder();
        if (a === 'resume') rec.recorder.resume(), drawRecorder();
        if (a === 'stop') {
          rec.preview = await rec.recorder.stop();
          drawRecorder();
        }
        if (a === 'listen') {
          const audio = new Audio(rec.preview.url);
          audio.play().catch(() => {});
        }
        if (a === 'send') sendRecording();
      })
    );
  };

  const markRead = () => {
    const last = messages.at(-1);
    if (!last || conv.status !== 'active' || document.hidden) return;
    post(`/conversations/${convId}/read`, { upTo: last.id })
      .then(refreshBadges)
      .catch(() => {});
  };

  // Menu d'un message (8.5).
  const openMessage = (m) => {
    if (m.kind === 'system') return;
    const mine = m.sender?.id === store.me.id;
    const myReaction = m.reactions.find((r) => r.userId === store.me.id)?.emoji;
    const items = [];
    if (!m.deleted) {
      items.push({ label: t('chat.reply'), icon: 'reply', run: () => ((replyTo = m), (editing = null), drawBottom(), $('[data-input]', bottom)?.focus()) });
      if (m.body) items.push({ label: t('chat.copy'), icon: 'copy', run: () => navigator.clipboard?.writeText(m.body).then(() => toast(t('common.done'))) });
      if (mine && m.kind === 'text' && Date.now() - m.createdAt < EDIT_WINDOW) items.push({ label: t('chat.edit'), icon: 'edit', run: () => ((editing = m), (replyTo = null), drawBottom()) });
      if ((mine && Date.now() - m.createdAt < DELETE_WINDOW) || (conv.type === 'group' && conv.role === 'admin'))
        items.push({
          label: t('chat.deleteAll'),
          icon: 'trash',
          danger: true,
          run: async () => {
            if (await dialog({ title: t('chat.deleteAll'), confirm: t('me.delete'), danger: true })) del(`/messages/${m.id}`).catch(showError);
          },
        });
    }
    if (!mine) items.push({ label: t('chat.report'), icon: 'flag', danger: true, run: () => reportFlow('message', m.id) });
    const header = m.deleted
      ? ''
      : html`<div class="quick-reactions">${QUICK.map((e) => html`<button data-react="${e}" class="${myReaction === e ? 'active' : ''}" aria-label="${e}">${e}</button>`)}</div>`;
    const close = actionSheet(items, { header });
    $$('[data-react]').forEach((b) =>
      b.addEventListener('click', () => {
        close();
        const e = b.dataset.react;
        (myReaction === e ? del(`/messages/${m.id}/reaction`) : put(`/messages/${m.id}/reaction`, { emoji: e })).catch(showError);
      })
    );
  };

  list.addEventListener('click', (e) => {
    if (e.target.closest('a')) return;
    const cb = e.target.closest('[data-callback]');
    if (cb) return startCall(conv, cb.dataset.callback);
    const v = e.target.closest('[data-v]');
    if (v) {
      const m = messages.find((x) => x.id === Number(v.closest('[data-voice]').dataset.voice));
      if (!m) return;
      if (v.dataset.v === 'play') player.toggle(m, voiceOpts(m));
      if (v.dataset.v === 'rate') player.cycleRate();
      if (v.dataset.v === 'seek') {
        const r = v.getBoundingClientRect();
        player.seek(m, (e.clientX - r.left) / r.width, voiceOpts(m));
      }
      return;
    }
    const row = e.target.closest('[data-mid]');
    if (!row) return;
    const m = messages.find((x) => x.id === Number(row.dataset.mid));
    if (m) openMessage(m);
  });
  list.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && e.target.classList.contains('bubble')) e.target.click();
  });

  // Historique : chargement des messages plus anciens en remontant.
  list.addEventListener('scroll', async () => {
    if (list.scrollTop > 40 || loadingOlder || noMore || !messages.length) return;
    loadingOlder = true;
    try {
      const older = await get(`/conversations/${convId}/messages?before=${messages[0].id}`);
      if (!older.length) noMore = true;
      older.forEach(upsert);
      drawList('top');
    } finally {
      loadingOlder = false;
    }
  });

  const blockPeer = async () => {
    if (!conv.peer) return;
    if (!(await dialog({ title: t('block.confirm', { name: conv.peer.name }), body: t('block.lead'), confirm: t('block.title'), danger: true }))) return;
    await post(`/users/${conv.peer.id}/block`);
    conv = await get(`/conversations/${convId}`);
    drawBottom();
  };

  const openMenu = () => {
    if (conv.type === 'group') return openGroupInfo();
    const items = [];
    if (conv.peer) items.push({ label: t('chat.viewProfile'), icon: 'me', run: () => go(`u/${conv.peer.username}`) });
    if (conv.peer && !conv.blocked) items.push({ label: t('chat.block'), icon: 'block', danger: true, run: blockPeer });
    if (conv.peer) items.push({ label: t('chat.report'), icon: 'flag', danger: true, run: () => reportFlow('user', conv.peer.id) });
    actionSheet(items);
  };

  const openGroupInfo = () =>
    sheet((box, close) => {
      const isAdmin = conv.role === 'admin';
      mount(
        box,
        html`<div class="grabber"></div>
          <div class="profile-head" style="padding-top:8px">${avatar({ name: conv.title }, 'lg')}<h2>${conv.title}</h2><div class="muted">${t('chat.members', { count: conv.memberCount })}</div></div>
          ${isAdmin
            ? html`<div class="menu-group">
                <button class="list-item" data-rename>${icon('edit')}<span class="grow">${t('chat.groupName')}</span></button>
                <label class="list-item">${icon('info')}<span class="grow">${t('chat.announceSetting')}</span><input type="checkbox" class="toggle" data-announce ${conv.announceOnly ? 'checked' : ''} /></label>
                <button class="list-item" data-add>${icon('userPlus')}<span class="grow">${t('chat.addMembers')}</span></button>
              </div>`
            : ''}
          <div class="section-title">${t('chat.members', { count: conv.memberCount })}</div>
          <ul class="list">
            ${conv.members.map(
              (m) => html`<li class="list-item" data-member="${m.id}">
                ${avatar(m, 'sm')}
                <div class="grow"><div class="title">${m.id === store.me.id ? store.me.displayName : m.name}</div><div class="preview">@${m.username}</div></div>
                ${m.role === 'admin' ? html`<span class="small" style="color:var(--accent)">${t('chat.admin')}</span>` : ''}
              </li>`
            )}
          </ul>
          <div class="sheet-actions"><button class="btn ghost block" data-leave style="color:var(--garnet)">${t('chat.leave')}</button></div>`
      );
      $('[data-rename]', box)?.addEventListener('click', async () => {
        const title = await dialog({ title: t('chat.groupName'), input: { value: conv.title } });
        close();
        if (!title?.trim()) return;
        try {
          conv = await patch(`/conversations/${convId}`, { title });
        } catch (err) {
          showError(err);
        }
        drawHead();
      });
      $('[data-announce]', box)?.addEventListener('change', async (e) => {
        conv = await patch(`/conversations/${convId}`, { announceOnly: e.target.checked });
        drawBottom();
      });
      $('[data-add]', box)?.addEventListener('click', async () => {
        close();
        const friends = (await get('/friends')).filter((f) => !conv.members.some((m) => m.id === f.id));
        pickPeople(friends, t('chat.addMembers'), async (ids) => {
          conv = await post(`/conversations/${convId}/members`, { userIds: ids });
          drawHead();
        });
      });
      $('[data-leave]', box).addEventListener('click', async () => {
        if (!(await dialog({ title: t('chat.leave'), confirm: t('chat.leave'), danger: true }))) return;
        await del(`/conversations/${convId}/members/me`);
        close();
        go('chats');
      });
      if (isAdmin)
        $$('[data-member]', box).forEach((li) =>
          li.addEventListener('click', () => {
            const m = conv.members.find((x) => x.id === Number(li.dataset.member));
            if (!m || m.id === store.me.id) return;
            close();
            actionSheet([
              {
                label: m.role === 'admin' ? t('chat.removeAdmin') : t('chat.makeAdmin'),
                icon: 'star',
                run: async () => (conv = await post(`/conversations/${convId}/members/${m.id}/admin`, { admin: m.role !== 'admin' })),
              },
              { label: t('chat.remove'), icon: 'trash', danger: true, run: () => del(`/conversations/${convId}/members/${m.id}`).catch(showError) },
            ]);
          })
        );
    });

  drawHead();
  drawCallbar();
  drawBottom();
  try {
    messages = await get(`/conversations/${convId}/messages`);
  } catch (err) {
    showError(err);
  }
  drawList('force');
  markRead();

  // Temps réel.
  const offs = [
    on('message', (m) => {
      if (m.conversationId !== convId) return;
      upsert(m);
      typingUntil = 0;
      drawHead();
      drawList();
      markRead();
    }),
    on('message:update', (m) => {
      if (m.conversationId !== convId) return;
      upsert(m);
      drawList(false);
    }),
    on('receipts', async (d) => {
      if (d.conversationId !== convId) return;
      const fresh = await get(`/conversations/${convId}/messages`).catch(() => []);
      fresh.forEach(upsert);
      drawList(false);
    }),
    on('typing', (d) => {
      if (d.conversationId !== convId) return;
      typingActivity = d.activity || 'typing';
      typingUntil = Date.now() + 4000;
      drawHead();
      clearTimeout(typingTimer);
      typingTimer = setTimeout(drawHead, 4100);
    }),
    on('presence', (d) => {
      if (conv.peer && d.userId === conv.peer.id) {
        conv.peer.online = d.online;
        conv.peer.lastSeen = d.lastSeen;
        drawHead();
      }
    }),
    on('voice:progress', (st) => updateVoice(st)),
    on('call:update', (d) => {
      if (d.conversationId !== convId) return;
      conv.activeCall = d.call;
      drawCallbar();
    }),
    on('conversation:update', async (d) => {
      if (d.id !== convId) return;
      try {
        conv = await get(`/conversations/${convId}`);
        drawHead();
        drawCallbar();
        if (!rec) drawBottom();
      } catch {
        go('chats');
      }
    }),
  ];
  const onVisible = () => !document.hidden && markRead();
  document.addEventListener('visibilitychange', onVisible);
  return () => {
    offs.forEach((off) => off());
    clearTimeout(typingTimer);
    stopListening();
    rec?.recorder.cancel();
    rec = null;
    document.removeEventListener('visibilitychange', onVisible);
  };
}

function setUniverseMe() {
  document.body.dataset.universe = 'me';
}

// Carte de publication World partagée dans une discussion (passerelle 4.4).
export function postCard(p) {
  if (!p || p.unavailable) return html`<div class="post-share"><div class="ps-head">🌍 ${t('chat.postUnavailable')}</div></div>`;
  return html`<a class="post-share" href="#/post/${p.id}">
    <div class="ps-head">🌍 ${p.author?.name} · @${p.author?.username}</div>
    ${p.media ? html`<img src="${p.media}" alt="" loading="lazy" />` : ''}
    ${p.body ? html`<div class="ps-body" style="padding-top:${p.media ? '8px' : '0'}">${p.body}</div>` : ''}
  </a>`;
}

// Sélecteur de personnes (cases à cocher).
export function pickPeople(people, title, onDone, { min = 1 } = {}) {
  sheet((box, close) => {
    mount(
      box,
      html`<div class="grabber"></div><h2>${title}</h2>
        ${people.length
          ? html`<ul class="list">${people.map(
              (p) => html`<li><label class="list-item">${avatar(p, 'sm')}<span class="grow title">${p.name}</span><input type="checkbox" value="${p.id}" /></label></li>`
            )}</ul>`
          : empty(t('me.noFriends'))}
        <div class="sheet-actions"><button class="btn block" data-ok disabled>${t('common.done')}</button></div>`
    );
    const ok = $('[data-ok]', box);
    const boxes = $$('input[type="checkbox"]', box);
    boxes.forEach((b) => b.addEventListener('change', () => (ok.disabled = boxes.filter((x) => x.checked).length < min)));
    ok.addEventListener('click', async () => {
      const ids = boxes.filter((x) => x.checked).map((x) => Number(x.value));
      close();
      try {
        await onDone(ids);
      } catch (err) {
        showError(err);
      }
    });
  });
}

// ---------------- Nouvelle discussion ----------------
export async function newChatScreen(root) {
  const main = layout(root, { universe: 'me', title: t('chats.newChat'), left: backButton() });
  wireBack(root);
  mount(
    main,
    html`<div class="searchbar"><input class="input" type="search" data-q placeholder="${t('chat.searchPeople')}" autofocus /></div>
      <a class="list-item" href="#/new-group">${avatar({ name: '+' }, 'sm')}<span class="title">${t('chats.newGroup')}</span></a>
      <div data-results>${skeleton(4)}</div>`
  );
  const results = $('[data-results]', main);
  const start = async (userId) => {
    try {
      const c = await post('/conversations/direct', { userId });
      go(`chat/${c.id}`);
    } catch (err) {
      showError(err);
    }
  };
  const show = (people, title) => {
    mount(
      results,
      people.length
        ? html`<div class="section-title">${title}</div><ul class="list">${people.map(
            (p) => html`<li><button class="list-item" data-user="${p.id}">${avatar(p, 'sm')}<span class="grow"><span class="title" style="display:block">${p.name}</span><span class="preview">@${p.username}</span></span></button></li>`
          )}</ul>`
        : empty(t('search.noResults'))
    );
    $$('[data-user]', results).forEach((b) => b.addEventListener('click', () => start(Number(b.dataset.user))));
  };
  const friends = await get('/friends').catch(() => []);
  show(friends, t('profile.friends'));
  $('[data-q]', main).addEventListener(
    'input',
    debounce(async (e) => {
      const q = e.target.value.trim();
      if (!q) return show(friends, t('profile.friends'));
      show(await get(`/users/search?q=${encodeURIComponent(q)}`).catch(() => []), t('search.people'));
    })
  );
}

export async function newGroupScreen(root) {
  const main = layout(root, { universe: 'me', title: t('chats.newGroup'), left: backButton() });
  wireBack(root);
  const friends = await get('/friends').catch(() => []);
  mount(
    main,
    html`<form class="section" data-form>
      <div class="field"><label for="gname">${t('chat.groupName')}</label><input class="input" id="gname" data-title maxlength="100" required /></div>
      <div class="section-title" style="margin-left:0">${t('chat.chooseFriends')}</div>
      ${friends.length
        ? html`<ul class="list card" style="margin-bottom:16px">${friends.map(
            (p) => html`<li><label class="list-item">${avatar(p, 'sm')}<span class="grow title">${p.name}</span><input type="checkbox" value="${p.id}" /></label></li>`
          )}</ul>`
        : empty(t('me.noFriends'), '', html`<a class="btn" href="#/search">${t('me.findFriends')}</a>`)}
      <button class="btn block" type="submit">${t('chat.create')}</button>
    </form>`
  );
  $('[data-form]', main).addEventListener('submit', async (e) => {
    e.preventDefault();
    const memberIds = $$('input[type="checkbox"]:checked', main).map((x) => Number(x.value));
    try {
      const c = await post('/conversations/group', { title: $('[data-title]', main).value, memberIds });
      go(`chat/${c.id}`);
    } catch (err) {
      showError(err);
    }
  });
}

// ---------------- Historique des appels (10.7) ----------------
export async function callsScreen(root, { filter = 'all' } = {}) {
  const main = layout(root, {
    universe: 'me',
    title: t('call.history'),
    tab: 'chats',
    left: backButton(),
    right: html`<button class="icon-btn" data-clear aria-label="${t('call.clear')}">${icon('trash')}</button>`,
  });
  wireBack(root, 'chats');
  const load = async () => {
    const all = await get('/calls').catch(() => []);
    const list = filter === 'missed' ? all.filter((c) => c.missed) : all;
    mount(
      main,
      html`<div class="chips">
          <a class="chip ${filter === 'all' ? 'active' : ''}" href="#/calls">${t('chats.all')}</a>
          <a class="chip ${filter === 'missed' ? 'active' : ''}" href="#/calls/missed">${t('call.missedFilter')}</a>
        </div>
        ${list.length
          ? html`<ul class="list">${list.map(
              (c) => html`<li class="list-item">
                <a href="#/chat/${c.conversationId}">${c.peer ? avatar(c.peer) : avatar({ name: c.title })}</a>
                <a class="grow" href="#/chat/${c.conversationId}" style="color:inherit;min-width:0">
                  <span class="title" style="display:block;${c.missed ? 'color:var(--garnet)' : ''}">${c.peer?.name || c.title}${c.participants > 2 ? ` (${c.participants})` : ''}</span>
                  <span class="preview">${c.direction === 'outgoing' ? '↗' : '↙'} ${c.missed ? t('call.missed') : c.answered ? fmtDuration(c.duration) : t('call.noAnswerMsg')} · ${listTime(c.createdAt)}</span>
                </a>
                <button class="icon-btn" data-again="${c.conversationId}:${c.type}" aria-label="${t('call.callBack')}" style="color:var(--accent)">${icon(c.type === 'video' ? 'video' : 'phone')}</button>
                <button class="icon-btn" data-del="${c.id}" aria-label="${t('me.delete')}">${icon('close')}</button>
              </li>`
            )}</ul>`
          : empty(t('call.empty'), t('call.emptyLead'))}`
    );
    $$('[data-again]', main).forEach((b) =>
      b.addEventListener('click', async () => {
        const [cid, type] = b.dataset.again.split(':');
        try {
          startCall(await get(`/conversations/${cid}`), type);
        } catch (err) {
          showError(err);
        }
      })
    );
    $$('[data-del]', main).forEach((b) => b.addEventListener('click', async () => (await del(`/calls/${b.dataset.del}`).catch(showError), load())));
  };
  $('[data-clear]', root).addEventListener('click', async () => {
    if (!(await dialog({ title: t('call.clear'), confirm: t('me.delete'), danger: true }))) return;
    await del('/calls/all').catch(showError);
    load();
  });
  await load();
  return on('call:ended', () => setTimeout(load, 300));
}
