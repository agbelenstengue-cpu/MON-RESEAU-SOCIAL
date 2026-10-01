// Section 22 : signalement, chaîne de modération, avertissements (strikes), appels.
import { now } from '../social.js';
import { tx } from '../db.js';

export const REPORT_REASONS = ['spam', 'harassment', 'hate', 'violence', 'nudity', 'minor_safety', 'self_harm', 'scam', 'impersonation', 'false_info', 'other'];
const REPORT_TARGETS = ['user', 'post', 'comment', 'message', 'story'];
// Priorité absolue pour la sécurité des enfants, l'automutilation et les menaces (22.3).
const SEVERITY = { minor_safety: 0, self_harm: 0, violence: 1, harassment: 2, hate: 2, nudity: 2, scam: 3, impersonation: 3, false_info: 3, spam: 4, other: 4 };
const DAY = 24 * 3600 * 1000;
const STRIKE_TTL = 90 * DAY; // 22.5

// Échelle 22.5 : 1 = avertissement ; 2 = restriction 24 h ; 3 = 7 j ; 4 = suspension 30 j ; 5 = bannissement.
export function sanctionFor(activeStrikes) {
  if (activeStrikes >= 5) return { kind: 'ban' };
  if (activeStrikes === 4) return { kind: 'suspend', ms: 30 * DAY };
  if (activeStrikes === 3) return { kind: 'restrict', ms: 7 * DAY };
  if (activeStrikes === 2) return { kind: 'restrict', ms: DAY };
  return { kind: 'warning' };
}

export default function moderationRoutes(api, ctx) {
  const { db, social, views, hub, notify, HttpError } = ctx;
  const q = {
    user: db.prepare('SELECT * FROM users WHERE id = ?'),
    report: db.prepare('INSERT INTO reports (reporter_id, target_type, target_id, reason, details, created_at) VALUES (?, ?, ?, ?, ?, ?)'),
    reportById: db.prepare('SELECT * FROM reports WHERE id = ?'),
    open: db.prepare("SELECT * FROM reports WHERE status = 'open' ORDER BY created_at ASC LIMIT 500"),
    sameTarget: db.prepare("SELECT * FROM reports WHERE status = 'open' AND target_type = ? AND target_id = ?"),
    decide: db.prepare('UPDATE reports SET status = ?, decision = ?, decided_by = ?, decided_at = ?, note = ? WHERE id = ?'),
    myReports: db.prepare('SELECT * FROM reports WHERE reporter_id = ? ORDER BY created_at DESC LIMIT 100'),
    post: db.prepare('SELECT * FROM posts WHERE id = ?'),
    comment: db.prepare('SELECT * FROM comments WHERE id = ?'),
    message: db.prepare('SELECT * FROM messages WHERE id = ?'),
    previous: db.prepare('SELECT * FROM messages WHERE conversation_id = ? AND id < ? ORDER BY id DESC LIMIT 5'),
    member: db.prepare('SELECT 1 FROM conversation_members WHERE conversation_id = ? AND user_id = ?'),
    story: db.prepare('SELECT * FROM stories WHERE id = ?'),
    removePost: db.prepare('UPDATE posts SET deleted_at = ? WHERE id = ?'),
    removeComment: db.prepare('DELETE FROM comments WHERE id = ?'),
    removeMessage: db.prepare("UPDATE messages SET deleted = 1, body = '', media = NULL WHERE id = ?"),
    removeStory: db.prepare('DELETE FROM stories WHERE id = ?'),
    addStrike: db.prepare('INSERT INTO strikes (user_id, report_id, reason, created_at, expires_at) VALUES (?, ?, ?, ?, ?)'),
    activeStrikes: db.prepare("SELECT * FROM strikes WHERE user_id = ? AND expires_at > ? AND appeal_status != 'overturned' ORDER BY created_at DESC"),
    strike: db.prepare('SELECT * FROM strikes WHERE id = ?'),
    appeal: db.prepare("UPDATE strikes SET appeal_status = 'pending', appeal_text = ?, appealed_at = ? WHERE id = ?"),
    appeals: db.prepare("SELECT * FROM strikes WHERE appeal_status = 'pending' ORDER BY appealed_at ASC"),
    resolveAppeal: db.prepare('UPDATE strikes SET appeal_status = ?, appeal_decided_by = ? WHERE id = ?'),
    setSanction: db.prepare('UPDATE users SET restricted_until = ?, suspended_until = ?, banned = ? WHERE id = ?'),
    killSessions: db.prepare('DELETE FROM sessions WHERE user_id = ?'),
    stats: db.prepare(`SELECT reason, COUNT(*) AS n, SUM(status != 'open') AS closed FROM reports GROUP BY reason`),
  };

  const requireModerator = (req) => {
    if (req.user.role !== 'moderator') throw new HttpError(403, 'moderators_only');
  };

  // Retrouve l'auteur et un aperçu du contenu visé.
  const target = (type, id) => {
    switch (type) {
      case 'user': {
        const u = q.user.get(id);
        return u && { authorId: u.id, preview: { name: u.display_name, publicName: u.public_name, bio: u.bio, about: u.about } };
      }
      case 'post': {
        const p = q.post.get(id);
        return p && { authorId: p.author_id, removed: !!p.deleted_at, preview: { body: p.body, media: p.media, video: p.video } };
      }
      case 'comment': {
        const c = q.comment.get(id);
        return c && { authorId: c.author_id, preview: { body: c.body, postId: c.post_id } };
      }
      case 'message': {
        const m = q.message.get(id);
        // 22.2 : le message signalé et jusqu'à 5 messages précédents sont transmis.
        return (
          m && {
            authorId: m.sender_id,
            removed: !!m.deleted,
            preview: {
              body: m.body,
              media: m.media,
              kind: m.kind,
              context: q.previous.all(m.conversation_id, m.id).reverse().map((x) => ({ sender: views.userCard(x.sender_id, x.sender_id)?.name, body: x.deleted ? '' : x.body, kind: x.kind })),
            },
          }
        );
      }
      case 'story': {
        const s = q.story.get(id);
        return s && { authorId: s.author_id, preview: { body: s.body, media: s.media, audience: s.audience } };
      }
      default:
        return null;
    }
  };

  // Le signalement n'est possible que sur un contenu que la personne peut voir.
  const canSee = (userId, type, id) => {
    switch (type) {
      case 'user':
        return !!q.user.get(id);
      case 'post':
        return social.canViewPost(userId, q.post.get(id));
      case 'comment': {
        const c = q.comment.get(id);
        return !!c && social.canViewPost(userId, q.post.get(c.post_id));
      }
      case 'message': {
        const m = q.message.get(id);
        return !!m && !!q.member.get(m.conversation_id, userId);
      }
      case 'story': {
        const s = q.story.get(id);
        return !!s && social.canViewStory(userId, s);
      }
      default:
        return false;
    }
  };

  api.post('/reports', (req, res) => {
    const { targetType, targetId, reason } = req.body ?? {};
    if (!REPORT_TARGETS.includes(targetType)) throw new HttpError(400, 'invalid_target');
    if (!REPORT_REASONS.includes(reason)) throw new HttpError(400, 'invalid_reason');
    const id = Number(targetId);
    if (!canSee(req.user.id, targetType, id)) throw new HttpError(404, 'not_found');
    const details = String(req.body?.details ?? '').slice(0, 500);
    q.report.run(req.user.id, targetType, id, reason, details, now());
    res.status(201).json({ reported: true });
  });

  // 22.2 : statut de mes signalements (reçu, en cours, décision).
  api.get('/me/reports', (req, res) => {
    res.json(q.myReports.all(req.user.id).map((r) => ({ id: r.id, targetType: r.target_type, reason: r.reason, status: r.status, decision: r.decision, createdAt: r.created_at, decidedAt: r.decided_at })));
  });

  // 22.5 : page « Account status ».
  api.get('/me/status', (req, res) => {
    const u = req.user;
    const t = now();
    res.json({
      strikes: q.activeStrikes.all(u.id, t).map((s) => ({ id: s.id, reason: s.reason, createdAt: s.created_at, expiresAt: s.expires_at, appealStatus: s.appeal_status })),
      restrictedUntil: u.restricted_until > t ? u.restricted_until : null,
      suspendedUntil: u.suspended_until > t ? u.suspended_until : null,
      banned: !!u.banned,
    });
  });

  api.post('/me/strikes/:id/appeal', (req, res) => {
    const s = q.strike.get(Number(req.params.id));
    if (!s || s.user_id !== req.user.id) throw new HttpError(404, 'not_found');
    if (s.appeal_status !== 'none') throw new HttpError(409, 'already_appealed');
    q.appeal.run(String(req.body?.text ?? '').slice(0, 1000), now(), s.id);
    res.json({ appealStatus: 'pending' });
  });

  // Recalcule la sanction à partir des avertissements actifs.
  const applySanctions = (userId, { ban = false } = {}) => {
    const active = q.activeStrikes.all(userId, now()).length;
    const s = ban ? { kind: 'ban' } : sanctionFor(active);
    const t = now();
    const u = q.user.get(userId);
    q.setSanction.run(
      s.kind === 'restrict' ? t + s.ms : s.kind === 'warning' ? null : u.restricted_until,
      s.kind === 'suspend' ? t + s.ms : null,
      s.kind === 'ban' ? 1 : 0,
      userId
    );
    if (s.kind === 'suspend' || s.kind === 'ban') {
      q.killSessions.run(userId);
      hub.send(userId, 'logout', {});
    }
    return s;
  };

  // --- Console de modération (27.4) ---
  api.get('/mod/reports', (req, res) => {
    requireModerator(req);
    // Regroupement par contenu visé, tri par gravité puis ancienneté.
    const groups = new Map();
    for (const r of q.open.all()) {
      const key = `${r.target_type}:${r.target_id}`;
      if (!groups.has(key)) groups.set(key, { targetType: r.target_type, targetId: r.target_id, reports: [] });
      groups.get(key).reports.push(r);
    }
    const out = [...groups.values()].map((g) => {
      const tg = target(g.targetType, g.targetId);
      const severity = Math.min(...g.reports.map((r) => SEVERITY[r.reason] ?? 4));
      return {
        id: g.reports[0].id,
        targetType: g.targetType,
        targetId: g.targetId,
        severity,
        reasons: [...new Set(g.reports.map((r) => r.reason))],
        details: g.reports.map((r) => r.details).filter(Boolean),
        count: g.reports.length,
        firstAt: g.reports[0].created_at,
        author: tg ? views.userCard(tg.authorId, tg.authorId) : null,
        authorStrikes: tg ? q.activeStrikes.all(tg.authorId, now()).length : 0,
        preview: tg?.preview ?? null,
        removed: !!tg?.removed,
      };
    });
    out.sort((a, b) => a.severity - b.severity || a.firstAt - b.firstAt);
    res.json(out);
  });

  // Décision : aucune action · suppression + avertissement · bannissement (22.3).
  api.post('/mod/reports/:id/decide', (req, res) => {
    requireModerator(req);
    const r = q.reportById.get(Number(req.params.id));
    if (!r || r.status !== 'open') throw new HttpError(404, 'not_found');
    const action = req.body?.action;
    if (!['dismiss', 'remove', 'ban'].includes(action)) throw new HttpError(400, 'invalid_action');
    const note = String(req.body?.note ?? '').slice(0, 500);
    const tg = target(r.target_type, r.target_id);
    const all = q.sameTarget.all(r.target_type, r.target_id);
    let sanction = null;
    tx(db, () => {
      for (const x of all) q.decide.run('closed', action, req.user.id, now(), note, x.id);
      if (action === 'dismiss' || !tg) return;
      if (r.target_type === 'post') q.removePost.run(now(), r.target_id);
      if (r.target_type === 'comment') q.removeComment.run(r.target_id);
      if (r.target_type === 'message') q.removeMessage.run(r.target_id);
      if (r.target_type === 'story') q.removeStory.run(r.target_id);
      if (tg.authorId) {
        q.addStrike.run(tg.authorId, r.id, r.reason, now(), now() + STRIKE_TTL);
        sanction = applySanctions(tg.authorId, { ban: action === 'ban' });
      }
    });
    // Notification à l'auteur (règle, sanction, appel) et aux personnes qui ont signalé.
    if (tg?.authorId && action !== 'dismiss') notify(tg.authorId, null, 'moderation_strike', r.id);
    for (const x of all) notify(x.reporter_id, null, 'report_update', x.id);
    res.json({ ok: true, sanction });
  });

  api.get('/mod/appeals', (req, res) => {
    requireModerator(req);
    res.json(
      q.appeals.all().map((s) => {
        const r = q.reportById.get(s.report_id);
        return { id: s.id, user: views.userCard(s.user_id, s.user_id), reason: s.reason, text: s.appeal_text, createdAt: s.created_at, appealedAt: s.appealed_at, preview: r ? target(r.target_type, r.target_id)?.preview : null, decidedBy: r?.decided_by };
      })
    );
  });

  // Appel revu par un modérateur différent de celui qui a décidé (22.3).
  api.post('/mod/appeals/:id', (req, res) => {
    requireModerator(req);
    const s = q.strike.get(Number(req.params.id));
    if (!s || s.appeal_status !== 'pending') throw new HttpError(404, 'not_found');
    const r = q.reportById.get(s.report_id);
    if (r?.decided_by === req.user.id) throw new HttpError(403, 'different_moderator_required');
    const decision = req.body?.decision === 'overturn' ? 'overturned' : 'upheld';
    q.resolveAppeal.run(decision, req.user.id, s.id);
    if (decision === 'overturned') applySanctions(s.user_id);
    notify(s.user_id, null, 'appeal_' + decision, s.id);
    res.json({ appealStatus: decision });
  });

  // Chiffres pour un futur rapport de transparence (22.6).
  api.get('/mod/stats', (req, res) => {
    requireModerator(req);
    res.json(q.stats.all());
  });
}
