// Globals Node attendus par le serveur MIC (injectés par esbuild dans le bundle).
import { Buffer } from 'buffer';

export { Buffer };

export const process = {
  env: { NODE_ENV: 'development' },
  platform: 'android',
  nextTick: (fn, ...args) => queueMicrotask(() => fn(...args)),
};

// Les minuteurs Node renvoient un objet doté de unref().
class Timer {
  constructor(id) {
    this.id = id;
  }
  unref() {
    return this;
  }
  ref() {
    return this;
  }
  [Symbol.toPrimitive]() {
    return this.id;
  }
}
const native = {
  setTimeout: globalThis.setTimeout.bind(globalThis),
  setInterval: globalThis.setInterval.bind(globalThis),
  clearTimeout: globalThis.clearTimeout.bind(globalThis),
  clearInterval: globalThis.clearInterval.bind(globalThis),
};
const idOf = (t) => (t instanceof Timer ? t.id : t);
const _setTimeout = (fn, ms, ...a) => new Timer(native.setTimeout(fn, ms, ...a));
const _setInterval = (fn, ms, ...a) => new Timer(native.setInterval(fn, ms, ...a));
const _clearTimeout = (t) => native.clearTimeout(idOf(t));
const _clearInterval = (t) => native.clearInterval(idOf(t));
export { _setTimeout as setTimeout, _setInterval as setInterval, _clearTimeout as clearTimeout, _clearInterval as clearInterval };
