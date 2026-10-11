#!/usr/bin/env node
// The restore drill: open a backup file read-only and show it is whole and recent.   node scripts/restore-check.js <backup.sqlite>
import { DatabaseSync } from 'node:sqlite';
const file = process.argv[2];
if (!file) { console.error('usage: restore-check.js <backup.sqlite>'); process.exit(1); }
const db = new DatabaseSync(file, { readOnly: true });
const q = (sql) => db.prepare(sql).get();
const out = {
  integrity: q('PRAGMA integrity_check').integrity_check,
  schemaVersion: q('PRAGMA user_version').user_version,
  gyms: q('SELECT COUNT(*) c FROM gyms').c,
  users: q('SELECT COUNT(*) c FROM users').c,
  members: q("SELECT COUNT(*) c FROM docs WHERE collection = 'members' AND deleted_at IS NULL").c,
  newestChange: q('SELECT MAX(updated_at) m FROM docs').m,
};
console.log(JSON.stringify(out, null, 2));
process.exit(out.integrity === 'ok' ? 0 : 1);
