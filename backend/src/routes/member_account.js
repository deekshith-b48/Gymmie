// Member self-service beyond the training log: the member's own profile and photo, changing their phone number,
// their signed-in devices, closing their app account, membership requests, privacy and notification choices.
//
// Every route here is `auth: 'member'`. The member is always the one in the session row (member_auth.js): no id, role,
// gym, status or permission is ever read from the request. A field list below is what a member MAY change; everything
// else about the member record (membership, payments, trainer, labels, notes, block state, joining date) stays with the
// gym's staff, and the validator drops any key it does not know.
import { randomUUID } from 'node:crypto';
import { S, validate } from '../validate.js';
import { conflict, forbidden, invalid, notFound } from '../errors.js';
import { created, noContent, raw } from '../http.js';
import { diffDays } from '../domain/dates.js';
import { currentMembership } from '../domain/membership.js';
import { revokeOpenGym } from '../member_auth.js';
import { storeFile } from './auth.js';
import { nowIso } from '../db.js';
import { SHARE_LEVELS, TRAINER_FIELDS } from '../domain/privacy.js';

export const FITNESS_GOALS = ['lose_fat', 'build_muscle', 'get_stronger', 'stay_fit', 'endurance', 'flexibility', 'recovery'];
export const FITNESS_LEVELS = ['beginner', 'intermediate', 'advanced'];
export const REQUEST_TYPES = ['renew', 'change_plan', 'cancel'];
/** Messages the member cannot switch off: they are part of the account, the money, or its security. */
export const MANDATORY_NOTICES = [
  'Sign-in and verification codes',
  'Receipts, payments and balance reminders',
  'Changes the gym makes to your membership',
];

const PROFILE = {
  name: S.str({ min: 2, max: 80 }),
  email: S.email({ nullable: true }),
  gender: S.oneOf(['male', 'female', 'other'], { nullable: true }),
  birthDate: S.date({ nullable: true }),
  bloodGroup: S.oneOf(['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'], { nullable: true }),
  address: S.str({ max: 250, nullable: true }),
  emergencyContact: S.obj({ name: S.str({ max: 80 }), phone: S.phone() }, { nullable: true }),
  heightCm: S.num({ min: 50, max: 260, nullable: true }),
  weightKg: S.num({ min: 10, max: 500, nullable: true }),
  fitness: S.obj({
    goal: S.oneOf(FITNESS_GOALS, { nullable: true }),
    level: S.oneOf(FITNESS_LEVELS, { nullable: true }),
    daysPerWeek: S.int({ min: 1, max: 7, nullable: true }),
    notes: S.str({ max: 200, nullable: true }),
  }),
};

const maskPhone = (t) => `${t.slice(0, 3)}${'*'.repeat(Math.max(0, t.length - 6))}${t.slice(-3)}`;

export function ageOf(birthDate, today) {
  if (!birthDate) return null;
  const years = Math.floor(diffDays(birthDate, today) / 365.25);
  return years >= 0 ? years : null;
}

const privacyOf = (m) => ({
  trainerCanSee: Object.fromEntries(TRAINER_FIELDS.map((k) => [k, m.privacy?.trainerCanSee?.[k] !== false])),
  shareTraining: SHARE_LEVELS.includes(m.privacy?.shareTraining) ? m.privacy.shareTraining : 'off',
});

const notificationsOf = (m) => ({
  announcements: { on: m.communication?.broadcasts !== false },
  membershipExpiry: {
    on: m.notifications?.membershipExpiry?.on !== false,
    daysBefore: Math.min(30, Math.max(1, m.notifications?.membershipExpiry?.daysBefore ?? 7)),
  },
  mandatory: MANDATORY_NOTICES,
  updatedAt: m.notifications?.updatedAt ?? m.communication?.updatedAt ?? null,
});

export function registerMemberAccountRoutes({ router, store, auth, config, limiter, memberSessions }) {
  const fresh = (ctx) => ctx.col('members').get(ctx.member.id);

  // ---- own profile -----------------------------------------------------------------------------------------------------
  const accountView = (ctx) => {
    const m = fresh(ctx);
    return {
      id: m.id, name: m.name, phone: m.phone, email: m.email ?? null, gender: m.gender ?? null, birthDate: m.birthDate ?? null,
      age: ageOf(m.birthDate, ctx.today()), bloodGroup: m.bloodGroup ?? null, address: m.address ?? null,
      emergencyContact: m.emergencyContact ?? null, heightCm: m.heightCm ?? null, weightKg: m.weightKg ?? null,
      fitness: { goal: null, level: null, daysPerWeek: null, notes: null, ...(m.fitness ?? {}) },
      photoUrl: m.photoFileId ? '/v5/member/me/photo' : null, admissionNo: m.admissionNo ?? null, joinedAt: m.joinedAt ?? null,
      // what the member may change, so the app never guesses
      editable: ['name', 'email', 'gender', 'birthDate', 'bloodGroup', 'address', 'emergencyContact', 'heightCm', 'weightKg', 'fitness', 'photo'],
    };
  };

  router.get('/v5/member/me/account', { auth: 'member' }, (ctx) => accountView(ctx));

  router.patch('/v5/member/me/account', { auth: 'member' }, (ctx) => {
    limiter.check(`macct:${ctx.gymId}:${ctx.member.id}`, 60, 600);
    const b = validate(PROFILE, ctx.body, { partial: true });
    if (b.birthDate) {
      const age = ageOf(b.birthDate, ctx.today());
      if (age === null || age < 5 || age > 110) throw invalid('Please enter a valid date of birth.');
    }
    const m = fresh(ctx);
    const patch = {};
    for (const [k, v] of Object.entries(b)) {
      if (k === 'fitness') patch.fitness = Object.fromEntries(Object.entries({ ...(m.fitness ?? {}), ...v }).filter(([, x]) => x !== null && x !== undefined));
      else patch[k] = v === null ? undefined : v;
    }
    ctx.col('members').update(m.id, patch);
    return accountView(ctx);
  });

  // The photo is the same one staff see in the member list (photoFileId); the member reads it through their own route
  // because the file ACL for staff does not cover members.
  router.put('/v5/member/me/photo', { auth: 'member', maxBody: 9 * 1024 * 1024 }, (ctx) => {
    limiter.check(`mphoto:${ctx.gymId}:${ctx.member.id}`, 20, 600);
    const b = validate({ data: S.str({ required: true, max: 8_000_000 }), contentType: S.str({ max: 60 }) }, ctx.body);
    const f = storeFile(store, { gymId: ctx.gymId, ownerId: ctx.member.id, data: b.data, declared: b.contentType });
    if (!f.mime.startsWith('image/')) {
      store.run('DELETE FROM files WHERE id = ?', f.id);
      throw invalid('Your photo must be an image.');
    }
    const m = fresh(ctx);
    ctx.col('members').update(m.id, { photoFileId: f.id });
    if (m.photoFileId) store.run('DELETE FROM files WHERE id = ? AND gym_id = ? AND owner_id = ?', m.photoFileId, ctx.gymId, ctx.member.id);
    return accountView(ctx);
  });

  router.get('/v5/member/me/photo', { auth: 'member' }, (ctx) => {
    const id = fresh(ctx).photoFileId;
    const f = id ? store.get('SELECT * FROM files WHERE id = ? AND gym_id = ?', id, ctx.gymId) : null;
    if (!f) throw notFound('No photo');
    return raw(200, f.mime, Buffer.from(f.bytes), { 'cache-control': 'private, max-age=300', 'content-disposition': 'inline' });
  });

  router.delete('/v5/member/me/photo', { auth: 'member' }, (ctx) => {
    const m = fresh(ctx);
    if (m.photoFileId) {
      ctx.col('members').update(m.id, { photoFileId: undefined });
      store.run('DELETE FROM files WHERE id = ? AND gym_id = ? AND owner_id = ?', m.photoFileId, ctx.gymId, ctx.member.id);
    }
    return noContent();
  });

  // ---- changing the phone number ------------------------------------------------------------------------------------------
  // The phone is the member's sign-in, so the new number must be proven with a code sent to it. Same answer whether or not
  // the number is free, so this cannot be used to find out who else is a member.
  const phoneTaken = (ctx, phone) => !!ctx.col('members').findOne((x) => x.phone === phone && x.id !== ctx.member.id);

  router.post('/v5/member/me/phone/otp', { auth: 'member' }, (ctx) => {
    const b = validate({ phone: S.phone({ required: true }) }, ctx.body);
    limiter.check(`mphone:${ctx.gymId}:${ctx.member.id}`, 6, 600);
    limiter.check(`mphone-target:${b.phone}`, 6, 600);
    if (b.phone === ctx.member.phone) throw invalid('This is already your number.');
    const shape = { expiresIn: config.otpTtlSec, resendIn: config.otpResendSec, maskedTarget: maskPhone(b.phone), channel: 'sms' };
    if (phoneTaken(ctx, b.phone)) return { requestId: randomUUID(), ...shape };
    const otp = auth.createOtp({ purpose: 'member-phone', channel: 'sms', target: b.phone, context: { memberId: ctx.member.id, gymId: ctx.gymId } });
    return { ...shape, requestId: otp.requestId, devOtp: config.devExposeOtp ? otp.devOtp : undefined };
  });

  router.post('/v5/member/me/phone/verify', { auth: 'member' }, (ctx) => {
    const b = validate({ requestId: S.str({ required: true }), otp: S.str({ required: true, min: 4, max: 8 }) }, ctx.body);
    limiter.check(`mphonev:${ctx.gymId}:${ctx.member.id}`, 20, 600);
    const r = auth.verifyOtp(b.requestId, b.otp, 'member-phone');
    // A code asked for by someone else is not ours to use.
    if (r.context.memberId !== ctx.member.id || r.context.gymId !== ctx.gymId) throw forbidden('This code was not requested for your account.');
    if (phoneTaken(ctx, r.target)) throw conflict('This number cannot be used.');
    store.tx(() => {
      ctx.col('members').update(ctx.member.id, { phone: r.target });
      const mine = store.get('SELECT family_id FROM member_sessions WHERE id = ?', ctx.sessionId);
      // every other phone signed in under the old number is signed out; this one carries on under the new number
      store.run('UPDATE member_sessions SET revoked = 1 WHERE gym_id = ? AND member_id = ? AND family_id <> ?', ctx.gymId, ctx.member.id, mine.family_id);
      store.run('UPDATE member_sessions SET phone = ? WHERE family_id = ?', r.target, mine.family_id);
    });
    void revokeOpenGym(config, ctx.gymId, ctx.member.id);
    return { phone: r.target };
  });

  // ---- signed-in devices -----------------------------------------------------------------------------------------------------
  router.get('/v5/member/me/sessions', { auth: 'member' }, (ctx) => {
    const rows = store.all(
      'SELECT id, family_id, device, created_at, expires_at, revoked FROM member_sessions WHERE gym_id = ? AND member_id = ? ORDER BY created_at',
      ctx.gymId, ctx.member.id,
    );
    const mine = store.get('SELECT family_id FROM member_sessions WHERE id = ?', ctx.sessionId)?.family_id;
    const fam = new Map();
    for (const r of rows) {
      const f = fam.get(r.family_id) ?? { id: r.family_id, device: r.device ?? 'Unknown device', signedInAt: r.created_at, lastActiveAt: r.created_at, live: true };
      f.lastActiveAt = Math.max(f.lastActiveAt, r.created_at);
      if (r.device) f.device = r.device;
      if (r.revoked || r.expires_at < Date.now()) f.live = false;
      fam.set(r.family_id, f);
    }
    return [...fam.values()].filter((f) => f.live)
      .sort((a, b) => b.lastActiveAt - a.lastActiveAt)
      .map((f) => ({ id: f.id, device: f.device, signedInAt: new Date(f.signedInAt).toISOString(), lastActiveAt: new Date(f.lastActiveAt).toISOString(), current: f.id === mine }));
  });

  router.delete('/v5/member/me/sessions/:id', { auth: 'member' }, (ctx) => {
    // the id is a device of THIS member or it does not exist: another member's device is "not found", never "forbidden"
    const own = store.get('SELECT 1 AS x FROM member_sessions WHERE family_id = ? AND gym_id = ? AND member_id = ? LIMIT 1', ctx.params.id, ctx.gymId, ctx.member.id);
    if (!own) throw notFound('Session not found');
    store.run('UPDATE member_sessions SET revoked = 1 WHERE family_id = ? AND gym_id = ? AND member_id = ?', ctx.params.id, ctx.gymId, ctx.member.id);
    return noContent();
  });

  router.post('/v5/member/me/sessions/revoke-others', { auth: 'member' }, (ctx) => {
    const mine = store.get('SELECT family_id FROM member_sessions WHERE id = ?', ctx.sessionId).family_id;
    store.run('UPDATE member_sessions SET revoked = 1 WHERE gym_id = ? AND member_id = ? AND family_id <> ?', ctx.gymId, ctx.member.id, mine);
    return noContent();
  });

  // ---- closing the app account ---------------------------------------------------------------------------------------------------
  // Deleting the account is the member's right over their OWN data; it is not the gym's business records. So: the training
  // log, photo, contact and fitness details, preferences and sign-ins are erased and the member can no longer use the app, while
  // the gym keeps what it must (name, phone, memberships, payments and invoices, attendance, health records its staff entered).
  // The gym can switch the app back on for them. A fresh code sent to the member's own number confirms it.
  router.post('/v5/member/me/account/delete-otp', { auth: 'member' }, (ctx) => {
    limiter.check(`mdel:${ctx.gymId}:${ctx.member.id}`, 6, 600);
    const otp = auth.createOtp({ purpose: 'member-delete', channel: 'sms', target: ctx.member.phone, context: { memberId: ctx.member.id, gymId: ctx.gymId } });
    return { requestId: otp.requestId, expiresIn: config.otpTtlSec, resendIn: config.otpResendSec, maskedTarget: maskPhone(ctx.member.phone), channel: 'sms', devOtp: config.devExposeOtp ? otp.devOtp : undefined };
  });

  router.delete('/v5/member/me/account', { auth: 'member' }, (ctx) => {
    const b = validate({ requestId: S.str({ required: true }), otp: S.str({ required: true, min: 4, max: 8 }), confirm: S.str({ required: true, max: 10 }) }, ctx.body);
    limiter.check(`mdelv:${ctx.gymId}:${ctx.member.id}`, 10, 600);
    if (b.confirm !== 'DELETE') throw invalid('Type DELETE to confirm.');
    const r = auth.verifyOtp(b.requestId, b.otp, 'member-delete');
    if (r.context.memberId !== ctx.member.id || r.context.gymId !== ctx.gymId || r.target !== ctx.member.phone) throw forbidden('This code was not requested for your account.');
    store.tx(() => {
      const m = fresh(ctx);
      store.run('DELETE FROM member_state WHERE gym_id = ? AND member_id = ?', ctx.gymId, m.id);
      if (m.photoFileId) store.run('DELETE FROM files WHERE id = ? AND gym_id = ? AND owner_id = ?', m.photoFileId, ctx.gymId, m.id);
      ctx.col('members').update(m.id, {
        email: undefined, birthDate: undefined, gender: undefined, bloodGroup: undefined, address: undefined, emergencyContact: undefined,
        heightCm: undefined, weightKg: undefined, fitness: undefined, photoFileId: undefined, communication: undefined,
        privacy: undefined, notifications: undefined, appClosedAt: nowIso(), appClosedBy: 'member',
      });
      for (const q of ctx.col('membershipRequests').find((x) => x.memberId === m.id && x.status === 'pending')) {
        ctx.col('membershipRequests').update(q.id, { status: 'withdrawn', decidedAt: nowIso(), decisionNote: 'The member closed their app account.' });
      }
      memberSessions.revokeMember(ctx.gymId, m.id);
    });
    void revokeOpenGym(config, ctx.gymId, ctx.member.id);
    return noContent();
  });

  // ---- membership requests (the member asks; the gym decides) ------------------------------------------------------------------------
  const requestView = (q) => ({
    id: q.id, type: q.type, status: q.status, planName: q.planName ?? null, planPrice: q.planPrice ?? null, note: q.note ?? null,
    decisionNote: q.decisionNote ?? null, createdAt: q.createdAt, decidedAt: q.decidedAt ?? null,
  });

  router.get('/v5/member/me/requests', { auth: 'member' }, (ctx) =>
    ctx.col('membershipRequests').find((q) => q.memberId === ctx.member.id)
      .sort((a, b) => b.createdAt.localeCompare(a.createdAt)).slice(0, 50).map(requestView));

  router.post('/v5/member/me/requests', { auth: 'member' }, (ctx) => {
    limiter.check(`mreq:${ctx.gymId}:${ctx.member.id}`, 10, 24 * 3600);
    const b = validate({ type: S.oneOf(REQUEST_TYPES, { required: true }), planId: S.str({ max: 64 }), note: S.str({ max: 300 }) }, ctx.body);
    const today = ctx.today();
    const mine = ctx.col('memberships').find((m) => m.memberId === ctx.member.id);
    const cur = currentMembership(mine, today);
    const open = ctx.col('membershipRequests').findOne((q) => q.memberId === ctx.member.id && q.type === b.type && q.status === 'pending');
    if (open) throw conflict('You already have a pending request of this kind.');
    let plan = null;
    if (b.type === 'cancel') {
      if (!cur || !['active', 'upcoming', 'paused'].includes(cur.s)) throw conflict('You have no running membership to cancel.');
    } else {
      const planId = b.planId ?? (b.type === 'renew' ? cur?.m.planId : undefined);
      if (!planId) throw invalid('Choose a plan.');
      plan = ctx.col('plans').get(planId);
      if (!plan || plan.active === false) throw invalid('That plan is not available.');
      if (b.type === 'change_plan' && cur && cur.m.planId === plan.id) throw invalid('You are already on this plan.');
    }
    const doc = ctx.col('membershipRequests').insert({
      memberId: ctx.member.id, type: b.type, status: 'pending', planId: plan?.id, planName: plan?.name ?? cur?.m.planName ?? null, planPrice: plan?.price,
      membershipId: cur?.m.id, note: b.note ?? null,
    });
    return created(requestView(doc));
  });

  router.delete('/v5/member/me/requests/:id', { auth: 'member' }, (ctx) => {
    const q = ctx.col('membershipRequests').get(ctx.params.id);
    if (!q || q.memberId !== ctx.member.id) throw notFound('Request not found'); // someone else's id looks exactly like a missing one
    if (q.status !== 'pending') throw conflict('This request has already been decided.');
    ctx.col('membershipRequests').update(q.id, { status: 'withdrawn', decidedAt: nowIso() });
    return noContent();
  });

  // ---- privacy -----------------------------------------------------------------------------------------------------------------------
  router.get('/v5/member/me/privacy', { auth: 'member' }, (ctx) => privacyOf(fresh(ctx)));
  router.put('/v5/member/me/privacy', { auth: 'member' }, (ctx) => {
    limiter.check(`mpriv:${ctx.gymId}:${ctx.member.id}`, 60, 600);
    const b = validate({
      trainerCanSee: S.obj(Object.fromEntries(TRAINER_FIELDS.map((k) => [k, S.bool()]))),
      shareTraining: S.oneOf(SHARE_LEVELS),
    }, ctx.body, { partial: true });
    const m = fresh(ctx);
    const cur = privacyOf(m);
    const next = { trainerCanSee: { ...cur.trainerCanSee, ...(b.trainerCanSee ?? {}) }, shareTraining: b.shareTraining ?? cur.shareTraining, updatedAt: nowIso() };
    ctx.col('members').update(m.id, { privacy: next });
    return privacyOf(fresh(ctx));
  });

  // ---- notifications ---------------------------------------------------------------------------------------------------------------------
  // Optional notices can be switched off; the mandatory ones cannot (they are listed so the app can say so). Workout reminders
  // are on the phone itself (the log's `reminder` setting). Delivery is through the gym's own messaging (WhatsApp/SMS).
  router.get('/v5/member/me/notifications', { auth: 'member' }, (ctx) => notificationsOf(fresh(ctx)));
  router.put('/v5/member/me/notifications', { auth: 'member' }, (ctx) => {
    limiter.check(`mnotif:${ctx.gymId}:${ctx.member.id}`, 60, 600);
    const b = validate({
      announcements: S.obj({ on: S.bool({ required: true }) }),
      membershipExpiry: S.obj({ on: S.bool(), daysBefore: S.int({ min: 1, max: 30 }) }),
    }, ctx.body, { partial: true });
    const m = fresh(ctx);
    const cur = notificationsOf(m);
    const at = nowIso();
    const patch = {};
    if (b.announcements) patch.communication = { ...(m.communication ?? {}), broadcasts: b.announcements.on, updatedAt: at };
    if (b.membershipExpiry) {
      patch.notifications = { ...(m.notifications ?? {}), membershipExpiry: { on: b.membershipExpiry.on ?? cur.membershipExpiry.on, daysBefore: b.membershipExpiry.daysBefore ?? cur.membershipExpiry.daysBefore }, updatedAt: at };
    }
    if (Object.keys(patch).length) ctx.col('members').update(m.id, patch);
    return notificationsOf(fresh(ctx));
  });
}

