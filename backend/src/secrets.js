// Seals small secrets (a gym's own payment-gateway keys) so they are not readable in a database copy or backup.
// AES-256-GCM, key derived from JWT_SECRET. Rotating JWT_SECRET makes sealed values unreadable (the owner re-enters them).
import { createCipheriv, createDecipheriv, hkdfSync, randomBytes } from 'node:crypto';

const key = (secret) => Buffer.from(hkdfSync('sha256', Buffer.from(secret), Buffer.alloc(0), 'gymmie-sealed-secrets', 32));

export function seal(secret, text) {
  const iv = randomBytes(12);
  const c = createCipheriv('aes-256-gcm', key(secret), iv);
  const enc = Buffer.concat([c.update(String(text), 'utf8'), c.final()]);
  return `v1.${iv.toString('base64url')}.${c.getAuthTag().toString('base64url')}.${enc.toString('base64url')}`;
}

export function unseal(secret, sealed) {
  const [v, iv, tag, enc] = String(sealed).split('.');
  if (v !== 'v1' || !iv || !tag || !enc) throw new Error('unreadable secret');
  const d = createDecipheriv('aes-256-gcm', key(secret), Buffer.from(iv, 'base64url'));
  d.setAuthTag(Buffer.from(tag, 'base64url'));
  return Buffer.concat([d.update(Buffer.from(enc, 'base64url')), d.final()]).toString('utf8');
}
