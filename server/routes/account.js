// Section 5 : inscription par numéro, OTP, identité, présence World, suppression.
import crypto from 'node:crypto';
import { USERNAME_RE, ageFromBirthDate, now } from '../social.js';
import { getPrivacy, mergePrivacy, isMinor, MINOR_LOCKED, PRIVACY_OPTIONS } from '../privacy.js';

const OTP_TTL = 10 * 60 * 1000;
const OTP_MAX_PER_HOUR = 5;
const MIN_AGE = 13; // à fixer par pays avec le juridique (section 23)
const ADULT_AGE = 18;
const LANGUAGES = ['en', 'fr', 'es', 'pt', 'ar', 'sw']; // langues de lancement (3.2)

export function normalizePhone(raw) {
  const digits = String(raw ?? '').replace(/[\s().-]/g, '');
  return /^\+[1-9]\d{7,14}$/.test(digits) ? digits : null;
}

export default function accountRoutes(api, { db, views, hub, saveMedia, HttpError, devOtp, moderators = [] }, requireAuth) {
  const tickets = new Map(); // ticket d'inscription -> { phone, expires }

  const q = {
    recentOtps: db.prepare('SELECT COUNT(*) AS n FROM otps WHERE phone = ? AND created_at > ?'),
    insertOtp: db.prepare('INSERT INTO otps (phone, code, expires_at, created_at) VALUES (?, ?, ?, ?)'),
    lastOtp: db.prepare('SELECT rowid, * FROM otps WHERE phone = ? ORDER BY created_at DESC LIMIT 1'),
    bumpOtp: db.prepare('UPDATE otps SET attempts = attempts + 1 WHERE rowid = ?'),
    clearOtps: db.prepare('DELETE FROM otps WHERE phone = ?'),
    userByPhone: db.prepare('SELECT * FROM users WHERE phone = ?'),
    userByName: db.prepare('SELECT id FROM users WHERE username = ?'),
    insertUser: db.prepare(`INSERT INTO users
      (phone, username, display_name, birth_date, language, country, world_enabled, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)`),
    insertSession: db.prepare('INSERT INTO sessions (token, user_id, created_at) VALUES (?, ?, ?)'),
    deleteSession: db.prepare('DELETE FROM sessions WHERE token = ?'),
    user: db.prepare('SELECT * FROM users WHERE id = ?'),
    deleteUser: db.prepare('DELETE FROM users WHERE id = ?'),
  };

  const newSession = (userId) => {
    const token = crypto.randomBytes(32).toString('hex');
    q.insertSession.run(token, userId, now());
    return token;
  };

  const suggestUsernames = (base) => {
    const clean = (base || 'mic').toLowerCase().normalize('NFD').replace(/[^a-z0-9._]/g, '').slice(0, 24) || 'mic';
    const out = [];
    for (const candidate of [clean, `${clean}237`, `${clean}.mic`, `${clean}_${crypto.randomInt(10, 999)}`]) {
      if (candidate.length >= 3 && !q.userByName.get(candidate)) out.push(candidate);
      if (out.length === 3) break;
    }
    return out;
  };

  // Étape 1 : envoi du code (le SMS est simulé tant qu'aucun fournisseur n'est branché).
  api.post('/auth/request-otp', (req, res) => {
    const phone = normalizePhone(req.body?.phone);
    if (!phone) throw new HttpError(400, 'invalid_phone');
    if (q.recentOtps.get(phone, now() - 3600_000).n >= OTP_MAX_PER_HOUR) throw new HttpError(429, 'too_many_codes');
    const code = String(crypto.randomInt(0, 1_000_000)).padStart(6, '0');
    q.insertOtp.run(phone, code, now() + OTP_TTL, now());
    if (devOtp) console.log(`[OTP] ${phone} → ${code}`);
    res.json({ sent: true, phone, ...(devOtp ? { devCode: code } : {}) });
  });

  // Étape 2 : vérification. Compte existant → connexion ; sinon ticket d'inscription.
  api.post('/auth/verify', (req, res) => {
    const phone = normalizePhone(req.body?.phone);
    const code = String(req.body?.code ?? '').replace(/\D/g, '').padEnd(6, 'x').slice(0, 6);
    const otp = phone && q.lastOtp.get(phone);
    if (!otp || otp.expires_at < now()) throw new HttpError(400, 'code_expired');
    if (otp.attempts >= 5) throw new HttpError(429, 'too_many_attempts');
    if (!crypto.timingSafeEqual(Buffer.from(otp.code), Buffer.from(code))) {
      q.bumpOtp.run(otp.rowid);
      throw new HttpError(400, 'wrong_code');
    }
    q.clearOtps.run(phone);
    const user = q.userByPhone.get(phone);
    if (user?.banned) throw new HttpError(403, 'account_banned');
    if (user) return res.json({ token: newSession(user.id), user: views.selfAccount(user) });
    const ticket = crypto.randomBytes(24).toString('hex');
    tickets.set(ticket, { phone, expires: now() + 30 * 60 * 1000 });
    res.json({ needsSignup: true, ticket });
  });

  api.get('/auth/username', (req, res) => {
    const u = String(req.query.u ?? '').toLowerCase();
    const valid = USERNAME_RE.test(u);
    const available = valid && !q.userByName.get(u);
    res.json({ valid, available, suggestions: available ? [] : suggestUsernames(u) });
  });

  // Étapes 3, 4 et 7 : date de naissance, identité, univers de départ.
  api.post('/auth/signup', (req, res) => {
    const { ticket, birthDate, displayName, username, joinWorld, language, country } = req.body ?? {};
    const t = tickets.get(ticket);
    if (!t || t.expires < now()) throw new HttpError(400, 'signup_expired');
    const age = ageFromBirthDate(String(birthDate ?? ''));
    if (Number.isNaN(age) || age > 120) throw new HttpError(400, 'invalid_birth_date');
    if (age < MIN_AGE) {
      tickets.delete(ticket);
      throw new HttpError(403, 'too_young');
    }
    const name = String(displayName ?? '').trim();
    if (name.length < 1 || name.length > 50) throw new HttpError(400, 'invalid_name');
    const handle = String(username ?? '').toLowerCase();
    if (!USERNAME_RE.test(handle)) throw new HttpError(400, 'invalid_username');
    if (q.userByName.get(handle)) throw new HttpError(409, 'username_taken');
    if (q.userByPhone.get(t.phone)) throw new HttpError(409, 'phone_taken');
    // Mineurs : « Stay private » uniquement (23).
    const world = joinWorld && age >= ADULT_AGE ? 1 : 0;
    const lang = LANGUAGES.includes(language) ? language : 'en';
    const info = q.insertUser.run(t.phone, handle, name, birthDate, lang, String(country || 'CM').slice(0, 2), world, now());
    tickets.delete(ticket);
    if (moderators.includes(handle)) db.prepare("UPDATE users SET role = 'moderator' WHERE id = ?").run(Number(info.lastInsertRowid));
    const user = q.user.get(Number(info.lastInsertRowid));
    res.status(201).json({ token: newSession(user.id), user: views.selfAccount(user) });
  });

  api.post('/auth/logout', requireAuth, (req, res) => {
    q.deleteSession.run(req.token);
    res.json({ ok: true });
  });

  api.get('/me', requireAuth, (req, res) => res.json(views.selfAccount(req.user)));

  api.patch('/me', requireAuth, (req, res) => {
    const b = req.body ?? {};
    const u = req.user;
    const fields = {};
    if (b.displayName !== undefined) {
      const v = String(b.displayName).trim();
      if (v.length < 1 || v.length > 50) throw new HttpError(400, 'invalid_name');
      fields.display_name = v;
    }
    if (b.about !== undefined) fields.about = String(b.about).slice(0, 140);
    if (b.avatar !== undefined) fields.avatar = saveMedia(b.avatar);
    if (b.language !== undefined) {
      if (!LANGUAGES.includes(b.language)) throw new HttpError(400, 'invalid_language');
      fields.language = b.language;
    }
    if (b.username !== undefined) {
      const v = String(b.username).toLowerCase();
      if (!USERNAME_RE.test(v)) throw new HttpError(400, 'invalid_username');
      const other = q.userByName.get(v);
      if (other && other.id !== u.id) throw new HttpError(409, 'username_taken');
      fields.username = v;
    }
    if (b.publicName !== undefined) fields.public_name = String(b.publicName).trim().slice(0, 50) || null;
    if (b.publicAvatar !== undefined) fields.public_avatar = saveMedia(b.publicAvatar);
    if (b.bio !== undefined) fields.bio = String(b.bio).slice(0, 300);
    if (b.worldPrivate !== undefined) fields.world_private = b.worldPrivate ? 1 : 0;
    if (b.firstPublicDone) fields.first_public_done = 1;
    const keys = Object.keys(fields);
    if (keys.length) {
      db.prepare(`UPDATE users SET ${keys.map((k) => `${k} = ?`).join(', ')} WHERE id = ?`).run(
        ...keys.map((k) => fields[k]),
        u.id
      );
    }
    // Passage en compte World public : les demandes en attente sont acceptées.
    if (fields.world_private === 0) {
      db.prepare("UPDATE follows SET status = 'active' WHERE followee_id = ? AND status = 'pending'").run(u.id);
    }
    res.json(views.selfAccount(q.user.get(u.id)));
  });

  // 15.1 : activer sa présence World (adultes ; mineurs selon la section 23).
  api.post('/me/world', requireAuth, (req, res) => {
    const enable = req.body?.enable !== false;
    if (enable && ageFromBirthDate(req.user.birth_date) < ADULT_AGE && !req.body?.private) {
      // Un mineur ne peut activer World qu'en compte privé.
      throw new HttpError(403, 'minor_world_private_only');
    }
    const priv = req.body?.private ? 1 : req.user.world_private;
    db.prepare('UPDATE users SET world_enabled = ?, world_private = ? WHERE id = ?').run(enable ? 1 : 0, priv, req.user.id);
    res.json(views.selfAccount(q.user.get(req.user.id)));
  });

  // 20.2 : réglages de confidentialité.
  const privacyView = (u) => ({ settings: getPrivacy(u), options: PRIVACY_OPTIONS, locked: isMinor(u) ? MINOR_LOCKED : [] });
  api.get('/me/privacy', requireAuth, (req, res) => res.json(privacyView(req.user)));
  api.patch('/me/privacy', requireAuth, (req, res) => {
    let merged;
    try {
      merged = mergePrivacy(req.user, req.body);
    } catch (err) {
      throw new HttpError(400, err.code || 'invalid_setting');
    }
    db.prepare('UPDATE users SET privacy = ? WHERE id = ?').run(JSON.stringify(merged), req.user.id);
    res.json(privacyView(q.user.get(req.user.id)));
  });

  // 5.8 : suppression du compte (immédiate dans ce prototype).
  api.delete('/me', requireAuth, (req, res) => {
    if (req.body?.confirm !== req.user.username) throw new HttpError(400, 'confirmation_required');
    q.deleteUser.run(req.user.id);
    hub.send(req.user.id, 'logout', {});
    res.json({ deleted: true });
  });

}
