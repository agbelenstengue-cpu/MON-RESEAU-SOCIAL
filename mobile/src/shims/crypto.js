// node:crypto : les seules fonctions utilisées par le serveur MIC.
import { Buffer } from 'buffer';

function randomBytes(n) {
  const b = new Uint8Array(n);
  crypto.getRandomValues(b);
  return Buffer.from(b);
}

function randomInt(min, max) {
  if (max === undefined) [min, max] = [0, min];
  const range = max - min;
  const limit = Math.floor(0x100000000 / range) * range;
  const u = new Uint32Array(1);
  do crypto.getRandomValues(u);
  while (u[0] >= limit);
  return min + (u[0] % range);
}

function timingSafeEqual(a, b) {
  if (a.length !== b.length) throw new RangeError('Input buffers must have the same byte length');
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

export { randomBytes, randomInt, timingSafeEqual };
export default { randomBytes, randomInt, timingSafeEqual };
