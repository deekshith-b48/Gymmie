#!/usr/bin/env node
// Encrypts database backups before they leave the server, with a PUBLIC key. The server only ever holds the public half, so someone who
// gets into the server or the bucket cannot read any backup, old or new; the private key lives offline with you (see docs/DEPLOY.md).
//
// Hybrid scheme: a fresh random 256-bit key encrypts the file with AES-256-GCM (streamed, so a multi-GB database is fine); that key is
// wrapped with RSA-OAEP (SHA-256, 4096-bit). The file header is authenticated too. Nothing is written to the destination unless the
// whole file decrypts and authenticates, so a corrupted or tampered backup is refused rather than half-restored.
//
//   node scripts/backup-crypt.js genkeypair <dir>          # once, on YOUR computer, not on the server. BACKUP_KEY_PASSPHRASE protects the private key
//   node scripts/backup-crypt.js encrypt <in> <out>         # BACKUP_PUBLIC_KEY_FILE=/keys/backup-public.pem
//   node scripts/backup-crypt.js decrypt <in> <out>         # BACKUP_PRIVATE_KEY_FILE=... BACKUP_KEY_PASSPHRASE=...
//   node scripts/backup-crypt.js verify <in>                # decrypts and authenticates without writing anything (restore drills)
import {
  constants, createCipheriv, createDecipheriv, createHash, createPrivateKey, createPublicKey, generateKeyPairSync, privateDecrypt, publicEncrypt, randomBytes,
} from 'node:crypto';
import { createReadStream, createWriteStream, existsSync, mkdirSync, readFileSync, renameSync, rmSync, statSync, writeFileSync, openSync, readSync, closeSync } from 'node:fs';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { join } from 'node:path';

const MAGIC = Buffer.from('GYMBK2\n');
const TAG = 16;
const OAEP = { padding: constants.RSA_PKCS1_OAEP_PADDING, oaepHash: 'sha256' };

const header = (wrapped, iv) => Buffer.concat([MAGIC, Buffer.from([wrapped.length >> 8, wrapped.length & 255]), wrapped, iv]);

export const fingerprint = (publicPem) => createHash('sha256').update(createPublicKey(publicPem).export({ type: 'spki', format: 'der' })).digest('hex').slice(0, 32);

export function genKeyPair(dir, passphrase) {
  if (!passphrase || passphrase.length < 12) throw new Error('BACKUP_KEY_PASSPHRASE must be at least 12 characters');
  mkdirSync(dir, { recursive: true });
  const priv = join(dir, 'backup-private.pem');
  const pub = join(dir, 'backup-public.pem');
  if (existsSync(priv) || existsSync(pub)) throw new Error(`refusing to overwrite an existing key in ${dir}`);
  const { publicKey, privateKey } = generateKeyPairSync('rsa', {
    modulusLength: 4096, publicKeyEncoding: { type: 'spki', format: 'pem' },
    privateKeyEncoding: { type: 'pkcs8', format: 'pem', cipher: 'aes-256-cbc', passphrase },
  });
  writeFileSync(priv, privateKey, { mode: 0o600 });
  writeFileSync(pub, publicKey, { mode: 0o644 });
  return { privateKeyFile: priv, publicKeyFile: pub, fingerprint: fingerprint(publicKey) };
}

/** Encrypts [src] into [dest] with the public key (PEM text). */
export async function encryptFile(src, dest, publicPem) {
  const dataKey = randomBytes(32);
  const iv = randomBytes(12);
  const wrapped = publicEncrypt({ key: createPublicKey(publicPem), ...OAEP }, dataKey);
  const head = header(wrapped, iv);
  const cipher = createCipheriv('aes-256-gcm', dataKey, iv);
  cipher.setAAD(head);
  const tmp = `${dest}.partial`;
  try {
    const out = createWriteStream(tmp, { mode: 0o600 });
    out.write(head);
    await pipeline(createReadStream(src), cipher, out, { end: false });
    out.write(cipher.getAuthTag());
    await new Promise((res, rej) => out.end((e) => (e ? rej(e) : res())));
    renameSync(tmp, dest);
  } catch (e) { rmSync(tmp, { force: true }); throw e; }
}

function readHeader(file) {
  const size = statSync(file).size;
  if (size < MAGIC.length + 2 + TAG + 12) throw new Error('not a Gymmie backup (too short)');
  const fd = openSync(file, 'r');
  try {
    const fixed = Buffer.alloc(MAGIC.length + 2);
    readSync(fd, fixed, 0, fixed.length, 0);
    if (!fixed.subarray(0, MAGIC.length).equals(MAGIC)) throw new Error('not a Gymmie backup (bad header)');
    const wlen = (fixed[MAGIC.length] << 8) | fixed[MAGIC.length + 1];
    const rest = Buffer.alloc(wlen + 12);
    readSync(fd, rest, 0, rest.length, fixed.length);
    const wrapped = rest.subarray(0, wlen);
    const iv = rest.subarray(wlen);
    return { size, wrapped, iv, head: Buffer.concat([fixed, rest]) };
  } finally { closeSync(fd); }
}

/** Decrypts [src]. With [dest] null nothing is written (verify only). Throws, leaving no output, unless the whole file authenticates. */
export async function decryptFile(src, dest, privatePem, passphrase) {
  const { size, wrapped, iv, head } = readHeader(src);
  const dataKey = privateDecrypt({ key: createPrivateKey({ key: privatePem, passphrase }), ...OAEP }, wrapped);
  const fd = openSync(src, 'r');
  const tag = Buffer.alloc(TAG);
  readSync(fd, tag, 0, TAG, size - TAG);
  closeSync(fd);
  const decipher = createDecipheriv('aes-256-gcm', dataKey, iv);
  decipher.setAAD(head);
  decipher.setAuthTag(tag);
  const ctLen = size - TAG - head.length;
  const input = ctLen > 0 ? createReadStream(src, { start: head.length, end: size - TAG - 1 }) : Readable.from([]);
  if (!dest) {
    await pipeline(input, decipher, async function consume(source) { for await (const _ of source) { /* authenticate only */ } });
    return;
  }
  const tmp = `${dest}.partial`;
  try {
    await pipeline(input, decipher, createWriteStream(tmp, { mode: 0o600 }));
    renameSync(tmp, dest);
  } catch (e) { rmSync(tmp, { force: true }); throw new Error(`backup could not be decrypted or has been altered (${e.code ?? e.message})`); }
}

const readPublic = () => (process.env.BACKUP_PUBLIC_KEY ?? (process.env.BACKUP_PUBLIC_KEY_FILE ? readFileSync(process.env.BACKUP_PUBLIC_KEY_FILE, 'utf8') : null));
const readPrivate = () => (process.env.BACKUP_PRIVATE_KEY_FILE ? readFileSync(process.env.BACKUP_PRIVATE_KEY_FILE, 'utf8') : null);

if (import.meta.url === `file://${process.argv[1]}`) {
  const [cmd, a, b] = process.argv.slice(2);
  try {
    if (cmd === 'genkeypair') {
      const r = genKeyPair(a ?? '.', process.env.BACKUP_KEY_PASSPHRASE);
      console.log(`Public key  (copy to the server):      ${r.publicKeyFile}\nPrivate key (KEEP OFFLINE, 2 copies):  ${r.privateKeyFile}\nFingerprint: ${r.fingerprint}\nWrite the passphrase and the fingerprint down separately from the key file.`);
    } else if (cmd === 'encrypt') {
      const pub = readPublic();
      if (!pub) throw new Error('set BACKUP_PUBLIC_KEY_FILE (or BACKUP_PUBLIC_KEY)');
      await encryptFile(a, b, pub);
      console.log(JSON.stringify({ level: 'info', msg: 'backup encrypted', file: b, bytes: statSync(b).size, key: fingerprint(pub) }));
    } else if (cmd === 'decrypt' || cmd === 'verify') {
      const priv = readPrivate();
      if (!priv) throw new Error('set BACKUP_PRIVATE_KEY_FILE and BACKUP_KEY_PASSPHRASE');
      await decryptFile(a, cmd === 'verify' ? null : b, priv, process.env.BACKUP_KEY_PASSPHRASE);
      console.log(cmd === 'verify' ? 'backup decrypts and authenticates' : `decrypted to ${b}`);
    } else {
      console.error('usage: backup-crypt.js genkeypair <dir> | encrypt <in> <out> | decrypt <in> <out> | verify <in>');
      process.exit(2);
    }
  } catch (e) { console.error(`backup-crypt: ${e.message}`); process.exit(1); }
}
