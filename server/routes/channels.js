// Section 11.8 (canaux, World) et 11.9 / 8.13 (listes de diffusion, Me).
import crypto from 'node:crypto';
import { now, USERNAME_RE } from '../social.js';
import { tx } from '../db.js';

const MAX_ADMINS = 16;
const MAX_BROADCAST = 256;
const REACTIONS = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

export const CHANNEL_SCHEMA = `
CREATE TABLE IF NOT EXISTS channels (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  owner_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  handle TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  avatar TEXT,
  visibility TEXT NOT NULL DEFAULT 'public', -- public | private (lien d'invitation)
  invite_code TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS channel_admins (
  channel_id INTEGER NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  PRIMARY KEY (channel_id, user_id)
);
CREATE TABLE IF NOT EXISTS channel_subs (
  channel_id INTEGER NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  last_read_id INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (channel_id, user_id)
);
CREATE TABLE IF NOT EXISTS channel_posts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  channel_id INTEGER NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
  author_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
  body TEXT NOT NULL DEFAULT '',
  media TEXT,
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS channel_reactions (
  post_id INTEGER NOT NULL REFERENCES channel_posts(id) ON DELETE CASCADE,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  emoji TEXT NOT NULL,
  PRIMARY KEY (post_id, user_id)
);
CREATE TABLE IF NOT EXISTS channel_views (
  post_id INTEGER NOT NULL REFERENCES channel_posts(id) ON DELETE CASCADE,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  PRIMARY KEY (post_id, user_id)
);
CREATE TABLE IF NOT EXISTS broadcast_lists (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  owner_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS broadcast_members (
  list_id INTEGER NOT NULL REFERENCES broadcast_lists(id) ON DELETE CASCADE,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  PRIMARY KEY (list_id, user_id)
);
CREATE TABLE IF NOT EXISTS broadcast_sent (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  list_id INTEGER NOT NULL REFERENCES broadcast_lists(id) ON DELETE CASCADE,
  body TEXT NOT NULL DEFAULT '',
  media TEXT,
  delivered INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);
`;

export default function channelRoutes(api, ctx) {
  const { db, social, views, hub, saveMedia, HttpError } = ctx;
  db.exec(CHANNEL_SCHEMA);
  const q = {
    byId: db.prepare('SELECT * FROM channels WHERE id = ?'),
    byHandle: db.prepare('SELECT * FROM channels WHERE handle = ?'),
    insert: db.prepare('INSERT INTO channels (owner_id, handle, name, description, visibility, invite_code, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)'),
    update: db.prepare('UPDATE channels SET name = ?, description = ?, avatar = ?, visibility = ? WHERE id = ?'),
    isAdmin: db.prepare('SELECT 1 FROM channel_admins WHERE channel_id = ? AND user_id = ?'),
    admins: db.prepare('SELECT user_id FROM channel_admins WHERE channel_id = ?'),
    addAdmin: db.prepare('INSERT OR IGNORE INTO channel_admins (channel_id, user_id) VALUES (?, ?)'),
    removeAdmin: db.prepare('DELETE FROM channel_admins WHERE channel_id = ? AND user_id = ?'),
    sub: db.prepare('SELECT * FROM channel_subs WHERE channel_id = ? AND user_id = ?'),
    subscribe: db.prepare('INSERT OR IGNORE INTO channel_subs (channel_id, user_id, created_at) VALUES (?, ?, ?)'),
    unsubscribe: db.prepare('DELETE FROM channel_subs WHERE channel_id = ? AND user_id = ?'),
    subCount: db.prepare('SELECT COUNT(*) AS n FROM channel_subs WHERE channel_id = ?'),
    subIds: db.prepare('SELECT user_id FROM channel_subs WHERE channel_id = ?'),
    mine: db.prepare(`SELECT c.* FROM channels c WHERE c.id IN
      (SELECT channel_id FROM channel_subs WHERE user_id = ? UNION SELECT channel_id FROM channel_admins WHERE user_id = ?)`),
    search: db.prepare(`SELECT * FROM channels WHERE visibility = 'public'
      AND (handle LIKE ? ESCAPE '\\' OR name LIKE ? ESCAPE '\\') ORDER BY name LIMIT 20`),
    posts: db.prepare('SELECT * FROM channel_posts WHERE channel_id = ? AND id < ? ORDER BY id DESC LIMIT 50'),
    lastPost: db.prepare('SELECT * FROM channel_posts WHERE channel_id = ? ORDER BY id DESC LIMIT 1'),
    unread: db.prepare('SELECT COUNT(*) AS n FROM channel_posts WHERE channel_id = ? AND id > ?'),
    post: db.prepare('SELECT * FROM channel_posts WHERE id = ?'),
    insertPost: db.prepare('INSERT INTO channel_posts (channel_id, author_id, body, media, created_at) VALUES (?, ?, ?, ?, ?)'),
    deletePost: db.prepare('DELETE FROM channel_posts WHERE id = ?'),
    reactions: db.prepare('SELECT emoji, COUNT(*) AS n FROM channel_reactions WHERE post_id = ? GROUP BY emoji'),
    myReaction: db.prepare('SELECT emoji FROM channel_reactions WHERE post_id = ? AND user_id = ?'),
    react: db.prepare('INSERT OR REPLACE INTO channel_reactions (post_id, user_id, emoji) VALUES (?, ?, ?)'),
    unreact: db.prepare('DELETE FROM channel_reactions WHERE post_id = ? AND user_id = ?'),
    view: db.prepare('INSERT OR IGNORE INTO channel_views (post_id, user_id) VALUES (?, ?)'),
    views: db.prepare('SELECT COUNT(*) AS n FROM channel_views WHERE post_id = ?'),
    markRead: db.prepare('UPDATE channel_subs SET last_read_id = MAX(last_read_id, ?) WHERE channel_id = ? AND user_id = ?'),
    unseen: db.prepare('SELECT id FROM channel_posts WHERE channel_id = ? AND id <= ?'),
    // Listes de diffusion
    lists: db.prepare('SELECT * FROM broadcast_lists WHERE owner_id = ? ORDER BY created_at DESC'),
    list: db.prepare('SELECT * FROM broadcast_lists WHERE id = ? AND owner_id = ?'),
    insertList: db.prepare('INSERT INTO broadcast_lists (owner_id, name, created_at) VALUES (?, ?, ?)'),
    renameList: db.prepare('UPDATE broadcast_lists SET name = ? WHERE id = ?'),
    deleteList: db.prepare('DELETE FROM broadcast_lists WHERE id = ?'),
    listMembers: db.prepare('SELECT user_id FROM broadcast_members WHERE list_id = ?'),
    clearMembers: db.prepare('DELETE FROM broadcast_members WHERE list_id = ?'),
    addMember: db.prepare('INSERT OR IGNORE INTO broadcast_members (list_id, user_id) VALUES (?, ?)'),
    sent: db.prepare('SELECT * FROM broadcast_sent WHERE list_id = ? ORDER BY id DESC LIMIT 50'),
    insertSent: db.prepare('INSERT INTO broadcast_sent (list_id, body, media, delivered, created_at) VALUES (?, ?, ?, ?, ?)'),
  };

  const isAdmin = (c, userId) => !!q.isAdmin.get(c.id, userId);
  const canRead = (c, userId) => c.visibility === 'public' || isAdmin(c, userId) || !!q.sub.get(c.id, userId);

  const channelView = (c, viewerId) => {
    const admin = isAdmin(c, viewerId);
    const sub = q.sub.get(c.id, viewerId);
    const last = q.lastPost.get(c.id);
    return {
      id: c.id,
      handle: c.handle,
      name: c.name,
      description: c.description,
      avatar: c.avatar,
      visibility: c.visibility,
      subscribers: q.subCount.get(c.id).n, // les abonnés ne se voient pas entre eux
      subscribed: !!sub,
      isAdmin: admin,
      isOwner: c.owner_id === viewerId,
      inviteCode: admin ? c.invite_code : undefined,
      admins: admin ? q.admins.all(c.id).map((r) => views.userCard(r.user_id, viewerId)) : undefined,
      unread: sub ? q.unread.get(c.id, sub.last_read_id).n : 0,
      lastPost: last ? { body: last.body.slice(0, 120), media: !!last.media, createdAt: last.created_at } : null,
    };
  };

  const postView = (p, viewerId, admin) => ({
    id: p.id,
    body: p.body,
    media: p.media,
    createdAt: p.created_at,
    reactions: q.reactions.all(p.id).map((r) => ({ emoji: r.emoji, count: r.n })),
    myReaction: q.myReaction.get(p.id, viewerId)?.emoji ?? null,
    views: admin ? q.views.get(p.id).n : undefined, // statistiques réservées aux admins
  });

  const load = (idOrHandle) => {
    const c = /^\d+$/.test(String(idOrHandle)) ? q.byId.get(Number(idOrHandle)) : q.byHandle.get(String(idOrHandle).toLowerCase());
    if (!c) throw new HttpError(404, 'channel_not_found');
    return c;
  };

  api.post('/channels', (req, res) => {
    if (!req.user.world_enabled) throw new HttpError(403, 'world_presence_required');
    ctx.assertNotRestricted(req.user);
    const name = String(req.body?.name ?? '').trim().slice(0, 80);
    const handle = String(req.body?.handle ?? '').toLowerCase();
    if (!name) throw new HttpError(400, 'invalid_name');
    if (!USERNAME_RE.test(handle)) throw new HttpError(400, 'invalid_handle');
    if (q.byHandle.get(handle)) throw new HttpError(409, 'handle_taken');
    const visibility = req.body?.visibility === 'private' ? 'private' : 'public';
    const id = tx(db, () => {
      const cid = Number(q.insert.run(req.user.id, handle, name, String(req.body?.description ?? '').slice(0, 500), visibility, crypto.randomBytes(8).toString('hex'), now()).lastInsertRowid);
      q.addAdmin.run(cid, req.user.id);
      return cid;
    });
    res.status(201).json(channelView(q.byId.get(id), req.user.id));
  });

  api.get('/channels', (req, res) => {
    const me = req.user.id;
    const list = q.mine.all(me, me).map((c) => channelView(c, me));
    list.sort((a, b) => (b.lastPost?.createdAt ?? 0) - (a.lastPost?.createdAt ?? 0));
    res.json(list);
  });

  api.get('/channels/search', (req, res) => {
    const term = String(req.query.q ?? '').trim().replace(/^@/, '');
    if (!term) return res.json([]);
    const like = `%${term.replace(/[\\%_]/g, (ch) => '\\' + ch)}%`;
    res.json(q.search.all(like, like).map((c) => channelView(c, req.user.id)));
  });

  api.get('/channels/:id', (req, res) => {
    const c = load(req.params.id);
    // Canal privé : visible avec le lien d'invitation (code) ou en étant abonné.
    if (!canRead(c, req.user.id) && req.query.code !== c.invite_code) throw new HttpError(404, 'channel_not_found');
    res.json({ ...channelView(c, req.user.id), canRead: canRead(c, req.user.id), reactions: REACTIONS, notEncrypted: true });
  });

  api.patch('/channels/:id', (req, res) => {
    const c = load(req.params.id);
    if (!isAdmin(c, req.user.id)) throw new HttpError(403, 'admin_only');
    const b = req.body ?? {};
    const name = b.name !== undefined ? String(b.name).trim().slice(0, 80) : c.name;
    if (!name) throw new HttpError(400, 'invalid_name');
    const avatar = b.avatar !== undefined ? saveMedia(b.avatar) : c.avatar;
    q.update.run(name, b.description !== undefined ? String(b.description).slice(0, 500) : c.description, avatar, b.visibility === 'private' ? 'private' : b.visibility === 'public' ? 'public' : c.visibility, c.id);
    res.json(channelView(q.byId.get(c.id), req.user.id));
  });

  api.post('/channels/:id/subscribe', (req, res) => {
    const c = load(req.params.id);
    if (c.visibility === 'private' && req.body?.code !== c.invite_code && !isAdmin(c, req.user.id)) throw new HttpError(403, 'invite_required');
    q.subscribe.run(c.id, req.user.id, now());
    res.json(channelView(c, req.user.id));
  });

  api.delete('/channels/:id/subscribe', (req, res) => {
    const c = load(req.params.id);
    q.unsubscribe.run(c.id, req.user.id);
    res.json(channelView(c, req.user.id));
  });

  // Jusqu'à 16 admins (11.8), nommés par le propriétaire parmi les abonnés.
  api.post('/channels/:id/admins', (req, res) => {
    const c = load(req.params.id);
    if (c.owner_id !== req.user.id) throw new HttpError(403, 'owner_only');
    const userId = Number(req.body?.userId);
    if (!q.sub.get(c.id, userId)) throw new HttpError(400, 'not_subscriber');
    if (q.admins.all(c.id).length >= MAX_ADMINS) throw new HttpError(400, 'too_many_admins');
    q.addAdmin.run(c.id, userId);
    res.json(channelView(c, req.user.id));
  });

  api.delete('/channels/:id/admins/:userId', (req, res) => {
    const c = load(req.params.id);
    if (c.owner_id !== req.user.id || Number(req.params.userId) === c.owner_id) throw new HttpError(403, 'owner_only');
    q.removeAdmin.run(c.id, Number(req.params.userId));
    res.json(channelView(c, req.user.id));
  });

  api.get('/channels/:id/posts', (req, res) => {
    const c = load(req.params.id);
    if (!canRead(c, req.user.id)) throw new HttpError(404, 'channel_not_found');
    const admin = isAdmin(c, req.user.id);
    const before = Number(req.query.before) || Number.MAX_SAFE_INTEGER;
    res.json(q.posts.all(c.id, before).reverse().map((p) => postView(p, req.user.id, admin)));
  });

  api.post('/channels/:id/posts', (req, res) => {
    const c = load(req.params.id);
    if (!isAdmin(c, req.user.id)) throw new HttpError(403, 'admin_only');
    ctx.assertNotRestricted(req.user);
    const body = String(req.body?.body ?? '').slice(0, 4096);
    const media = saveMedia(req.body?.media);
    if (!body.trim() && !media) throw new HttpError(400, 'empty_post');
    const id = Number(q.insertPost.run(c.id, req.user.id, body, media, now()).lastInsertRowid);
    const p = q.post.get(id);
    // Diffusion en temps réel aux abonnés connectés.
    for (const { user_id } of q.subIds.all(c.id)) hub.send(user_id, 'channel:post', { channelId: c.id, post: postView(p, user_id, isAdmin(c, user_id)) });
    res.status(201).json(postView(p, req.user.id, true));
  });

  api.delete('/channel-posts/:id', (req, res) => {
    const p = q.post.get(Number(req.params.id));
    if (!p || !isAdmin(q.byId.get(p.channel_id), req.user.id)) throw new HttpError(404, 'not_found');
    q.deletePost.run(p.id);
    res.json({ ok: true });
  });

  api.put('/channel-posts/:id/reaction', (req, res) => {
    const p = q.post.get(Number(req.params.id));
    const c = p && q.byId.get(p.channel_id);
    if (!c || !canRead(c, req.user.id)) throw new HttpError(404, 'not_found');
    const emoji = req.body?.emoji;
    if (emoji == null) q.unreact.run(p.id, req.user.id);
    else if (!REACTIONS.includes(emoji)) throw new HttpError(400, 'invalid_emoji');
    else q.react.run(p.id, req.user.id, emoji);
    res.json(postView(p, req.user.id, isAdmin(c, req.user.id)));
  });

  // Lecture : met à jour les non-lus et compte une vue par publication.
  api.post('/channels/:id/read', (req, res) => {
    const c = load(req.params.id);
    if (!canRead(c, req.user.id)) throw new HttpError(404, 'channel_not_found');
    const upTo = Number(req.body?.upTo) || 0;
    tx(db, () => {
      for (const { id } of q.unseen.all(c.id, upTo)) q.view.run(id, req.user.id);
      q.markRead.run(upTo, c.id, req.user.id);
    });
    res.json({ ok: true });
  });

  // ---------------- Listes de diffusion (Me) ----------------
  const listView = (l, viewerId) => ({
    id: l.id,
    name: l.name,
    members: q.listMembers.all(l.id).map((r) => views.userCard(r.user_id, viewerId)).filter(Boolean),
    sent: q.sent.all(l.id).map((s) => ({ id: s.id, body: s.body, media: s.media, delivered: s.delivered, createdAt: s.created_at })),
  });

  const setMembers = (listId, ids, ownerId) => {
    const unique = [...new Set((ids ?? []).map(Number))].filter((id) => id !== ownerId);
    if (!unique.length) throw new HttpError(400, 'no_members');
    if (unique.length > MAX_BROADCAST) throw new HttpError(400, 'too_many_members');
    for (const id of unique) if (!social.isFriend(ownerId, id)) throw new HttpError(403, 'not_friend');
    q.clearMembers.run(listId);
    for (const id of unique) q.addMember.run(listId, id);
  };

  api.get('/broadcasts', (req, res) => res.json(q.lists.all(req.user.id).map((l) => listView(l, req.user.id))));

  api.post('/broadcasts', (req, res) => {
    const name = String(req.body?.name ?? '').trim().slice(0, 80);
    if (!name) throw new HttpError(400, 'invalid_name');
    const id = tx(db, () => {
      const lid = Number(q.insertList.run(req.user.id, name, now()).lastInsertRowid);
      setMembers(lid, req.body?.memberIds, req.user.id);
      return lid;
    });
    res.status(201).json(listView(q.list.get(id, req.user.id), req.user.id));
  });

  api.patch('/broadcasts/:id', (req, res) => {
    const l = q.list.get(Number(req.params.id), req.user.id);
    if (!l) throw new HttpError(404, 'not_found');
    tx(db, () => {
      if (req.body?.name !== undefined) q.renameList.run(String(req.body.name).trim().slice(0, 80) || l.name, l.id);
      if (req.body?.memberIds) setMembers(l.id, req.body.memberIds, req.user.id);
    });
    res.json(listView(q.list.get(l.id, req.user.id), req.user.id));
  });

  api.delete('/broadcasts/:id', (req, res) => {
    const l = q.list.get(Number(req.params.id), req.user.id);
    if (!l) throw new HttpError(404, 'not_found');
    q.deleteList.run(l.id);
    res.json({ ok: true });
  });

  // Chaque destinataire reçoit le message dans sa discussion privée avec moi ;
  // seuls mes amis le reçoivent (« seuls ceux qui m'ont en contact »).
  api.post('/broadcasts/:id/send', (req, res) => {
    const l = q.list.get(Number(req.params.id), req.user.id);
    if (!l) throw new HttpError(404, 'not_found');
    const body = String(req.body?.body ?? '').slice(0, 4096);
    const media = saveMedia(req.body?.media);
    if (!body.trim() && !media) throw new HttpError(400, 'empty_message');
    let delivered = 0;
    for (const { user_id } of q.listMembers.all(l.id)) {
      if (ctx.sendDirectMessage(req.user.id, user_id, { body, media, kind: media ? 'image' : 'text' })) delivered++;
    }
    q.insertSent.run(l.id, body, media, delivered, now());
    res.json({ delivered });
  });
}
