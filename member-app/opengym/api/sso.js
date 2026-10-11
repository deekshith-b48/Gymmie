/* Gymmie single sign-on (members of a gym).
 *
 * The Gymmie backend authenticates a gym member (phone + one-time code) and hands the Gymmie app a
 * short-lived assertion: `<base64url JSON claims>.<HMAC-SHA256>`. The app's WebView posts it to
 * POST /api/sso/redeem, which turns it into this server's own session cookie. openGym never sees
 * the member's phone number, and no passkey or password is involved.
 *
 *   - The MAC key is GYMMIE_SSO_SECRET, shared with the Gymmie backend only. The MAC covers a
 *     domain prefix, so a signature made for another purpose with the same secret is not valid here.
 *   - Claims: v (1), gid + mid (gym id, member id), name, iat, exp, jti. An assertion lives for at
 *     most SSO_MAX_TTL_MS and is accepted once: its jti is remembered until it expires.
 *   - Pure functions plus a small replay guard; the route, the throttle and the audit are
 *     server.js's. */
import crypto from 'node:crypto';

export const SSO_MAX_TTL_MS = 120 * 1000;
export const SSO_MIN_SECRET = 32;
const PREFIX = 'opengym-sso:v1:';

const b64u = b => Buffer.from(b).toString('base64url');
const mac = (secret, payload) => crypto.createHmac('sha256', secret).update(PREFIX + payload).digest('base64url');

export function signAssertion(secret, claims) {
  const payload = b64u(JSON.stringify({ v: 1, ...claims }));
  return payload + '.' + mac(secret, payload);
}

const ID = /^[A-Za-z0-9_-]{1,64}$/;

/* → the claims, or null. A wrong MAC, an old or far-future one, a replayed one and a malformed one
 * all look the same from outside. `guard.seen(jti, exp)` is how a caller refuses a second use. */
export function verifyAssertion(secret, token, { now = Date.now(), guard = null } = {}) {
  if (typeof secret !== 'string' || secret.length < SSO_MIN_SECRET) return null;
  if (typeof token !== 'string' || token.length > 2048) return null;
  const i = token.lastIndexOf('.');
  if (i < 0) return null;
  const payload = token.slice(0, i);
  const given = Buffer.from(token.slice(i + 1));
  const want = Buffer.from(mac(secret, payload));
  if (given.length !== want.length || !crypto.timingSafeEqual(given, want)) return null;
  let c;
  try { c = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')); } catch { return null; }
  if (!c || c.v !== 1) return null;
  if (!ID.test(String(c.gid)) || !ID.test(String(c.mid)) || !ID.test(String(c.jti))) return null;
  if (!Number.isFinite(c.iat) || !Number.isFinite(c.exp)) return null;
  if (c.exp <= now || c.iat > now + 30000) return null;           // expired / issued in the future
  if (c.exp - c.iat > SSO_MAX_TTL_MS) return null;                // refuse a long-lived one outright
  if (guard && !guard.seen(c.jti, c.exp)) return null;           // already redeemed
  const name = typeof c.name === 'string' ? c.name.replace(/[\u0000-\u001f]/g, '').trim().slice(0, 40) : '';
  return { gid: String(c.gid), mid: String(c.mid), name: name || 'Member', jti: c.jti, exp: c.exp };
}

export const externalId = (gid, mid) => `gymmie:${gid}:${mid}`;

/* Remembers jtis until they expire. seen() is true the first time, false after. Bounded: past
 * `max` the oldest goes, which only matters under a flood of valid assertions. */
export function createReplayGuard({ max = 50000, now = Date.now } = {}) {
  const map = new Map();
  return {
    seen(jti, exp) {
      const t = now();
      if (map.size >= max) {
        for (const [k, e] of map) if (e <= t) map.delete(k);
        while (map.size >= max) map.delete(map.keys().next().value);
      }
      if (map.has(jti) && map.get(jti) > t) return false;
      map.set(jti, exp);
      return true;
    },
    get size() { return map.size; }
  };
}

/* The routes SSO_ONLY switches off: every other way of getting a session or a credential. A member
 * is signed in by their gym, so passkeys, passwords, e-mail recovery, pairing and device links
 * would only be extra doors. */
export const SSO_BLOCKED = new Set([
  'POST /api/register/options', 'POST /api/register/verify',
  'POST /api/login/options', 'POST /api/login/verify',
  'POST /api/login/password', 'POST /api/register/password', 'POST /api/login/password-reset',
  'POST /api/pair/create', 'POST /api/pair/redeem',
  'POST /api/device-link/options', 'POST /api/device-link/verify', 'POST /api/account/device-link',
  'GET /api/account/passkeys', 'POST /api/account/passkeys/options', 'POST /api/account/passkeys/verify',
  'POST /api/account/passkeys/rename', 'DELETE /api/account/passkeys',
  'GET /api/account/password', 'POST /api/account/password', 'DELETE /api/account/password',
  'POST /api/account/email', 'DELETE /api/account/email',
  'POST /api/admin/user/password-reset'
]);
