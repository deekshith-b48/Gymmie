// Attendance: manual, QR and biometric check-ins plus logs / summaries / export.
import { S, validate } from '../validate.js';
import { conflict, forbidden, invalid, notFound } from '../errors.js';
import { created, noContent, raw } from '../http.js';
import { addDays, dateOf, diffDays, inRange, periodRange } from '../domain/dates.js';
import { currentMembership } from '../domain/membership.js';
import { toCsv } from '../helpers.js';

/**
 * Shared check-in rules. `source` is manual | qr | biometric.
 * Returns the created attendance doc or throws a 4xx explaining why the check-in was refused.
 */
export function checkIn(ctx, { memberId, source = 'manual', at = new Date(), allowExpired = false }) {
  const member = ctx.col('members').get(memberId);
  if (!member) throw notFound('Member not found');
  if (member.blocked) throw forbidden('This member is blocked');
  const date = dateOf(at.toISOString(), ctx.gym.timezone);
  const mems = ctx.col('memberships').find((m) => m.memberId === memberId);
  const cur = currentMembership(mems, date);
  if (!allowExpired) {
    if (!cur) throw invalid('Member has no membership. Add a plan before marking attendance.');
    if (cur.s === 'paused') throw invalid('This membership is frozen');
    if (cur.s === 'upcoming') throw invalid(`Membership starts on ${cur.m.startDate}`);
    if (cur.s === 'expired' || cur.s === 'ended') throw invalid('Membership Expired');
  }
  const overdue = ctx.col('balanceReminders').findOne((r) => r.memberId === memberId && !r.done && r.reminderDate < date);
  if (overdue && source === 'biometric') throw forbidden('Device check-in was blocked because of an overdue balance reminder');
  const open = ctx.col('attendance').findOne((a) => a.kind === 'member' && a.memberId === memberId && a.date === date && !a.checkOut);
  if (open) throw conflict('Attendance already marked for today');
  return ctx.col('attendance').insert({ kind: 'member', memberId, date, checkIn: at.toISOString(), source, markedById: ctx.user?.id ?? null });
}

export function registerAttendanceRoutes({ router }) {
  const members = (ctx) => new Map(ctx.col('members').all().map((m) => [m.id, m]));
  const row = (a, mm) => ({
    ...a, member: a.memberId ? (mm.get(a.memberId) ? { id: a.memberId, name: mm.get(a.memberId).name, phone: mm.get(a.memberId).phone, photoUrl: mm.get(a.memberId).photoFileId ? `/v5/files/${mm.get(a.memberId).photoFileId}` : null } : null) : null,
  });

  function list(ctx) {
    const today = ctx.today();
    let range = ctx.query.period ? periodRange(ctx.query.period, today, { from: ctx.query.from, to: ctx.query.to }) : null;
    if (ctx.query.date) range = { from: ctx.query.date, to: ctx.query.date };
    else if (!range && ctx.query.from && ctx.query.to) range = { from: ctx.query.from, to: ctx.query.to };
    const mm = members(ctx);
    return ctx.col('attendance').all().filter((a) => inRange(a.date, range))
      .filter((a) => !ctx.query.memberId || a.memberId === ctx.query.memberId)
      .filter((a) => !ctx.query.source || a.source === ctx.query.source)
      .filter((a) => ctx.role !== 'trainer' || (a.memberId && mm.get(a.memberId)?.trainerId === ctx.user.id))
      .map((a) => row(a, mm)).sort((a, b) => b.checkIn.localeCompare(a.checkIn));
  }

  router.get('/v5/attendance', { perm: 'attendance.read' }, (ctx) => {
    const all = list(ctx);
    const page = Math.max(1, parseInt(ctx.query.page ?? '1', 10) || 1);
    const limit = Math.min(500, Math.max(1, parseInt(ctx.query.limit ?? '30', 10) || 30));
    return { __envelope: true, status: 200, body: { data: all.slice((page - 1) * limit, page * limit), meta: { page, limit, total: all.length, totalPages: Math.max(1, Math.ceil(all.length / limit)) } } };
  });

  router.get('/v5/attendance/export', { perm: 'attendance.read' }, (ctx) => raw(200, 'text/csv; charset=utf-8', toCsv(list(ctx), [
    { header: 'Date', value: (a) => a.date }, { header: 'Name', value: (a) => a.member?.name ?? a.guestName }, { header: 'Phone', value: (a) => a.member?.phone ?? a.guestPhone },
    { header: 'Check In', value: (a) => a.checkIn }, { header: 'Check Out', value: (a) => a.checkOut }, { header: 'Source', value: (a) => a.source },
  ]), { 'content-disposition': `attachment; filename="attendance-${ctx.today()}.csv"` }));

  // Daily counts for the dashboard chart (today / week / month).
  router.get('/v5/attendance/summary', { perm: 'attendance.read' }, (ctx) => {
    const today = ctx.today();
    const range = periodRange(ctx.query.period ?? 'thisWeek', today, { from: ctx.query.from, to: ctx.query.to }) ?? periodRange('thisWeek', today);
    const days = [];
    for (let d = range.from; d <= range.to && days.length < 400; d = addDays(d, 1)) days.push(d);
    const all = ctx.col('attendance').all().filter((a) => inRange(a.date, range));
    return {
      from: range.from, to: range.to, total: all.length,
      days: days.map((d) => ({ date: d, count: all.filter((a) => a.date === d).length, unique: new Set(all.filter((a) => a.date === d).map((a) => a.memberId ?? a.guestPhone)).size })),
    };
  });

  const MARK = {
    memberId: S.str({ required: true }), source: S.oneOf(['manual', 'qr'], { default: 'manual' }),
    at: S.dt(), allowExpired: S.bool({ default: false }),
  };
  router.post('/v5/attendance/mark', { perm: 'attendance.write' }, (ctx) => {
    const b = validate(MARK, ctx.body);
    const at = b.at ? new Date(b.at) : new Date();
    if (at.getTime() > Date.now() + 60_000) throw invalid('Selected date and time cannot be in the future.');
    if (b.allowExpired && !['owner', 'manager'].includes(ctx.role)) throw forbidden('Only a manager or owner can override an expired membership');
    return created(row(checkIn(ctx, { memberId: b.memberId, source: b.source, at, allowExpired: b.allowExpired }), members(ctx)));
  });

  // QR attendance: the scanned payload identifies the member and must belong to this gym.
  router.post('/v5/attendance/mark-by-qr', { perm: 'attendance.write' }, (ctx) => {
    const b = validate({ payload: S.str({ required: true, max: 300 }) }, ctx.body);
    const m = /^(?:gymmie|dgymbook):\/\/member\/(\d{6})\/([A-Za-z0-9-]{8,64})$/.exec(b.payload);
    if (!m) throw invalid('This QR code is not a Gymmie member code');
    if (m[1] !== ctx.gym.code) throw forbidden('This member belongs to a different gym');
    return created(row(checkIn(ctx, { memberId: m[2], source: 'qr' }), members(ctx)));
  });

  router.post('/v5/attendance/guest', { perm: 'attendance.write' }, (ctx) => {
    const b = validate({ guestName: S.str({ required: true, min: 2, max: 80 }), guestPhone: S.phone() }, ctx.body);
    return created(ctx.col('attendance').insert({ kind: 'guest', ...b, date: ctx.today(), checkIn: new Date().toISOString(), source: 'manual', markedById: ctx.user.id }));
  });

  router.post('/v5/attendance/:id/checkout', { perm: 'attendance.write' }, (ctx) => {
    const a = ctx.col('attendance').get(ctx.params.id);
    if (!a) throw notFound('Log not found');
    if (a.checkOut) throw conflict('Already checked out');
    return row(ctx.col('attendance').update(a.id, { checkOut: new Date().toISOString() }), members(ctx));
  });

  router.delete('/v5/attendance/:id', { perm: 'attendance.write' }, (ctx) => {
    if (!ctx.col('attendance').remove(ctx.params.id)) throw notFound('Log not found');
    return noContent();
  });
}
