// node:fs : les fichiers téléversés (photos, vocaux, vidéos) sont rangés dans le
// stockage de l'application (Cache Storage) et servis par le service worker.
import { mediaStore } from '../media-store.js';

const name = (p) => String(p).split('/').pop();

const fs = {
  mkdirSync() {},
  existsSync: () => false,
  writeFileSync(path, data) {
    mediaStore.put(name(path), data);
  },
  rm(path, opts, cb) {
    mediaStore.remove(name(path));
    (typeof opts === 'function' ? opts : cb)?.(null);
  },
};

export default fs;
export const { mkdirSync, existsSync, writeFileSync, rm } = fs;
