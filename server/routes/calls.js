// Section 10 : appels audio et vidéo, individuels et de groupe.
// Le serveur ne relaie que la signalisation WebRTC (offres, réponses, candidats ICE) :
// le son et l'image circulent directement entre les appareils, chiffrés par DTLS-SRTP.
import { now } from '../social.js';

const RING_TIMEOUT = 40 * 1000;
const MAX_PARTICIPANTS = 32; // 10.1

export default function callRoutes(api, ctx) {
  const { db, social, views, hub } = ctx;
  const q = {
    conv: db.prepare('SELECT * FROM conversations WHERE id = ?'),
    member: db.prepare('SELECT * FROM conversation_members WHERE conversation_id = ? AND user_id = ?'),
    members: db.prepare('SELECT * FROM conversation_members WHERE conversation_id = ?'),
    insertCall: db.prepare('INSERT INTO calls (conversation_id, caller_id, type, status, created_at) VALUES (?, ?, ?, ?, ?)'),
    addParticipant: db.prepare('INSERT OR IGNORE INTO call_participants (call_id, user_id, joined_at) VALUES (?, ?, ?)'),
    joined: db.prepare('UPDATE call_participants SET joined_at = COALESCE(joined_at, ?), left_at = NULL WHERE call_id = ? AND user_id = ?'),
    left: db.prepare('UPDATE call_participants SET left_at = ? WHERE call_id = ? AND user_id = ? AND joined_at IS NOT NULL'),
    answered: db.prepare("UPDATE calls SET status = 'ongoing', answered_at = COALESCE(answered_at, ?) WHERE id = ?"),
    end: db.prepare('UPDATE calls SET status = ?, ended_at = ? WHERE id = ?'),
    call: db.prepare('SELECT * FROM calls WHERE id = ?'),
    history: db.prepare(`SELECT c.*, p.joined_at AS my_joined_at FROM call_participants p JOIN calls c ON c.id = p.call_id
      WHERE p.user_id = ? AND p.hidden = 0 AND c.status IN ('ended', 'missed') ORDER BY c.created_at DESC LIMIT 100`),
    participants: db.prepare('SELECT user_id, joined_at FROM call_participants WHERE call_id = ?'),
    hide: db.prepare('UPDATE call_participants SET hidden = 1 WHERE call_id = ? AND user_id = ?'),
    hideAll: db.prepare('UPDATE call_participants SET hidden = 1 WHERE user_id = ?'),
  };

  // Appels en cours, en mémoire : id -> { id, convId, type, callerId, joined:Set, ringing:Set, timer }
  const live = new Map();
  const userCall = (userId) => [...live.values()].find((c) => c.joined.has(userId));

  const publicCall = (call) => ({
    id: call.id,
    conversationId: call.convId,
    type: call.type,
    callerId: call.callerId,
    participants: [...call.joined],
    ringing: [...call.ringing],
  });

  // Tous les membres de la discussion voient le bandeau « Rejoindre l'appel » (10.2).
  const broadcast = (call, ended = false) => {
    const ids = q.members.all(call.convId).map((m) => m.user_id);
    hub.sendMany(ids, 'call:update', { conversationId: call.convId, call: ended ? null : publicCall(call) });
  };

  ctx.activeCallFor = (convId, viewerId) => {
    const call = [...live.values()].find((c) => c.convId === convId);
    if (!call || !q.member.get(convId, viewerId)) return null;
    return publicCall(call);
  };

  // Droit d'appeler (10.8) : jamais un compte bloqué ; en individuel, seulement entre amis
  // (réglage par défaut « My contacts »).
  const canRing = (callerId, calleeId, conv) => {
    if (social.isBlockedEither(callerId, calleeId)) return false;
    // Réglage « Who can call me » (20.2), « friends » par défaut.
    if (conv.type === 'direct') return social.allowsFor(calleeId, 'whoCanCall', callerId);
    return true;
  };

  const finish = (call) => {
    if (!live.has(call.id)) return;
    live.delete(call.id);
    clearTimeout(call.timer);
    const row = q.call.get(call.id);
    const status = row.answered_at ? 'ended' : 'missed';
    const t = now();
    q.end.run(status, t, call.id);
    for (const uid of call.joined) q.left.run(t, call.id, uid);
    hub.sendMany([...call.joined, ...call.ringing], 'call:ended', { callId: call.id });
    broadcast(call, true);
    // Trace dans la discussion, avec « Rappeler » pour un appel manqué (10.3).
    ctx.postEventMessage(call.convId, call.callerId, 'call', {
      callId: call.id,
      type: call.type,
      status,
      duration: row.answered_at ? t - row.answered_at : 0,
    });
  };

  const leave = (call, userId) => {
    call.joined.delete(userId);
    call.ringing.delete(userId);
    q.left.run(now(), call.id, userId);
    hub.sendMany([...call.joined], 'call:peer-left', { callId: call.id, userId });
    const conv = q.conv.get(call.convId);
    // En individuel, l'appel s'arrête dès qu'une personne raccroche ou refuse.
    if (conv?.type === 'direct' || call.joined.size === 0 || (call.joined.size === 1 && call.ringing.size === 0)) finish(call);
    else broadcast(call);
  };

  const start = (userId, { conversationId, callType }) => {
    const conv = q.conv.get(Number(conversationId));
    const me = conv && q.member.get(conv.id, userId);
    if (!me || me.status !== 'active') return hub.send(userId, 'call:error', { error: 'conversation_not_found' });
    if (userCall(userId)) return hub.send(userId, 'call:error', { error: 'already_in_call' });
    const existing = [...live.values()].find((c) => c.convId === conv.id);
    if (existing) return join(userId, { callId: existing.id }); // un appel de groupe est déjà en cours
    const others = q.members.all(conv.id).filter((m) => m.user_id !== userId && m.status === 'active');
    if (others.length + 1 > MAX_PARTICIPANTS) return hub.send(userId, 'call:error', { error: 'too_many_participants' });
    const allowed = others.filter((m) => canRing(userId, m.user_id, conv)).map((m) => m.user_id);
    if (!allowed.length) return hub.send(userId, 'call:error', { error: 'cannot_call' });
    const kind = callType === 'video' ? 'video' : 'audio';
    const id = Number(q.insertCall.run(conv.id, userId, kind, 'ringing', now()).lastInsertRowid);
    q.addParticipant.run(id, userId, now());
    const call = { id, convId: conv.id, type: kind, callerId: userId, joined: new Set([userId]), ringing: new Set() };
    live.set(id, call);
    const busy = [];
    for (const uid of allowed) {
      q.addParticipant.run(id, uid, null);
      if (userCall(uid)) busy.push(uid);
      else call.ringing.add(uid);
    }
    hub.send(userId, 'call:started', { call: publicCall(call), busy });
    for (const uid of call.ringing) {
      hub.send(uid, 'call:incoming', {
        call: publicCall(call),
        caller: views.userCard(userId, uid),
        conversation: { id: conv.id, type: conv.type, title: conv.title },
      });
    }
    if (!call.ringing.size) {
      hub.send(userId, 'call:busy', { callId: id });
      return finish(call);
    }
    // Sans réponse : les sonneries s'arrêtent et l'appel est noté manqué.
    call.timer = setTimeout(() => {
      for (const uid of call.ringing) hub.send(uid, 'call:ended', { callId: call.id });
      call.ringing.clear();
      if (call.joined.size <= 1) finish(call);
      else broadcast(call);
    }, RING_TIMEOUT);
    broadcast(call);
  };

  const join = (userId, { callId }) => {
    const call = live.get(Number(callId));
    if (!call) return hub.send(userId, 'call:error', { error: 'call_ended' });
    const me = q.member.get(call.convId, userId);
    if (!me || me.status !== 'active') return hub.send(userId, 'call:error', { error: 'conversation_not_found' });
    if (call.joined.has(userId)) return;
    const current = userCall(userId);
    if (current) leave(current, userId);
    if (call.joined.size >= MAX_PARTICIPANTS) return hub.send(userId, 'call:error', { error: 'too_many_participants' });
    if ([...call.joined].some((uid) => social.isBlockedEither(uid, userId)) && q.conv.get(call.convId).type === 'direct') {
      return hub.send(userId, 'call:error', { error: 'cannot_call' });
    }
    const peers = [...call.joined];
    call.ringing.delete(userId);
    call.joined.add(userId);
    q.addParticipant.run(call.id, userId, now());
    q.joined.run(now(), call.id, userId);
    q.answered.run(now(), call.id);
    // Le nouvel arrivant envoie une offre à chaque participant déjà présent (maillage).
    hub.send(userId, 'call:joined', { call: publicCall(call), peers: peers.map((uid) => views.userCard(uid, userId)) });
    for (const uid of peers) hub.send(uid, 'call:peer-joined', { callId: call.id, user: views.userCard(userId, uid) });
    // Les autres appareils de la personne arrêtent de sonner.
    hub.send(userId, 'call:answered-elsewhere', { callId: call.id });
    broadcast(call);
  };

  const decline = (userId, { callId }) => {
    const call = live.get(Number(callId));
    if (!call || !call.ringing.has(userId)) return;
    call.ringing.delete(userId);
    hub.sendMany([...call.joined], 'call:declined', { callId: call.id, userId });
    const conv = q.conv.get(call.convId);
    if (conv.type === 'direct' || (call.ringing.size === 0 && call.joined.size <= 1)) finish(call);
    else broadcast(call);
  };

  hub.on('message', (userId, msg) => {
    const type = msg?.type;
    if (typeof type !== 'string' || !type.startsWith('call:')) return;
    switch (type) {
      case 'call:start':
        return start(userId, msg);
      case 'call:join':
        return join(userId, msg);
      case 'call:decline':
        return decline(userId, msg);
      case 'call:leave': {
        const call = live.get(Number(msg.callId));
        if (call?.joined.has(userId)) leave(call, userId);
        return;
      }
      case 'call:signal': {
        // Offre / réponse / candidat ICE vers un participant précis du même appel.
        const call = live.get(Number(msg.callId));
        const to = Number(msg.to);
        if (!call?.joined.has(userId) || !call.joined.has(to) || to === userId) return;
        const data = msg.data;
        if (!data || typeof data !== 'object' || JSON.stringify(data).length > 64 * 1024) return;
        return hub.send(to, 'call:signal', { callId: call.id, from: userId, data });
      }
      case 'call:media': {
        const call = live.get(Number(msg.callId));
        if (!call?.joined.has(userId)) return;
        return hub.sendMany(
          [...call.joined].filter((id) => id !== userId),
          'call:peer-media',
          { callId: call.id, userId, audio: !!msg.audio, video: !!msg.video }
        );
      }
      case 'call:reaction': {
        const call = live.get(Number(msg.callId));
        const emoji = String(msg.emoji ?? '');
        if (!call?.joined.has(userId) || !emoji || [...emoji].length > 4) return;
        return hub.sendMany([...call.joined], 'call:reaction', { callId: call.id, userId, emoji });
      }
    }
  });

  // Fermer la dernière connexion revient à raccrocher.
  hub.on('disconnect', (userId) => {
    for (const call of [...live.values()]) {
      if (call.joined.has(userId)) leave(call, userId);
      else if (call.ringing.has(userId)) decline(userId, { callId: call.id });
    }
  });

  // Serveurs ICE : STUN public par défaut ; un serveur TURN se configure par MIC_ICE_SERVERS (JSON).
  let iceServers = [{ urls: 'stun:stun.l.google.com:19302' }];
  try {
    if (process.env.MIC_ICE_SERVERS) iceServers = JSON.parse(process.env.MIC_ICE_SERVERS);
  } catch {
    console.warn('MIC_ICE_SERVERS invalide : STUN par défaut utilisé.');
  }
  api.get('/calls/config', (req, res) => res.json({ iceServers }));

  // Historique (10.7) : entrant ↙ / sortant ↗ / manqué.
  api.get('/calls', (req, res) => {
    const me = req.user.id;
    const rows = q.history.all(me).flatMap((c) => {
      const conv = q.conv.get(c.conversation_id);
      if (!conv) return [];
      const parts = q.participants.all(c.id);
      const outgoing = c.caller_id === me;
      const others = q.members.all(conv.id).filter((m) => m.user_id !== me);
      return [
        {
          id: c.id,
          conversationId: conv.id,
          type: c.type,
          direction: outgoing ? 'outgoing' : 'incoming',
          missed: !outgoing && !c.my_joined_at,
          answered: !!c.answered_at,
          duration: c.answered_at && c.ended_at ? c.ended_at - c.answered_at : 0,
          createdAt: c.created_at,
          participants: parts.filter((p) => p.joined_at).length,
          title: conv.type === 'group' ? conv.title : null,
          peer: conv.type === 'direct' && others[0] ? views.userCard(others[0].user_id, me) : null,
        },
      ];
    });
    res.json(rows);
  });

  api.delete('/calls/:id', (req, res) => {
    if (req.params.id === 'all') q.hideAll.run(req.user.id);
    else q.hide.run(Number(req.params.id), req.user.id);
    res.json({ ok: true });
  });

}
