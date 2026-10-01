// node:path (POSIX, réduit).
const join = (...parts) => parts.filter(Boolean).join('/').replace(/\/+/g, '/');
const basename = (p) => String(p).split('/').pop();
const dirname = (p) => String(p).split('/').slice(0, -1).join('/') || '/';
const extname = (p) => {
  const b = basename(p);
  const i = b.lastIndexOf('.');
  return i > 0 ? b.slice(i) : '';
};
const path = { join, basename, dirname, extname, sep: '/' };
export default path;
export { join, basename, dirname, extname };
