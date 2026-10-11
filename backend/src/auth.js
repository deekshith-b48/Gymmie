// Authentication: HS256 access tokens, rotating refresh tokens, one-time passwords, role permissions.
import { createHash, createHmac, randomBytes, randomInt, timingSafeEqual, randomUUID } from 'node:crypto';
import { ApiError, forbidden, invalid, tooMany, unauthorized } from './errors.js';
import { nowIso } from './db.js';

const b64u = (b) => Buffer.from(b).toString('base64url');
const sha256 = (s) => createHash('sha256').update(s).digest('hex');

export const ROLES = ['owner', 'manager', 'staff', 'trainer'];

/** Capability matrix. 'owner' implicitly has everything. */
export const PERMISSIONS = {
  owner: ['*'],
  manager: [
    'members.read', 'members.write', 'plans.read', 'plans.write', 'finance.read', 'finance.write',
    'leads.read', 'leads.write', 'attendance.write', 'attendance.read', 'products.read', 'products.write',
    'expenses.read', 'expenses.write', 'broadcasts.read', 'broadcasts.write', 'plansets.read',
    'plansets.write', 'staff.read', 'devices.read', 'devices.write', 'reports.read', 'settings.read',
    'feedback.read', 'videos.write', 'trainers.write', 'settings.write', 'requests.read', 'requests.write',
  ],
  staff: [
    'members.read', 'members.write', 'plans.read', 'finance.read', 'finance.write', 'leads.read',
    'leads.write', 'attendance.write', 'attendance.read', 'products.read', 'products.write',
    'plansets.read', 'reports.read', 'settings.read', 'feedback.read', 'requests.read',
  ],
  trainer: ['members.read', 'attendance.read', 'plans.read', 'plansets.read', 'plansets.write', 'trainer.self'],
};

export const can = (role, perm) => {
  const p = PERMISSIONS[role] ?? [];
  return p.includes('*') || p.includes(perm);
};

export class AuthService {
  constructor(store, config) {
    this.store = store;
    this.config = config;
  }

  // ---- access tokens ------------------------------------------------------------------
  /** `extra` adds claims (member tokens carry `typ:'member'`); staff tokens are unchanged. */
  signAccess(userId, sessionId, extra = {}) {
    const now = Math.floor(Date.now() / 1000);
    const head = b64u(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
    const body = b64u(JSON.stringify({ iss: 'gymmie', sub: userId, sid: sessionId, iat: now, exp: now + this.config.accessTtlSec, ...extra }));
    const sig = createHmac('sha256', this.config.jwtSecret).update(`${head}.${body}`).digest('base64url');
    return `${head}.${body}.${sig}`;
  }

  verifyAccess(token) {
    const parts = String(token).split('.');
    if (parts.length !== 3) throw unauthorized('Invalid token');
    const [h, b, s] = parts;
    const expect = createHmac('sha256', this.config.jwtSecret).update(`${h}.${b}`).digest();
    const got = Buffer.from(s, 'base64url');
    if (got.length !== expect.length || !timingSafeEqual(got, expect)) throw unauthorized('Invalid token');
    let header, payload;
    try {
      header = JSON.parse(Buffer.from(h, 'base64url').toString());
      payload = JSON.parse(Buffer.from(b, 'base64url').toString());
    } catch { throw unauthorized('Invalid token'); }
    if (header.alg !== 'HS256') throw unauthorized('Invalid token');
    if (!payload.exp || payload.exp < Math.floor(Date.now() / 1000)) throw new ApiError(401, 'TOKEN_EXPIRED', 'Access token expired');
    return payload;
  }

  // ---- sessions / refresh tokens ------------------------------------------------------
  startSession(userId, device) {
    const familyId = randomUUID();
    return this._issue(userId, familyId, device);
  }

  _issue(userId, familyId, device) {
    const refresh = randomBytes(32).toString('base64url');
    const id = randomUUID();
    this.store.run(
      'INSERT INTO sessions(id, user_id, family_id, token_hash, device, expires_at, created_at) VALUES (?,?,?,?,?,?,?)',
      id, userId, familyId, sha256(refresh), device ?? null,
      Date.now() + this.config.refreshTtlSec * 1000, Date.now(),
    );
    return { accessToken: this.signAccess(userId, id), refreshToken: refresh, expiresIn: this.config.accessTtlSec };
  }

  refresh(refreshToken, device) {
    if (typeof refreshToken !== 'string' || refreshToken.length < 20) throw unauthorized('Invalid refresh token');
    const row = this.store.get('SELECT * FROM sessions WHERE token_hash = ?', sha256(refreshToken));
    if (!row) throw unauthorized('Invalid refresh token');
    if (row.replaced || row.revoked) {
      // A rotated/revoked token is being replayed: kill the whole family.
      this.store.run('UPDATE sessions SET revoked = 1 WHERE family_id = ?', row.family_id);
      throw unauthorized('Session expired. Please sign in again.');
    }
    if (row.expires_at < Date.now()) throw unauthorized('Session expired. Please sign in again.');
    const user = this.store.get('SELECT disabled FROM users WHERE id = ?', row.user_id);
    if (!user || user.disabled) throw forbidden('Your account is disabled.');
    this.store.run('UPDATE sessions SET replaced = 1 WHERE id = ?', row.id);
    return this._issue(row.user_id, row.family_id, device ?? row.device);
  }

  revokeSession(sessionId) {
    const row = this.store.get('SELECT family_id FROM sessions WHERE id = ?', sessionId);
    if (row) this.store.run('UPDATE sessions SET revoked = 1 WHERE family_id = ?', row.family_id);
  }

  revokeAll(userId) { this.store.run('UPDATE sessions SET revoked = 1 WHERE user_id = ?', userId); }

  sessionActive(sessionId) {
    const row = this.store.get('SELECT revoked FROM sessions WHERE id = ?', sessionId);
    return !!row && !row.revoked;
  }

  // ---- one-time passwords -------------------------------------------------------------
  _hashOtp(id, code) { return createHmac('sha256', this.config.jwtSecret).update(`${id}:${code}`).digest('hex'); }

  /**
   * Creates an OTP challenge. Delivery is the single integration point for an SMS / WhatsApp /
   * email provider: without a configured provider the dev backend only logs the code locally
   * (never in production).
   */
  createOtp({ purpose, channel, target, userId = null, context = {} }) {
    const recent = this.store.get(
      'SELECT created_at FROM otp_requests WHERE target = ? AND purpose = ? ORDER BY created_at DESC LIMIT 1', target, purpose,
    );
    if (recent && Date.now() - recent.created_at < this.config.otpResendSec * 1000) {
      throw tooMany(`Please wait before requesting another code`, Math.ceil((this.config.otpResendSec * 1000 - (Date.now() - recent.created_at)) / 1000));
    }
    const id = randomUUID();
    const code = this.config.fixedOtp || String(randomInt(0, 1_000_000)).padStart(6, '0');
    this.store.run(
      'INSERT INTO otp_requests(id, purpose, channel, target, user_id, code_hash, expires_at, context, created_at) VALUES (?,?,?,?,?,?,?,?,?)',
      id, purpose, channel, target, userId, this._hashOtp(id, code), Date.now() + this.config.otpTtlSec * 1000, JSON.stringify(context), Date.now(),
    );
    if (!this.config.devExposeOtp) {
      // Production: the code goes out through the configured provider. Never silently drop a code.
      if (!this.messenger?.canSendOtp(channel)) {
        throw new ApiError(501, 'OTP_PROVIDER_NOT_CONFIGURED', 'No OTP delivery provider is configured on this server');
      }
      // Sent in the background so a slow provider never holds the request; the person can ask again after the resend timer.
      this.messenger.sendOtp({ channel, to: target, code }).catch((e) => console.error(`[otp] ${channel} delivery failed (${purpose}): ${e.message}`));
      return { requestId: id, expiresIn: this.config.otpTtlSec, resendIn: this.config.otpResendSec };
    }
    console.log(`[otp:dev] ${purpose} via ${channel} -> ${target}: ${code}`);
    return { requestId: id, expiresIn: this.config.otpTtlSec, resendIn: this.config.otpResendSec, devOtp: code };
  }

  verifyOtp(requestId, code, purpose) {
    const row = this.store.get('SELECT * FROM otp_requests WHERE id = ? AND purpose = ?', String(requestId), purpose);
    if (!row || row.consumed) throw invalid('This code is no longer valid. Request a new one.');
    if (row.expires_at < Date.now()) throw invalid('This code has expired. Request a new one.');
    if (row.attempts >= this.config.otpMaxAttempts) throw tooMany('Too many incorrect attempts. Request a new code.');
    this.store.run('UPDATE otp_requests SET attempts = attempts + 1 WHERE id = ?', row.id);
    const expect = Buffer.from(row.code_hash, 'hex');
    const got = Buffer.from(this._hashOtp(row.id, String(code ?? '')), 'hex');
    if (expect.length !== got.length || !timingSafeEqual(expect, got)) throw invalid('OTP not valid. Enter 6 digit OTP');
    this.store.run('UPDATE otp_requests SET consumed = 1 WHERE id = ?', row.id);
    return { target: row.target, channel: row.channel, userId: row.user_id, context: JSON.parse(row.context) };
  }

  // ---- users --------------------------------------------------------------------------
  findUserByIdentifier({ phone, email }) {
    if (phone) return this.store.get('SELECT * FROM users WHERE phone = ?', phone) ?? null;
    if (email) return this.store.get('SELECT * FROM users WHERE email = ?', email) ?? null;
    return null;
  }

  createUser({ phone = null, email = null, name = '', language = 'en', timezone = null }) {
    const id = randomUUID();
    this.store.run(
      'INSERT INTO users(id, phone, email, name, language, timezone, phone_verified, email_verified, created_at) VALUES (?,?,?,?,?,?,?,?,?)',
      id, phone, email, name, language, timezone, phone ? 1 : 0, email ? 1 : 0, nowIso(),
    );
    return this.store.get('SELECT * FROM users WHERE id = ?', id);
  }
}
