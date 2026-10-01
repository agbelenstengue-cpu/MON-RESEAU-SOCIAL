// Prépare www/ pour l'application Android : l'interface MIC (public/) et le
// serveur MIC (server/) regroupé pour tourner dans la WebView (src/backend.js).
import { build } from 'esbuild';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const mobile = path.dirname(here);
const root = path.dirname(mobile);
const www = path.join(mobile, 'www');
const shim = (name) => path.join(mobile, 'src', 'shims', name);

fs.rmSync(www, { recursive: true, force: true });
fs.cpSync(path.join(root, 'public'), www, { recursive: true });

await build({
  entryPoints: [path.join(mobile, 'src', 'backend.js')],
  outfile: path.join(www, 'js', 'mic-local.js'),
  bundle: true,
  format: 'esm',
  platform: 'browser',
  target: ['chrome90'],
  minify: true,
  sourcemap: false,
  legalComments: 'none',
  loader: { '.wasm': 'binary' },
  inject: [shim('globals.js')],
  alias: {
    'node:sqlite': shim('sqlite.js'),
    'node:crypto': shim('crypto.js'),
    'node:fs': shim('fs.js'),
    'node:path': shim('path.js'),
    'node:url': shim('url.js'),
    'node:http': shim('http.js'),
    express: shim('express.js'),
    ws: shim('ws.js'),
  },
  nodePaths: [path.join(mobile, 'node_modules')],
  logLevel: 'warning',
});

// Service worker de l'application (médias) à la place de celui du web.
fs.copyFileSync(path.join(mobile, 'src', 'sw.js'), path.join(www, 'sw.js'));

// Le serveur local se charge avant l'interface.
const indexFile = path.join(www, 'index.html');
const html = fs.readFileSync(indexFile, 'utf8');
const tag = '<script type="module" src="/js/app.js"></script>';
if (!html.includes(tag)) throw new Error('index.html : balise de app.js introuvable');
fs.writeFileSync(indexFile, html.replace(tag, `<script type="module" src="/js/mic-local.js"></script>\n    ${tag}`));

// Serveur en ligne (mic.config.json) : l'application ouvre MIC en ligne ; sinon le
// serveur local ci-dessus est utilisé. capacitor.config.json est écrit ici.
let server = '';
try {
  server = JSON.parse(fs.readFileSync(path.join(root, 'mic.config.json'), 'utf8')).server || '';
} catch {
  /* pas de configuration : MIC autonome */
}
const online = /^https?:\/\//.test(server) ? new URL(server).origin : null;
const capConfig = {
  appId: 'com.mic.interconnected',
  appName: 'MIC',
  webDir: 'www',
  ...(online ? { server: { url: online, errorPath: 'offline.html', cleartext: online.startsWith('http:') } } : {}),
  plugins: { SystemBars: { insetsHandling: 'native', initialViewportFitValueHint: 'cover' } },
};
fs.writeFileSync(path.join(mobile, 'capacitor.config.json'), JSON.stringify(capConfig, null, 2) + '\n');
if (online) {
  fs.writeFileSync(
    path.join(www, 'offline.html'),
    `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
<title>MIC</title>
<style>
  :root { color-scheme: light dark; --bg: #faf7f2; --text: #1c1410; --muted: #6f625a; --accent: #3b2418; }
  @media (prefers-color-scheme: dark) { :root { --bg: #14100d; --text: #f3ece4; --muted: #b3a597; --accent: #c89a77; } }
  body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: var(--bg); color: var(--text);
    font: 16px/1.5 system-ui, sans-serif; text-align: center; padding: 24px; box-sizing: border-box; }
  img { width: 96px; height: 96px; }
  h1 { font-family: Georgia, serif; margin: 12px 0 4px; }
  p { color: var(--muted); margin: 0 0 24px; }
  button { font: inherit; font-weight: 600; border: 0; border-radius: 999px; padding: 12px 28px; background: var(--accent); color: var(--bg); }
</style>
</head>
<body>
<main>
  <img src="/img/logo.svg" alt="" />
  <h1>Pas de connexion</h1>
  <p>MIC a besoin d’Internet pour vous relier aux autres.<br />Vérifiez le Wi-Fi ou les données mobiles.</p>
  <button onclick="location.href='${online}/'">Réessayer</button>
</main>
</body>
</html>
`
  );
}

const size = fs.statSync(path.join(www, 'js', 'mic-local.js')).size;
console.log(`www/ prêt (${online ? `MIC en ligne : ${online}` : 'MIC autonome'} ; serveur local : ${(size / 1024).toFixed(0)} Ko)`);
