// Member principal: a gym member (a `members` document, not a staff `users` row) signed in by phone + OTP.
//
// Deliberately separate from staff auth. A member token carries `typ:'member'` and is only honoured on
// routes declared `auth:'member'`; staff routes refuse it (app.js). Its sessions live in their own table,
// there is no `users` row, no `gym_users` role and nothing in the staff permission matrix, so a member
// can never reach a staff route even one that forgot to declare a permission.
import { createHash, createHmac, randomBytes, randomUUID, timingSafeEqual } from 'node:crypto';
import { forbidden, unauthorized } from './errors.js';
import { ensureFeature, loadGym } from './helpers.js';
import { todayIn } from './domain/dates.js';
import { planAllows, subscriptionState } from './domain/billing.js';

const sha256 = (s) => createHash('sha256').update(s).digest('hex');
const b64u = (b) => Buffer.from(b).toString('base64url');

export const MEMBER_FEATURE = 'MEMBER_APP';

/** The one place a member document is judged fit to sign in (also re-run on every request). */
export function memberAllowed(store, gymId, memberId, phone) {
  const gym = loadGym(store, gymId);
  if (!gym) return null;
  if (!(gym.features?.[MEMBER_FEATURE] ?? false)) return null;
  if (!planAllows(gym, MEMBER_FEATURE)) return null; // the plan no longer includes the member app
  if (subscriptionState(gym).status === 'locked') return null; // a gym that stopped paying locks its members out too
  const member = store.col(gymId, 'members').get(memberId);
  if (!member || member.blocked || member.appClosedAt) return null; // blocked by staff, or closed by the member
  if (phone && member.phone !== phone) return null; // a staff phone edit ends the old number's access
  return { gym, member };
}

/** Every live member document holding this phone, across gyms (uses idx_docs_member_phone). */
export function findMembersByPhone(store, phone, gymCode = null) {
  const rows = store.all(
    "SELECT id, gym_id FROM docs WHERE collection = 'members' AND deleted_at IS NULL AND json_extract(data, '$.phone') = ?",
    phone,
  );
  const out = [];
  for (const r of rows) {
    const ok = memberAllowed(store, r.gym_id, r.id, phone);
    if (!ok) continue;
    if (gymCode && ok.gym.code !== String(gymCode)) continue;
    out.push({ gymId: r.gym_id, memberId: r.id });
  }
  return out;
}

export class MemberSessions {
  constructor(store, auth, config) {
    this.store = store;
    this.auth = auth;
    this.config = config;
  }

  start({ gymId, memberId, phone }, device) {
    return this._issue({ gymId, memberId, phone }, randomUUID(), device);
  }

  _issue({ gymId, memberId, phone }, familyId, device) {
    const refresh = randomBytes(32).toString('base64url');
    const id = randomUUID();
    this.store.run(
      'INSERT INTO member_sessions(id, gym_id, member_id, phone, family_id, token_hash, device, expires_at, created_at) VALUES (?,?,?,?,?,?,?,?,?)',
      id, gymId, memberId, phone, familyId, sha256(refresh), device ?? null,
      Date.now() + this.config.refreshTtlSec * 1000, Date.now(),
    );
    return {
      accessToken: this.auth.signAccess(`${gymId}:${memberId}`, id, { typ: 'member', gid: gymId, mid: memberId }),
      refreshToken: refresh,
      expiresIn: this.config.accessTtlSec,
      tokenType: 'Bearer',
    };
  }

  refresh(refreshToken, device) {
    if (typeof refreshToken !== 'string' || refreshToken.length < 20) throw unauthorized('Invalid refresh token');
    const row = this.store.get('SELECT * FROM member_sessions WHERE token_hash = ?', sha256(refreshToken));
    if (!row) throw unauthorized('Invalid refresh token');
    if (row.replaced || row.revoked) {
      this.store.run('UPDATE member_sessions SET revoked = 1 WHERE family_id = ?', row.family_id); // replay: kill the family
      throw unauthorized('Session expired. Please sign in again.');
    }
    if (row.expires_at < Date.now()) throw unauthorized('Session expired. Please sign in again.');
    if (!memberAllowed(this.store, row.gym_id, row.member_id, row.phone)) {
      this.store.run('UPDATE member_sessions SET revoked = 1 WHERE family_id = ?', row.family_id);
      throw forbidden('Member access is not available.');
    }
    this.store.run('UPDATE member_sessions SET replaced = 1 WHERE id = ?', row.id);
    return this._issue({ gymId: row.gym_id, memberId: row.member_id, phone: row.phone }, row.family_id, device ?? row.device);
  }

  revokeSession(sessionId) {
    const row = this.store.get('SELECT family_id FROM member_sessions WHERE id = ?', sessionId);
    if (row) this.store.run('UPDATE member_sessions SET revoked = 1 WHERE family_id = ?', row.family_id);
  }

  revokeMember(gymId, memberId) {
    this.store.run('UPDATE member_sessions SET revoked = 1 WHERE gym_id = ? AND member_id = ?', gymId, memberId);
  }
}

/**
 * Builds the request context for an `auth:'member'` route from a verified access-token payload.
 * Everything is re-read from the database: a block, delete, phone change or flag-off takes effect on the
 * next request. The member id comes from the session row, never from the URL or body.
 */
export function memberContext(ctx, payload, today = todayIn) {
  if (payload.typ !== 'member') throw forbidden('This area is for gym members.');
  const { store } = ctx;
  const sess = store.get('SELECT * FROM member_sessions WHERE id = ?', payload.sid);
  if (!sess || sess.revoked) throw unauthorized('Session ended. Please sign in again.');
  const ok = memberAllowed(store, sess.gym_id, sess.member_id, sess.phone);
  if (!ok) {
    store.run('UPDATE member_sessions SET revoked = 1 WHERE family_id = ?', sess.family_id);
    throw forbidden('Member access is not available. Ask your gym.');
  }
  ensureFeature(ok.gym, MEMBER_FEATURE);
  ctx.sessionId = sess.id;
  ctx.role = 'member';
  ctx.gymId = sess.gym_id;
  ctx.gym = ok.gym;
  ctx.member = ok.member;
  ctx.today = () => today(ok.gym.timezone);
  ctx.col = (name) => store.col(sess.gym_id, name);
}

// ---- short-lived signed tokens for the multi-gym picker (same pattern as the public portal) ------------------------
const sign = (secret, payload) => createHmac('sha256', secret).update(`member-select:${payload}`).digest('base64url');
export function makeSelectionToken(secret, data, ttlMs = 5 * 60 * 1000) {
  const body = b64u(JSON.stringify({ ...data, e: Date.now() + ttlMs }));
  return `${body}.${sign(secret, body)}`;
}
export function readSelectionToken(secret, token) {
  const [body, sig] = String(token ?? '').split('.');
  if (!body || !sig) throw unauthorized('Please verify your number again.');
  const a = Buffer.from(sig);
  const b = Buffer.from(sign(secret, body));
  if (a.length !== b.length || !timingSafeEqual(a, b)) throw unauthorized('Please verify your number again.');
  const d = JSON.parse(Buffer.from(body, 'base64url').toString());
  if (d.e < Date.now()) throw unauthorized('Your verification expired. Please verify again.');
  return d;
}

// ---- openGym single sign-on (contract: member-app/opengym/api/sso.js) -------------------------------------------------
const SSO_PREFIX = 'opengym-sso:v1:';
export function signOpenGymAssertion(secret, claims) {
  const payload = b64u(JSON.stringify({ v: 1, ...claims }));
  return `${payload}.${createHmac('sha256', secret).update(SSO_PREFIX + payload).digest('base64url')}`;
}

/** Ends this member's sessions inside openGym. Best effort: Gymmie access is already cut off. */
export async function revokeOpenGym(config, gymId, memberId, fetchImpl = fetch) {
  const og = config.openGym;
  if (!og?.apiUrl || !og.ssoSecret) return false;
  try {
    const r = await fetchImpl(`${og.apiUrl}/api/sso/revoke`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${og.ssoSecret}` },
      body: JSON.stringify({ gid: gymId, mid: memberId }),
      signal: AbortSignal.timeout(5000),
    });
    return r.ok;
  } catch (e) {
    console.error('[openGym revoke]', e.message);
    return false;
  }
}
