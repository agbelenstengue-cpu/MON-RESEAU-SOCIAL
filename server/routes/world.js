// Sections 14 (World), 16 (interactions) et 17 (recherche, hashtags, recommandation).
import { now, extractHashtags, extractMentions } from '../social.js';
import { tx } from '../db.js';

const AUDIENCES = ['everyone', 'followers', 'friends', 'only_me'];
const COMMENTERS = ['everyone', 'followers', 'friends', 'nobody'];
const MAX_POST = 5000; // 14.3
const MAX_COMMENT = 500; // 16.2
const EDIT_COMMENT_WINDOW = 15 * 60 * 1000;
const DAY = 24 * 3600 * 1000;

export default function worldRoutes(api, ctx) {
  const { db, social, views, notify, saveMedia, HttpError } = ctx;
  const q = {
    post: db.prepare('SELECT * FROM posts WHERE id = ?'),
    user: db.prepare('SELECT * FROM users WHERE id = ?'),
    byName: db.prepare('SELECT * FROM users WHERE username = ?'),
    insert: db.prepare(`INSERT INTO posts (author_id, body, media, audience, who_can_comment, hide_likes, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)`),
    addTag: db.prepare('INSERT OR IGNORE INTO post_hashtags (post_id, tag) VALUES (?, ?)'),
    clearTags: db.prepare('DELETE FROM post_hashtags WHERE post_id = ?'),
    recent: db.prepare('SELECT * FROM posts WHERE deleted_at IS NULL AND created_at > ? ORDER BY created_at DESC LIMIT 800'),
    following: db.prepare(`SELECT p.* FROM posts p
      WHERE p.deleted_at IS NULL AND (p.author_id = ? OR p.author_id IN
        (SELECT followee_id FROM follows WHERE follower_id = ? AND status = 'active'))
      AND p.created_at < ? ORDER BY p.created_at DESC LIMIT 200`),
    like: db.prepare('INSERT OR IGNORE INTO likes (post_id, user_id, created_at) VALUES (?, ?, ?)'),
    unlike: db.prepare('DELETE FROM likes WHERE post_id = ? AND user_id = ?'),
    save: db.prepare('INSERT OR IGNORE INTO saves (post_id, user_id, created_at) VALUES (?, ?, ?)'),
    unsave: db.prepare('DELETE FROM saves WHERE post_id = ? AND user_id = ?'),
    saved: db.prepare('SELECT p.* FROM saves s JOIN posts p ON p.id = s.post_id WHERE s.user_id = ? ORDER BY s.created_at DESC'),
    share: db.prepare('INSERT INTO shares (post_id, created_at) VALUES (?, ?)'),
    notInterested: db.prepare('INSERT OR IGNORE INTO not_interested (post_id, user_id) VALUES (?, ?)'),
    hidden: db.prepare('SELECT post_id FROM not_interested WHERE user_id = ?'),
    comments: db.prepare('SELECT * FROM comments WHERE post_id = ? ORDER BY created_at ASC LIMIT 500'),
    comment: db.prepare('SELECT * FROM comments WHERE id = ?'),
    addComment: db.prepare('INSERT INTO comments (post_id, author_id, body, created_at) VALUES (?, ?, ?, ?)'),
    delComment: db.prepare('DELETE FROM comments WHERE id = ?'),
    editComment: db.prepare('UPDATE comments SET body = ? WHERE id = ?'),
    likedTags: db.prepare(`SELECT h.tag, COUNT(*) AS n FROM likes l JOIN post_hashtags h ON h.post_id = l.post_id
      WHERE l.user_id = ? GROUP BY h.tag ORDER BY n DESC LIMIT 20`),
    stats: db.prepare(`SELECT
      (SELECT COUNT(*) FROM likes WHERE post_id = ?) AS likes,
      (SELECT COUNT(*) FROM comments WHERE post_id = ?) AS comments,
      (SELECT COUNT(*) FROM shares WHERE post_id = ?) AS shares,
      (SELECT COUNT(*) FROM saves WHERE post_id = ?) AS saves`),
    byTag: db.prepare(`SELECT p.* FROM post_hashtags h JOIN posts p ON p.id = h.post_id
      WHERE h.tag = ? AND p.deleted_at IS NULL ORDER BY p.created_at DESC LIMIT 200`),
    tagCount: db.prepare('SELECT COUNT(*) AS n FROM post_hashtags h JOIN posts p ON p.id = h.post_id WHERE h.tag = ? AND p.deleted_at IS NULL'),
    trending: db.prepare(`SELECT h.tag, COUNT(*) AS posts FROM post_hashtags h JOIN posts p ON p.id = h.post_id
      WHERE p.deleted_at IS NULL AND p.audience = 'everyone' AND p.created_at > ?
      GROUP BY h.tag ORDER BY posts DESC, h.tag LIMIT 15`),
    tagSearch: db.prepare(`SELECT tag, COUNT(*) AS posts FROM post_hashtags WHERE tag LIKE ? ESCAPE '\\'
      GROUP BY tag ORDER BY posts DESC LIMIT 10`),
    postSearch: db.prepare(`SELECT * FROM posts WHERE deleted_at IS NULL AND body LIKE ? ESCAPE '\\'
      ORDER BY created_at DESC LIMIT 100`),
    softDelete: db.prepare('UPDATE posts SET deleted_at = ? WHERE id = ?'),
  };

  const visiblePost = (id, viewerId) => {
    const p = q.post.get(Number(id));
    if (!p || !social.canViewPost(viewerId, p)) throw new HttpError(404, 'post_not_found');
    return p;
  };

  const requireWorld = (user) => {
    if (!user.world_enabled) throw new HttpError(403, 'world_presence_required');
  };

  const indexTags = (postId, body) => {
    q.clearTags.run(postId);
    for (const tag of extractHashtags(body)) q.addTag.run(postId, tag);
  };

  // Mentions dans une publication publique : notification (sauf blocage — 22.4).
  const notifyMentions = (body, actorId, postId) => {
    for (const name of extractMentions(body)) {
      const u = q.byName.get(name);
      if (!u) continue;
      // Réglage « Who can mention me » (20.2).
      const level = social.privacy(u).whoCanMention;
      if (level === 'nobody' || (level === 'following' && !social.isFollower(u.id, actorId))) continue;
      notify(u.id, actorId, 'mention', postId);
    }
  };

  // --- Publication (14.3, 14.4) ---
  api.post('/posts', (req, res) => {
    requireWorld(req.user);
    const b = req.body ?? {};
    const body = String(b.body ?? '').slice(0, MAX_POST);
    const media = saveMedia(b.media);
    if (!body.trim() && !media) throw new HttpError(400, 'empty_post');
    const audience = AUDIENCES.includes(b.audience) ? b.audience : 'everyone';
    const whoCanComment = COMMENTERS.includes(b.whoCanComment) ? b.whoCanComment : 'everyone';
    const id = tx(db, () => {
      const pid = Number(q.insert.run(req.user.id, body, media, audience, whoCanComment, b.hideLikes ? 1 : 0, now()).lastInsertRowid);
      indexTags(pid, body);
      return pid;
    });
    if (audience !== 'only_me') notifyMentions(body, req.user.id, id);
    res.status(201).json(views.post(q.post.get(id), req.user.id));
  });

  api.get('/posts/:id', (req, res) => {
    res.json(views.post(visiblePost(req.params.id, req.user.id), req.user.id));
  });

  // Légende et réglages modifiables après publication ; mention « Edited ».
  api.patch('/posts/:id', (req, res) => {
    const p = q.post.get(Number(req.params.id));
    if (!p || p.author_id !== req.user.id || p.deleted_at) throw new HttpError(404, 'post_not_found');
    const b = req.body ?? {};
    const body = b.body !== undefined ? String(b.body).slice(0, MAX_POST) : p.body;
    if (!body.trim() && !p.media) throw new HttpError(400, 'empty_post');
    const audience = AUDIENCES.includes(b.audience) ? b.audience : p.audience;
    const who = COMMENTERS.includes(b.whoCanComment) ? b.whoCanComment : p.who_can_comment;
    const hide = b.hideLikes !== undefined ? (b.hideLikes ? 1 : 0) : p.hide_likes;
    tx(db, () => {
      db.prepare('UPDATE posts SET body = ?, audience = ?, who_can_comment = ?, hide_likes = ?, edited_at = ? WHERE id = ?').run(
        body, audience, who, hide, body !== p.body ? now() : p.edited_at, p.id
      );
      indexTags(p.id, body);
    });
    res.json(views.post(q.post.get(p.id), req.user.id));
  });

  // Suppression : 30 jours dans « Recently deleted » (14.3) — ici masquage immédiat.
  api.delete('/posts/:id', (req, res) => {
    const p = q.post.get(Number(req.params.id));
    if (!p || p.author_id !== req.user.id) throw new HttpError(404, 'post_not_found');
    q.softDelete.run(now(), p.id);
    res.json({ ok: true });
  });

  // --- Fils (14.1, 17.5) ---
  api.get('/feed/following', (req, res) => {
    const me = req.user.id;
    const before = Number(req.query.before) || Number.MAX_SAFE_INTEGER;
    const posts = q.following.all(me, me, before).filter((p) => social.canViewPost(me, p)).slice(0, 30);
    res.json(posts.map((p) => views.post(p, me)));
  });

  // Recommandation simple et explicable : engagement pondéré, fraîcheur,
  // affinité avec les comptes suivis et les hashtags aimés.
  const rank = (viewerId) => {
    const hidden = new Set(q.hidden.all(viewerId).map((r) => r.post_id));
    const tagAffinity = new Map(q.likedTags.all(viewerId).map((r) => [r.tag, r.n]));
    const t = now();
    const out = [];
    for (const p of q.recent.all(t - 30 * DAY)) {
      if (p.author_id === viewerId || hidden.has(p.id)) continue;
      if (!social.canViewPost(viewerId, p)) continue;
      const s = q.stats.get(p.id, p.id, p.id, p.id);
      const engagement = 1 + s.likes + 2 * s.comments + 3 * s.shares + 2 * s.saves;
      const hours = (t - p.created_at) / 3600_000;
      let score = engagement / Math.pow(hours + 2, 1.4);
      const reasons = [];
      if (social.isFollower(viewerId, p.author_id)) {
        score *= 1.6;
        reasons.push({ type: 'following' });
      }
      if (social.isFriend(viewerId, p.author_id)) {
        score *= 1.3;
        reasons.push({ type: 'friend' });
      }
      const tags = extractHashtags(p.body).filter((tag) => tagAffinity.has(tag));
      if (tags.length) {
        score *= 1 + Math.min(tags.length, 3) * 0.4;
        reasons.push({ type: 'hashtag', tags });
      }
      if (engagement > 10) reasons.push({ type: 'popular' });
      if (hours < 6) reasons.push({ type: 'recent' });
      if (!reasons.length) reasons.push({ type: 'discovery' });
      out.push({ p, score, reasons });
    }
    return out.sort((a, b) => b.score - a.score);
  };

  api.get('/feed/for-you', (req, res) => {
    const offset = Math.max(Number(req.query.offset) || 0, 0);
    const ranked = rank(req.user.id).slice(offset, offset + 30);
    res.json(ranked.map((r) => views.post(r.p, req.user.id)));
  });

  // « Why am I seeing this? » (1.4 Transparence, 17.5).
  api.get('/posts/:id/why', (req, res) => {
    const p = visiblePost(req.params.id, req.user.id);
    const found = rank(req.user.id).find((r) => r.p.id === p.id);
    res.json({ reasons: found ? found.reasons : [{ type: p.author_id === req.user.id ? 'own' : 'direct' }] });
  });

  // --- Interactions (16) ---
  api.post('/posts/:id/like', (req, res) => {
    const p = visiblePost(req.params.id, req.user.id);
    const r = q.like.run(p.id, req.user.id, now());
    if (r.changes) notify(p.author_id, req.user.id, 'like', p.id);
    res.json(views.post(p, req.user.id));
  });

  api.delete('/posts/:id/like', (req, res) => {
    const p = visiblePost(req.params.id, req.user.id);
    q.unlike.run(p.id, req.user.id);
    res.json(views.post(p, req.user.id));
  });

  // Enregistrer : invisible pour l'auteur (16.5).
  api.post('/posts/:id/save', (req, res) => {
    const p = visiblePost(req.params.id, req.user.id);
    q.save.run(p.id, req.user.id, now());
    res.json(views.post(p, req.user.id));
  });

  api.delete('/posts/:id/save', (req, res) => {
    const p = q.post.get(Number(req.params.id));
    if (p) q.unsave.run(p.id, req.user.id);
    res.json({ ok: true });
  });

  api.get('/saved', (req, res) => {
    const me = req.user.id;
    res.json(q.saved.all(me).filter((p) => social.canViewPost(me, p)).map((p) => views.post(p, me)));
  });

  api.post('/posts/:id/not-interested', (req, res) => {
    const p = visiblePost(req.params.id, req.user.id);
    q.notInterested.run(p.id, req.user.id);
    res.json({ ok: true });
  });

  // Partage World → Me : l'auteur ne voit qu'un compteur global (4.4).
  api.post('/posts/:id/share', (req, res) => {
    const p = visiblePost(req.params.id, req.user.id);
    const ids = [...new Set((req.body?.conversationIds ?? []).map(Number))].slice(0, 5);
    if (!ids.length) throw new HttpError(400, 'no_destination');
    for (const cid of ids) ctx.sendPostToConversation(req.user.id, cid, p.id, req.body?.body ?? '');
    q.share.run(p.id, now());
    res.json({ shared: ids.length });
  });

  const commentView = (c, viewerId, post) => ({
    id: c.id,
    body: c.body,
    createdAt: c.created_at,
    author: views.userCard(c.author_id, viewerId),
    mine: c.author_id === viewerId,
    canDelete: c.author_id === viewerId || post.author_id === viewerId,
  });

  api.get('/posts/:id/comments', (req, res) => {
    const p = visiblePost(req.params.id, req.user.id);
    const me = req.user.id;
    res.json(q.comments.all(p.id).filter((c) => !social.isBlockedEither(me, c.author_id)).map((c) => commentView(c, me, p)));
  });

  api.post('/posts/:id/comments', (req, res) => {
    const p = visiblePost(req.params.id, req.user.id);
    requireWorld(req.user); // commenter publiquement demande une présence World (4.2)
    if (!social.canComment(req.user.id, p)) throw new HttpError(403, 'comments_restricted');
    const body = String(req.body?.body ?? '').trim().slice(0, MAX_COMMENT);
    if (!body) throw new HttpError(400, 'empty_comment');
    const id = Number(q.addComment.run(p.id, req.user.id, body, now()).lastInsertRowid);
    notify(p.author_id, req.user.id, 'comment', p.id);
    notifyMentions(body, req.user.id, p.id);
    res.status(201).json(commentView(q.comment.get(id), req.user.id, p));
  });

  api.patch('/comments/:id', (req, res) => {
    const c = q.comment.get(Number(req.params.id));
    if (!c || c.author_id !== req.user.id) throw new HttpError(404, 'comment_not_found');
    if (now() - c.created_at > EDIT_COMMENT_WINDOW) throw new HttpError(403, 'edit_window_passed');
    const body = String(req.body?.body ?? '').trim().slice(0, MAX_COMMENT);
    if (!body) throw new HttpError(400, 'empty_comment');
    q.editComment.run(body, c.id);
    res.json({ ok: true });
  });

  api.delete('/comments/:id', (req, res) => {
    const c = q.comment.get(Number(req.params.id));
    const p = c && q.post.get(c.post_id);
    if (!c || (c.author_id !== req.user.id && p?.author_id !== req.user.id)) throw new HttpError(404, 'comment_not_found');
    q.delComment.run(c.id);
    res.json({ ok: true });
  });

  // --- Hashtags, tendances, recherche (17) ---
  api.get('/hashtags/:tag', (req, res) => {
    const tag = String(req.params.tag).toLowerCase().replace(/^#/, '');
    const me = req.user.id;
    const posts = q.byTag.all(tag).filter((p) => social.canViewPost(me, p));
    res.json({ tag, count: q.tagCount.get(tag).n, posts: posts.slice(0, 60).map((p) => views.post(p, me)) });
  });

  api.get('/trending', (req, res) => {
    res.json(q.trending.all(now() - 7 * DAY));
  });

  api.get('/search', (req, res) => {
    const term = String(req.query.q ?? '').trim();
    const me = req.user.id;
    if (!term) return res.json({ hashtags: [], posts: [] });
    const esc = (s) => s.replace(/[\\%_]/g, (c) => '\\' + c);
    const hashtags = q.tagSearch.all(`${esc(term.replace(/^#/, '').toLowerCase())}%`);
    const posts = q.postSearch.all(`%${esc(term)}%`).filter((p) => social.canViewPost(me, p)).slice(0, 30);
    res.json({ hashtags, posts: posts.map((p) => views.post(p, me)) });
  });
}
