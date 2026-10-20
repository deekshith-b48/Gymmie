// Authentication: HS256 access tokens, rotating refresh tokens, one-time passwords, role permissions.
import { createHash, createHmac, randomBytes, randomInt, timingSafeEqual, randomUUID } from 'node:crypto';
import { ApiError, forbidden, invalid, tooMany, unauthorized } from './errors.js';
import { nowIso } from './db.js';
import { maskPhone } from './ops.js';

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

  /** Same wording for every way a code can fail to work, so the answer never says whether a number or a request exists. */
  static NOT_VALID = 'This code is not valid or has expired. Request a new one.';

  // -- abuse guard: failures are counted per PHONE across all codes, so asking for a fresh code never resets the guesses --
  _guardRow(target) { return this.store.get('SELECT * FROM otp_guard WHERE target = ?', target); }

  /** Seconds the target is locked for (0 = not locked). */
  lockedFor(target) {
    const g = this._guardRow(target);
    return g && g.locked_until > Date.now() ? Math.ceil((g.locked_until - Date.now()) / 1000) : 0;
  }

  _recordFailure(target, ip) {
    const cfg = this.config.otpGuard;
    const now = Date.now();
    let g = this._guardRow(target);
    if (!g) {
      this.store.run('INSERT INTO otp_guard(target, fails, window_start, locked_until, level, last_fail) VALUES (?,?,?,?,?,?)', target, 0, now, 0, 0, now);
      g = this._guardRow(target);
    }
    let { fails, window_start: windowStart, level } = g;
    if (now - g.last_fail > cfg.levelResetSec * 1000) { level = 0; fails = 0; windowStart = now; }   // quiet for a day: forgiven
    if (now - windowStart > cfg.windowSec * 1000) { fails = 0; windowStart = now; }
    fails += 1;
    let lockedUntil = g.locked_until;
    if (fails >= cfg.failsBeforeLock) {
      level += 1;
      const secs = Math.min(cfg.lockMaxSec, cfg.lockBaseSec * 2 ** (level - 1));
      lockedUntil = now + secs * 1000;
      fails = 0;
      this.ops?.event('otp_lockout', { subject: maskPhone(target), ip, detail: { level, lockedSec: secs }, alert: level >= 3 });
    }
    this.store.run('UPDATE otp_guard SET fails = ?, window_start = ?, locked_until = ?, level = ?, last_fail = ? WHERE target = ?', fails, windowStart, lockedUntil, level, now, target);
    this._ipFailure(ip);
  }

  _ipFailure(ip) {
    if (!ip) return;
    this._ipFails ??= new Map();
    const now = Date.now();
    const arr = (this._ipFails.get(ip) ?? []).filter((t) => now - t < 10 * 60 * 1000);
    arr.push(now);
    this._ipFails.set(ip, arr);
    if (arr.length === Math.max(10, Math.round(25 * this.config.rateLimitScale))) this.ops?.event('otp_guessing_from_address', { ip, detail: { failuresIn10Min: arr.length } });
    if (this._ipFails.size > 5000) for (const [k, v] of this._ipFails) if (!v.some((t) => now - t < 10 * 60 * 1000)) this._ipFails.delete(k);
  }

  // -- sending budgets: a hard ceiling on what a code can cost, whoever asks -----------------------------------------------------
  _count(where, ...args) { return this.store.get(`SELECT COUNT(*) c FROM otp_requests WHERE ${where}`, ...args).c; }

  /** Returns the name of the first budget that is used up, or null. Only sms and whatsapp cost money. */
  _overBudget({ channel, target, userId, ip, scope }) {
    if (channel === 'email') return null;
    const b = this.config.sendBudget;
    const k = Math.max(1, this.config.rateLimitScale);
    const now = Date.now();
    const hour = now - 3600_000;
    const day = now - 86_400_000;
    const checks = [
      ['phone-hour', this._count('target = ? AND created_at > ?', target, hour), b.phonePerHour * k],
      ['phone-day', this._count('target = ? AND created_at > ?', target, day), b.phonePerDay * k],
      ...(ip ? [['address-hour', this._count('ip = ? AND created_at > ?', ip, hour), b.ipPerHour * k]] : []),
      ...(userId ? [['account-day', this._count('user_id = ? AND created_at > ?', userId, day), b.accountPerDay * k]] : []),
      ...(scope ? [['scope-day', this._count('scope = ? AND created_at > ?', scope, day), b.scopePerDay * k]] : []),
      ['global-hour', this._count('created_at > ?', hour), b.globalPerHour * k],
      ['global-day', this._count('created_at > ?', day), b.globalPerDay * k],
    ];
    for (const [name, used, max] of checks) {
      if (used >= max) return name;
      if (name.startsWith('global') && used + 1 >= Math.floor(max * 0.8) && used < Math.floor(max * 0.8)) this.ops?.event('sms_budget_80_percent', { detail: { budget: name, used: used + 1, max }, alert: true });
    }
    return null;
  }

  /**
   * Creates an OTP challenge. Delivery is the single integration point for an SMS / WhatsApp / email provider: without a configured
   * provider the dev backend only logs the code locally (never in production).
   *
   * When the phone is locked or a sending budget is used up, NOTHING is sent. On a public endpoint (`quiet`, the default) the answer
   * is still the normal-looking one, with a request id that can never verify, so an outsider cannot tell a locked or unknown number from
   * a working one; signed-in callers (`quiet: false`) get a plain "try later".
   */
  createOtp({ purpose, channel, target, userId = null, context = {}, ip = null, scope = null, quiet = true }) {
    const shape = (requestId, extra = {}) => ({ requestId, expiresIn: this.config.otpTtlSec, resendIn: this.config.otpResendSec, ...extra });
    const refuse = (kind, secs, detail) => {
      this.ops?.event(kind, { subject: maskPhone(target), ip, detail: { purpose, ...detail }, alert: kind === 'sms_budget_exhausted' && /global/.test(detail?.budget ?? '') });
      if (!quiet) throw tooMany('Too many codes were asked for. Please try again later.', secs);
      return shape(randomUUID(), { decoy: true });
    };
    const lock = this.lockedFor(target);
    if (lock) return refuse('otp_request_while_locked', lock, { lockedSec: lock });
    const over = this._overBudget({ channel, target, userId, ip, scope });
    if (over) return refuse('sms_budget_exhausted', 3600, { budget: over });

    const recent = this.store.get(
      'SELECT created_at FROM otp_requests WHERE target = ? AND purpose = ? ORDER BY created_at DESC LIMIT 1', target, purpose,
    );
    if (recent && Date.now() - recent.created_at < this.config.otpResendSec * 1000) {
      throw tooMany(`Please wait before requesting another code`, Math.ceil((this.config.otpResendSec * 1000 - (Date.now() - recent.created_at)) / 1000));
    }
    const id = randomUUID();
    const code = this.config.fixedOtp || String(randomInt(0, 1_000_000)).padStart(6, '0');
    this.store.run(
      'INSERT INTO otp_requests(id, purpose, channel, target, user_id, code_hash, expires_at, context, created_at, ip, scope) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
      id, purpose, channel, target, userId, this._hashOtp(id, code), Date.now() + this.config.otpTtlSec * 1000, JSON.stringify(context), Date.now(), ip, scope,
    );
    if (!this.config.devExposeOtp) {
      // Production: the code goes out through the configured provider. Never silently drop a code.
      if (!this.messenger?.canSendOtp(channel)) {
        throw new ApiError(501, 'OTP_PROVIDER_NOT_CONFIGURED', 'No OTP delivery provider is configured on this server');
      }
      // Sent in the background so a slow provider never holds the request; the person can ask again after the resend timer.
      this.messenger.sendOtp({ channel, to: target, code }).catch((e) => console.error(`[otp] ${channel} delivery failed (${purpose}): ${e.message}`));
      return shape(id);
    }
    console.log(`[otp:dev] ${purpose} via ${channel} -> ${target}: ${code}`);
    return shape(id, { devOtp: code });
  }

  verifyOtp(requestId, code, purpose, { ip = null } = {}) {
    const id = String(requestId ?? '');
    const row = this.store.get('SELECT * FROM otp_requests WHERE id = ? AND purpose = ?', id, purpose);
    if (!row || row.consumed || row.expires_at < Date.now()) {
      // An id that does not exist (a number that is not registered, a locked number, a made-up id) behaves exactly like a real one:
      // the same wording, and the same five tries before "too many".
      this._decoy ??= new Map();
      const n = (this._decoy.get(id) ?? 0) + 1;
      this._decoy.set(id, n);
      if (this._decoy.size > 20000) this._decoy.clear();
      this._ipFailure(ip);
      if (n > this.config.otpMaxAttempts) throw tooMany('Too many incorrect attempts. Request a new code.');
      throw invalid(AuthService.NOT_VALID);
    }
    const lock = this.lockedFor(row.target);
    if (lock) throw tooMany('Too many incorrect attempts. Try again later.', lock);
    if (row.attempts >= this.config.otpMaxAttempts) throw tooMany('Too many incorrect attempts. Request a new code.');
    this.store.run('UPDATE otp_requests SET attempts = attempts + 1 WHERE id = ?', row.id);
    const expect = Buffer.from(row.code_hash, 'hex');
    const got = Buffer.from(this._hashOtp(row.id, String(code ?? '')), 'hex');
    if (expect.length !== got.length || !timingSafeEqual(expect, got)) {
      this._recordFailure(row.target, ip);
      throw invalid(AuthService.NOT_VALID);
    }
    // consume atomically: of several simultaneous correct answers only one wins
    const won = this.store.run('UPDATE otp_requests SET consumed = 1 WHERE id = ? AND consumed = 0', row.id);
    if (won.changes === 0) throw invalid(AuthService.NOT_VALID);
    this.store.run('DELETE FROM otp_guard WHERE target = ?', row.target);
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
