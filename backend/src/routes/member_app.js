// Member app: gym members sign in (phone + OTP) and open the openGym training log.
//
// Everything under /v5/member/ is self-scoped: the member id comes from the session row (member_auth.js),
// never from the URL or body, and responses are built from explicit field whitelists (no staff notes,
// labels, block reasons or *ById fields).
import { randomUUID } from 'node:crypto';
import { S, validate } from '../validate.js';
import { ApiError, forbidden, invalid } from '../errors.js';
import { addDays, diffDays } from '../domain/dates.js';
import { balanceOf, currentMembership, daysLeft, membershipStatus, sessionsLeft } from '../domain/membership.js';
import {
  findMembersByPhone, makeSelectionToken, memberAllowed, readSelectionToken, revokeOpenGym, signOpenGymAssertion,
} from '../member_auth.js';
import { noContent } from '../http.js';

// The member's training log: one JSON document in openGym's own shape (so a log can be moved between
// the two), versioned for optimistic concurrency. Active (in-progress) workouts stay on the device.
const STATE_MAX = 2 * 1024 * 1024;
const isList = (v) => v == null || Array.isArray(v);

// The member's settings live inside the log document under openGym's own key names. Only the type and
// range of the keys this app reads are checked (enum values stay open: openGym and older apps may write
// others, and every reader falls back to a default for a value it does not know).
const SETTING_RULES = {
  unit: { t: 'string', max: 8 }, theme: { t: 'string', max: 16 }, accent: { t: 'string', max: 24 },
  accentCustom: { t: 'string', max: 7 }, body: { t: 'string', max: 16 }, heatmapMetric: { t: 'string', max: 16 },
  logRef: { t: 'string', max: 16 }, gifSize: { t: 'string', max: 16 }, startFrom: { t: 'string', max: 16 },
  oneRmFormula: { t: 'string', max: 24 }, effort: { t: 'string', max: 8, nullable: true },
  restSec: { t: 'number', min: 0, max: 3600 }, weekStart: { t: 'number', min: 0, max: 6 }, wdec: { t: 'number', min: 1, max: 3 },
  sound: { t: 'boolean' }, vibrate: { t: 'boolean' }, timerFlash: { t: 'boolean' }, keepAwake: { t: 'boolean' },
  weighIn: { t: 'boolean' }, collapseCompleted: { t: 'boolean' }, checkIn: { t: 'boolean' }, showWeightCard: { t: 'boolean' },
  connStatus: { t: 'boolean' }, equipFilterOn: { t: 'boolean' },
  equipProfiles: { t: 'list', max: 20 }, wc: { t: 'object' },
};

/** Throws a 422 naming the first setting that has the wrong type or is out of range. */
export function checkSettings(st) {
  for (const [key, rule] of Object.entries(SETTING_RULES)) {
    const v = st[key];
    if (v === undefined || (v === null && rule.nullable !== false)) continue;
    let ok = true;
    if (rule.t === 'string') ok = typeof v === 'string' && v.length <= rule.max;
    else if (rule.t === 'number') ok = typeof v === 'number' && Number.isFinite(v) && v >= rule.min && v <= rule.max;
    else if (rule.t === 'boolean') ok = typeof v === 'boolean';
    else if (rule.t === 'list') ok = Array.isArray(v) && v.length <= rule.max;
    else if (rule.t === 'object') ok = typeof v === 'object' && !Array.isArray(v);
    if (!ok) throw invalid(`Setting "${key}" has an invalid value`);
  }
}

const maskPhone = (t) => `${t.slice(0, 3)}${'*'.repeat(Math.max(0, t.length - 6))}${t.slice(-3)}`;

export function gymBriefForMember(g) {
  return {
    id: g.id, code: g.code, name: g.name, city: g.city ?? null, timezone: g.timezone,
    currencySymbol: g.currencySymbol, logoUrl: null,
  };
}

/** paid in full, part-paid, nothing paid yet, or nothing to pay. */
function paymentStatusOf(m) {
  const total = m.total ?? 0;
  if (total <= 0) return 'free';
  const left = balanceOf(m);
  if (left <= 0) return 'paid';
  return (m.amountReceived ?? 0) > 0 ? 'partial' : 'unpaid';
}

function memberView(ctx) {
  const { member, gym } = ctx;
  const today = ctx.today();
  const mine = ctx.col('memberships').find((m) => m.memberId === member.id);
  const cur = currentMembership(mine, today);
  const visits = ctx.col('attendance')
    .find((a) => (!a.kind || a.kind === 'member') && a.memberId === member.id)
    .map((a) => a.date);
  const trainer = member.trainerId ? ctx.store.get('SELECT name FROM users WHERE id = ?', member.trainerId) : null;
  return {
    member: {
      id: member.id, name: member.name, admissionNo: member.admissionNo ?? null, joinedAt: member.joinedAt ?? null,
      gender: member.gender ?? null,
    },
    gym: gymBriefForMember(gym),
    membership: cur ? {
      planName: cur.m.planName, startDate: cur.m.startDate, endDate: cur.m.endDate, status: cur.s,
      daysLeft: daysLeft(cur.m, today), sessionsLeft: sessionsLeft(cur.m), sessionsTotal: cur.m.sessions?.total ?? null,
      balance: balanceOf(cur.m),
    } : null,
    trainer: trainer ? { name: trainer.name } : null,
    visitsLast30: visits.filter((d) => diffDays(d, today) <= 29 && diffDays(d, today) >= 0).length,
    lastAttendedAt: visits.length ? visits.reduce((a, b) => (a > b ? a : b)) : null,
    // Where openGym serves exercise pictures from (null when the training log is not set up).
    // exercise pictures are only shown when the operator holds a licence for them (EXERCISE_MEDIA_LICENSED=1)
    mediaBase: ctx.config?.exerciseMediaLicensed ? (ctx.config?.openGym?.publicUrl || null) : null,
    // The code staff scan at the desk (same payload as the staff-side ID card).
    qrPayload: `gymmie://member/${gym.code}/${member.id}`,
  };
}

export function registerMemberAppRoutes({ router, store, auth, config, limiter, memberSessions }) {
  const bundle = (sess, gymId, memberId) => {
    const ok = memberAllowed(store, gymId, memberId, null);
    return {
      ...sess,
      member: { id: ok.member.id, name: ok.member.name },
      gym: gymBriefForMember(ok.gym),
    };
  };

  // ---- sign-in -----------------------------------------------------------------------------------------------------
  // Same answer whether or not the number belongs to a member, so this cannot be used to find out who is a member.
  router.post('/v5/member/auth/otp', { auth: 'none' }, (ctx) => {
    const b = validate({ phone: S.phone({ required: true }), gymCode: S.str({ max: 12 }) }, ctx.body);
    limiter.check(`motp-ip:${ctx.ip}`, 30, 600);
    limiter.check(`motp-phone:${b.phone}`, 6, 600);
    limiter.check(`motp-resend:${b.phone}`, 1, Math.max(1, config.otpResendSec));
    const candidates = findMembersByPhone(store, b.phone, b.gymCode);
    const shape = { expiresIn: config.otpTtlSec, resendIn: config.otpResendSec, maskedTarget: maskPhone(b.phone), channel: 'sms' };
    if (!candidates.length) return { requestId: randomUUID(), ...shape };
    const otp = auth.createOtp({ purpose: 'member-login', channel: 'sms', target: b.phone, context: { candidates } });
    return { ...shape, requestId: otp.requestId, devOtp: config.devExposeOtp ? otp.devOtp : undefined };
  });

  router.post('/v5/member/auth/otp/verify', { auth: 'none' }, (ctx) => {
    const b = validate({ requestId: S.str({ required: true }), otp: S.str({ required: true, min: 4, max: 8 }), device: S.str({ max: 120 }) }, ctx.body);
    limiter.check(`motpv-ip:${ctx.ip}`, 60, 600);
    const r = auth.verifyOtp(b.requestId, b.otp, 'member-login');
    // Re-judge each candidate now: it may have been blocked or removed since the code was sent.
    const live = (r.context.candidates ?? []).filter((c) => memberAllowed(store, c.gymId, c.memberId, r.target));
    if (!live.length) throw forbidden('Member access is not available for this number. Ask your gym.');
    if (live.length === 1) {
      const c = live[0];
      return bundle(memberSessions.start({ gymId: c.gymId, memberId: c.memberId, phone: r.target }, b.device), c.gymId, c.memberId);
    }
    const gyms = live.map((c) => {
      const ok = memberAllowed(store, c.gymId, c.memberId, r.target);
      return { id: c.gymId, code: ok.gym.code, name: ok.gym.name, city: ok.gym.city ?? null };
    });
    return {
      status: 'select_gym', gyms,
      selectionToken: makeSelectionToken(config.jwtSecret, { p: r.target, c: live }),
    };
  });

  router.post('/v5/member/auth/select-gym', { auth: 'none' }, (ctx) => {
    const b = validate({ selectionToken: S.str({ required: true, max: 4000 }), gymId: S.str({ required: true, max: 64 }), device: S.str({ max: 120 }) }, ctx.body);
    limiter.check(`motpv-ip:${ctx.ip}`, 60, 600);
    const t = readSelectionToken(config.jwtSecret, b.selectionToken);
    const c = (t.c ?? []).find((x) => x.gymId === b.gymId);
    if (!c || !memberAllowed(store, c.gymId, c.memberId, t.p)) throw forbidden('Member access is not available for this gym.');
    return bundle(memberSessions.start({ gymId: c.gymId, memberId: c.memberId, phone: t.p }, b.device), c.gymId, c.memberId);
  });

  router.post('/v5/member/auth/refresh', { auth: 'none' }, (ctx) => {
    const b = validate({ refreshToken: S.str({ required: true }), device: S.str({ max: 120 }) }, ctx.body);
    limiter.check(`mrefresh:${ctx.ip}`, 120, 600);
    return memberSessions.refresh(b.refreshToken, b.device);
  });

  router.post('/v5/member/auth/logout', { auth: 'member' }, (ctx) => {
    memberSessions.revokeSession(ctx.sessionId);
    // Leaving Gymmie also ends the openGym session so a shared phone does not keep it open.
    void revokeOpenGym(config, ctx.gymId, ctx.member.id);
    return noContent();
  });

  // "Sign out everywhere": every session this member has, on every phone. The openGym session ends too.
  router.post('/v5/member/auth/logout-all', { auth: 'member' }, (ctx) => {
    memberSessions.revokeMember(ctx.gymId, ctx.member.id);
    void revokeOpenGym(config, ctx.gymId, ctx.member.id);
    return noContent();
  });

  // ---- self service -------------------------------------------------------------------------------------------------
  router.get('/v5/member/me', { auth: 'member' }, (ctx) => memberView(ctx));


  // ---- what the member lets the gym send them --------------------------------------------------------------------------
  // Stored on the member's own record at the gym, so the owner sees it (member detail) and broadcasts honour it.
  // Account notices (renewal, balance, receipts) are not affected: they are part of the membership.
  const prefsView = (m) => ({ broadcasts: m.communication?.broadcasts !== false, updatedAt: m.communication?.updatedAt ?? null });
  router.get('/v5/member/me/preferences', { auth: 'member' }, (ctx) => prefsView(ctx.member));
  router.put('/v5/member/me/preferences', { auth: 'member' }, (ctx) => {
    limiter.check(`mprefs:${ctx.gymId}:${ctx.member.id}`, 60, 600);
    const b = validate({ broadcasts: S.bool({ required: true }) }, ctx.body);
    const communication = { ...(ctx.member.communication ?? {}), broadcasts: b.broadcasts, updatedAt: new Date().toISOString() };
    return prefsView(ctx.col('members').update(ctx.member.id, { communication }));
  });

  // ---- profile, attendance and the plans the gym assigned ------------------------------------------------------------
  // The member's own record at the gym: what staff would read out at the desk, without staff-only fields
  // (internal notes, labels, block reasons, who created what).
  router.get('/v5/member/me/profile', { auth: 'member' }, (ctx) => {
    const { member, gym } = ctx;
    const today = ctx.today();
    const trainer = member.trainerId ? ctx.store.get('SELECT name FROM users WHERE id = ?', member.trainerId) : null;
    const planById = new Map(ctx.col('plans').all().map((p) => [p.id, p]));
    const memberships = ctx.col('memberships').find((m) => m.memberId === member.id)
      .map((m) => ({
        id: m.id, planId: m.planId ?? null, planName: m.planName, startDate: m.startDate, endDate: m.endDate, status: membershipStatus(m, today),
        daysLeft: ['active', 'paused'].includes(membershipStatus(m, today)) ? diffDays(today, m.endDate) : null,
        sessionsLeft: sessionsLeft(m), sessionsTotal: m.sessions?.total ?? null,
        total: m.total ?? 0, amountReceived: m.amountReceived ?? 0, balance: balanceOf(m), invoiceNo: m.invoiceNo ?? null,
        paymentStatus: paymentStatusOf(m),
        benefits: planById.get(m.planId)?.benefits ?? [],
      }))
      .sort((a, b) => b.startDate.localeCompare(a.startDate)).slice(0, 24);
    const gymPlans = ctx.col('plans').find((p) => p.active !== false)
      
      .map((p) => ({ id: p.id, name: p.name, price: p.price, durationDays: p.durationDays, description: p.description ?? null, benefits: p.benefits ?? [], sessionsTotal: p.sessions?.enabled ? p.sessions.count : null }))
      .sort((a, b) => a.price - b.price);
    // The member's own payments and invoices (no staff notes, no who-recorded-it).
    const planOf = new Map(ctx.col('memberships').find((m) => m.memberId === member.id).map((m) => [m.id, m]));
    const payments = ctx.col('transactions').find((t) => t.memberId === member.id && t.kind !== 'writeoff')
      .sort((a, b) => (b.date ?? '').localeCompare(a.date ?? '') || (b.createdAt ?? '').localeCompare(a.createdAt ?? '')).slice(0, 50)
      .map((t) => ({ id: t.id, date: t.date ?? null, amount: t.amount, paymentType: t.paymentType ?? null, kind: t.kind ?? 'payment', invoiceNo: t.invoiceNo ?? null, planName: planOf.get(t.parentId)?.planName ?? null }));
    return {
      payments,
      member: {
        id: member.id, name: member.name, phone: member.phone, email: member.email ?? null, gender: member.gender ?? null,
        birthDate: member.birthDate ?? null, bloodGroup: member.bloodGroup ?? null, address: member.address ?? null,
        joinedAt: member.joinedAt ?? null, admissionNo: member.admissionNo ?? null, heightCm: member.heightCm ?? null,
        weightKg: member.weightKg ?? null, emergencyContact: member.emergencyContact ?? null,
      },
      gym: {
        name: gym.name, code: gym.code, address: gym.address ?? null, city: gym.city ?? null, state: gym.state ?? null,
        phone: gym.phone ?? null, email: gym.email ?? null, currencySymbol: gym.currencySymbol, timezone: gym.timezone,
        // what this gym has switched on that a member can use (read-only for members)
        features: { workoutPlans: !!gym.features?.WORKOUT_PLANS, dietPlans: !!gym.features?.DIET_PLANS },
      },
      trainer: trainer ? { name: trainer.name } : null,
      memberships, gymPlans,
    };
  });

  router.get('/v5/member/me/attendance', { auth: 'member' }, (ctx) => {
    const days = Math.max(7, Math.min(365, parseInt(ctx.query.days ?? '90', 10) || 90));
    const today = ctx.today();
    const mine = ctx.col('attendance').find((a) => (!a.kind || a.kind === 'member') && a.memberId === ctx.member.id);
    const dates = new Set(mine.map((a) => a.date));
    const visits = mine.filter((a) => diffDays(a.date, today) <= days - 1 && diffDays(a.date, today) >= 0)
      .sort((a, b) => b.checkIn.localeCompare(a.checkIn))
      .map((a) => ({ date: a.date, checkIn: a.checkIn, checkOut: a.checkOut ?? null, source: a.source ?? 'manual' }));
    // consecutive days with a visit, counting back from today (or yesterday if today has none yet)
    let streak = 0;
    let d = dates.has(today) ? today : addDays(today, -1);
    while (dates.has(d)) { streak++; d = addDays(d, -1); }
    return {
      days, visits, total: mine.length, last30: mine.filter((a) => diffDays(a.date, today) <= 29 && diffDays(a.date, today) >= 0).length,
      lastAttendedAt: mine.length ? mine.map((a) => a.date).sort().at(-1) : null, streakDays: streak,
    };
  });

  // The workout and diet plan the trainer assigned. Off (null) when the gym has that feature switched off.
  router.get('/v5/member/me/plans', { auth: 'member' }, (ctx) => {
    const pick = (coll, feature) => {
      if (!(ctx.gym.features?.[feature] ?? false)) return null;
      const p = ctx.col(coll).findOne((x) => x.ownerType === 'member' && x.memberId === ctx.member.id);
      if (!p) return null;
      const { createdById, sourceTemplateId, memberId, ownerType, ...rest } = p;
      return rest;
    };
    return { workout: pick('workoutPlans', 'WORKOUT_PLANS'), diet: pick('dietPlans', 'DIET_PLANS') };
  });

  // ---- training data ---------------------------------------------------------------------------------------------
  const stateRow = (ctx) => store.get('SELECT rev, wid, data FROM member_state WHERE gym_id = ? AND member_id = ?', ctx.gymId, ctx.member.id);

  router.get('/v5/member/data', { auth: 'member' }, (ctx) => {
    const r = stateRow(ctx);
    return r ? { rev: r.rev, wid: r.wid, state: JSON.parse(r.data) } : { rev: 0, wid: null, state: null };
  });

  router.put('/v5/member/data', { auth: 'member', maxBody: STATE_MAX + 64 * 1024 }, (ctx) => {
    limiter.check(`mdata:${ctx.gymId}:${ctx.member.id}`, 240, 600);
    const b = ctx.body ?? {};
    const st = b.state;
    if (!st || typeof st !== 'object' || Array.isArray(st) || !Object.keys(st).some((k) => k !== '_rev' && k !== '_wid' && k !== '_ts')) {
      throw invalid('state is required');
    }
    if (!isList(st.workouts) || !isList(st.routines)) throw invalid('workouts and routines must be lists');
    checkSettings(st);
    if (b.baseRev != null && !Number.isInteger(b.baseRev)) throw invalid('baseRev must be a whole number');
    delete st.active; // an unfinished workout never leaves the phone
    delete st._rev; delete st._wid; delete st._ts;
    const text = JSON.stringify(st);
    if (text.length > STATE_MAX) throw new ApiError(413, 'PAYLOAD_TOO_LARGE', 'Your training log is too large to sync');
    return store.tx(() => {
      const cur = stateRow(ctx);
      const curRev = cur?.rev ?? 0;
      if (b.baseRev != null && b.baseRev !== curRev) {
        throw new ApiError(409, 'CONFLICT', 'Your log changed on another device', {
          rev: curRev, wid: cur?.wid ?? null, state: cur ? JSON.parse(cur.data) : null,
        });
      }
      const wid = randomUUID();
      store.run(
        `INSERT INTO member_state(gym_id, member_id, rev, wid, data, updated_at) VALUES (?,?,?,?,?,?)
         ON CONFLICT(gym_id, member_id) DO UPDATE SET rev = excluded.rev, wid = excluded.wid, data = excluded.data, updated_at = excluded.updated_at`,
        ctx.gymId, ctx.member.id, curRev + 1, wid, text, new Date().toISOString(),
      );
      return { rev: curRev + 1, wid };
    });
  });

  // "Delete everything": the member's own log, nothing else.
  router.delete('/v5/member/data', { auth: 'member' }, (ctx) => {
    store.run('DELETE FROM member_state WHERE gym_id = ? AND member_id = ?', ctx.gymId, ctx.member.id);
    return noContent();
  });

  // ---- openGym launch -----------------------------------------------------------------------------------------------
  // Mints a 60-second, single-use assertion that openGym turns into its own session (member-app/opengym/api/sso.js).
  router.post('/v5/member/opengym/launch', { auth: 'member' }, (ctx) => {
    const og = config.openGym;
    if (!og?.publicUrl || !og.ssoSecret) throw new ApiError(501, 'OPENGYM_NOT_CONFIGURED', 'The training log is not set up on this server');
    limiter.check(`mlaunch:${ctx.gymId}:${ctx.member.id}`, 30, 600);
    const now = Date.now();
    const assertion = signOpenGymAssertion(og.ssoSecret, {
      gid: ctx.gymId, mid: ctx.member.id, name: ctx.member.name,
      iat: now, exp: now + 60_000, jti: randomUUID().replaceAll('-', ''),
    });
    return { url: og.publicUrl, redeemUrl: `${og.publicUrl}/api/sso/redeem`, assertion, expiresIn: 60 };
  });
}
