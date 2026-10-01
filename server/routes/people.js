// Section 6 (graphe social), 15 (profils), 19 (notifications), 22 (blocage, signalement).
import { now } from '../social.js';
import { tx } from '../db.js';


export default function peopleRoutes(api, { db, social, views, hub, notify, HttpError }) {
  const q = {
    user: db.prepare('SELECT * FROM users WHERE id = ?'),
    byName: db.prepare('SELECT * FROM users WHERE username = ?'),
    search: db.prepare(`SELECT * FROM users
      WHERE (username LIKE ? ESCAPE '\\' OR display_name LIKE ? ESCAPE '\\' OR public_name LIKE ? ESCAPE '\\')
      ORDER BY world_enabled DESC, username LIMIT 30`),
    addRequest: db.prepare('INSERT OR IGNORE INTO friend_requests (from_id, to_id, created_at) VALUES (?, ?, ?)'),
    delRequest: db.prepare('DELETE FROM friend_requests WHERE from_id = ? AND to_id = ?'),
    received: db.prepare('SELECT * FROM friend_requests WHERE to_id = ? ORDER BY created_at DESC'),
    sent: db.prepare('SELECT * FROM friend_requests WHERE from_id = ? ORDER BY created_at DESC'),
    addFriend: db.prepare('INSERT OR IGNORE INTO friendships (user_id, friend_id, created_at) VALUES (?, ?, ?)'),
    delFriend: db.prepare('DELETE FROM friendships WHERE (user_id = ? AND friend_id = ?) OR (user_id = ? AND friend_id = ?)'),
    friends: db.prepare(`SELECT u.* FROM friendships f JOIN users u ON u.id = f.friend_id
      WHERE f.user_id = ? ORDER BY u.display_name COLLATE NOCASE`),
    friendCount: db.prepare('SELECT COUNT(*) AS n FROM friendships WHERE user_id = ?'),
    addClose: db.prepare('INSERT OR IGNORE INTO close_friends (owner_id, friend_id) VALUES (?, ?)'),
    delClose: db.prepare('DELETE FROM close_friends WHERE owner_id = ? AND friend_id = ?'),
    delCloseBoth: db.prepare('DELETE FROM close_friends WHERE (owner_id = ? AND friend_id = ?) OR (owner_id = ? AND friend_id = ?)'),
    follow: db.prepare('INSERT OR IGNORE INTO follows (follower_id, followee_id, status, created_at) VALUES (?, ?, ?, ?)'),
    unfollow: db.prepare('DELETE FROM follows WHERE follower_id = ? AND followee_id = ?'),
    acceptFollow: db.prepare("UPDATE follows SET status = 'active' WHERE follower_id = ? AND followee_id = ?"),
    followRequests: db.prepare("SELECT * FROM follows WHERE followee_id = ? AND status = 'pending' ORDER BY created_at DESC"),
    followers: db.prepare("SELECT COUNT(*) AS n FROM follows WHERE followee_id = ? AND status = 'active'"),
    following: db.prepare("SELECT COUNT(*) AS n FROM follows WHERE follower_id = ? AND status = 'active'"),
    postCount: db.prepare('SELECT COUNT(*) AS n FROM posts WHERE author_id = ? AND deleted_at IS NULL'),
    userPosts: db.prepare('SELECT * FROM posts WHERE author_id = ? AND deleted_at IS NULL ORDER BY created_at DESC LIMIT 60'),
    block: db.prepare('INSERT OR IGNORE INTO blocks (blocker_id, blocked_id, created_at) VALUES (?, ?, ?)'),
    unblock: db.prepare('DELETE FROM blocks WHERE blocker_id = ? AND blocked_id = ?'),
    blocked: db.prepare('SELECT u.* FROM blocks b JOIN users u ON u.id = b.blocked_id WHERE b.blocker_id = ?'),
    notifs: db.prepare('SELECT * FROM notifications WHERE user_id = ? ORDER BY created_at DESC LIMIT 100'),
    readNotifs: db.prepare('UPDATE notifications SET read = 1 WHERE user_id = ?'),
    unread: db.prepare('SELECT COUNT(*) AS n FROM notifications WHERE user_id = ? AND read = 0'),
    mutual: db.prepare(`SELECT COUNT(*) AS n FROM friendships a JOIN friendships b ON a.friend_id = b.friend_id
      WHERE a.user_id = ? AND b.user_id = ?`),
    suggestions: db.prepare(`SELECT f2.friend_id AS id, COUNT(*) AS mutual FROM friendships f1
      JOIN friendships f2 ON f2.user_id = f1.friend_id
      WHERE f1.user_id = ? AND f2.friend_id != ?
        AND f2.friend_id NOT IN (SELECT friend_id FROM friendships WHERE user_id = ?)
        AND f2.friend_id NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id = ?)
        AND f2.friend_id NOT IN (SELECT blocker_id FROM blocks WHERE blocked_id = ?)
      GROUP BY f2.friend_id ORDER BY mutual DESC LIMIT 10`),
  };

  const target = (id) => {
    const u = q.user.get(Number(id));
    if (!u) throw new HttpError(404, 'user_not_found');
    return u;
  };
  const notSelf = (req, u) => {
    if (u.id === req.user.id) throw new HttpError(400, 'self');
  };
  const notBlocked = (req, u) => {
    if (social.isBlockedEither(req.user.id, u.id)) throw new HttpError(403, 'blocked');
  };

  // Recherche par @username ou nom (les personnes bloquées n'apparaissent pas — 22.4).
  api.get('/users/search', (req, res) => {
    const term = String(req.query.q ?? '').trim().replace(/^@/, '');
    if (!term) return res.json([]);
    const like = `%${term.replace(/[\\%_]/g, (c) => '\\' + c)}%`;
    const rows = q.search.all(like, like, like).filter((u) => !social.isBlockedEither(req.user.id, u.id));
    res.json(rows.map((u) => ({ ...views.userCard(u, req.user.id), relationship: social.relationship(req.user.id, u.id) })));
  });

  api.get('/users/suggestions', (req, res) => {
    const me = req.user.id;
    // Réglage « Suggest my account to others » (20.2).
    const rows = q.suggestions.all(me, me, me, me, me).filter((r) => social.privacy(r.id).suggestAccount);
    res.json(rows.map((r) => ({ ...views.userCard(r.id, me), mutual: r.mutual })));
  });

  // Profil : privé pour les amis, World pour le public (4.3).
  api.get('/users/:username', (req, res) => {
    const u = q.byName.get(String(req.params.username).toLowerCase());
    // La personne bloquée ne trouve plus le profil ; celle qui bloque garde
    // une fiche minimale pour pouvoir débloquer (22.4).
    if (!u || social.hasBlocked(u.id, req.user.id)) throw new HttpError(404, 'user_not_found');
    const me = req.user.id;
    const rel = social.relationship(me, u.id);
    if (rel.blocked) return res.json({ ...views.userCard(u, me), relationship: rel, counts: {}, canSeeWorld: false, posts: [] });
    const intimate = rel.self || rel.friend;
    const canSeeWorld = u.world_enabled && (rel.self || !u.world_private || social.isFollower(me, u.id));
    const posts = canSeeWorld ? q.userPosts.all(u.id).filter((p) => social.canViewPost(me, p, u)) : [];
    res.json({
      ...views.userCard(u, me),
      about: social.allowsFor(u.id, 'about', me) ? u.about : undefined,
      bio: u.world_enabled ? u.bio : '',
      worldPrivate: !!u.world_private,
      relationship: rel,
      counts: {
        friends: rel.self ? q.friendCount.get(u.id).n : undefined,
        mutualFriends: rel.self ? undefined : q.mutual.get(me, u.id).n,
        followers: u.world_enabled ? q.followers.get(u.id).n : undefined,
        following: u.world_enabled ? q.following.get(u.id).n : undefined,
        posts: u.world_enabled ? q.postCount.get(u.id).n : undefined,
      },
      canSeeWorld: !!canSeeWorld,
      posts: posts.map((p) => views.post(p, me)),
    });
  });

  // --- Amis (6.5) ---
  api.post('/users/:id/friend-request', (req, res) => {
    const u = target(req.params.id);
    notSelf(req, u);
    notBlocked(req, u);
    if (social.isFriend(req.user.id, u.id)) return res.json({ status: 'friends' });
    // Demande croisée : l'amitié est établie directement.
    if (social.hasRequest(u.id, req.user.id)) {
      tx(db, () => makeFriends(req.user.id, u.id));
      notify(u.id, req.user.id, 'friend_accepted');
      return res.json({ status: 'friends' });
    }
    q.addRequest.run(req.user.id, u.id, now());
    notify(u.id, req.user.id, 'friend_request');
    res.json({ status: 'requested' });
  });

  api.delete('/users/:id/friend-request', (req, res) => {
    q.delRequest.run(req.user.id, Number(req.params.id));
    res.json({ status: 'none' });
  });

  const makeFriends = (a, b) => {
    q.delRequest.run(a, b);
    q.delRequest.run(b, a);
    q.addFriend.run(a, b, now());
    q.addFriend.run(b, a, now());
    // Les demandes de message en attente entre eux deviennent des discussions normales.
    db.prepare(`UPDATE conversation_members SET status = 'active' WHERE status = 'request' AND user_id IN (?, ?)
      AND conversation_id IN (SELECT c.id FROM conversations c WHERE c.type = 'direct'
        AND EXISTS (SELECT 1 FROM conversation_members m WHERE m.conversation_id = c.id AND m.user_id = ?)
        AND EXISTS (SELECT 1 FROM conversation_members m WHERE m.conversation_id = c.id AND m.user_id = ?))`).run(a, b, a, b);
  };

  api.get('/friend-requests', (req, res) => {
    const me = req.user.id;
    res.json({
      received: q.received.all(me).map((r) => ({ user: views.userCard(r.from_id, me), createdAt: r.created_at, mutual: q.mutual.get(me, r.from_id).n })),
      sent: q.sent.all(me).map((r) => ({ user: views.userCard(r.to_id, me), createdAt: r.created_at })),
    });
  });

  api.post('/friend-requests/:id/accept', (req, res) => {
    const from = target(req.params.id);
    if (!social.hasRequest(from.id, req.user.id)) throw new HttpError(404, 'no_request');
    tx(db, () => makeFriends(req.user.id, from.id));
    notify(from.id, req.user.id, 'friend_accepted');
    hub.send(from.id, 'friends:changed', {});
    res.json({ status: 'friends' });
  });

  // Refus silencieux : l'autre personne n'est pas notifiée (6.5).
  api.post('/friend-requests/:id/delete', (req, res) => {
    q.delRequest.run(Number(req.params.id), req.user.id);
    res.json({ status: 'none' });
  });

  api.get('/friends', (req, res) => {
    const me = req.user.id;
    res.json(q.friends.all(me).map((u) => ({ ...views.userCard(u, me), closeFriend: social.isCloseFriend(me, u.id) })));
  });

  api.delete('/friends/:id', (req, res) => {
    const id = Number(req.params.id);
    tx(db, () => {
      q.delFriend.run(req.user.id, id, id, req.user.id);
      q.delCloseBoth.run(req.user.id, id, id, req.user.id);
    });
    res.json({ status: 'none' });
  });

  api.put('/close-friends/:id', (req, res) => {
    const u = target(req.params.id);
    if (!social.isFriend(req.user.id, u.id)) throw new HttpError(400, 'not_friend');
    q.addClose.run(req.user.id, u.id);
    res.json({ closeFriend: true });
  });

  api.delete('/close-friends/:id', (req, res) => {
    q.delClose.run(req.user.id, Number(req.params.id));
    res.json({ closeFriend: false });
  });

  // --- Abonnements World (6.6) ---
  api.post('/users/:id/follow', (req, res) => {
    const u = target(req.params.id);
    notSelf(req, u);
    notBlocked(req, u);
    if (!u.world_enabled) throw new HttpError(400, 'no_world_presence');
    const status = u.world_private ? 'pending' : 'active';
    q.follow.run(req.user.id, u.id, status, now());
    notify(u.id, req.user.id, status === 'active' ? 'follow' : 'follow_request');
    res.json({ following: social.followStatus(req.user.id, u.id) });
  });

  api.delete('/users/:id/follow', (req, res) => {
    q.unfollow.run(req.user.id, Number(req.params.id));
    res.json({ following: null });
  });

  api.delete('/users/:id/follower', (req, res) => {
    q.unfollow.run(Number(req.params.id), req.user.id);
    res.json({ ok: true });
  });

  api.get('/follow-requests', (req, res) => {
    res.json(q.followRequests.all(req.user.id).map((r) => ({ user: views.userCard(r.follower_id, req.user.id), createdAt: r.created_at })));
  });

  api.post('/follow-requests/:id/accept', (req, res) => {
    q.acceptFollow.run(Number(req.params.id), req.user.id);
    notify(Number(req.params.id), req.user.id, 'follow_accepted');
    res.json({ ok: true });
  });

  api.post('/follow-requests/:id/delete', (req, res) => {
    db.prepare("DELETE FROM follows WHERE follower_id = ? AND followee_id = ? AND status = 'pending'").run(Number(req.params.id), req.user.id);
    res.json({ ok: true });
  });

  // --- Blocage : effets 22.4 (abonnements réciproques et amitié supprimés, pas de notification) ---
  api.post('/users/:id/block', (req, res) => {
    const u = target(req.params.id);
    notSelf(req, u);
    const me = req.user.id;
    tx(db, () => {
      q.block.run(me, u.id, now());
      q.unfollow.run(me, u.id);
      q.unfollow.run(u.id, me);
      q.delFriend.run(me, u.id, u.id, me);
      q.delCloseBoth.run(me, u.id, u.id, me);
      q.delRequest.run(me, u.id);
      q.delRequest.run(u.id, me);
    });
    res.json({ blocked: true });
  });

  api.delete('/users/:id/block', (req, res) => {
    q.unblock.run(req.user.id, Number(req.params.id));
    res.json({ blocked: false });
  });

  api.get('/blocked', (req, res) => {
    res.json(q.blocked.all(req.user.id).map((u) => views.userCard(u, req.user.id)));
  });

  // --- Notifications (19) ---
  api.get('/notifications', (req, res) => {
    const me = req.user.id;
    const items = q.notifs.all(me).flatMap((n) => {
      const actor = n.actor_id ? views.userCard(n.actor_id, me) : null;
      if (n.actor_id && !actor) return [];
      return [{ id: n.id, type: n.type, refId: n.ref_id, read: !!n.read, createdAt: n.created_at, actor }];
    });
    res.json({ items, unread: q.unread.get(me).n });
  });

  api.post('/notifications/read', (req, res) => {
    q.readNotifs.run(req.user.id);
    res.json({ ok: true });
  });
}
