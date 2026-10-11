// Authentication, partner registration, self profile and file storage.
import { randomUUID } from 'node:crypto';
import { S, validate, normalizePhone } from '../validate.js';
import { conflict, forbidden, invalid, notFound, unauthorized, badRequest } from '../errors.js';
import { created, noContent, raw } from '../http.js';
import { nowIso } from '../db.js';
import {
  defaultFeatures, gymBrief, loadGym, newGymCode, publicUser, userGyms, saveGym, parseGym,
} from '../helpers.js';
import { COUNTRIES } from './config.js';
import { pendingTrial, startTrialIfDue } from '../domain/trial.js';
import { addDays, todayIn } from '../domain/dates.js';

const CHANNELS = ['sms', 'whatsapp', 'email'];
const MAX_FILE = 5 * 1024 * 1024; // "Max file size is 5MB"

function maskTarget(t) {
  if (t.includes('@')) { const [a, d] = t.split('@'); return `${a.slice(0, 2)}${'*'.repeat(Math.max(1, a.length - 2))}@${d}`; }
  return `${t.slice(0, 3)}${'*'.repeat(Math.max(0, t.length - 6))}${t.slice(-3)}`;
}

function sniffMime(buf) {
  if (buf.length >= 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'image/jpeg';
  if (buf.length >= 8 && buf.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'image/png';
  if (buf.length >= 12 && buf.subarray(0, 4).toString() === 'RIFF' && buf.subarray(8, 12).toString() === 'WEBP') return 'image/webp';
  if (buf.length >= 5 && buf.subarray(0, 5).toString() === '%PDF-') return 'application/pdf';
  return null;
}

export function storeFile(store, { gymId = null, ownerId, data, declared }) {
  if (typeof data !== 'string' || !data) throw invalid('data is required (base64)');
  const bytes = Buffer.from(data, 'base64');
  if (bytes.length === 0) throw invalid('File is empty');
  if (bytes.length > MAX_FILE) throw invalid('Max file size is 5MB');
  const mime = sniffMime(bytes);
  if (!mime) throw invalid('Unsupported file type. Upload a JPG, PNG, WebP or PDF.');
  if (declared && declared !== mime) throw invalid('File content does not match its declared type');
  const id = randomUUID();
  store.run('INSERT INTO files(id, gym_id, owner_id, mime, bytes, created_at) VALUES (?,?,?,?,?,?)', id, gymId, ownerId, mime, bytes, nowIso());
  return { id, url: `/v5/files/${id}`, mime, size: bytes.length };
}

export function registerAuthRoutes({ router, store, auth, config, limiter }) {
  const authBundle = (user, device) => {
    const tokens = auth.startSession(user.id, device);
    return { ...tokens, tokenType: 'Bearer', user: publicUser(user), gyms: userGyms(store, user.id) };
  };

  const identifier = (body) => {
    const b = validate({ phone: S.phone(), email: S.email(), channel: S.oneOf(CHANNELS) }, body);
    if (!!b.phone === !!b.email) throw invalid('Provide either a phone number or an email address');
    const channel = b.channel ?? (b.email ? 'email' : 'sms');
    if (b.email && channel !== 'email') throw invalid('Email codes can only be sent by email');
    if (b.phone && channel === 'email') throw invalid('Phone numbers cannot receive email codes');
    return { ...b, channel, target: b.phone ?? b.email };
  };

  // ---- login -----------------------------------------------------------------------------
  router.post('/v5/auth/login/otp', { auth: 'none' }, (ctx) => {
    const b = identifier(ctx.body);
    limiter.check(`otp-ip:${ctx.ip}`, 30, 600);
    limiter.check(`otp-target:${b.target}`, 6, 600);
    const user = auth.findUserByIdentifier(b);
    if (!user) throw notFound('No account found for this number. Sign up to get started.');
    if (user.disabled) throw forbidden('Your account is disabled.');
    const otp = auth.createOtp({ purpose: 'login', channel: b.channel, target: b.target, userId: user.id });
    return { ...otp, channel: b.channel, maskedTarget: maskTarget(b.target), devOtp: config.devExposeOtp ? otp.devOtp : undefined };
  });

  router.post('/v5/auth/login/otp/verify', { auth: 'none' }, (ctx) => {
    const b = validate({ requestId: S.str({ required: true }), otp: S.str({ required: true, min: 4, max: 8 }), device: S.str({ max: 120 }) }, ctx.body);
    limiter.check(`otpv-ip:${ctx.ip}`, 60, 600);
    const r = auth.verifyOtp(b.requestId, b.otp, 'login');
    const user = store.get('SELECT * FROM users WHERE id = ?', r.userId);
    if (!user || user.disabled) throw forbidden('Your account is disabled.');
    if (r.channel === 'email') store.run('UPDATE users SET email_verified = 1 WHERE id = ?', user.id);
    else store.run('UPDATE users SET phone_verified = 1 WHERE id = ?', user.id);
    // A successful sign-in accepts any pending staff invitations.
    store.run("UPDATE gym_users SET status = 'active' WHERE user_id = ? AND status = 'invited'", user.id);
    return authBundle(store.get('SELECT * FROM users WHERE id = ?', user.id), b.device);
  });

  router.post('/v5/auth/refresh', { auth: 'none' }, (ctx) => {
    const b = validate({ refreshToken: S.str({ required: true }), device: S.str({ max: 120 }) }, ctx.body);
    limiter.check(`refresh:${ctx.ip}`, 120, 600);
    return { ...auth.refresh(b.refreshToken, b.device), tokenType: 'Bearer' };
  });

  router.post('/v3/auth/logout', { auth: 'user' }, (ctx) => { auth.revokeSession(ctx.sessionId); return noContent(); });
  router.post('/v5/users/self/revoke-sessions', { auth: 'user' }, (ctx) => { auth.revokeAll(ctx.user.id); return noContent(); });

  // ---- partner registration ---------------------------------------------------------------
  router.post('/v5/register/partner', { auth: 'none' }, (ctx) => {
    const b = validate({
      name: S.str({ required: true, min: 2, max: 80 }), phone: S.phone({ required: true }), email: S.email(),
      referralCode: S.str({ max: 40 }), channel: S.oneOf(['sms', 'whatsapp']), consentVersion: S.str({ max: 24 }),
    }, ctx.body);
    limiter.check(`reg-ip:${ctx.ip}`, 10, 600);
    if (!/^[\p{L}\p{M} .'-]+$/u.test(b.name)) throw invalid('Name cannot contain special characters');
    if (auth.findUserByIdentifier({ phone: b.phone }) || (b.email && auth.findUserByIdentifier({ email: b.email }))) {
      throw conflict('Email or Phone is already used in another account');
    }
    const otp = auth.createOtp({
      purpose: 'register', channel: b.channel ?? 'sms', target: b.phone, context: { name: b.name, email: b.email ?? null, referralCode: b.referralCode ?? null, consentVersion: b.consentVersion ?? null },
    });
    return { ...otp, maskedTarget: maskTarget(b.phone) };
  });

  router.post('/v5/register/partner/verify', { auth: 'none' }, (ctx) => {
    const b = validate({ requestId: S.str({ required: true }), otp: S.str({ required: true, min: 4, max: 8 }) }, ctx.body);
    const r = auth.verifyOtp(b.requestId, b.otp, 'register');
    if (auth.findUserByIdentifier({ phone: r.target })) throw conflict('Email or Phone is already used in another account');
    const user = store.tx(() => auth.createUser({ phone: r.target, email: r.context.email, name: r.context.name }));
    store.run('UPDATE users SET email_verified = 0 WHERE id = ?', user.id);
    // what the person agreed to, and when (kept as evidence of consent)
    if (r.context.consentVersion) store.run('INSERT INTO consents(user_id, version, accepted_at, ip) VALUES (?,?,?,?)', user.id, r.context.consentVersion, nowIso(), ctx.ip);
    return { ...authBundle(store.get('SELECT * FROM users WHERE id = ?', user.id)), nextStep: 'gym', isNewUser: true };
  });

  router.post('/v5/register/partner/gym', { auth: 'user' }, (ctx) => {
    const b = validate({
      name: S.str({ required: true, min: 2, max: 80 }), address: S.str({ required: true, min: 5, max: 250 }),
      pincode: S.str({ pattern: /^[A-Za-z0-9 -]{4,10}$/, patternMessage: 'Please enter a valid pincode' }), city: S.str({ max: 80 }),
      state: S.str({ max: 80 }), country: S.str({ default: 'IN', max: 2 }), phone: S.phone(), email: S.email(),
      timezone: S.str({ max: 64 }), referralCode: S.str({ max: 40 }),
    }, ctx.body);
    const country = COUNTRIES.find((c) => c.code === b.country.toUpperCase()) ?? COUNTRIES[0];
    const dup = store.all(
      `SELECT g.data FROM gym_users gu JOIN gyms g ON g.id = gu.gym_id WHERE gu.user_id = ? AND gu.role = 'owner'`, ctx.user.id,
    ).some((r) => JSON.parse(r.data).name.toLowerCase() === b.name.toLowerCase());
    if (dup) throw conflict('Gym Already Registered');
    const gym = createGym(store, ctx.user, { ...b, country: country.code }, country);
    return created({ gym: gymBrief(store, gym, 'owner'), gyms: userGyms(store, ctx.user.id) });
  });

  router.post('/v5/register/partner/complete', { auth: 'gym', perm: 'settings.read' }, (ctx) => {
    saveGym(store, ctx.gymId, { onboardingCompleted: true });
    // Registration and setup are done: this is when the 14-day trial starts (once per owner, kept on the server).
    const gym = startTrialIfDue(store, ctx.gymId);
    return { onboardingCompleted: true, trial: gym.trial ?? null, subscription: gym.subscription ?? null };
  });

  // ---- profile ------------------------------------------------------------------------------
  router.get('/v5/users/self', { auth: 'user' }, (ctx) => ({ user: publicUser(ctx.user), gyms: userGyms(store, ctx.user.id) }));

  // ---- closing a staff / owner account ---------------------------------------------------------------------------------
  // A code to the person's own phone confirms it. The person's identity is erased (name, phone, email, photo, sign-ins) and
  // their access to every gym ends; records they created in a gym stay (they are the gym's books) but show no name.
  // An account that owns a gym cannot be closed here: closing the gym deletes the business's data, which support does
  // on request (scripts/admin.js delete-gym).
  const ownsGym = (userId) => store.all(
    `SELECT g.id, g.data FROM gym_users gu JOIN gyms g ON g.id = gu.gym_id WHERE gu.user_id = ? AND gu.role = 'owner' AND gu.status = 'active'`, userId,
  );
  router.post('/v5/users/self/delete-otp', { auth: 'user' }, (ctx) => {
    limiter.check(`udel:${ctx.user.id}`, 6, 600);
    const owned = ownsGym(ctx.user.id);
    if (owned.length) throw conflict(`You own ${JSON.parse(owned[0].data).name}. To close it and delete its data, contact support.`, { ownsGym: true });
    const channel = ctx.user.phone ? 'sms' : 'email';
    const target = ctx.user.phone ?? ctx.user.email;
    const otp = auth.createOtp({ purpose: 'user-delete', channel, target, userId: ctx.user.id });
    return { ...otp, channel, maskedTarget: maskTarget(target), devOtp: config.devExposeOtp ? otp.devOtp : undefined };
  });
  router.delete('/v5/users/self', { auth: 'user' }, (ctx) => {
    const b = validate({ requestId: S.str({ required: true }), otp: S.str({ required: true, min: 4, max: 8 }), confirm: S.str({ required: true, max: 10 }) }, ctx.body);
    limiter.check(`udelv:${ctx.user.id}`, 10, 600);
    if (b.confirm !== 'DELETE') throw invalid('Type DELETE to confirm.');
    const r = auth.verifyOtp(b.requestId, b.otp, 'user-delete');
    if (r.userId !== ctx.user.id) throw forbidden('This code was not requested for your account.');
    if (ownsGym(ctx.user.id).length) throw conflict('You own a gym. Contact support to close it first.');
    store.tx(() => {
      if (ctx.user.photo_file_id) store.run('DELETE FROM files WHERE id = ? AND owner_id = ?', ctx.user.photo_file_id, ctx.user.id);
      store.run('DELETE FROM gym_users WHERE user_id = ?', ctx.user.id);
      store.run("UPDATE users SET name = 'Deleted user', phone = NULL, email = NULL, photo_file_id = NULL, disabled = 1 WHERE id = ?", ctx.user.id);
      auth.revokeAll(ctx.user.id);
    });
    return noContent();
  });

  router.patch('/v5/users/self', { auth: 'user' }, (ctx) => {
    const b = validate({
      name: S.str({ min: 2, max: 80 }), language: S.oneOf(['en', 'hi', 'bn', 'gu', 'kn', 'mr', 'ta', 'te']),
      timezone: S.str({ max: 64 }),
    }, ctx.body, { partial: true });
    if (b.timezone) { try { new Intl.DateTimeFormat('en', { timeZone: b.timezone }); } catch { throw invalid('Unknown time zone'); } }
    const sets = Object.keys(b);
    if (sets.length) {
      store.run(`UPDATE users SET ${sets.map((k) => `${k} = ?`).join(', ')} WHERE id = ?`, ...sets.map((k) => b[k]), ctx.user.id);
    }
    return { user: publicUser(store.get('SELECT * FROM users WHERE id = ?', ctx.user.id)) };
  });

  // Contact verification (adds / changes the phone or email on the account).
  const contactOtp = (ctx) => {
    const b = validate({ channel: S.oneOf(CHANNELS, { required: true }), target: S.str({ required: true, max: 254 }) }, ctx.body);
    const target = b.channel === 'email' ? validate({ e: S.email({ required: true }) }, { e: b.target }).e : normalizePhone(b.target);
    if (!target) throw invalid('Please enter a valid phone number');
    const other = auth.findUserByIdentifier(b.channel === 'email' ? { email: target } : { phone: target });
    if (other && other.id !== ctx.user.id) throw conflict('Email or Phone is already used in another account');
    limiter.check(`contact-otp:${ctx.user.id}`, 6, 600);
    return { ...auth.createOtp({ purpose: 'verify-contact', channel: b.channel, target, userId: ctx.user.id }), maskedTarget: maskTarget(target) };
  };
  router.post('/v3/users/self/otp', { auth: 'user' }, contactOtp);
  router.post('/v3/users/self/email/verification', { auth: 'user' }, (ctx) => contactOtp({ ...ctx, body: { channel: 'email', target: ctx.body.email ?? ctx.user.email ?? '' } }));
  router.post('/v3/users/self/otp/verify', { auth: 'user' }, (ctx) => {
    const b = validate({ requestId: S.str({ required: true }), otp: S.str({ required: true, min: 4, max: 8 }) }, ctx.body);
    const r = auth.verifyOtp(b.requestId, b.otp, 'verify-contact');
    if (r.userId !== ctx.user.id) throw forbidden();
    const col = r.channel === 'email' ? 'email' : 'phone';
    const other = auth.findUserByIdentifier({ [col]: r.target });
    if (other && other.id !== ctx.user.id) throw conflict('Email or Phone is already used in another account');
    store.run(`UPDATE users SET ${col} = ?, ${col}_verified = 1 WHERE id = ?`, r.target, ctx.user.id);
    return { user: publicUser(store.get('SELECT * FROM users WHERE id = ?', ctx.user.id)) };
  });

  router.post('/v5/users/self/photo', { auth: 'user' }, (ctx) => {
    const b = validate({ data: S.str({ required: true, max: 8_000_000, allowEmpty: false }), contentType: S.str({ max: 60 }) }, ctx.body);
    const f = storeFile(store, { ownerId: ctx.user.id, data: b.data, declared: b.contentType });
    if (!f.mime.startsWith('image/')) throw invalid('Profile photo must be an image');
    store.run('UPDATE users SET photo_file_id = ? WHERE id = ?', f.id, ctx.user.id);
    return { user: publicUser(store.get('SELECT * FROM users WHERE id = ?', ctx.user.id)) };
  });
  router.delete('/v5/users/self/photo', { auth: 'user' }, (ctx) => {
    store.run('UPDATE users SET photo_file_id = NULL WHERE id = ?', ctx.user.id);
    return noContent();
  });

  // ---- files ---------------------------------------------------------------------------------
  router.post('/v5/files', { auth: 'gym' }, (ctx) => {
    const b = validate({ data: S.str({ required: true, max: 8_000_000 }), contentType: S.str({ max: 60 }) }, ctx.body);
    return created(storeFile(store, { gymId: ctx.gymId, ownerId: ctx.user.id, data: b.data, declared: b.contentType }));
  });

  router.get('/v5/files/:id', { auth: 'user' }, (ctx) => {
    const f = store.get('SELECT * FROM files WHERE id = ?', ctx.params.id);
    if (!f) throw notFound('Asset not found');
    const mine = f.owner_id === ctx.user.id
      || (f.gym_id && store.get("SELECT 1 FROM gym_users WHERE gym_id = ? AND user_id = ? AND status = 'active'", f.gym_id, ctx.user.id))
      // profile photos of people in a shared gym are visible to that gym's staff
      || store.get(
        `SELECT 1 FROM users u JOIN gym_users a ON a.user_id = u.id JOIN gym_users b ON b.gym_id = a.gym_id
         WHERE u.photo_file_id = ? AND b.user_id = ? AND b.status = 'active' LIMIT 1`, f.id, ctx.user.id);
    if (!mine) throw forbidden('You do not have access to this file');
    return raw(200, f.mime, Buffer.from(f.bytes), { 'cache-control': 'private, max-age=3600', 'content-disposition': 'inline' });
  });
}

export function createGym(store, user, b, country) {
  const id = randomUUID();
  const today = todayIn(b.timezone || country.timezone);
  const data = {
    name: b.name, address: b.address, pincode: b.pincode ?? null, city: b.city ?? null, state: b.state ?? null,
    country: country.code, phone: b.phone ?? user.phone ?? null, email: b.email ?? user.email ?? null,
    currencyCode: country.currencyCode, currencySymbol: country.currencySymbol,
    timezone: b.timezone || country.timezone, upiId: null, logoFileId: null,
    features: defaultFeatures(), preferences: { simpleMemberCard: false, renewalSound: false },
    paymentMethods: { active: ['cash', 'upi', 'debitCard', 'creditCard'], default: 'cash' },
    ...pendingTrial(today),
    whatsapp: { enabled: false, status: 'disconnected' }, creditBalance: 0, portalQrVersion: 1,
    onboardingCompleted: false, ownerId: user.id, referralCode: b.referralCode ?? null,
  };
  const code = newGymCode(store);
  store.tx(() => {
    store.run('INSERT INTO gyms(id, code, data, created_at, updated_at) VALUES (?,?,?,?,?)', id, code, JSON.stringify(data), nowIso(), nowIso());
    store.run('INSERT INTO gym_users(gym_id, user_id, role, status, profile, created_at) VALUES (?,?,?,?,?,?)', id, user.id, 'owner', 'active', '{}', nowIso());
  });
  return loadGym(store, id);
}
