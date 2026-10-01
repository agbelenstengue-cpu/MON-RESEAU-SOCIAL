import { isMinor } from './privacy.js';
// Mise en forme des objets renvoyés au client.
// Principe 4.3 : « une personne, deux visages » — un ami voit le nom et la photo
// privés, le public voit le nom et la photo World.

export function makeViews(db, social, hub) {
  const q = {
    user: db.prepare('SELECT * FROM users WHERE id = ?'),
    likeCount: db.prepare('SELECT COUNT(*) AS n FROM likes WHERE post_id = ?'),
    commentCount: db.prepare('SELECT COUNT(*) AS n FROM comments WHERE post_id = ?'),
    shareCount: db.prepare('SELECT COUNT(*) AS n FROM shares WHERE post_id = ?'),
    saveCount: db.prepare('SELECT COUNT(*) AS n FROM saves WHERE post_id = ?'),
    liked: db.prepare('SELECT 1 FROM likes WHERE post_id = ? AND user_id = ?'),
    saved: db.prepare('SELECT 1 FROM saves WHERE post_id = ? AND user_id = ?'),
    tags: db.prepare('SELECT tag FROM post_hashtags WHERE post_id = ?'),
    reactions: db.prepare('SELECT user_id, emoji FROM message_reactions WHERE message_id = ?'),
    msg: db.prepare('SELECT * FROM messages WHERE id = ?'),
    plays: db.prepare('SELECT user_id FROM voice_plays WHERE message_id = ?'),
    opens: db.prepare('SELECT user_id FROM message_opens WHERE message_id = ?'),
    post: db.prepare('SELECT * FROM posts WHERE id = ?'),
    viewCount: db.prepare('SELECT COUNT(*) AS n FROM post_views WHERE post_id = ?'),
  };

  const views = {
    // Carte d'utilisateur vue par `viewerId`.
    userCard(u, viewerId) {
      if (typeof u === 'number') u = q.user.get(u);
      if (!u) return null;
      const intimate = u.id === viewerId || social.isFriend(u.id, viewerId);
      // Photo privée selon le réglage « Private profile photo » ; sinon photo World.
      const privatePhoto = social.allowsFor(u.id, 'profilePhoto', viewerId) ? u.avatar : null;
      const publicPhoto = u.world_enabled ? u.public_avatar : null;
      const card = {
        id: u.id,
        username: u.username,
        name: intimate ? u.display_name : u.public_name || u.display_name,
        avatar: intimate ? privatePhoto || publicPhoto : publicPhoto || privatePhoto,
        world: !!u.world_enabled,
      };
      if (social.canSeePresence(viewerId, u.id)) {
        card.online = hub.isOnline(u.id);
        card.lastSeen = u.last_seen;
      }
      return card;
    },

    // Compte complet pour son propriétaire (jamais envoyé à un tiers).
    selfAccount(u) {
      return {
        id: u.id,
        phone: u.phone,
        hasPassword: !!u.password_hash,
        username: u.username,
        displayName: u.display_name,
        about: u.about,
        avatar: u.avatar,
        birthDate: u.birth_date,
        language: u.language,
        country: u.country,
        world: {
          enabled: !!u.world_enabled,
          private: !!u.world_private,
          publicName: u.public_name,
          publicAvatar: u.public_avatar,
          bio: u.bio,
        },
        firstPublicDone: !!u.first_public_done,
        isMinor: isMinor(u),
        role: u.role || 'user',
        restrictedUntil: u.restricted_until > Date.now() ? u.restricted_until : null,
        suspendedUntil: u.suspended_until > Date.now() ? u.suspended_until : null,
        createdAt: u.created_at,
      };
    },

    post(p, viewerId) {
      const author = q.user.get(p.author_id);
      const isAuthor = p.author_id === viewerId;
      const likes = q.likeCount.get(p.id).n;
      return {
        id: p.id,
        author: views.userCard(author, viewerId),
        body: p.body,
        media: p.media,
        kind: p.video ? 'clip' : 'post',
        video: p.video || undefined,
        duration: p.video ? p.duration : undefined,
        allowDownload: p.video ? !!p.allow_download : undefined,
        views: p.video ? q.viewCount.get(p.id).n : undefined,
        audience: p.audience,
        whoCanComment: p.who_can_comment,
        hideLikes: !!p.hide_likes,
        createdAt: p.created_at,
        editedAt: p.edited_at,
        hashtags: q.tags.all(p.id).map((r) => r.tag),
        likes: p.hide_likes && !isAuthor ? null : likes,
        comments: q.commentCount.get(p.id).n,
        shares: q.shareCount.get(p.id).n,
        saves: isAuthor ? q.saveCount.get(p.id).n : undefined,
        liked: !!q.liked.get(p.id, viewerId),
        saved: !!q.saved.get(p.id, viewerId),
        canComment: social.canComment(viewerId, p),
        mine: isAuthor,
      };
    },

    // Statut d'un message envoyé (8.3) : sent → delivered → read, calculé sur
    // l'ensemble des autres membres actifs.
    // Accusés de lecture (20.2) : réciproques ; un membre qui les a coupés ne
    // fait jamais passer un message en « lu », et ne voit pas les « lu » des autres.
    messageStatus(m, members) {
      const others = members.filter((mb) => mb.user_id !== m.sender_id && mb.status === 'active');
      if (!others.length) return 'sent';
      const receipts = (id) => social.privacy(id)?.readReceipts !== false;
      if (receipts(m.sender_id) && others.every((mb) => mb.last_read_id >= m.id && receipts(mb.user_id))) return 'read';
      if (others.every((mb) => mb.last_delivered_id >= m.id)) return 'delivered';
      return 'sent';
    },

    message(m, viewerId, members) {
      const out = {
        id: m.id,
        conversationId: m.conversation_id,
        sender: m.sender_id ? views.userCard(m.sender_id, viewerId) : null,
        kind: m.kind,
        body: m.deleted ? '' : m.body,
        media: m.deleted ? null : m.media,
        meta: null,
        deleted: !!m.deleted,
        editedAt: m.edited_at,
        createdAt: m.created_at,
        reactions: q.reactions.all(m.id).map((r) => ({ userId: r.user_id, emoji: r.emoji })),
      };
      if (m.sender_id === viewerId && members) out.status = views.messageStatus(m, members);
      if (m.expires_at) out.expiresAt = m.expires_at;
      // Vue unique : le fichier n'est jamais listé, il s'obtient une fois via /open.
      if (m.view_once) {
        out.viewOnce = true;
        out.media = null;
        const opened = new Set(q.opens.all(m.id).map((r) => r.user_id));
        if (m.sender_id === viewerId) {
          const others = (members || []).filter((mb) => mb.user_id !== m.sender_id);
          out.opened = others.length > 0 && others.every((mb) => opened.has(mb.user_id));
        } else out.opened = opened.has(viewerId);
      }
      if (m.meta && !m.deleted) {
        try {
          out.meta = JSON.parse(m.meta);
        } catch {
          out.meta = null;
        }
      }
      // Vocal : écouté par moi ? écouté par tous les autres (micro vert côté expéditeur, 9.4) ?
      if (m.kind === 'voice' && !m.deleted) {
        const played = new Set(q.plays.all(m.id).map((r) => r.user_id));
        out.playedByMe = m.sender_id === viewerId || played.has(viewerId);
        if (m.sender_id === viewerId && members) {
          const others = members.filter((mb) => mb.user_id !== m.sender_id && mb.status === 'active');
          out.played = others.length > 0 && others.every((mb) => played.has(mb.user_id));
        }
      }
      if (m.reply_to) {
        const r = q.msg.get(m.reply_to);
        if (r && r.conversation_id === m.conversation_id) {
          const sender = r.sender_id ? q.user.get(r.sender_id) : null;
          out.replyTo = {
            id: r.id,
            body: r.deleted ? '' : r.body.slice(0, 140),
            kind: r.kind,
            deleted: !!r.deleted,
            senderName: sender ? views.userCard(sender, viewerId).name : '',
          };
        }
      }
      if (m.kind === 'post' && m.post_id && !m.deleted) {
        const p = q.post.get(m.post_id);
        // Passerelle World → Me (4.4) : la carte n'est montrée que si le
        // destinataire a lui-même le droit de voir la publication.
        out.post = p && social.canViewPost(viewerId, p) ? views.post(p, viewerId) : { unavailable: true };
      }
      return out;
    },
  };
  return views;
}
