import { createServer } from './app.js';

const port = Number(process.env.PORT) || 3000;
const host = process.env.HOST || '0.0.0.0';
const { server } = createServer({ dbFile: process.env.MIC_DB || undefined });

server.listen(port, host, () => {
  console.log(`MIC — Monde Interconnecté : http://localhost:${port}`);
  if (process.env.NODE_ENV !== 'production') {
    console.log('Mode développement : les codes de vérification (OTP) sont affichés ici et dans l’interface.');
  }
});
