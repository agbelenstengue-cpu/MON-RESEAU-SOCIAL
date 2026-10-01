// Mode économie de données / MIC Lite (26.3) et compteur de consommation.
let enabled = false;
try {
  enabled = localStorage.getItem('mic.dataSaver') === '1';
} catch {
  /* ignore */
}

export const dataSaver = () => enabled;

export function setDataSaver(on) {
  enabled = !!on;
  try {
    localStorage.setItem('mic.dataSaver', enabled ? '1' : '0');
  } catch {
    /* ignore */
  }
  applyDataSaver();
}

// En mode économie : pas de polices web, images plus légères, pas de lecture
// automatique des vidéos (voir world.js et api.js).
export function applyDataSaver() {
  document.documentElement.dataset.datasaver = enabled ? 'on' : 'off';
  const fonts = document.getElementById('webfonts');
  if (fonts) fonts.disabled = enabled;
}

// Octets échangés pendant cette session, par catégorie (Settings → Storage & data).
export function networkUsage() {
  const out = { api: 0, media: 0, app: 0 };
  for (const e of performance.getEntriesByType('resource')) {
    const size = e.transferSize || e.encodedBodySize || 0;
    const path = new URL(e.name, location.href).pathname;
    if (path.startsWith('/api/')) out.api += size;
    else if (path.startsWith('/uploads/')) out.media += size;
    else out.app += size;
  }
  return out;
}

export function fmtBytes(n) {
  if (n < 1024) return `${n} o`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} Ko`;
  return `${(n / 1024 / 1024).toFixed(1)} Mo`;
}
