// SQLite persistence (node:sqlite) with a small document-store layer for gym-scoped collections.
//
// Relational tables hold identity/security data (users, gym membership, OTP, sessions, files,
// counters). Everything gym-scoped lives in `docs` (collection + JSON), which keeps the dev
// backend compact while still giving real durability and tenant isolation (every query is
// parameterised by gym_id).
import { DatabaseSync } from 'node:sqlite';
import { randomUUID } from 'node:crypto';
import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

const SCHEMA = `
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  phone TEXT UNIQUE,
  email TEXT UNIQUE,
  name TEXT NOT NULL DEFAULT '',
  photo_file_id TEXT,
  language TEXT NOT NULL DEFAULT 'en',
  timezone TEXT,
  phone_verified INTEGER NOT NULL DEFAULT 0,
  email_verified INTEGER NOT NULL DEFAULT 0,
  disabled INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS gyms (
  id TEXT PRIMARY KEY,
  code TEXT UNIQUE NOT NULL,
  data TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS gym_users (
  gym_id TEXT NOT NULL REFERENCES gyms(id),
  user_id TEXT NOT NULL REFERENCES users(id),
  role TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  profile TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  PRIMARY KEY (gym_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_gym_users_user ON gym_users(user_id);
CREATE TABLE IF NOT EXISTS otp_requests (
  id TEXT PRIMARY KEY,
  purpose TEXT NOT NULL,
  channel TEXT NOT NULL,
  target TEXT NOT NULL,
  user_id TEXT,
  code_hash TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  expires_at INTEGER NOT NULL,
  consumed INTEGER NOT NULL DEFAULT 0,
  context TEXT NOT NULL DEFAULT '{}',
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS sessions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  family_id TEXT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  device TEXT,
  expires_at INTEGER NOT NULL,
  revoked INTEGER NOT NULL DEFAULT 0,
  replaced INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);
CREATE TABLE IF NOT EXISTS docs (
  id TEXT PRIMARY KEY,
  gym_id TEXT NOT NULL,
  collection TEXT NOT NULL,
  data TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_docs_scope ON docs(gym_id, collection, deleted_at);
CREATE TABLE IF NOT EXISTS files (
  id TEXT PRIMARY KEY,
  gym_id TEXT,
  owner_id TEXT,
  mime TEXT NOT NULL,
  bytes BLOB NOT NULL,
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS counters (
  gym_id TEXT NOT NULL,
  name TEXT NOT NULL,
  value INTEGER NOT NULL,
  PRIMARY KEY (gym_id, name)
);
`;

export const nowIso = () => new Date().toISOString();

export function openDb(file) {
  if (file !== ':memory:') mkdirSync(dirname(file), { recursive: true });
  const db = new DatabaseSync(file);
  db.exec(SCHEMA);
  return new Store(db);
}

export class Store {
  constructor(db) {
    this.db = db;
    this._stmts = new Map();
    this._depth = 0;
  }

  prepare(sql) {
    let s = this._stmts.get(sql);
    if (!s) {
      s = this.db.prepare(sql);
      this._stmts.set(sql, s);
    }
    return s;
  }

  get(sql, ...params) { return this.prepare(sql).get(...params); }
  all(sql, ...params) { return this.prepare(sql).all(...params); }
  run(sql, ...params) { return this.prepare(sql).run(...params); }

  /** Re-entrant transaction: nested calls join the outermost one. */
  tx(fn) {
    if (this._depth > 0) return fn();
    this.db.exec('BEGIN IMMEDIATE');
    this._depth = 1;
    try {
      const r = fn();
      this.db.exec('COMMIT');
      return r;
    } catch (e) {
      this.db.exec('ROLLBACK');
      throw e;
    } finally {
      this._depth = 0;
    }
  }

  nextCounter(gymId, name) {
    return this.tx(() => {
      const row = this.get('SELECT value FROM counters WHERE gym_id = ? AND name = ?', gymId, name);
      const v = (row?.value ?? 0) + 1;
      this.run(
        'INSERT INTO counters(gym_id, name, value) VALUES (?, ?, ?) ON CONFLICT(gym_id, name) DO UPDATE SET value = excluded.value',
        gymId, name, v,
      );
      return v;
    });
  }

  /** Document collection scoped to a gym. */
  col(gymId, name) { return new Collection(this, gymId, name); }

  close() { this.db.close(); }
}

const unpack = (row) => {
  if (!row) return null;
  const d = JSON.parse(row.data);
  return { ...d, id: row.id, createdAt: row.created_at, updatedAt: row.updated_at };
};

export class Collection {
  constructor(store, gymId, name) {
    this.store = store;
    this.gymId = gymId;
    this.name = name;
  }

  insert(data, id = randomUUID()) {
    const ts = nowIso();
    const { id: _i, createdAt: _c, updatedAt: _u, ...clean } = data;
    this.store.run(
      'INSERT INTO docs(id, gym_id, collection, data, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      id, this.gymId, this.name, JSON.stringify(clean), ts, ts,
    );
    return { ...clean, id, createdAt: ts, updatedAt: ts };
  }

  get(id) {
    if (typeof id !== 'string') return null;
    return unpack(this.store.get(
      'SELECT * FROM docs WHERE id = ? AND gym_id = ? AND collection = ? AND deleted_at IS NULL',
      id, this.gymId, this.name,
    ));
  }

  /** Includes soft-deleted rows (used for historical joins such as an expense's removed category). */
  getAny(id) {
    return unpack(this.store.get(
      'SELECT * FROM docs WHERE id = ? AND gym_id = ? AND collection = ?', id, this.gymId, this.name,
    ));
  }

  all() {
    return this.store.all(
      'SELECT * FROM docs WHERE gym_id = ? AND collection = ? AND deleted_at IS NULL ORDER BY created_at, rowid',
      this.gymId, this.name,
    ).map(unpack);
  }

  find(pred) { return this.all().filter(pred); }
  findOne(pred) { return this.all().find(pred) ?? null; }

  update(id, patch) {
    const cur = this.get(id);
    if (!cur) return null;
    const { id: _i, createdAt, updatedAt: _u, ...rest } = cur;
    const { id: _pi, createdAt: _pc, updatedAt: _pu, ...p } = patch;
    const merged = { ...rest, ...p };
    for (const k of Object.keys(merged)) if (merged[k] === undefined) delete merged[k];
    const ts = nowIso();
    this.store.run('UPDATE docs SET data = ?, updated_at = ? WHERE id = ? AND gym_id = ? AND collection = ?',
      JSON.stringify(merged), ts, id, this.gymId, this.name);
    return { ...merged, id, createdAt, updatedAt: ts };
  }

  /** Replace the whole document (keeps id/createdAt). */
  replace(id, data) {
    const cur = this.get(id);
    if (!cur) return null;
    const ts = nowIso();
    this.store.run('UPDATE docs SET data = ?, updated_at = ? WHERE id = ? AND gym_id = ? AND collection = ?',
      JSON.stringify(data), ts, id, this.gymId, this.name);
    return { ...data, id, createdAt: cur.createdAt, updatedAt: ts };
  }

  remove(id) {
    const r = this.store.run(
      'UPDATE docs SET deleted_at = ? WHERE id = ? AND gym_id = ? AND collection = ? AND deleted_at IS NULL',
      nowIso(), id, this.gymId, this.name,
    );
    return r.changes > 0;
  }

  count(pred) { return pred ? this.find(pred).length : this.all().length; }
}
