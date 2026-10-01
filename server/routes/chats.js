// Section 8 (messagerie) et 11 (groupes) + présence temps réel (8.4).
import { now, ageFromBirthDate } from '../social.js';
import { tx } from '../db.js';

const EDIT_WINDOW = 15 * 60 * 1000; // 8.5
const DELETE_WINDOW = 48 * 3600 * 1000; // 8.5
const MAX_BODY = 4096;
const MAX_GROUP = 1024;
const MAX_VOICE = 60 * 60 * 1000; // 9.1

// Métadonnées d'un vocal : durée (ms) et onde sonore (64 valeurs entre 0 et 1).
function voiceMeta(b) {
  const duration = Math.round(Number(b.duration));
  const waveform = Array.isArray(b.waveform) ? b.waveform.slice(0, 64).map((v) => Math.max(0, Math.min(1, Number(v) || 0))) : [];
  return { duration: Number.isFinite(duration) && duration > 0 ? Math.min(duration, MAX_VOICE) : 0, waveform: waveform.map((v) => Math.round(v * 100) / 100) };
}

export default function chatRoutes(api, ctx) {
  const { db, social, views, hub, saveMedia, HttpError } = ctx;
  const q = {
    conv: db.prepare('SELECT * FROM conversations WHERE id = ?'),
    member: db.prepare('SELECT * FROM conversation_members WHERE conversation_id = ? AND user_id = ?'),
    members: db.prepare('SELECT * FROM conversation_members WHERE conversation_id = ?'),
    myConvs: db.prepare(`SELECT c.*, m.status AS my_status, m.last_read_id, m.role AS my_role
      FROM conversation_members m JOIN conversations c ON c.id = m.conversation_id WHERE m.user_id = ?`),
    findDirect: db.prepare(`SELECT c.id FROM conversations c
      JOIN conversation_members a ON a.conversation_id = c.id AND a.user_id = ?
      JOIN conversation_members b ON b.conversation_id = c.id AND b.user_id = ?
      WHERE c.type = 'direct' LIMIT 1`),
    insertConv: db.prepare('INSERT INTO conversations (type, title, created_by, created_at) VALUES (?, ?, ?, ?)'),
    insertMember: db.prepare(`INSERT OR IGNORE INTO conversation_members
      (conversation_id, user_id, role, status, joined_at) VALUES (?, ?, ?, ?, ?)`),
    removeMember: db.prepare('DELETE FROM conversation_members WHERE conversation_id = ? AND user_id = ?'),
    setStatus: db.prepare('UPDATE conversation_members SET status = ? WHERE conversation_id = ? AND user_id = ?'),
    setRole: db.prepare('UPDATE conversation_members SET role = ? WHERE conversation_id = ? AND user_id = ?'),
    lastMsg: db.prepare('SELECT * FROM messages WHERE conversation_id = ? ORDER BY id DESC LIMIT 1'),
    unread: db.prepare(`SELECT COUNT(*) AS n FROM messages
      WHERE conversation_id = ? AND id > ? AND (sender_id IS NULL OR sender_id != ?) AND deleted = 0`),
    page: db.prepare('SELECT * FROM messages WHERE conversation_id = ? AND id < ? ORDER BY id DESC LIMIT ?'),
    msg: db.prepare('SELECT * FROM messages WHERE id = ?'),
    insertMsg: db.prepare(`INSERT INTO messages (conversation_id, sender_id, kind, body, media, post_id, reply_to, created_at, meta)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`),
    play: db.prepare('INSERT OR IGNORE INTO voice_plays (message_id, user_id, played_at) VALUES (?, ?, ?)'),
    editMsg: db.prepare('UPDATE messages SET body = ?, edited_at = ? WHERE id = ?'),
    deleteMsg: db.prepare('UPDATE messages SET deleted = 1, body = \'\', media = NULL WHERE id = ?'),
    react: db.prepare('INSERT OR REPLACE INTO message_reactions (message_id, user_id, emoji) VALUES (?, ?, ?)'),
    unreact: db.prepare('DELETE FROM message_reactions WHERE message_id = ? AND user_id = ?'),
    markRead: db.prepare(`UPDATE conversation_members SET last_read_id = MAX(last_read_id, ?),
      last_delivered_id = MAX(last_delivered_id, ?) WHERE conversation_id = ? AND user_id = ?`),
    markDelivered: db.prepare(`UPDATE conversation_members SET last_delivered_id = MAX(last_delivered_id, ?)
      WHERE conversation_id = ? AND user_id = ?`),
    maxId: db.prepare('SELECT COALESCE(MAX(id), 0) AS id FROM messages WHERE conversation_id = ?'),
    updateConv: db.prepare('UPDATE conversations SET title = ?, announce_only = ? WHERE id = ?'),
    user: db.prepare('SELECT * FROM users WHERE id = ?'),
    touchSeen: db.prepare('UPDATE users SET last_seen = ? WHERE id = ?'),
    friendIds: db.prepare('SELECT friend_id FROM friendships WHERE user_id = ?'),
  };

  const membership = (convId, userId) => {
    const conv = q.conv.get(Number(convId));
    const me = conv && q.member.get(conv.id, userId);
    if (!me) throw new HttpError(404, 'conversation_not_found');
    return { conv, me };
  };

  const memberIds = (convId) => q.members.all(convId).map((m) => m.user_id);

  const convSummary = (c, viewerId) => {
    const members = q.members.all(c.id);
    const me = members.find((m) => m.user_id === viewerId);
    const last = q.lastMsg.get(c.id);
    const others = members.filter((m) => m.user_id !== viewerId);
    const out = {
      id: c.id,
      type: c.type,
      title: c.title,
      announceOnly: !!c.announce_only,
      status: me.status,
      role: me.role,
      unread: q.unread.get(c.id, me.last_read_id, viewerId).n,
      lastMessage: last ? views.message(last, viewerId, members) : null,
      updatedAt: last?.created_at ?? c.created_at,
      memberCount: members.length,
      activeCall: ctx.activeCallFor?.(c.id, viewerId) ?? null,
    };
    if (c.type === 'direct') {
      const other = others[0] ? q.user.get(others[0].user_id) : null;
      out.peer = other ? views.userCard(other, viewerId) : null;
      out.blocked = other ? social.hasBlocked(viewerId, other.id) : false;
    } else {
      out.members = members.map((m) => ({ ...views.userCard(m.user_id, viewerId), role: m.role }));
    }
    return out;
  };

  // Accusés « distribué » à la connexion d'un appareil.
  const deliverAll = (userId) => {
    for (const c of q.myConvs.all(userId)) {
      if (c.my_status !== 'active') continue;
      const maxId = q.maxId.get(c.id).id;
      q.markDelivered.run(maxId, c.id, userId);
      hub.sendMany(memberIds(c.id), 'receipts', { conversationId: c.id });
    }
  };

  const broadcastPresence = (userId) => {
    const u = q.user.get(userId);
    if (!u) return;
    const ids = q.friendIds.all(userId).map((r) => r.friend_id);
    hub.sendMany(ids, 'presence', { userId, online: hub.isOnline(userId), lastSeen: u.last_seen });
  };

  hub.on('connect', (userId) => {
    q.touchSeen.run(now(), userId);
    deliverAll(userId);
    broadcastPresence(userId);
  });
  hub.on('disconnect', (userId) => {
    q.touchSeen.run(now(), userId);
    broadcastPresence(userId);
  });
  // « écrit… » (8.4) : relayé aux autres membres, jamais stocké.
  hub.on('message', (userId, msg) => {
    if (msg?.type !== 'typing') return;
    const activity = msg.activity === 'recording' ? 'recording' : 'typing';
    const convId = Number(msg.conversationId);
    const me = q.member.get(convId, userId);
    if (!me || me.status !== 'active') return;
    const ids = memberIds(convId).filter((id) => id !== userId && !social.isBlockedEither(id, userId));
    hub.sendMany(ids, 'typing', { conversationId: convId, userId, activity });
  });

  api.get('/conversations', (req, res) => {
    const list = q.myConvs.all(req.user.id).map((c) => convSummary(c, req.user.id));
    list.sort((a, b) => b.updatedAt - a.updatedAt);
    res.json(list);
  });

  // Discussion individuelle. Règle 6.2 : un non-ami arrive dans « Message requests »,
  // et un mineur ne peut pas être contacté par un inconnu.
  api.post('/conversations/direct', (req, res) => {
    const other = q.user.get(Number(req.body?.userId));
    if (!other || other.id === req.user.id) throw new HttpError(404, 'user_not_found');
    if (social.isBlockedEither(req.user.id, other.id)) throw new HttpError(403, 'blocked');
    const existing = q.findDirect.get(req.user.id, other.id);
    if (existing) return res.json(convSummary(q.conv.get(existing.id), req.user.id));
    const friends = social.isFriend(other.id, req.user.id);
    if (!friends && ageFromBirthDate(other.birth_date) < 18) throw new HttpError(403, 'cannot_message_minor');
    const id = tx(db, () => {
      const convId = Number(q.insertConv.run('direct', null, req.user.id, now()).lastInsertRowid);
      q.insertMember.run(convId, req.user.id, 'member', 'active', now());
      q.insertMember.run(convId, other.id, 'member', friends ? 'active' : 'request', now());
      return convId;
    });
    res.status(201).json(convSummary(q.conv.get(id), req.user.id));
  });

  // Groupe privé (11.1) : on ajoute directement ses amis uniquement (6.2).
  api.post('/conversations/group', (req, res) => {
    const title = String(req.body?.title ?? '').trim();
    if (!title || title.length > 100) throw new HttpError(400, 'invalid_title');
    const ids = [...new Set((req.body?.memberIds ?? []).map(Number))].filter((id) => id !== req.user.id);
    if (!ids.length) throw new HttpError(400, 'no_members');
    if (ids.length + 1 > MAX_GROUP) throw new HttpError(400, 'group_too_large');
    for (const id of ids) if (!social.isFriend(req.user.id, id)) throw new HttpError(403, 'not_friend');
    const convId = tx(db, () => {
      const cid = Number(q.insertConv.run('group', title, req.user.id, now()).lastInsertRowid);
      q.insertMember.run(cid, req.user.id, 'admin', 'active', now());
      for (const id of ids) q.insertMember.run(cid, id, 'member', 'active', now());
      q.insertMsg.run(cid, req.user.id, 'system', 'group_created', null, null, null, now(), null);
      return cid;
    });
    hub.sendMany(ids, 'conversation:new', { id: convId });
    res.status(201).json(convSummary(q.conv.get(convId), req.user.id));
  });

  api.get('/conversations/:id', (req, res) => {
    const { conv } = membership(req.params.id, req.user.id);
    res.json(convSummary(conv, req.user.id));
  });

  api.patch('/conversations/:id', (req, res) => {
    const { conv, me } = membership(req.params.id, req.user.id);
    if (conv.type !== 'group' || me.role !== 'admin') throw new HttpError(403, 'admin_only');
    const title = req.body?.title !== undefined ? String(req.body.title).trim().slice(0, 100) : conv.title;
    if (!title) throw new HttpError(400, 'invalid_title');
    const announce = req.body?.announceOnly !== undefined ? (req.body.announceOnly ? 1 : 0) : conv.announce_only;
    q.updateConv.run(title, announce, conv.id);
    hub.sendMany(memberIds(conv.id), 'conversation:update', { id: conv.id });
    res.json(convSummary(q.conv.get(conv.id), req.user.id));
  });

  api.post('/conversations/:id/members', (req, res) => {
    const { conv, me } = membership(req.params.id, req.user.id);
    if (conv.type !== 'group' || me.role !== 'admin') throw new HttpError(403, 'admin_only');
    const ids = [...new Set((req.body?.userIds ?? []).map(Number))];
    for (const id of ids) if (!social.isFriend(req.user.id, id)) throw new HttpError(403, 'not_friend');
    tx(db, () => {
      for (const id of ids) {
        if (q.member.get(conv.id, id)) continue;
        q.insertMember.run(conv.id, id, 'member', 'active', now());
        q.insertMsg.run(conv.id, id, 'system', 'member_added', null, null, null, now(), null);
      }
    });
    hub.sendMany(memberIds(conv.id), 'conversation:update', { id: conv.id });
    res.json(convSummary(conv, req.user.id));
  });

  api.post('/conversations/:id/members/:userId/admin', (req, res) => {
    const { conv, me } = membership(req.params.id, req.user.id);
    if (conv.type !== 'group' || me.role !== 'admin') throw new HttpError(403, 'admin_only');
    const target = q.member.get(conv.id, Number(req.params.userId));
    if (!target) throw new HttpError(404, 'member_not_found');
    q.setRole.run(req.body?.admin === false ? 'member' : 'admin', conv.id, target.user_id);
    hub.sendMany(memberIds(conv.id), 'conversation:update', { id: conv.id });
    res.json(convSummary(conv, req.user.id));
  });

  // Quitter un groupe ou retirer un membre (admin).
  api.delete('/conversations/:id/members/:userId', (req, res) => {
    const { conv, me } = membership(req.params.id, req.user.id);
    if (conv.type !== 'group') throw new HttpError(400, 'not_group');
    const userId = req.params.userId === 'me' ? req.user.id : Number(req.params.userId);
    if (userId !== req.user.id && me.role !== 'admin') throw new HttpError(403, 'admin_only');
    tx(db, () => {
      q.removeMember.run(conv.id, userId);
      q.insertMsg.run(conv.id, userId, 'system', userId === req.user.id ? 'member_left' : 'member_removed', null, null, null, now(), null);
      // Un groupe garde toujours au moins un admin (11.6).
      const rest = q.members.all(conv.id);
      if (rest.length && !rest.some((m) => m.role === 'admin')) q.setRole.run('admin', conv.id, rest[0].user_id);
    });
    hub.sendMany([...memberIds(conv.id), userId], 'conversation:update', { id: conv.id });
    res.json({ ok: true });
  });

  // Accepter une demande de message.
  api.post('/conversations/:id/accept', (req, res) => {
    const { conv } = membership(req.params.id, req.user.id);
    q.setStatus.run('active', conv.id, req.user.id);
    res.json(convSummary(conv, req.user.id));
  });

  api.get('/conversations/:id/messages', (req, res) => {
    const { conv } = membership(req.params.id, req.user.id);
    const before = Number(req.query.before) || Number.MAX_SAFE_INTEGER;
    const limit = Math.min(Number(req.query.limit) || 50, 100);
    const members = q.members.all(conv.id);
    const rows = q.page.all(conv.id, before, limit).reverse();
    res.json(rows.map((m) => views.message(m, req.user.id, members)));
  });

  const pushMessage = (convId, messageId, type = 'message') => {
    const members = q.members.all(convId);
    const m = q.msg.get(messageId);
    for (const mb of members) {
      if (m.sender_id && mb.user_id !== m.sender_id && social.hasBlocked(mb.user_id, m.sender_id) && type === 'message') continue;
      hub.send(mb.user_id, type, views.message(m, mb.user_id, members));
    }
  };

  api.post('/conversations/:id/messages', (req, res) => {
    const { conv, me } = membership(req.params.id, req.user.id);
    const b = req.body ?? {};
    const kind = ['text', 'image', 'voice'].includes(b.kind) ? b.kind : 'text';
    const body = kind === 'voice' ? '' : String(b.body ?? '').slice(0, MAX_BODY);
    if (kind === 'text' && !body.trim()) throw new HttpError(400, 'empty_message');
    if (conv.type === 'group' && conv.announce_only && me.role !== 'admin') throw new HttpError(403, 'admins_only');
    if (conv.type === 'direct') {
      const other = q.members.all(conv.id).find((m) => m.user_id !== req.user.id);
      if (!other) throw new HttpError(403, 'conversation_closed');
      if (social.isBlockedEither(req.user.id, other.user_id)) throw new HttpError(403, 'blocked');
    }
    let meta = null;
    if (kind === 'voice') meta = JSON.stringify(voiceMeta(b));
    const media = kind === 'text' ? null : saveMedia(b.media, kind === 'voice' ? 'audio' : 'image');
    if (kind !== 'text' && !media) throw new HttpError(400, 'invalid_media');
    let replyTo = null;
    if (b.replyTo) {
      const r = q.msg.get(Number(b.replyTo));
      if (r && r.conversation_id === conv.id) replyTo = r.id;
    }
    const id = tx(db, () => {
      // Répondre à une demande de message vaut acceptation.
      if (me.status === 'request') q.setStatus.run('active', conv.id, req.user.id);
      const mid = Number(q.insertMsg.run(conv.id, req.user.id, kind, body, media, null, replyTo, now(), meta).lastInsertRowid);
      q.markRead.run(mid, mid, conv.id, req.user.id);
      // Les destinataires connectés reçoivent immédiatement : « distribué ».
      for (const mb of q.members.all(conv.id)) {
        if (mb.user_id !== req.user.id && mb.status === 'active' && hub.isOnline(mb.user_id)) q.markDelivered.run(mid, conv.id, mb.user_id);
      }
      return mid;
    });
    pushMessage(conv.id, id);
    const members = q.members.all(conv.id);
    res.status(201).json(views.message(q.msg.get(id), req.user.id, members));
  });

  // Passerelle World → Me (4.4) : partage d'une publication dans une discussion.
  ctx.sendPostToConversation = (userId, convId, postId, body = '') => {
    const { conv, me } = membership(convId, userId);
    if (conv.type === 'group' && conv.announce_only && me.role !== 'admin') throw new HttpError(403, 'admins_only');
    if (conv.type === 'direct') {
      const other = q.members.all(conv.id).find((m) => m.user_id !== userId);
      if (!other || social.isBlockedEither(userId, other.user_id)) throw new HttpError(403, 'blocked');
    }
    const mid = Number(q.insertMsg.run(conv.id, userId, 'post', String(body).slice(0, MAX_BODY), null, postId, null, now(), null).lastInsertRowid);
    q.markRead.run(mid, mid, conv.id, userId);
    pushMessage(conv.id, mid);
    return mid;
  };

  const ownMessage = (req) => {
    const m = q.msg.get(Number(req.params.id));
    if (!m) throw new HttpError(404, 'message_not_found');
    const me = q.member.get(m.conversation_id, req.user.id);
    if (!me) throw new HttpError(404, 'message_not_found');
    return { m, me };
  };

  api.patch('/messages/:id', (req, res) => {
    const { m } = ownMessage(req);
    if (m.sender_id !== req.user.id || m.kind !== 'text' || m.deleted) throw new HttpError(403, 'cannot_edit');
    if (now() - m.created_at > EDIT_WINDOW) throw new HttpError(403, 'edit_window_passed');
    const body = String(req.body?.body ?? '').slice(0, MAX_BODY);
    if (!body.trim()) throw new HttpError(400, 'empty_message');
    q.editMsg.run(body, now(), m.id);
    pushMessage(m.conversation_id, m.id, 'message:update');
    res.json({ ok: true });
  });

  // « Delete for everyone » : 48 h pour l'auteur ; à tout moment pour un admin de groupe.
  api.delete('/messages/:id', (req, res) => {
    const { m, me } = ownMessage(req);
    const conv = q.conv.get(m.conversation_id);
    const isAdmin = conv.type === 'group' && me.role === 'admin';
    if (m.sender_id !== req.user.id && !isAdmin) throw new HttpError(403, 'cannot_delete');
    if (m.sender_id === req.user.id && !isAdmin && now() - m.created_at > DELETE_WINDOW) throw new HttpError(403, 'delete_window_passed');
    q.deleteMsg.run(m.id);
    pushMessage(m.conversation_id, m.id, 'message:update');
    res.json({ ok: true });
  });

  // Une réaction par personne et par message (8.5).
  api.put('/messages/:id/reaction', (req, res) => {
    const { m } = ownMessage(req);
    const emoji = String(req.body?.emoji ?? '');
    if (!emoji || [...emoji].length > 8) throw new HttpError(400, 'invalid_emoji');
    if (m.deleted) throw new HttpError(400, 'message_deleted');
    q.react.run(m.id, req.user.id, emoji);
    pushMessage(m.conversation_id, m.id, 'message:update');
    res.json({ ok: true });
  });

  api.delete('/messages/:id/reaction', (req, res) => {
    const { m } = ownMessage(req);
    q.unreact.run(m.id, req.user.id);
    pushMessage(m.conversation_id, m.id, 'message:update');
    res.json({ ok: true });
  });

  // Statut « écouté » d'un vocal (9.4).
  api.post('/messages/:id/played', (req, res) => {
    const { m, me } = ownMessage(req);
    if (m.kind !== 'voice' || m.deleted) throw new HttpError(400, 'not_voice');
    if (m.sender_id !== req.user.id && me.status === 'active') {
      q.play.run(m.id, req.user.id, now());
      pushMessage(m.conversation_id, m.id, 'message:update');
    }
    res.json({ ok: true });
  });

  // Message d'événement (appel terminé ou manqué) inséré par le module d'appels.
  ctx.postEventMessage = (convId, senderId, kind, meta) => {
    const mid = Number(q.insertMsg.run(convId, senderId, kind, '', null, null, null, now(), JSON.stringify(meta)).lastInsertRowid);
    pushMessage(convId, mid);
    return mid;
  };

  // Accusés de lecture : pas envoyés tant qu'une demande n'est pas acceptée (7.3).
  api.post('/conversations/:id/read', (req, res) => {
    const { conv, me } = membership(req.params.id, req.user.id);
    const upTo = Math.min(Number(req.body?.upTo) || 0, q.maxId.get(conv.id).id);
    if (me.status === 'active' && upTo > me.last_read_id) {
      q.markRead.run(upTo, upTo, conv.id, req.user.id);
      hub.sendMany(memberIds(conv.id), 'receipts', { conversationId: conv.id });
    }
    res.json({ ok: true });
  });
}
