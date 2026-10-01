// Données de démonstration : `npm run seed`, puis connexion avec l'un des numéros affichés.
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { openDatabase, tx } from './db.js';
import { extractHashtags } from './social.js';
import { CHANNEL_SCHEMA } from './routes/channels.js';

const ROOT = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const db = openDatabase(process.env.MIC_DB || path.join(ROOT, 'data', 'mic.db'));
db.exec(CHANNEL_SCHEMA);
const now = Date.now();
const H = 3600_000;

const PEOPLE = [
  ['+237670000001', 'angele', 'Angèle Nkoa', '1994-03-12', 1, 'Angèle N.', 'Photographe à Douala · lumière, rues et visages.'],
  ['+237670000002', 'paul', 'Paul Mbarga', '1990-07-02', 1, null, 'Cuisine camerounaise et voyages.'],
  ['+237670000003', 'sophie', 'Sophie Ekane', '1998-11-23', 0, null, ''],
  ['+237670000004', 'kofi', 'Kofi Mensah', '1992-01-30', 1, 'Kofi Creates', 'Musicien · Accra ↔ Yaoundé'],
  ['+33600000005', 'lea', 'Léa Martin', '1996-05-08', 1, null, 'Diaspora · Paris'],
];

const existing = db.prepare('SELECT COUNT(*) AS n FROM users WHERE username IN (?, ?, ?, ?, ?)').get(...PEOPLE.map((p) => p[1])).n;
if (existing) {
  console.log('Les comptes de démonstration existent déjà. Supprimez data/mic.db pour repartir de zéro.');
  process.exit(0);
}

tx(db, () => {
  const ids = {};
  const insertUser = db.prepare(`INSERT INTO users (phone, username, display_name, birth_date, world_enabled, public_name, bio, created_at, last_seen, first_public_done)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`);
  for (const [phone, username, name, birth, world, publicName, bio] of PEOPLE) {
    ids[username] = Number(insertUser.run(phone, username, name, birth, world, publicName, bio, now - 30 * 24 * H, now - 2 * H, world).lastInsertRowid);
  }
  // Compte de démonstration modérateur (console de modération).
  db.prepare("UPDATE users SET role = 'moderator' WHERE id = ?").run(ids.angele);
  const friend = db.prepare('INSERT INTO friendships (user_id, friend_id, created_at) VALUES (?, ?, ?)');
  const befriend = (a, b) => {
    friend.run(ids[a], ids[b], now);
    friend.run(ids[b], ids[a], now);
  };
  befriend('angele', 'paul');
  befriend('angele', 'sophie');
  befriend('paul', 'sophie');
  befriend('angele', 'kofi');
  db.prepare('INSERT INTO close_friends (owner_id, friend_id) VALUES (?, ?)').run(ids.angele, ids.sophie);
  db.prepare('INSERT INTO friend_requests (from_id, to_id, created_at) VALUES (?, ?, ?)').run(ids.lea, ids.angele, now - H);

  const follow = db.prepare("INSERT INTO follows (follower_id, followee_id, status, created_at) VALUES (?, ?, 'active', ?)");
  for (const [a, b] of [['paul', 'angele'], ['sophie', 'angele'], ['lea', 'angele'], ['angele', 'kofi'], ['paul', 'kofi'], ['lea', 'kofi'], ['kofi', 'angele']]) {
    follow.run(ids[a], ids[b], now);
  }

  const insertPost = db.prepare('INSERT INTO posts (author_id, body, audience, created_at) VALUES (?, ?, ?, ?)');
  const tag = db.prepare('INSERT OR IGNORE INTO post_hashtags (post_id, tag) VALUES (?, ?)');
  const like = db.prepare('INSERT OR IGNORE INTO likes (post_id, user_id, created_at) VALUES (?, ?, ?)');
  const comment = db.prepare('INSERT INTO comments (post_id, author_id, body, created_at) VALUES (?, ?, ?, ?)');
  const posts = [
    ['angele', 'Coucher de soleil sur le Wouri ce soir. Douala sait se faire belle 🌅 #Douala #photographie', 3, ['paul', 'sophie', 'kofi', 'lea'], [['kofi', 'Magnifique lumière !']]],
    ['kofi', 'Nouveau son en préparation, entre makossa et highlife. Qui veut une avant-première ? #musique #makossa', 6, ['angele', 'paul'], [['paul', 'Moi !! 🎶']]],
    ['paul', 'Recette du jour : ndolé aux crevettes. La patience est le secret. #cuisine #ndole', 20, ['angele'], []],
    ['lea', 'Paris → Yaoundé dans 10 jours. Vos adresses incontournables ? #voyage #Cameroun', 30, ['kofi'], [['angele', 'Le marché Mokolo, sans hésiter.']]],
    ['angele', 'Bienvenue sur MIC : une seule identité, deux univers. Me pour les proches, World pour le monde. #MIC', 48, ['lea', 'kofi'], []],
  ];
  for (const [author, body, ago, likers, comments] of posts) {
    const pid = Number(insertPost.run(ids[author], body, 'everyone', now - ago * H).lastInsertRowid);
    for (const t of extractHashtags(body)) tag.run(pid, t);
    for (const l of likers) like.run(pid, ids[l], now - ago * H + H);
    for (const [who, text] of comments) comment.run(pid, ids[who], text, now - ago * H + 2 * H);
  }

  const story = db.prepare('INSERT INTO stories (author_id, audience, kind, body, bg, created_at, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?)');
  story.run(ids.paul, 'friends', 'text', 'Dimanche en famille à Kribi 🌊', 'emerald', now - 2 * H, now + 22 * H);
  story.run(ids.sophie, 'friends', 'text', 'Examens terminés !!! 🎉', 'cognac', now - 5 * H, now + 19 * H);
  story.run(ids.kofi, 'world', 'text', 'Studio ce soir. Live bientôt sur MIC ✨', 'ebony', now - H, now + 23 * H);

  // Canal de démonstration (11.8).
  const ch = Number(db.prepare("INSERT INTO channels (owner_id, handle, name, description, visibility, invite_code, created_at) VALUES (?, 'mic.officiel', 'MIC Officiel', 'Les nouveautés de MIC — Monde Interconnecté.', 'public', 'demo', ?)").run(ids.angele, now - 10 * 24 * H).lastInsertRowid);
  db.prepare('INSERT INTO channel_admins (channel_id, user_id) VALUES (?, ?)').run(ch, ids.angele);
  for (const u of ['paul', 'kofi', 'lea']) db.prepare('INSERT INTO channel_subs (channel_id, user_id, created_at) VALUES (?, ?, ?)').run(ch, ids[u], now);
  for (const [body, ago] of [['Bienvenue sur le canal officiel de MIC 👋', 30], ['Nouveau : les messages vocaux et les appels vidéo sont disponibles.', 5]]) {
    db.prepare('INSERT INTO channel_posts (channel_id, author_id, body, created_at) VALUES (?, ?, ?, ?)').run(ch, ids.angele, body, now - ago * H);
  }

  const conv = db.prepare('INSERT INTO conversations (type, title, created_by, created_at) VALUES (?, ?, ?, ?)');
  const member = db.prepare("INSERT INTO conversation_members (conversation_id, user_id, role, status, joined_at, last_read_id, last_delivered_id) VALUES (?, ?, ?, 'active', ?, ?, ?)");
  const msg = db.prepare('INSERT INTO messages (conversation_id, sender_id, kind, body, created_at) VALUES (?, ?, ?, ?, ?)');

  const c1 = Number(conv.run('direct', null, ids.paul, now - 5 * H).lastInsertRowid);
  const m1 = [
    ['paul', 'Salut Angèle ! Tu viens dimanche ?', 5],
    ['angele', 'Oui bien sûr, j’apporte les plantains 😄', 4.8],
    ['paul', 'Parfait. Sophie vient aussi.', 1],
  ].map(([who, body, ago]) => Number(msg.run(c1, ids[who], 'text', body, now - ago * H).lastInsertRowid));
  member.run(c1, ids.paul, 'member', now, m1[2], m1[2]);
  member.run(c1, ids.angele, 'member', now, m1[1], m1[2]);

  const g = Number(conv.run('group', 'Famille ❤️', ids.angele, now - 24 * H).lastInsertRowid);
  msg.run(g, ids.angele, 'system', 'group_created', now - 24 * H);
  const m2 = [
    ['sophie', 'Bonjour la famille !', 3],
    ['paul', 'Bonjour ma sœur 🙏', 2.5],
  ].map(([who, body, ago]) => Number(msg.run(g, ids[who], 'text', body, now - ago * H).lastInsertRowid));
  member.run(g, ids.angele, 'admin', now, 0, m2[1]);
  member.run(g, ids.paul, 'member', now, m2[1], m2[1]);
  member.run(g, ids.sophie, 'member', now, m2[1], m2[1]);
});

console.log('Comptes de démonstration créés. Connectez-vous avec l’un de ces numéros :');
for (const [phone, username, name] of PEOPLE) console.log(`  ${phone}  @${username}  (${name})${username === 'angele' ? ' — modératrice' : ''}`);
console.log('Le code de vérification s’affiche à l’écran en mode développement.');
