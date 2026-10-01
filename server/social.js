// Règles du graphe social et de visibilité (sections 6, 12, 14 du cahier).
// Toutes les décisions « qui peut voir quoi » passent par ce module.

export const HASHTAG_RE = /#([\p{L}\p{N}_]{1,50})/gu;
export const MENTION_RE = /@([a-z0-9._]{3,30})/g;
export const USERNAME_RE = /^[a-z0-9._]{3,30}$/;

export function now() {
  return Date.now();
}

export function extractHashtags(text) {
  const tags = new Set();
  for (const m of text.matchAll(HASHTAG_RE)) tags.add(m[1].toLowerCase());
  return [...tags];
}

export function extractMentions(text) {
  const names = new Set();
  for (const m of text.matchAll(MENTION_RE)) names.add(m[1]);
  return [...names];
}

export function ageFromBirthDate(birth, today = new Date()) {
  const d = new Date(birth + 'T00:00:00Z');
  if (Number.isNaN(d.getTime())) return NaN;
  let age = today.getUTCFullYear() - d.getUTCFullYear();
  const m = today.getUTCMonth() - d.getUTCMonth();
  if (m < 0 || (m === 0 && today.getUTCDate() < d.getUTCDate())) age--;
  return age;
}

export function makeSocial(db) {
  const q = {
    isFriend: db.prepare('SELECT 1 FROM friendships WHERE user_id = ? AND friend_id = ?'),
    isClose: db.prepare('SELECT 1 FROM close_friends WHERE owner_id = ? AND friend_id = ?'),
    follow: db.prepare('SELECT status FROM follows WHERE follower_id = ? AND followee_id = ?'),
    blocked: db.prepare(
      'SELECT 1 FROM blocks WHERE (blocker_id = ? AND blocked_id = ?) OR (blocker_id = ? AND blocked_id = ?)'
    ),
    iBlocked: db.prepare('SELECT 1 FROM blocks WHERE blocker_id = ? AND blocked_id = ?'),
    request: db.prepare('SELECT 1 FROM friend_requests WHERE from_id = ? AND to_id = ?'),
    user: db.prepare('SELECT * FROM users WHERE id = ?'),
  };

  const social = {
    isFriend: (a, b) => !!q.isFriend.get(a, b),
    isCloseFriend: (owner, viewer) => !!q.isClose.get(owner, viewer),
    followStatus: (follower, followee) => q.follow.get(follower, followee)?.status ?? null,
    isFollower: (follower, followee) => q.follow.get(follower, followee)?.status === 'active',
    isBlockedEither: (a, b) => !!q.blocked.get(a, b, b, a),
    hasBlocked: (blocker, blocked) => !!q.iBlocked.get(blocker, blocked),
    hasRequest: (from, to) => !!q.request.get(from, to),

    relationship(viewerId, targetId) {
      if (viewerId === targetId) return { self: true };
      return {
        friend: social.isFriend(viewerId, targetId),
        closeFriend: social.isCloseFriend(viewerId, targetId), // dans MA liste de proches
        following: social.followStatus(viewerId, targetId),
        followsMe: social.isFollower(targetId, viewerId),
        requestSent: social.hasRequest(viewerId, targetId),
        requestReceived: social.hasRequest(targetId, viewerId),
        blocked: social.hasBlocked(viewerId, targetId),
      };
    },

    // Story : audiences 12.1.
    canViewStory(viewerId, story) {
      if (story.author_id === viewerId) return true;
      if (social.isBlockedEither(viewerId, story.author_id)) return false;
      switch (story.audience) {
        case 'friends':
          return social.isFriend(story.author_id, viewerId);
        case 'close_friends':
          return social.isCloseFriend(story.author_id, viewerId);
        case 'world': {
          const author = q.user.get(story.author_id);
          if (!author?.world_enabled) return false;
          return !author.world_private || social.isFollower(viewerId, story.author_id);
        }
        default:
          return false; // only_me
      }
    },

    // Publication World : réglage « Who can view » (14.4).
    canViewPost(viewerId, post, author = q.user.get(post.author_id)) {
      if (!post || post.deleted_at) return false;
      if (post.author_id === viewerId) return true;
      if (social.isBlockedEither(viewerId, post.author_id)) return false;
      if (!author?.world_enabled) return false;
      switch (post.audience) {
        case 'everyone':
          return !author.world_private || social.isFollower(viewerId, post.author_id);
        case 'followers':
          return social.isFollower(viewerId, post.author_id);
        case 'friends':
          return social.isFriend(post.author_id, viewerId);
        default:
          return false;
      }
    },

    canComment(viewerId, post) {
      if (post.author_id === viewerId) return true;
      switch (post.who_can_comment) {
        case 'everyone':
          return true;
        case 'followers':
          return social.isFollower(viewerId, post.author_id);
        case 'friends':
          return social.isFriend(post.author_id, viewerId);
        default:
          return false;
      }
    },

    // Section 6.2 : qui voit « en ligne » / « vu à » (amis seulement par défaut).
    canSeePresence(viewerId, targetId) {
      return viewerId === targetId || social.isFriend(targetId, viewerId);
    },
  };
  return social;
}
