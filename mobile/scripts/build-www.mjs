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

const size = fs.statSync(path.join(www, 'js', 'mic-local.js')).size;
console.log(`www/ prêt (serveur local : ${(size / 1024).toFixed(0)} Ko)`);
