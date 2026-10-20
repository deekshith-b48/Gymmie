// V-09: backups are encrypted before they leave the server, and can always be restored with the private key.
import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync, existsSync, readdirSync, truncateSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomBytes } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { decryptFile, encryptFile, fingerprint, genKeyPair } from '../scripts/backup-crypt.js';

let dir; let keys; let pub; let priv; const PASS = 'a-long-test-passphrase';
before(() => {
  dir = mkdtempSync(join(tmpdir(), 'bk-'));
  keys = genKeyPair(join(dir, 'keys'), PASS);
  pub = readFileSync(keys.publicKeyFile, 'utf8');
  priv = readFileSync(keys.privateKeyFile, 'utf8');
});

test('a backup encrypts, contains none of its plaintext, and decrypts to the identical bytes', async () => {
  const plain = join(dir, 'a.sqlite');
  writeFileSync(plain, Buffer.concat([Buffer.from('SQLite format 3\0 member Priya Sharma +919876543210 PAR-Q heart problem'), randomBytes(200_000)]));
  const enc = join(dir, 'a.enc');
  await encryptFile(plain, enc, pub);
  const bytes = readFileSync(enc);
  assert.ok(!bytes.includes(Buffer.from('Priya Sharma')) && !bytes.includes(Buffer.from('+919876543210')), 'no plaintext in the encrypted file');
  const out = join(dir, 'a.out');
  await decryptFile(enc, out, priv, PASS);
  assert.ok(readFileSync(out).equals(readFileSync(plain)));
});

test('two encryptions of the same file differ (fresh key and nonce each time)', async () => {
  const plain = join(dir, 'b.sqlite'); writeFileSync(plain, 'same content');
  await encryptFile(plain, join(dir, 'b1.enc'), pub); await encryptFile(plain, join(dir, 'b2.enc'), pub);
  assert.ok(!readFileSync(join(dir, 'b1.enc')).equals(readFileSync(join(dir, 'b2.enc'))));
});

test('large files stream through (6 MB) and an empty file round-trips', async () => {
  for (const [name, size] of [['big', 6 * 1024 * 1024], ['empty', 0]]) {
    const plain = join(dir, `${name}.bin`); writeFileSync(plain, randomBytes(size));
    await encryptFile(plain, join(dir, `${name}.enc`), pub);
    await decryptFile(join(dir, `${name}.enc`), join(dir, `${name}.out`), priv, PASS);
    assert.ok(readFileSync(join(dir, `${name}.out`)).equals(readFileSync(plain)), name);
  }
});

test('the wrong key, the wrong passphrase, a changed byte, a changed header and a truncated file are all refused, leaving no output', async () => {
  const plain = join(dir, 'c.sqlite'); writeFileSync(plain, randomBytes(50_000));
  const enc = join(dir, 'c.enc');
  await encryptFile(plain, enc, pub);
  const other = genKeyPair(join(dir, 'keys2'), PASS);
  const tries = [];
  const attempt = async (name, file, key, pass) => {
    const out = join(dir, `${name}.out`);
    await assert.rejects(() => decryptFile(file, out, key, pass), undefined, name);
    assert.ok(!existsSync(out) && !existsSync(`${out}.partial`), `${name}: no output left behind`);
    tries.push(name);
  };
  await attempt('wrongkey', enc, readFileSync(other.privateKeyFile, 'utf8'), PASS);
  await attempt('wrongpass', enc, priv, 'not-the-passphrase');
  const flipped = readFileSync(enc); flipped[flipped.length - 100] ^= 1; writeFileSync(join(dir, 'flip.enc'), flipped);
  await attempt('flipped', join(dir, 'flip.enc'), priv, PASS);
  const headTamper = readFileSync(enc); headTamper[headTamper.length > 600 ? 12 : 9] ^= 1; writeFileSync(join(dir, 'head.enc'), headTamper);
  await attempt('header', join(dir, 'head.enc'), priv, PASS);
  const cut = readFileSync(enc).subarray(0, readFileSync(enc).length - 20); writeFileSync(join(dir, 'cut.enc'), cut);
  await attempt('truncated', join(dir, 'cut.enc'), priv, PASS);
  writeFileSync(join(dir, 'junk.enc'), 'this is not a backup at all, just text of some length');
  await attempt('junk', join(dir, 'junk.enc'), priv, PASS);
  assert.equal(tries.length, 6);
});

test('verify mode authenticates without writing, and a real database survives the round trip and opens', async () => {
  const dbFile = join(dir, 'real.sqlite');
  const db = new DatabaseSync(dbFile);
  db.exec("CREATE TABLE t(x TEXT); INSERT INTO t VALUES ('hello'); VACUUM INTO '" + join(dir, 'real-copy.sqlite') + "'");
  db.close();
  const enc = join(dir, 'real.enc');
  await encryptFile(join(dir, 'real-copy.sqlite'), enc, pub);
  await decryptFile(enc, null, priv, PASS);
  const out = join(dir, 'real-restored.sqlite');
  await decryptFile(enc, out, priv, PASS);
  const r = new DatabaseSync(out, { readOnly: true });
  assert.equal(r.prepare('SELECT x FROM t').get().x, 'hello');
  assert.equal(r.prepare('PRAGMA integrity_check').get().integrity_check, 'ok');
  r.close();
});

test('key generation protects the private key, refuses weak passphrases and refuses to overwrite', () => {
  assert.throws(() => genKeyPair(join(dir, 'k3'), 'short'), /at least 12/);
  const k = genKeyPair(join(dir, 'k4'), PASS);
  assert.match(readFileSync(k.privateKeyFile, 'utf8'), /BEGIN ENCRYPTED PRIVATE KEY/);
  assert.throws(() => genKeyPair(join(dir, 'k4'), PASS), /refusing to overwrite/);
  assert.equal(k.fingerprint, fingerprint(readFileSync(k.publicKeyFile, 'utf8')));
  assert.equal(k.fingerprint.length, 32);
});
