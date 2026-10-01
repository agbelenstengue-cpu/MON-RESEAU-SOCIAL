// Section 12 : My Story (Me) et World Story ne se mélangent jamais ; 24 h puis archives.
import { now } from '../social.js';

const STORY_TTL = 24 * 3600 * 1000;
const AUDIENCES = ['friends', 'close_friends', 'only_me', 'world'];
const BACKGROUNDS = ['espresso', 'cognac', 'emerald', 'sage', 'brass', 'ebony'];

export default function storyRoutes(api, { db, social, views, hub, saveMedia, HttpError }) {
  const q = {
    story: db.prepare('SELECT * FROM stories WHERE id = ?'),
    insert: db.prepare(`INSERT INTO stories (author_id, audience, kind, body, bg, media, created_at, expires_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)`),
    active: db.prepare('SELECT * FROM stories WHERE expires_at > ? ORDER BY created_at ASC'),
    archive: db.prepare('SELECT * FROM stories WHERE author_id = ? ORDER BY created_at DESC LIMIT 200'),
    view: db.prepare('INSERT OR IGNORE INTO story_views (story_id, viewer_id, viewed_at) VALUES (?, ?, ?)'),
    viewed: db.prepare('SELECT 1 FROM story_views WHERE story_id = ? AND viewer_id = ?'),
    viewers: db.prepare('SELECT * FROM story_views WHERE story_id = ? ORDER BY viewed_at DESC'),
    viewCount: db.prepare('SELECT COUNT(*) AS n FROM story_views WHERE story_id = ?'),
    del: db.prepare('DELETE FROM stories WHERE id = ?'),
    user: db.prepare('SELECT * FROM users WHERE id = ?'),
  };

  const storyView = (s, viewerId) => ({
    id: s.id,
    audience: s.audience,
    kind: s.kind,
    body: s.body,
    bg: s.bg,
    media: s.media,
    createdAt: s.created_at,
    expiresAt: s.expires_at,
    seen: s.author_id === viewerId || !!q.viewed.get(s.id, viewerId),
    views: s.author_id === viewerId ? q.viewCount.get(s.id).n : undefined,
  });

  // Onglet Stories (7.4) : amis en haut (Me), comptes World suivis en dessous.
  api.get('/stories', (req, res) => {
    const me = req.user.id;
    const groups = new Map();
    for (const s of q.active.all(now())) {
      if (!social.canViewStory(me, s)) continue;
      const universe = s.audience === 'world' ? 'world' : 'me';
      // Pour les autres : une World story n'apparaît que si on suit l'auteur
      // (ou qu'on est ami avec lui) ; elle reste accessible depuis son profil.
      if (s.author_id !== me && universe === 'world' && !social.isFollower(me, s.author_id) && !social.isFriend(me, s.author_id)) continue;
      const key = `${universe}:${s.author_id}`;
      if (!groups.has(key)) groups.set(key, { universe, author: views.userCard(s.author_id, me), stories: [] });
      groups.get(key).stories.push(storyView(s, me));
    }
    const all = [...groups.values()].map((g) => ({
      ...g,
      allSeen: g.stories.every((s) => s.seen),
      closeFriends: g.stories.some((s) => s.audience === 'close_friends'),
      latest: g.stories.at(-1).createdAt,
    }));
    const byFreshness = (a, b) => a.allSeen - b.allSeen || b.latest - a.latest;
    res.json({
      mine: all.filter((g) => g.author.id === me),
      friends: all.filter((g) => g.author.id !== me && g.universe === 'me').sort(byFreshness),
      world: all.filter((g) => g.author.id !== me && g.universe === 'world').sort(byFreshness),
    });
  });

  api.get('/stories/archive', (req, res) => {
    res.json(q.archive.all(req.user.id).map((s) => storyView(s, req.user.id)));
  });

  api.post('/stories', (req, res) => {
    const b = req.body ?? {};
    if (!AUDIENCES.includes(b.audience)) throw new HttpError(400, 'invalid_audience');
    if (b.audience === 'world' && !req.user.world_enabled) throw new HttpError(403, 'world_presence_required');
    const kind = b.kind === 'image' ? 'image' : 'text';
    const body = String(b.body ?? '').slice(0, 500);
    if (kind === 'text' && !body.trim()) throw new HttpError(400, 'empty_story');
    const media = kind === 'image' ? saveMedia(b.media) : null;
    if (kind === 'image' && !media) throw new HttpError(400, 'invalid_media');
    const bg = BACKGROUNDS.includes(b.bg) ? b.bg : 'espresso';
    const t = now();
    const id = Number(q.insert.run(req.user.id, b.audience, kind, body, bg, media, t, t + STORY_TTL).lastInsertRowid);
    hub.send(req.user.id, 'stories:changed', {});
    res.status(201).json(storyView(q.story.get(id), req.user.id));
  });

  api.post('/stories/:id/view', (req, res) => {
    const s = q.story.get(Number(req.params.id));
    if (!s || s.expires_at < now() || !social.canViewStory(req.user.id, s)) throw new HttpError(404, 'story_not_found');
    if (s.author_id !== req.user.id) q.view.run(s.id, req.user.id, now());
    res.json({ ok: true });
  });

  // 12.4 : l'auteur voit la liste des personnes qui ont vu sa story.
  api.get('/stories/:id/viewers', (req, res) => {
    const s = q.story.get(Number(req.params.id));
    if (!s || s.author_id !== req.user.id) throw new HttpError(404, 'story_not_found');
    res.json(
      q.viewers
        .all(s.id)
        .filter((v) => !social.isBlockedEither(req.user.id, v.viewer_id))
        .map((v) => ({ user: views.userCard(v.viewer_id, req.user.id), viewedAt: v.viewed_at }))
    );
  });

  api.delete('/stories/:id', (req, res) => {
    const s = q.story.get(Number(req.params.id));
    if (!s || s.author_id !== req.user.id) throw new HttpError(404, 'story_not_found');
    q.del.run(s.id);
    res.json({ ok: true });
  });

}
