import express from 'express';
import http from 'node:http';
import path from 'node:path';
import fs from 'node:fs';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { openDatabase } from './db.js';
import { makeSocial } from './social.js';
import { makeViews } from './views.js';
import { createHub } from './realtime.js';
import accountRoutes from './routes/account.js';
import peopleRoutes from './routes/people.js';
import chatRoutes from './routes/chats.js';
import storyRoutes from './routes/stories.js';
import worldRoutes from './routes/world.js';
import callRoutes from './routes/calls.js';

const ROOT = path.dirname(path.dirname(fileURLToPath(import.meta.url)));

export class HttpError extends Error {
  constructor(status, code, message = code) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

export function createServer({
  dbFile = path.join(ROOT, 'data', 'mic.db'),
  uploadsDir = path.join(ROOT, 'data', 'uploads'),
  devOtp = process.env.NODE_ENV !== 'production',
} = {}) {
  const db = openDatabase(dbFile);
  const hub = createHub();
  const social = makeSocial(db);
  const views = makeViews(db, social, hub);
  fs.mkdirSync(uploadsDir, { recursive: true });

  const sessionUser = db.prepare(
    'SELECT u.* FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token = ?'
  );
  const authenticate = (token) => (token ? sessionUser.get(token) : undefined);

  const app = express();
  app.disable('x-powered-by');
  app.use(express.json({ limit: '16mb' }));
  app.use((req, res, next) => {
    res.set('X-Content-Type-Options', 'nosniff');
    res.set('Referrer-Policy', 'same-origin');
    next();
  });

  const requireAuth = (req, res, next) => {
    const header = req.get('authorization') || '';
    const user = authenticate(header.startsWith('Bearer ') ? header.slice(7) : null);
    if (!user) return next(new HttpError(401, 'unauthorized'));
    req.user = user;
    req.token = header.slice(7);
    next();
  };

  // Notifications d'activité (section 19) + push temps réel.
  const insertNotif = db.prepare(
    'INSERT INTO notifications (user_id, actor_id, type, ref_id, created_at) VALUES (?, ?, ?, ?, ?)'
  );
  const notify = (userId, actorId, type, refId = null) => {
    if (userId === actorId) return;
    if (social.isBlockedEither(userId, actorId)) return;
    insertNotif.run(userId, actorId, type, refId, Date.now());
    hub.send(userId, 'notification', { type });
  };

  // Téléversement des médias : data URL → fichier. Images (5 Mo) et audio (10 Mo).
  const MEDIA = {
    image: { types: { png: 'png', jpeg: 'jpg', webp: 'webp', gif: 'gif' }, max: 5 * 1024 * 1024 },
    audio: { types: { webm: 'webm', ogg: 'ogg', mp4: 'm4a', mpeg: 'mp3', wav: 'wav' }, max: 10 * 1024 * 1024 },
  };
  const saveMedia = (dataUrl, kind = 'image') => {
    if (dataUrl == null || dataUrl === '') return null;
    const m = /^data:(image|audio)\/([\w.+-]+)((?:;[\w-]+=[\w.+-]+)*);base64,([A-Za-z0-9+/=]+)$/.exec(String(dataUrl));
    const spec = MEDIA[kind];
    const ext = m && m[1] === kind && spec.types[m[2]];
    if (!ext) throw new HttpError(400, 'invalid_media');
    const buf = Buffer.from(m[4], 'base64');
    if (buf.length > spec.max) throw new HttpError(413, 'media_too_large');
    const name = `${crypto.randomBytes(16).toString('hex')}.${ext}`;
    fs.writeFileSync(path.join(uploadsDir, name), buf);
    return `/uploads/${name}`;
  };

  const ctx = { db, social, views, hub, notify, saveMedia, HttpError, devOtp, authenticate };

  const api = express.Router();
  accountRoutes(api, ctx, requireAuth);
  api.use(requireAuth);
  peopleRoutes(api, ctx);
  chatRoutes(api, ctx);
  callRoutes(api, ctx);
  storyRoutes(api, ctx);
  worldRoutes(api, ctx);
  api.use((req, res, next) => next(new HttpError(404, 'not_found')));

  app.use('/api', api);
  app.use('/uploads', express.static(uploadsDir, { maxAge: '7d', immutable: true }));
  app.use(express.static(path.join(ROOT, 'public')));
  app.get(/^\/(?!api|uploads|ws).*/, (req, res) => res.sendFile(path.join(ROOT, 'public', 'index.html')));

  // eslint-disable-next-line no-unused-vars
  app.use((err, req, res, next) => {
    if (err instanceof HttpError) return res.status(err.status).json({ error: err.code });
    if (err.type === 'entity.too.large') return res.status(413).json({ error: 'media_too_large' });
    if (err instanceof SyntaxError) return res.status(400).json({ error: 'bad_json' });
    console.error(err);
    res.status(500).json({ error: 'server_error' });
  });

  const server = http.createServer(app);
  hub.attach(server, authenticate);
  return { app, server, db, hub };
}
