// Données de démonstration : `npm run seed`, puis connexion avec l'un des numéros affichés.
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { openDatabase } from './db.js';
import { seedDemo, DEMO_PEOPLE } from './demo.js';

const ROOT = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const db = openDatabase(process.env.MIC_DB || path.join(ROOT, 'data', 'mic.db'));

if (!seedDemo(db)) {
  console.log('Les comptes de démonstration existent déjà. Supprimez data/mic.db pour repartir de zéro.');
  process.exit(0);
}

console.log('Comptes de démonstration créés. Connectez-vous avec l’un de ces numéros :');
for (const [phone, username, name] of DEMO_PEOPLE) console.log(`  ${phone}  @${username}  (${name})${username === 'angele' ? ' — modératrice' : ''}`);
console.log('Le code de vérification s’affiche à l’écran en mode développement.');
