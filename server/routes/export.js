// Section 24.2 : « Download my data » — archive JSON (machine) ou HTML (lisible).
import { getPrivacy } from '../privacy.js';

export default function exportRoutes(api, ctx) {
  const { db } = ctx;
  const all = (sql, ...args) => db.prepare(sql).all(...args);
  const one = (sql, ...args) => db.prepare(sql).get(...args);

  const collect = (u) => {
    const id = u.id;
    const name = (uid) => one('SELECT username FROM users WHERE id = ?', uid)?.username ?? null;
    const conversations = all(
      `SELECT c.id, c.type, c.title, c.created_at FROM conversation_members m JOIN conversations c ON c.id = m.conversation_id WHERE m.user_id = ?`,
      id
    ).map((c) => ({
      id: c.id,
      type: c.type,
      title: c.title,
      createdAt: c.created_at,
      members: all('SELECT user_id FROM conversation_members WHERE conversation_id = ?', c.id).map((r) => name(r.user_id)),
      messages: all('SELECT sender_id, kind, body, media, created_at, deleted FROM messages WHERE conversation_id = ? ORDER BY id', c.id)
        .filter((m) => !m.deleted)
        .map((m) => ({ from: name(m.sender_id), kind: m.kind, text: m.body, media: m.media, at: m.created_at })),
    }));
    return {
      generatedAt: Date.now(),
      notice: 'Archive MIC — Monde Interconnecté. Vos données personnelles (section 24.2 du cahier).',
      account: {
        username: u.username,
        phone: u.phone,
        displayName: u.display_name,
        about: u.about,
        birthDate: u.birth_date,
        language: u.language,
        country: u.country,
        createdAt: u.created_at,
        world: { enabled: !!u.world_enabled, private: !!u.world_private, publicName: u.public_name, bio: u.bio },
      },
      privacy: getPrivacy(u),
      friends: all('SELECT friend_id, created_at FROM friendships WHERE user_id = ?', id).map((r) => ({ username: name(r.friend_id), since: r.created_at })),
      closeFriends: all('SELECT friend_id FROM close_friends WHERE owner_id = ?', id).map((r) => name(r.friend_id)),
      following: all("SELECT followee_id FROM follows WHERE follower_id = ? AND status = 'active'", id).map((r) => name(r.followee_id)),
      followers: all("SELECT follower_id FROM follows WHERE followee_id = ? AND status = 'active'", id).map((r) => name(r.follower_id)),
      blocked: all('SELECT blocked_id FROM blocks WHERE blocker_id = ?', id).map((r) => name(r.blocked_id)),
      posts: all('SELECT id, body, media, video, audience, created_at, deleted_at FROM posts WHERE author_id = ? ORDER BY id', id),
      comments: all('SELECT post_id, body, created_at FROM comments WHERE author_id = ? ORDER BY id', id),
      likes: all('SELECT post_id, created_at FROM likes WHERE user_id = ?', id),
      saved: all('SELECT post_id, created_at FROM saves WHERE user_id = ?', id),
      stories: all('SELECT audience, kind, body, media, created_at FROM stories WHERE author_id = ? ORDER BY id', id),
      conversations,
      calls: all(
        'SELECT c.type, c.status, c.created_at, c.answered_at, c.ended_at FROM call_participants p JOIN calls c ON c.id = p.call_id WHERE p.user_id = ? ORDER BY c.id',
        id
      ),
      communities: all("SELECT c.name, c.handle, m.role FROM community_members m JOIN communities c ON c.id = m.community_id WHERE m.user_id = ? AND m.status = 'active'", id),
      events: all('SELECT e.title, e.starts_at, r.status FROM event_rsvps r JOIN events e ON e.id = r.event_id WHERE r.user_id = ?', id),
      channels: all('SELECT c.name, c.handle FROM channel_subs s JOIN channels c ON c.id = s.channel_id WHERE s.user_id = ?', id),
      reports: all('SELECT target_type, reason, status, decision, created_at FROM reports WHERE reporter_id = ?', id),
      strikes: all('SELECT reason, created_at, expires_at, appeal_status FROM strikes WHERE user_id = ?', id),
      notifications: all('SELECT type, created_at FROM notifications WHERE user_id = ? ORDER BY id DESC LIMIT 500', id),
    };
  };

  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
  const date = (ms) => (ms ? new Date(ms).toISOString().replace('T', ' ').slice(0, 16) : '');

  const toHtml = (d) => {
    const section = (title, rows) => `<h2>${esc(title)}</h2>${rows.length ? `<ul>${rows.map((r) => `<li>${r}</li>`).join('')}</ul>` : '<p>—</p>'}`;
    return `<!doctype html><html lang="fr"><head><meta charset="utf-8"><title>Mes données MIC</title>
<style>body{font-family:system-ui,sans-serif;max-width:760px;margin:2rem auto;padding:0 1rem;color:#1c1a19;background:#faf7f2}h1,h2{font-family:Georgia,serif;color:#3b2418}h2{border-bottom:1px solid #e6dfd4;padding-bottom:4px}li{margin:4px 0}.m{color:#6f6660;font-size:.9em}</style></head><body>
<h1>Mes données MIC — @${esc(d.account.username)}</h1><p class="m">${esc(d.notice)} Générée le ${date(d.generatedAt)} (UTC).</p>
${section('Compte', Object.entries({ ...d.account, world: undefined }).filter(([, v]) => v !== undefined).map(([k, v]) => `<b>${esc(k)}</b> : ${esc(k === 'createdAt' ? date(v) : v)}`))}
${section('Confidentialité', Object.entries(d.privacy).map(([k, v]) => `<b>${esc(k)}</b> : ${esc(v)}`))}
${section('Amis', d.friends.map((f) => `@${esc(f.username)} <span class="m">depuis ${date(f.since)}</span>`))}
${section('Abonnements', d.following.map((u) => `@${esc(u)}`))}
${section('Abonnés', d.followers.map((u) => `@${esc(u)}`))}
${section('Publications', d.posts.map((p) => `${esc(p.body || (p.video ? '[clip]' : '[photo]'))} <span class="m">${date(p.created_at)} · ${esc(p.audience)}${p.deleted_at ? ' · supprimée' : ''}</span>`))}
${section('Commentaires', d.comments.map((c) => `${esc(c.body)} <span class="m">${date(c.created_at)}</span>`))}
${section('Stories', d.stories.map((s) => `${esc(s.body || '[photo]')} <span class="m">${date(s.created_at)} · ${esc(s.audience)}</span>`))}
${d.conversations
  .map((c) => section(`Discussion ${c.type === 'group' ? `« ${c.title} »` : `avec ${c.members.filter((m) => m !== d.account.username).map((m) => '@' + m).join(', ')}`}`, c.messages.map((m) => `<b>@${esc(m.from)}</b> : ${esc(m.text || `[${m.kind}]`)} <span class="m">${date(m.at)}</span>`)))
  .join('')}
${section('Communautés', d.communities.map((c) => `${esc(c.name)} (@${esc(c.handle)}) · ${esc(c.role)}`))}
${section('Événements', d.events.map((e) => `${esc(e.title)} · ${date(e.starts_at)} · ${esc(e.status)}`))}
${section('Signalements effectués', d.reports.map((r) => `${esc(r.reason)} · ${esc(r.status)} <span class="m">${date(r.created_at)}</span>`))}
${section('Avertissements', d.strikes.map((s) => `${esc(s.reason)} · expire ${date(s.expires_at)}`))}
</body></html>`;
  };

  api.get('/me/export', (req, res) => {
    const data = collect(req.user);
    const stamp = new Date().toISOString().slice(0, 10);
    if (req.query.format === 'html') {
      res.set('Content-Type', 'text/html; charset=utf-8');
      res.set('Content-Disposition', `attachment; filename="mic-${req.user.username}-${stamp}.html"`);
      res.set('Content-Security-Policy', "default-src 'none'; style-src 'unsafe-inline'");
      return res.send(toHtml(data));
    }
    res.set('Content-Disposition', `attachment; filename="mic-${req.user.username}-${stamp}.json"`);
    res.json(data);
  });
}
