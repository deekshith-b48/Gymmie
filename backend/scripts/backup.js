#!/usr/bin/env node
// Consistent online backup of the SQLite database (safe while the server runs): VACUUM INTO a dated file, verify it,
// and keep the newest N. Ship the folder off the machine with rclone/aws s3 sync (see docs/DEPLOY.md).
//   DB_FILE=/data/gymmie.sqlite BACKUP_DIR=/backups KEEP=14 node scripts/backup.js
import { mkdirSync, readdirSync, rmSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { loadConfig } from '../src/config.js';

const config = loadConfig();
const dir = process.env.BACKUP_DIR ?? join(config.dbFile, '..', 'backups');
const keep = Number(process.env.KEEP ?? 14);
mkdirSync(dir, { recursive: true });
const stamp = new Date().toISOString().replace(/[:.]/g, '-');
const out = join(dir, `gymmie-${stamp}.sqlite`);

const src = new DatabaseSync(config.dbFile);
src.exec(`VACUUM INTO '${out.replaceAll("'", "''")}'`);
src.close();

// a backup that cannot be opened is not a backup
const check = new DatabaseSync(out, { readOnly: true });
const ok = check.prepare('PRAGMA integrity_check').get().integrity_check;
const gyms = check.prepare('SELECT COUNT(*) c FROM gyms').get().c;
check.close();
if (ok !== 'ok') { rmSync(out); console.error(`Backup failed its integrity check: ${ok}`); process.exit(1); }

const files = readdirSync(dir).filter((f) => /^gymmie-.*\.sqlite$/.test(f)).sort();
for (const f of files.slice(0, Math.max(0, files.length - keep))) rmSync(join(dir, f));
console.log(JSON.stringify({ level: 'info', msg: 'backup ok', file: out, bytes: statSync(out).size, gyms, kept: Math.min(files.length, keep) }));
