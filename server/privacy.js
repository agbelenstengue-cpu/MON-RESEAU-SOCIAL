// Section 20.2 : réglages de confidentialité et valeurs par défaut.
// MIC n'a pas (encore) de carnet d'adresses : « My contacts » correspond ici aux amis.
import { ageFromBirthDate } from './social.js';

export const TIMERS = [0, 24 * 3600 * 1000, 7 * 24 * 3600 * 1000, 90 * 24 * 3600 * 1000];

export const PRIVACY_OPTIONS = {
  lastSeen: ['everyone', 'friends', 'nobody'],
  profilePhoto: ['everyone', 'friends', 'nobody'],
  about: ['everyone', 'friends', 'nobody'],
  readReceipts: [true, false],
  typingIndicator: [true, false],
  whoCanMessage: ['everyone', 'friends'],
  whoCanCall: ['everyone', 'friends', 'nobody'],
  whoCanMention: ['everyone', 'following', 'nobody'],
  suggestAccount: [true, false],
  defaultTimer: TIMERS,
};

const ADULT = {
  lastSeen: 'friends',
  profilePhoto: 'friends',
  about: 'friends',
  readReceipts: true,
  typingIndicator: true,
  whoCanMessage: 'everyone', // les inconnus arrivent dans « Message requests »
  whoCanCall: 'friends',
  whoCanMention: 'everyone',
  suggestAccount: true,
  defaultTimer: 0,
};

// Section 23 : valeurs plus strictes et verrouillées pour les mineurs.
const MINOR = { ...ADULT, whoCanMessage: 'friends', whoCanCall: 'friends', whoCanMention: 'following', suggestAccount: false };
export const MINOR_LOCKED = ['whoCanMessage', 'whoCanCall'];

export function isMinor(user) {
  return ageFromBirthDate(user.birth_date) < 18;
}

export function getPrivacy(user) {
  const base = isMinor(user) ? MINOR : ADULT;
  let saved = {};
  try {
    saved = user.privacy ? JSON.parse(user.privacy) : {};
  } catch {
    saved = {};
  }
  const out = { ...base };
  for (const [k, v] of Object.entries(saved)) {
    if (PRIVACY_OPTIONS[k]?.includes(v) && !(isMinor(user) && MINOR_LOCKED.includes(k))) out[k] = v;
  }
  return out;
}

// Applique une modification partielle ; renvoie le JSON à stocker ou lève une erreur.
export function mergePrivacy(user, patch) {
  const current = getPrivacy(user);
  for (const [k, v] of Object.entries(patch ?? {})) {
    if (!PRIVACY_OPTIONS[k]) throw Object.assign(new Error(k), { code: 'invalid_setting' });
    if (!PRIVACY_OPTIONS[k].includes(v)) throw Object.assign(new Error(k), { code: 'invalid_setting' });
    if (isMinor(user) && MINOR_LOCKED.includes(k)) throw Object.assign(new Error(k), { code: 'locked_for_minors' });
    current[k] = v;
  }
  return current;
}

// « everyone » / « friends » / « nobody » appliqué à une relation.
export function allows(level, { self, friend }) {
  if (self) return true;
  if (level === 'everyone') return true;
  if (level === 'friends') return !!friend;
  return false;
}
