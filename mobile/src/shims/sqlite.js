// node:sqlite (DatabaseSync) au-dessus de sql.js (SQLite compilé en WebAssembly).
// La base vit en mémoire ; backend.js l'enregistre sur le téléphone après chaque écriture.
let SQL = null;
let initialBytes = null;
let onWrite = () => {};

export function configureSqlite({ sql, bytes, onChange }) {
  SQL = sql;
  initialBytes = bytes;
  onWrite = onChange;
}

const READ_ONLY = /^\s*(SELECT|PRAGMA\s+table_info|WITH\b[\s\S]*\bSELECT)\b/i;

class StatementSync {
  constructor(db, sql) {
    this.db = db;
    this.sql = sql;
    this.gen = -1;
    this.stmt = null;
    this.readOnly = READ_ONLY.test(sql);
  }

  // sql.js libère les requêtes préparées à chaque export : on les prépare à nouveau.
  prepared() {
    if (this.gen !== this.db.gen) {
      this.stmt = this.db.raw.prepare(this.sql);
      this.gen = this.db.gen;
    }
    return this.stmt;
  }

  bind(params) {
    const s = this.prepared();
    s.reset();
    if (params.length) s.bind(params.map((v) => (v === undefined ? null : typeof v === 'boolean' ? Number(v) : v)));
    return s;
  }

  run(...params) {
    const s = this.bind(params);
    try {
      s.step();
    } finally {
      s.reset();
    }
    const changes = this.db.raw.getRowsModified();
    const lastInsertRowid = this.db.lastRowid();
    if (!this.readOnly) this.db.changed();
    return { changes, lastInsertRowid };
  }

  get(...params) {
    const s = this.bind(params);
    try {
      return s.step() ? s.getAsObject() : undefined;
    } finally {
      s.reset();
    }
  }

  all(...params) {
    const s = this.bind(params);
    const rows = [];
    try {
      while (s.step()) rows.push(s.getAsObject());
    } finally {
      s.reset();
    }
    return rows;
  }
}

export class DatabaseSync {
  constructor() {
    if (!SQL) throw new Error('sql.js non initialisé');
    this.raw = new SQL.Database(initialBytes || undefined);
    this.gen = 0;
    this.inTx = 0;
    this.raw.exec('PRAGMA foreign_keys = ON');
  }

  lastRowid() {
    const r = this.raw.exec('SELECT last_insert_rowid()');
    return r[0]?.values[0][0] ?? 0;
  }

  changed() {
    if (!this.inTx) onWrite();
  }

  exec(sql) {
    const head = sql.trim().toUpperCase();
    if (head.startsWith('BEGIN')) this.inTx++;
    this.raw.exec(sql);
    if (head.startsWith('COMMIT') || head.startsWith('ROLLBACK') || head.startsWith('END')) this.inTx = Math.max(0, this.inTx - 1);
    if (!READ_ONLY.test(sql)) this.changed();
  }

  prepare(sql) {
    return new StatementSync(this, sql);
  }

  // Copie binaire de la base (pour l'enregistrer) ; les requêtes préparées sont refaites.
  serialize() {
    const bytes = this.raw.export();
    this.gen++;
    this.raw.exec('PRAGMA foreign_keys = ON');
    return bytes;
  }

  close() {
    this.raw.close();
  }
}
