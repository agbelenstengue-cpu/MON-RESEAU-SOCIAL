// Section 18 : communautés (World) et événements.
import { now, USERNAME_RE, ageFromBirthDate, extractHashtags } from '../social.js';
import { tx } from '../db.js';

const TYPES = ['public', 'private', 'hidden'];
const CATEGORIES = ['education', 'business', 'culture', 'sport', 'faith', 'tech', 'food', 'local', 'other'];
const ROLE_RANK = { member: 0, moderator: 1, admin: 2, owner: 3 };
const EVENT_VISIBILITY = ['public', 'followers', 'friends', 'community'];
const HOUR = 3600 * 1000;

export default function communityRoutes(api, ctx) {
  const { db, social, views, notify, saveMedia, HttpError } = ctx;
  const q = {
    byId: db.prepare('SELECT * FROM communities WHERE id = ?'),
    byHandle: db.prepare('SELECT * FROM communities WHERE handle = ?'),
    insert: db.prepare('INSERT INTO communities (owner_id, handle, name, description, category, type, rules, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'),
    update: db.prepare('UPDATE communities SET name = ?, description = ?, category = ?, type = ?, rules = ?, avatar = ? WHERE id = ?'),
    pin: db.prepare('UPDATE communities SET pinned_post_id = ? WHERE id = ?'),
    member: db.prepare('SELECT * FROM community_members WHERE community_id = ? AND user_id = ?'),
    addMember: db.prepare('INSERT OR REPLACE INTO community_members (community_id, user_id, role, status, created_at) VALUES (?, ?, ?, ?, ?)'),
    removeMember: db.prepare('DELETE FROM community_members WHERE community_id = ? AND user_id = ?'),
    setRole: db.prepare('UPDATE community_members SET role = ? WHERE community_id = ? AND user_id = ?'),
    setStatus: db.prepare('UPDATE community_members SET status = ? WHERE community_id = ? AND user_id = ?'),
    members: db.prepare("SELECT * FROM community_members WHERE community_id = ? AND status = 'active' ORDER BY CASE role WHEN 'owner' THEN 0 WHEN 'admin' THEN 1 WHEN 'moderator' THEN 2 ELSE 3 END, created_at LIMIT 200"),
    pending: db.prepare("SELECT * FROM community_members WHERE community_id = ? AND status = 'pending' ORDER BY created_at"),
    count: db.prepare("SELECT COUNT(*) AS n FROM community_members WHERE community_id = ? AND status = 'active'"),
    mine: db.prepare("SELECT c.* FROM community_members m JOIN communities c ON c.id = m.community_id WHERE m.user_id = ? AND m.status = 'active' ORDER BY c.name"),
    discover: db.prepare(`SELECT c.*, (SELECT COUNT(*) FROM community_members m WHERE m.community_id = c.id AND m.status = 'active') AS n
      FROM communities c WHERE c.type != 'hidden' AND (? = '' OR c.name LIKE ? ESCAPE '\\' OR c.handle LIKE ? ESCAPE '\\' OR c.category = ?)
      ORDER BY n DESC, c.created_at DESC LIMIT 30`),
    posts: db.prepare('SELECT * FROM posts WHERE community_id = ? AND deleted_at IS NULL ORDER BY created_at DESC LIMIT 60'),
    feed: db.prepare(`SELECT p.* FROM posts p JOIN community_members m ON m.community_id = p.community_id AND m.user_id = ? AND m.status = 'active'
      WHERE p.deleted_at IS NULL ORDER BY p.created_at DESC LIMIT 60`),
    post: db.prepare('SELECT * FROM posts WHERE id = ?'),
    insertPost: db.prepare(`INSERT INTO posts (author_id, body, media, audience, who_can_comment, hide_likes, created_at, community_id)
      VALUES (?, ?, ?, 'everyone', ?, 0, ?, ?)`),
    addTag: db.prepare('INSERT OR IGNORE INTO post_hashtags (post_id, tag) VALUES (?, ?)'),
    removePost: db.prepare('UPDATE posts SET deleted_at = ? WHERE id = ?'),
    log: db.prepare('INSERT INTO community_log (community_id, actor_id, action, target, created_at) VALUES (?, ?, ?, ?, ?)'),
    logs: db.prepare('SELECT * FROM community_log WHERE community_id = ? ORDER BY id DESC LIMIT 100'),
    // Événements
    event: db.prepare('SELECT * FROM events WHERE id = ?'),
    insertEvent: db.prepare(`INSERT INTO events (host_id, community_id, title, description, starts_at, ends_at, timezone, location, online_url, visibility, cover, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`),
    updateEvent: db.prepare(`UPDATE events SET title = ?, description = ?, starts_at = ?, ends_at = ?, timezone = ?, location = ?, online_url = ?, visibility = ?, cover = ?, cancelled = ? WHERE id = ?`),
    upcoming: db.prepare('SELECT * FROM events WHERE (ends_at IS NULL AND starts_at > ?) OR ends_at > ? ORDER BY starts_at ASC LIMIT 300'),
    communityEvents: db.prepare('SELECT * FROM events WHERE community_id = ? AND starts_at > ? ORDER BY starts_at ASC LIMIT 50'),
    rsvp: db.prepare('INSERT INTO event_rsvps (event_id, user_id, status, created_at) VALUES (?, ?, ?, ?) ON CONFLICT(event_id, user_id) DO UPDATE SET status = excluded.status'),
    unrsvp: db.prepare('DELETE FROM event_rsvps WHERE event_id = ? AND user_id = ?'),
    myRsvp: db.prepare('SELECT status FROM event_rsvps WHERE event_id = ? AND user_id = ?'),
    rsvpCounts: db.prepare('SELECT status, COUNT(*) AS n FROM event_rsvps WHERE event_id = ? GROUP BY status'),
    attendees: db.prepare("SELECT user_id, status FROM event_rsvps WHERE event_id = ? AND status != 'cant' LIMIT 100"),
    interestedIds: db.prepare("SELECT user_id FROM event_rsvps WHERE event_id = ? AND status IN ('going', 'interested')"),
    dueReminders: db.prepare(`SELECT r.event_id, r.user_id, r.reminded, e.starts_at FROM event_rsvps r JOIN events e ON e.id = r.event_id
      WHERE r.status IN ('going', 'interested') AND e.cancelled = 0 AND e.starts_at > ? AND e.starts_at <= ?`),
    markReminded: db.prepare('UPDATE event_rsvps SET reminded = ? WHERE event_id = ? AND user_id = ?'),
  };

  const load = (idOrHandle) => {
    const c = /^\d+$/.test(String(idOrHandle)) ? q.byId.get(Number(idOrHandle)) : q.byHandle.get(String(idOrHandle).toLowerCase());
    if (!c) throw new HttpError(404, 'community_not_found');
    return c;
  };
  const roleOf = (c, userId) => {
    const m = q.member.get(c.id, userId);
    return m?.status === 'active' ? m.role : null;
  };
  const requireRole = (c, userId, min) => {
    const role = roleOf(c, userId);
    if (!role || ROLE_RANK[role] < ROLE_RANK[min]) throw new HttpError(403, 'community_role_required');
    return role;
  };
  const audit = (c, actorId, action, target = '') => q.log.run(c.id, actorId, action, String(target), now());

  const communityView = (c, viewerId) => {
    const m = q.member.get(c.id, viewerId);
    const role = m?.status === 'active' ? m.role : null;
    let rules = [];
    try {
      rules = JSON.parse(c.rules);
    } catch {
      rules = [];
    }
    return {
      id: c.id,
      handle: c.handle,
      name: c.name,
      description: c.description,
      category: c.category,
      type: c.type,
      rules,
      avatar: c.avatar,
      members: q.count.get(c.id).n,
      role,
      status: m?.status ?? null,
      canSeeContent: c.type === 'public' || !!role,
      pinnedPostId: c.pinned_post_id,
      pendingCount: role && ROLE_RANK[role] >= ROLE_RANK.admin ? q.pending.all(c.id).length : undefined,
    };
  };

  const parseRules = (rules) => (Array.isArray(rules) ? rules : []).map((r) => String(r).trim().slice(0, 200)).filter(Boolean).slice(0, 10);

  // --- Communautés ---
  api.post('/communities', (req, res) => {
    const u = req.user;
    if (!u.world_enabled) throw new HttpError(403, 'world_presence_required');
    ctx.assertNotRestricted(u);
    const b = req.body ?? {};
    const type = TYPES.includes(b.type) ? b.type : 'public';
    // 18.2 : 18 ans et plus pour créer une communauté publique.
    if (type === 'public' && ageFromBirthDate(u.birth_date) < 18) throw new HttpError(403, 'adults_only');
    const name = String(b.name ?? '').trim().slice(0, 80);
    const handle = String(b.handle ?? '').toLowerCase();
    if (!name) throw new HttpError(400, 'invalid_name');
    if (!USERNAME_RE.test(handle)) throw new HttpError(400, 'invalid_handle');
    if (q.byHandle.get(handle)) throw new HttpError(409, 'handle_taken');
    const category = CATEGORIES.includes(b.category) ? b.category : 'other';
    const id = tx(db, () => {
      const cid = Number(q.insert.run(u.id, handle, name, String(b.description ?? '').slice(0, 1000), category, type, JSON.stringify(parseRules(b.rules)), now()).lastInsertRowid);
      q.addMember.run(cid, u.id, 'owner', 'active', now());
      return cid;
    });
    res.status(201).json(communityView(q.byId.get(id), u.id));
  });

  api.get('/communities', (req, res) => {
    const term = String(req.query.q ?? '').trim();
    const like = `%${term.replace(/[\\%_]/g, (ch) => '\\' + ch)}%`;
    res.json({
      mine: q.mine.all(req.user.id).map((c) => communityView(c, req.user.id)),
      discover: q.discover.all(term, like, like, term).map((c) => communityView(c, req.user.id)),
      categories: CATEGORIES,
    });
  });

  // Fil « Communities » (14.1) : publications des communautés dont je suis membre.
  api.get('/feed/communities', (req, res) => {
    const me = req.user.id;
    res.json(q.feed.all(me).filter((p) => social.canViewPost(me, p)).map((p) => ({ ...views.post(p, me), community: communityView(q.byId.get(p.community_id), me) })));
  });

  api.get('/communities/:id', (req, res) => {
    const c = load(req.params.id);
    const role = roleOf(c, req.user.id);
    const invited = q.member.get(c.id, req.user.id)?.status === 'invited';
    // Communauté cachée : introuvable sans en être membre ou invité.
    if (c.type === 'hidden' && !role && !invited) throw new HttpError(404, 'community_not_found');
    res.json(communityView(c, req.user.id));
  });

  api.patch('/communities/:id', (req, res) => {
    const c = load(req.params.id);
    requireRole(c, req.user.id, 'admin');
    const b = req.body ?? {};
    const name = b.name !== undefined ? String(b.name).trim().slice(0, 80) || c.name : c.name;
    const type = TYPES.includes(b.type) ? b.type : c.type;
    q.update.run(
      name,
      b.description !== undefined ? String(b.description).slice(0, 1000) : c.description,
      CATEGORIES.includes(b.category) ? b.category : c.category,
      type,
      b.rules !== undefined ? JSON.stringify(parseRules(b.rules)) : c.rules,
      b.avatar !== undefined ? saveMedia(b.avatar) : c.avatar,
      c.id
    );
    audit(c, req.user.id, 'settings_updated');
    res.json(communityView(q.byId.get(c.id), req.user.id));
  });

  // Rejoindre : direct (publique), sur demande (privée), sur invitation (cachée).
  api.post('/communities/:id/join', (req, res) => {
    const c = load(req.params.id);
    const m = q.member.get(c.id, req.user.id);
    if (m?.status === 'active') return res.json(communityView(c, req.user.id));
    if (c.type === 'hidden' && m?.status !== 'invited') throw new HttpError(404, 'community_not_found');
    const status = c.type === 'private' && m?.status !== 'invited' ? 'pending' : 'active';
    q.addMember.run(c.id, req.user.id, 'member', status, now());
    if (status === 'pending') {
      for (const a of q.members.all(c.id)) if (ROLE_RANK[a.role] >= ROLE_RANK.admin) notify(a.user_id, req.user.id, 'community_request', c.id);
    }
    res.json(communityView(c, req.user.id));
  });

  api.post('/communities/:id/leave', (req, res) => {
    const c = load(req.params.id);
    if (c.owner_id === req.user.id) throw new HttpError(400, 'owner_cannot_leave');
    q.removeMember.run(c.id, req.user.id);
    res.json(communityView(c, req.user.id));
  });

  api.get('/communities/:id/members', (req, res) => {
    const c = load(req.params.id);
    if (!communityView(c, req.user.id).canSeeContent) throw new HttpError(404, 'community_not_found');
    const role = roleOf(c, req.user.id);
    const isAdmin = role && ROLE_RANK[role] >= ROLE_RANK.admin;
    res.json({
      members: q.members.all(c.id).map((m) => ({ ...views.userCard(m.user_id, req.user.id), role: m.role })),
      pending: isAdmin ? q.pending.all(c.id).map((m) => views.userCard(m.user_id, req.user.id)) : undefined,
    });
  });

  // Gestion des membres : approuver, inviter, nommer, exclure (18.3).
  api.post('/communities/:id/members/:userId', (req, res) => {
    const c = load(req.params.id);
    const userId = Number(req.params.userId);
    const action = req.body?.action;
    const myRole = requireRole(c, req.user.id, action === 'remove' ? 'moderator' : 'admin');
    const target = q.member.get(c.id, userId);
    if (action === 'invite') {
      if (!social.isFriend(req.user.id, userId)) throw new HttpError(403, 'not_friend');
      if (!target) q.addMember.run(c.id, userId, 'member', 'invited', now());
      notify(userId, req.user.id, 'community_invite', c.id);
    } else if (!target) {
      throw new HttpError(404, 'member_not_found');
    } else if (action === 'approve') {
      q.setStatus.run('active', c.id, userId);
      notify(userId, req.user.id, 'community_approved', c.id);
    } else if (action === 'decline') {
      q.removeMember.run(c.id, userId);
    } else if (action === 'remove') {
      if (target.role === 'owner' || ROLE_RANK[target.role] >= ROLE_RANK[myRole]) throw new HttpError(403, 'community_role_required');
      q.removeMember.run(c.id, userId);
    } else if (action === 'role') {
      const role = req.body?.role;
      if (!['member', 'moderator', 'admin'].includes(role) || target.role === 'owner') throw new HttpError(400, 'invalid_role');
      q.setRole.run(role, c.id, userId);
    } else throw new HttpError(400, 'invalid_action');
    audit(c, req.user.id, action, userId);
    res.json({ ok: true });
  });

  api.get('/communities/:id/log', (req, res) => {
    const c = load(req.params.id);
    requireRole(c, req.user.id, 'admin');
    res.json(q.logs.all(c.id).map((l) => ({ id: l.id, action: l.action, target: l.target, createdAt: l.created_at, actor: l.actor_id ? views.userCard(l.actor_id, req.user.id) : null })));
  });

  api.get('/communities/:id/posts', (req, res) => {
    const c = load(req.params.id);
    if (!communityView(c, req.user.id).canSeeContent) throw new HttpError(404, 'community_not_found');
    const me = req.user.id;
    const posts = q.posts.all(c.id).filter((p) => social.canViewPost(me, p));
    // Annonce épinglée en tête.
    posts.sort((a, b) => (b.id === c.pinned_post_id) - (a.id === c.pinned_post_id));
    res.json(posts.map((p) => ({ ...views.post(p, me), pinned: p.id === c.pinned_post_id })));
  });

  api.post('/communities/:id/posts', (req, res) => {
    const c = load(req.params.id);
    requireRole(c, req.user.id, 'member');
    if (!req.user.world_enabled) throw new HttpError(403, 'world_presence_required');
    ctx.assertNotRestricted(req.user);
    const body = String(req.body?.body ?? '').slice(0, 5000);
    const media = saveMedia(req.body?.media);
    if (!body.trim() && !media) throw new HttpError(400, 'empty_post');
    const id = tx(db, () => {
      const pid = Number(q.insertPost.run(req.user.id, body, media, 'everyone', now(), c.id).lastInsertRowid);
      for (const tag of extractHashtags(body)) q.addTag.run(pid, tag);
      return pid;
    });
    res.status(201).json(views.post(q.post.get(id), req.user.id));
  });

  // Modérateurs : retirer une publication ; admins : épingler (18.3, 18.5).
  api.delete('/communities/:id/posts/:postId', (req, res) => {
    const c = load(req.params.id);
    const p = q.post.get(Number(req.params.postId));
    if (!p || p.community_id !== c.id) throw new HttpError(404, 'post_not_found');
    if (p.author_id !== req.user.id) requireRole(c, req.user.id, 'moderator');
    q.removePost.run(now(), p.id);
    audit(c, req.user.id, 'post_removed', p.id);
    res.json({ ok: true });
  });

  api.post('/communities/:id/pin', (req, res) => {
    const c = load(req.params.id);
    requireRole(c, req.user.id, 'admin');
    const postId = req.body?.postId ? Number(req.body.postId) : null;
    if (postId && q.post.get(postId)?.community_id !== c.id) throw new HttpError(404, 'post_not_found');
    q.pin.run(postId, c.id);
    audit(c, req.user.id, postId ? 'pinned' : 'unpinned', postId ?? '');
    res.json(communityView(q.byId.get(c.id), req.user.id));
  });

  // --- Événements (18.6) ---
  const canSeeEvent = (e, viewerId) => {
    if (e.host_id === viewerId) return true;
    if (social.isBlockedEither(e.host_id, viewerId)) return false;
    if (e.community_id) {
      const c = q.byId.get(e.community_id);
      if (!c) return false;
      return e.visibility === 'public' ? c.type === 'public' || !!roleOf(c, viewerId) : !!roleOf(c, viewerId);
    }
    switch (e.visibility) {
      case 'public':
        return true;
      case 'followers':
        return social.isFollower(viewerId, e.host_id) || social.isFriend(e.host_id, viewerId);
      case 'friends':
        return social.isFriend(e.host_id, viewerId);
      default:
        return false;
    }
  };

  const eventView = (e, viewerId) => {
    const my = q.myRsvp.get(e.id, viewerId)?.status ?? null;
    const counts = Object.fromEntries(q.rsvpCounts.all(e.id).map((r) => [r.status, r.n]));
    const isHost = e.host_id === viewerId;
    // L'adresse exacte d'un événement non public n'est visible que des participants confirmés.
    const showAddress = e.visibility === 'public' || isHost || my === 'going';
    return {
      id: e.id,
      title: e.title,
      description: e.description,
      startsAt: e.starts_at,
      endsAt: e.ends_at,
      timezone: e.timezone,
      location: showAddress ? e.location : e.location ? null : '',
      locationHidden: !showAddress && !!e.location,
      onlineUrl: showAddress ? e.online_url : e.online_url ? null : '',
      visibility: e.visibility,
      cover: e.cover,
      cancelled: !!e.cancelled,
      host: views.userCard(e.host_id, viewerId),
      community: e.community_id ? (({ id, handle, name }) => ({ id, handle, name }))(q.byId.get(e.community_id) || {}) : null,
      going: counts.going || 0,
      interested: counts.interested || 0,
      myRsvp: my,
      isHost,
    };
  };

  const loadEvent = (id, viewerId) => {
    const e = q.event.get(Number(id));
    if (!e || !canSeeEvent(e, viewerId)) throw new HttpError(404, 'event_not_found');
    return e;
  };

  const eventFields = (b, base = {}) => {
    const title = b.title !== undefined ? String(b.title).trim().slice(0, 120) : base.title;
    if (!title) throw new HttpError(400, 'invalid_title');
    const startsAt = b.startsAt !== undefined ? Number(b.startsAt) : base.starts_at;
    const endsAt = b.endsAt !== undefined ? (b.endsAt ? Number(b.endsAt) : null) : (base.ends_at ?? null);
    if (!Number.isFinite(startsAt)) throw new HttpError(400, 'invalid_date');
    if (endsAt != null && (!Number.isFinite(endsAt) || endsAt < startsAt)) throw new HttpError(400, 'invalid_date');
    const visibility = EVENT_VISIBILITY.includes(b.visibility) ? b.visibility : base.visibility || 'public';
    const onlineUrl = b.onlineUrl !== undefined ? String(b.onlineUrl).trim().slice(0, 300) : base.online_url || '';
    if (onlineUrl && !/^https?:\/\//i.test(onlineUrl)) throw new HttpError(400, 'invalid_url');
    return {
      title,
      description: b.description !== undefined ? String(b.description).slice(0, 3000) : base.description || '',
      startsAt,
      endsAt,
      timezone: b.timezone !== undefined ? String(b.timezone).slice(0, 60) : base.timezone || 'UTC',
      location: b.location !== undefined ? String(b.location).trim().slice(0, 300) : base.location || '',
      onlineUrl,
      visibility,
    };
  };

  api.post('/events', (req, res) => {
    ctx.assertNotRestricted(req.user);
    const b = req.body ?? {};
    let communityId = null;
    if (b.communityId) {
      const c = load(b.communityId);
      requireRole(c, req.user.id, 'member');
      communityId = c.id;
    }
    const f = eventFields(b);
    if (f.startsAt < now() - HOUR) throw new HttpError(400, 'invalid_date');
    // 18.6 : un mineur ne peut pas publier d'adresse dans un événement public.
    if (f.visibility === 'public' && f.location && ageFromBirthDate(req.user.birth_date) < 18) throw new HttpError(403, 'minor_public_address');
    if (f.visibility === 'community' && !communityId) throw new HttpError(400, 'community_required');
    const cover = saveMedia(b.cover);
    const id = Number(q.insertEvent.run(req.user.id, communityId, f.title, f.description, f.startsAt, f.endsAt, f.timezone, f.location, f.onlineUrl, f.visibility, cover, now()).lastInsertRowid);
    q.rsvp.run(id, req.user.id, 'going', now());
    res.status(201).json(eventView(q.event.get(id), req.user.id));
  });

  api.get('/events', (req, res) => {
    const me = req.user.id;
    const t = now();
    const all = q.upcoming.all(t, t).filter((e) => canSeeEvent(e, me) && !e.cancelled);
    // Mes événements, ceux de mes amis, comptes suivis et communautés, puis les publics.
    const relevant = (e) =>
      e.host_id === me || !!q.myRsvp.get(e.id, me) || social.isFriend(e.host_id, me) || social.isFollower(me, e.host_id) || (e.community_id && social.communityMember(e.community_id, me));
    res.json({
      mine: all.filter(relevant).map((e) => eventView(e, me)),
      discover: all.filter((e) => !relevant(e) && e.visibility === 'public').slice(0, 30).map((e) => eventView(e, me)),
    });
  });

  api.get('/communities/:id/events', (req, res) => {
    const c = load(req.params.id);
    res.json(q.communityEvents.all(c.id, now() - 12 * HOUR).filter((e) => canSeeEvent(e, req.user.id)).map((e) => eventView(e, req.user.id)));
  });

  api.get('/events/:id', (req, res) => {
    const e = loadEvent(req.params.id, req.user.id);
    const out = eventView(e, req.user.id);
    out.attendees = q.attendees.all(e.id).map((r) => ({ ...views.userCard(r.user_id, req.user.id), status: r.status }));
    res.json(out);
  });

  // Modification ou annulation : les participants sont prévenus (18.6).
  api.patch('/events/:id', (req, res) => {
    const e = loadEvent(req.params.id, req.user.id);
    if (e.host_id !== req.user.id) throw new HttpError(403, 'host_only');
    const f = eventFields(req.body ?? {}, e);
    const cancelled = req.body?.cancelled !== undefined ? (req.body.cancelled ? 1 : 0) : e.cancelled;
    const cover = req.body?.cover !== undefined ? saveMedia(req.body.cover) : e.cover;
    q.updateEvent.run(f.title, f.description, f.startsAt, f.endsAt, f.timezone, f.location, f.onlineUrl, f.visibility, cover, cancelled, e.id);
    for (const { user_id } of q.interestedIds.all(e.id)) notify(user_id, req.user.id, cancelled && !e.cancelled ? 'event_cancelled' : 'event_updated', e.id);
    res.json(eventView(q.event.get(e.id), req.user.id));
  });

  api.post('/events/:id/rsvp', (req, res) => {
    const e = loadEvent(req.params.id, req.user.id);
    const status = req.body?.status;
    if (status === null) q.unrsvp.run(e.id, req.user.id);
    else if (!['going', 'interested', 'cant'].includes(status)) throw new HttpError(400, 'invalid_status');
    else q.rsvp.run(e.id, req.user.id, status, now());
    if (status === 'going') notify(e.host_id, req.user.id, 'event_going', e.id);
    res.json(eventView(q.event.get(e.id), req.user.id));
  });

  // Ajout au calendrier du téléphone (fichier iCalendar).
  api.get('/events/:id/ics', (req, res) => {
    const e = loadEvent(req.params.id, req.user.id);
    const v = eventView(e, req.user.id);
    const stamp = (ms) => new Date(ms).toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
    const esc = (s) => String(s ?? '').replace(/[\\;,]/g, (ch) => '\\' + ch).replace(/\r?\n/g, '\\n');
    const lines = [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//MIC//Interconnected World//FR',
      'BEGIN:VEVENT',
      `UID:mic-event-${e.id}@mic`,
      `DTSTAMP:${stamp(now())}`,
      `DTSTART:${stamp(e.starts_at)}`,
      `DTEND:${stamp(e.ends_at || e.starts_at + 2 * HOUR)}`,
      `SUMMARY:${esc(e.title)}`,
      `DESCRIPTION:${esc(e.description)}`,
      v.location ? `LOCATION:${esc(v.location)}` : null,
      v.onlineUrl ? `URL:${esc(v.onlineUrl)}` : null,
      e.cancelled ? 'STATUS:CANCELLED' : 'STATUS:CONFIRMED',
      'END:VEVENT',
      'END:VCALENDAR',
    ].filter(Boolean);
    res.set('Content-Type', 'text/calendar; charset=utf-8');
    res.set('Content-Disposition', `attachment; filename="mic-event-${e.id}.ics"`);
    res.send(lines.join('\r\n'));
  });

  // Rappels : 1 jour et 1 heure avant (18.6), vérifiés chaque minute.
  const sendReminders = () => {
    const t = now();
    for (const r of q.dueReminders.all(t, t + 24 * HOUR)) {
      const kind = r.starts_at - t <= HOUR ? 'hour' : 'day';
      if (r.reminded.includes(kind)) continue;
      q.markReminded.run(`${r.reminded},${kind}`, r.event_id, r.user_id);
      notify(r.user_id, null, kind === 'hour' ? 'event_reminder_hour' : 'event_reminder_day', r.event_id);
    }
  };
  setInterval(sendReminders, 60 * 1000).unref();
  ctx.sendEventReminders = sendReminders;
}
