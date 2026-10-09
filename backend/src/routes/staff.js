// Staff management, trainers' working hours and trainer session bookings.
import { S, validate } from '../validate.js';
import { conflict, forbidden, invalid, notFound } from '../errors.js';
import { created, noContent } from '../http.js';
import { ROLES } from '../auth.js';
import { publicUser } from '../helpers.js';
import { addDays, dayOfWeek, diffDays } from '../domain/dates.js';
import { currentMembership, sessionsLeft } from '../domain/membership.js';
import { nowIso } from '../db.js';
import { randomUUID } from 'node:crypto';

const TIME = /^([01]\d|2[0-3]):[0-5]\d$/;
const toMin = (t) => Number(t.slice(0, 2)) * 60 + Number(t.slice(3));

export function registerStaffRoutes({ router, store, auth, config }) {
  const staffRow = (ctx, r) => ({
    userId: r.id, name: r.name, phone: r.phone, email: r.email, role: r.role, status: r.status,
    photoUrl: r.photo_file_id ? `/v5/files/${r.photo_file_id}` : null, joinedAt: r.created_at,
    memberCount: r.role === 'trainer' ? ctx.col('members').count((m) => m.trainerId === r.id) : undefined,
  });
  const staffRows = (ctx) => store.all(
    `SELECT u.id, u.name, u.phone, u.email, u.photo_file_id, gu.role, gu.status, gu.created_at FROM gym_users gu JOIN users u ON u.id = gu.user_id
     WHERE gu.gym_id = ? ORDER BY gu.created_at`, ctx.gymId);
  const link = (ctx, userId) => store.get('SELECT * FROM gym_users WHERE gym_id = ? AND user_id = ?', ctx.gymId, userId);

  router.get('/v5/gyms/staffs', { perm: 'staff.read' }, (ctx) => staffRows(ctx).filter((r) => !ctx.query.role || r.role === ctx.query.role).map((r) => staffRow(ctx, r)));

  router.post('/v5/gyms/staffs', { perm: 'staff.write' }, (ctx) => {
    const b = validate({ name: S.str({ required: true, min: 2, max: 80 }), phone: S.phone({ required: true }), email: S.email(), role: S.oneOf(['manager', 'staff', 'trainer'], { required: true }) }, ctx.body);
    const limit = ctx.gym.subscription?.limits?.staff;
    if (limit && staffRows(ctx).length >= limit) throw forbidden('You are running out of limits for your membership plan');
    let user = auth.findUserByIdentifier({ phone: b.phone });
    if (user && link(ctx, user.id)) throw conflict('Email or Phone is already used in another account');
    if (b.email) {
      const e = auth.findUserByIdentifier({ email: b.email });
      if (e && (!user || e.id !== user.id)) throw conflict('Email or Phone is already used in another account');
    }
    store.tx(() => {
      if (!user) {
        user = auth.createUser({ phone: b.phone, email: b.email ?? null, name: b.name });
        // Contact details are unverified until the invited person signs in with an OTP.
        store.run('UPDATE users SET phone_verified = 0, email_verified = 0 WHERE id = ?', user.id);
      }
      store.run('INSERT INTO gym_users(gym_id, user_id, role, status, profile, created_at) VALUES (?,?,?,?,?,?)', ctx.gymId, user.id, b.role, 'invited', '{}', nowIso());
    });
    return created(staffRow(ctx, staffRows(ctx).find((r) => r.id === user.id)));
  });

  router.patch('/v5/gyms/staffs/:userId', { perm: 'staff.write' }, (ctx) => {
    const l = link(ctx, ctx.params.userId);
    if (!l) throw notFound('Staff not found');
    if (l.role === 'owner') throw forbidden('The owner cannot be modified here');
    const b = validate({ name: S.str({ min: 2, max: 80 }), role: S.oneOf(['manager', 'staff', 'trainer']), email: S.email() }, ctx.body, { partial: true });
    if (b.role && b.role !== l.role && l.role === 'trainer' && ctx.col('members').count((m) => m.trainerId === l.user_id) > 0) {
      throw conflict('Trainer cannot be deleted while members are assigned');
    }
    store.tx(() => {
      if (b.role) store.run('UPDATE gym_users SET role = ? WHERE gym_id = ? AND user_id = ?', b.role, ctx.gymId, l.user_id);
      if (b.name) store.run('UPDATE users SET name = ? WHERE id = ?', b.name, l.user_id);
      if (b.email) {
        const e = auth.findUserByIdentifier({ email: b.email });
        if (e && e.id !== l.user_id) throw conflict('Email or Phone is already used in another account');
        store.run('UPDATE users SET email = ? WHERE id = ?', b.email, l.user_id);
      }
    });
    return staffRow(ctx, staffRows(ctx).find((r) => r.id === l.user_id));
  });

  router.delete('/v5/gyms/staffs/:userId', { perm: 'staff.write' }, (ctx) => {
    const l = link(ctx, ctx.params.userId);
    if (!l) throw notFound('Staff not found');
    if (l.role === 'owner') throw forbidden('The owner cannot be removed');
    if (l.role === 'trainer' && ctx.col('members').count((m) => m.trainerId === l.user_id) > 0) throw conflict('Trainer cannot be deleted while members are assigned');
    store.run('DELETE FROM gym_users WHERE gym_id = ? AND user_id = ?', ctx.gymId, l.user_id);
    return noContent();
  });

  router.post('/v5/gyms/staffs/:userId/resend-invite', { perm: 'staff.write' }, (ctx) => {
    const l = link(ctx, ctx.params.userId);
    if (!l) throw notFound('Staff not found');
    if (l.status !== 'invited') throw invalid('This person has already accepted the invitation');
    // Delivery hook: with a provider configured this would resend the invite message.
    return { resent: true, status: l.status };
  });

  // ---- trainers -------------------------------------------------------------------------------------------------
  router.get('/v5/trainers', { perm: 'members.read' }, (ctx) => {
    const today = ctx.today();
    return staffRows(ctx).filter((r) => r.role === 'trainer' && r.status === 'active').map((r) => ({
      ...staffRow(ctx, r), todaysBookings: ctx.col('bookings').count((b) => b.trainerId === r.id && b.date === today && b.status === 'booked'),
    }));
  });

  const hoursSchema = S.list(S.obj({
    day: S.int({ required: true, min: 0, max: 6 }), enabled: S.bool({ required: true }),
    start: S.str({ pattern: TIME, patternMessage: 'must be HH:MM' }), end: S.str({ pattern: TIME, patternMessage: 'must be HH:MM' }),
  }), { required: true, min: 1, max: 7 });
  const defaultHours = () => Array.from({ length: 7 }, (_, day) => ({ day, enabled: false, start: '06:00', end: '21:00' }));
  const getHours = (ctx, trainerId) => {
    const doc = ctx.col('workHours').findOne((w) => w.trainerId === trainerId);
    const base = defaultHours();
    for (const d of doc?.days ?? []) base[d.day] = d;
    return { configured: !!doc, days: base };
  };
  const requireTrainer = (ctx, id) => {
    const l = link(ctx, id);
    if (!l || l.role !== 'trainer') throw notFound('Trainer not found');
    return l;
  };

  const saveHours = (ctx, trainerId) => {
    const b = validate({ days: hoursSchema }, ctx.body);
    for (const d of b.days) {
      if (d.enabled) {
        if (!d.start || !d.end) throw invalid('Set a start and end time for each enabled day');
        if (toMin(d.start) >= toMin(d.end)) throw invalid('End of working hours must be after the start');
      }
    }
    const merged = defaultHours();
    for (const d of b.days) merged[d.day] = { day: d.day, enabled: d.enabled, start: d.start ?? '06:00', end: d.end ?? '21:00' };
    const existing = ctx.col('workHours').findOne((w) => w.trainerId === trainerId);
    if (existing) ctx.col('workHours').update(existing.id, { days: merged });
    else ctx.col('workHours').insert({ trainerId, days: merged });
    return getHours(ctx, trainerId);
  };
  router.get('/v5/trainers/me/work-hours', { perm: 'trainer.self' }, (ctx) => getHours(ctx, ctx.user.id));
  router.put('/v5/trainers/me/work-hours', { perm: 'trainer.self' }, (ctx) => saveHours(ctx, ctx.user.id));
  router.get('/v5/trainers/:id/work-hours', { perm: 'members.read' }, (ctx) => { requireTrainer(ctx, ctx.params.id); return getHours(ctx, ctx.params.id); });

  // ---- bookings ----------------------------------------------------------------------------------------------------------
  const nowMinutes = (ctx) => {
    const parts = new Intl.DateTimeFormat('en-GB', { timeZone: ctx.gym.timezone, hour: '2-digit', minute: '2-digit', hour12: false }).formatToParts(new Date());
    return Number(parts.find((p) => p.type === 'hour').value) % 24 * 60 + Number(parts.find((p) => p.type === 'minute').value);
  };
  const SLOT = S.obj({ date: S.date({ required: true }), start: S.str({ required: true, pattern: TIME, patternMessage: 'must be HH:MM' }), end: S.str({ required: true, pattern: TIME, patternMessage: 'must be HH:MM' }) });

  const resolveTrainerId = (ctx, explicit) => {
    if (ctx.role === 'trainer') return ctx.user.id;
    if (!explicit) throw invalid('trainerId is required');
    requireTrainer(ctx, explicit);
    return explicit;
  };

  function checkSlots(ctx, trainerId, memberId, slots) {
    const member = ctx.col('members').get(memberId);
    if (!member) throw notFound('Member not found');
    if (member.trainerId !== trainerId) throw forbidden('Member is not assigned to this trainer.');
    const today = ctx.today();
    const cur = currentMembership(ctx.col('memberships').find((m) => m.memberId === memberId), today);
    const m = cur?.m;
    const hours = getHours(ctx, trainerId).days;
    const existing = ctx.col('bookings').find((b) => b.status === 'booked');
    const budget = m?.sessions ? sessionsLeft(m) - existing.filter((b) => b.memberId === memberId && (b.date > today || (b.date === today))).length : 0;
    const results = slots.map((s, i) => {
      const fail = (reason) => ({ ...s, ok: false, reason });
      if (toMin(s.start) >= toMin(s.end)) return fail('End of working hours must be after the start');
      if (toMin(s.end) - toMin(s.start) > 240) return fail('A session cannot be longer than 4 hours');
      if (s.date < today || (s.date === today && toMin(s.start) <= nowMinutes(ctx))) return fail("Selected slot is in the past or beyond the plan's end date.");
      if (!m || !m.sessions || ['expired', 'ended'].includes(cur.s)) return fail('Member has no active session plan with sessions left.');
      if (s.date > m.endDate) return fail("Selected slot is in the past or beyond the plan's end date.");
      const h = hours[dayOfWeek(s.date)];
      if (!h.enabled || toMin(s.start) < toMin(h.start) || toMin(s.end) > toMin(h.end)) return fail('Selected slot is outside your enabled working hours.');
      const overlap = (b) => b.date === s.date && toMin(s.start) < toMin(b.end) && toMin(b.start) < toMin(s.end);
      if (existing.some((b) => b.memberId === memberId && overlap(b))) return fail('Duplicate slot, or the member already holds that time.');
      if (existing.some((b) => b.trainerId === trainerId && overlap(b))) return fail('Already booked');
      if (slots.some((o, j) => j < i && o.date === s.date && toMin(s.start) < toMin(o.end) && toMin(o.start) < toMin(s.end))) return fail('Duplicate slot, or the member already holds that time.');
      return { ...s, ok: true };
    });
    const okCount = results.filter((r) => r.ok).length;
    const overBudget = okCount > Math.max(0, budget);
    return { results, budget: Math.max(0, budget), overBudget, membershipId: m?.id ?? null };
  }

  router.post('/v5/trainers/me/bookings/preview', { perm: ['trainer.self', 'trainers.write'] }, (ctx) => {
    const b = validate({ memberId: S.str({ required: true }), trainerId: S.str(), slots: S.list(SLOT, { required: true, min: 1, max: 30 }) }, ctx.body);
    const r = checkSlots(ctx, resolveTrainerId(ctx, b.trainerId), b.memberId, b.slots);
    return { ...r, valid: !r.overBudget && r.results.every((x) => x.ok), message: r.overBudget ? "More slots selected than member's available session budget." : null };
  });

  router.post('/v5/trainers/me/bookings', { perm: ['trainer.self', 'trainers.write'] }, (ctx) => {
    const b = validate({ memberId: S.str({ required: true }), trainerId: S.str(), slots: S.list(SLOT, { required: true, min: 1, max: 30 }) }, ctx.body);
    const trainerId = resolveTrainerId(ctx, b.trainerId);
    const r = checkSlots(ctx, trainerId, b.memberId, b.slots);
    const bad = r.results.find((x) => !x.ok);
    if (bad) throw invalid(bad.reason, { slots: r.results });
    if (r.overBudget) throw invalid("More slots selected than member's available session budget.");
    const docs = store.tx(() => b.slots.map((s) => ctx.col('bookings').insert({ trainerId, memberId: b.memberId, membershipId: r.membershipId, ...s, status: 'booked', createdById: ctx.user.id })));
    return created(docs);
  });

  const bookingView = (ctx, b, members) => ({ ...b, member: members.get(b.memberId) ? { id: b.memberId, name: members.get(b.memberId).name, phone: members.get(b.memberId).phone } : null });
  const listBookings = (ctx, trainerId) => {
    const members = new Map(ctx.col('members').all().map((m) => [m.id, m]));
    const date = ctx.query.date;
    return ctx.col('bookings').find((b) => b.trainerId === trainerId && b.status !== 'cancelled' && (!date || b.date === date)
      && (!ctx.query.from || b.date >= ctx.query.from) && (!ctx.query.to || b.date <= ctx.query.to) && (!ctx.query.memberId || b.memberId === ctx.query.memberId))
      .sort((a, b) => a.date.localeCompare(b.date) || a.start.localeCompare(b.start)).map((b) => bookingView(ctx, b, members));
  };
  router.get('/v5/trainers/me/bookings', { perm: 'trainer.self' }, (ctx) => listBookings(ctx, ctx.user.id));
  router.get('/v5/trainers/:id/bookings', { perm: 'members.read' }, (ctx) => { requireTrainer(ctx, ctx.params.id); return listBookings(ctx, ctx.params.id); });

  const cancel = (ctx, b) => {
    if (b.status === 'cancelled') throw conflict('Booking was already cancelled.');
    const started = b.date < ctx.today() || (b.date === ctx.today() && toMin(b.start) <= nowMinutes(ctx));
    if (started) throw invalid('Booking has already started and cannot be cancelled.');
    return ctx.col('bookings').update(b.id, { status: 'cancelled', cancelledAt: nowIso(), cancelledById: ctx.user.id });
  };
  router.delete('/v5/trainers/me/bookings/:id', { perm: ['trainer.self', 'trainers.write'] }, (ctx) => {
    const b = ctx.col('bookings').get(ctx.params.id);
    if (!b || (ctx.role === 'trainer' && b.trainerId !== ctx.user.id)) throw notFound('Booking not found');
    cancel(ctx, b);
    return noContent();
  });
  router.post('/v5/trainers/me/bookings/clear', { perm: ['trainer.self', 'trainers.write'] }, (ctx) => {
    const b = validate({ memberId: S.str({ required: true }) }, ctx.body);
    let n = 0;
    for (const bk of ctx.col('bookings').find((x) => x.memberId === b.memberId && x.status === 'booked' && (ctx.role !== 'trainer' || x.trainerId === ctx.user.id))) {
      try { cancel(ctx, bk); n++; } catch { /* already started: keep */ }
    }
    return { cancelled: n };
  });
}
