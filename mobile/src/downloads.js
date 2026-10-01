// Téléchargements dans l'application Android (« Télécharger mes données »,
// événement vers l'agenda, clip) : la WebView ne sait pas enregistrer un fichier,
// on l'écrit dans l'application puis on ouvre le partage Android (Fichiers,
// Drive, WhatsApp…).
import { Capacitor } from '@capacitor/core';
import { Filesystem, Directory } from '@capacitor/filesystem';
import { Share } from '@capacitor/share';

const EXT = { 'video/webm': 'webm', 'video/mp4': 'mp4', 'video/quicktime': 'mov', 'application/json': 'json', 'text/html': 'html', 'text/calendar': 'ics' };

const toBase64 = (blob) =>
  new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(String(r.result).split(',')[1]);
    r.onerror = () => reject(r.error);
    r.readAsDataURL(blob);
  });

async function saveAndShare(href, name) {
  const blob = await (await fetch(href)).blob();
  const type = (blob.type || '').split(';')[0];
  if (!/\.\w{2,5}$/.test(name) && EXT[type]) name = `${name}.${EXT[type]}`;
  const { uri } = await Filesystem.writeFile({ path: name, data: await toBase64(blob), directory: Directory.Cache });
  await Share.share({ title: name, files: [uri], dialogTitle: name });
}

export function installDownloads() {
  if (!Capacitor.isNativePlatform()) return;
  const click = HTMLAnchorElement.prototype.click;
  HTMLAnchorElement.prototype.click = function () {
    if (!this.hasAttribute('download') || !this.href) return click.call(this);
    const name = (this.getAttribute('download') || this.href.split('/').pop() || 'mic').replace(/[^\w.-]+/g, '_');
    saveAndShare(this.href, name).catch((err) => {
      if (!/cancel/i.test(String(err?.message))) console.error('[MIC] téléchargement', err);
    });
  };
}
