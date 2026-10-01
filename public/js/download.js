// Enregistrer un fichier (mes données, événement, clip). Dans le navigateur :
// téléchargement classique. Dans l'application Android, la WebView ne sait pas
// télécharger : le fichier est écrit dans l'application puis le partage Android
// s'ouvre (Fichiers, Drive, WhatsApp…).
const EXT = { 'video/webm': 'webm', 'video/mp4': 'mp4', 'video/quicktime': 'mov', 'application/json': 'json', 'text/html': 'html', 'text/calendar': 'ics' };

const toBase64 = (blob) =>
  new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(String(r.result).split(',')[1]);
    r.onerror = () => reject(r.error);
    r.readAsDataURL(blob);
  });

export async function saveFile(source, name) {
  const cap = window.Capacitor;
  if (cap?.isNativePlatform?.() && cap.nativePromise) {
    const blob = source instanceof Blob ? source : await (await fetch(source)).blob();
    const type = (blob.type || '').split(';')[0];
    let file = String(name).replace(/[^\w.-]+/g, '_');
    if (!/\.\w{2,5}$/.test(file) && EXT[type]) file = `${file}.${EXT[type]}`;
    const { uri } = await cap.nativePromise('Filesystem', 'writeFile', { path: file, data: await toBase64(blob), directory: 'CACHE' });
    try {
      await cap.nativePromise('Share', 'share', { title: file, files: [uri], dialogTitle: file });
    } catch (err) {
      if (!/cancel/i.test(String(err?.message))) throw err;
    }
    return;
  }
  const url = source instanceof Blob ? URL.createObjectURL(source) : source;
  const a = document.createElement('a');
  a.href = url;
  a.download = name;
  a.click();
  if (source instanceof Blob) setTimeout(() => URL.revokeObjectURL(url), 5000);
}
