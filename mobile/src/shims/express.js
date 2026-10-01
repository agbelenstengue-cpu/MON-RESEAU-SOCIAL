// Sous-ensemble d'Express utilisé par le serveur MIC, exécuté dans la WebView.
// Les requêtes /api arrivent par dispatch() (fetch intercepté dans backend.js).

function compile(path, end) {
  if (path instanceof RegExp) return { re: path, keys: [] };
  const keys = [];
  const src = path
    .replace(/\/$/, '')
    .replace(/[.+*?^${}()|[\]\\]/g, '\\$&')
    .replace(/:(\w+)/g, (_, k) => {
      keys.push(k);
      return '([^/]+)';
    });
  return { re: new RegExp(`^${src}${end ? '/?$' : '(?=/|$)'}`, 'i'), keys };
}

function createRouter() {
  const stack = [];
  const router = function (req, res, next) {
    router.handle(req, res, next);
  };
  router.use = (...args) => {
    const path = typeof args[0] === 'string' ? args.shift() : '/';
    for (const fn of args.flat()) stack.push({ method: null, ...compile(path === '/' ? '' : path, false), mount: path !== '/', fn });
    return router;
  };
  for (const method of ['get', 'post', 'put', 'patch', 'delete']) {
    router[method] = (path, ...fns) => {
      for (const fn of fns.flat()) stack.push({ method: method.toUpperCase(), ...compile(path, true), fn });
      return router;
    };
  }
  router.handle = (req, res, done) => {
    let i = 0;
    const basePath = req.path;
    const baseParams = req.params;
    const next = (err) => {
      req.path = basePath;
      req.params = baseParams;
      while (i < stack.length) {
        const layer = stack[i++];
        if (layer.method && layer.method !== req.method) continue;
        const m = layer.re.exec(basePath);
        if (!m) continue;
        const isErrorHandler = layer.fn.length === 4;
        if (err ? !isErrorHandler : isErrorHandler) continue;
        const params = { ...baseParams };
        layer.keys.forEach((k, j) => (params[k] = decodeURIComponent(m[j + 1])));
        req.params = params;
        if (layer.mount) req.path = basePath.slice(m[0].length) || '/';
        try {
          if (err) layer.fn(err, req, res, next);
          else layer.fn(req, res, next);
        } catch (e) {
          next(e);
        }
        return;
      }
      done(err);
    };
    next();
  };
  return router;
}

function createResponse(resolve) {
  const res = {
    statusCode: 200,
    headers: {},
    finished: false,
    status(code) {
      res.statusCode = code;
      return res;
    },
    set(name, value) {
      res.headers[name.toLowerCase()] = String(value);
      return res;
    },
    json(data) {
      if (!res.headers['content-type']) res.set('Content-Type', 'application/json; charset=utf-8');
      return res.send(JSON.stringify(data));
    },
    send(body) {
      if (res.finished) return res;
      res.finished = true;
      if (body !== undefined && typeof body !== 'string' && !(body instanceof Uint8Array)) return res.json(body);
      if (!res.headers['content-type']) res.set('Content-Type', 'text/html; charset=utf-8');
      resolve({ status: res.statusCode, headers: res.headers, body: body ?? '' });
      return res;
    },
    sendFile() {
      res.status(404).send('');
    },
  };
  return res;
}

export default function express() {
  const router = createRouter();
  const app = function (req, res, next) {
    router.handle(req, res, next);
  };
  Object.assign(app, router);
  app.disable = () => app;
  // Traite une requête et renvoie { status, headers, body }.
  app.dispatch = ({ method, url, headers = {}, body }) =>
    new Promise((resolve) => {
      const u = new URL(url, 'http://localhost');
      const lower = Object.fromEntries(Object.entries(headers).map(([k, v]) => [k.toLowerCase(), v]));
      const req = {
        method: method.toUpperCase(),
        url: u.pathname + u.search,
        path: u.pathname,
        query: Object.fromEntries(u.searchParams),
        params: {},
        headers: lower,
        body,
        get: (name) => lower[name.toLowerCase()],
      };
      const res = createResponse(resolve);
      router.handle(req, res, (err) => {
        if (res.finished) return;
        if (err) {
          console.error(err);
          res.status(500).json({ error: 'server_error' });
        } else res.status(404).json({ error: 'not_found' });
      });
    });
  return app;
}

express.Router = createRouter;
const passthrough = () => (req, res, next) => next();
express.json = passthrough;
express.raw = passthrough;
express.static = passthrough;
