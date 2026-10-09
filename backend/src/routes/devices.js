// Biometric ("Biohub") devices: management API (user auth) + device callback API (device-key auth).
// There is no physical device in this environment; devices (or scripts/simulate-device.js) call the callback API.
import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { S, validate } from '../validate.js';
import { conflict, forbidden, invalid, notFound, unauthorized } from '../errors.js';
import { created, noContent, raw } from '../http.js';
import { loadGym, toCsv } from '../helpers.js';
import { checkIn } from './attendance.js';
import { nowIso } from '../db.js';
import { inRange, monthEnd, monthStart } from '../domain/dates.js';
import { ApiError } from '../errors.js';

const sha = (s) => createHash('sha256').update(s).digest('hex');
const OFFLINE_AFTER_MS = 5 * 60 * 1000;

export function registerDeviceRoutes({ router, store }) {
  const view = (d) => {
    const { keyHash, ...rest } = d;
    const online = d.lastPingAt && Date.now() - Date.parse(d.lastPingAt) < OFFLINE_AFTER_MS;
    return { ...rest, status: d.lastPingAt ? (online ? 'connected' : 'offline') : 'unknown' };
  };
  const find = (ctx, id) => { const d = ctx.col('devices').get(id); if (!d) throw notFound('Device not found'); return d; };
  const DEV = {
    name: S.str({ required: true, min: 1, max: 60 }), serialNumber: S.str({ required: true, min: 3, max: 60 }),
    ip: S.str({ max: 45, pattern: /^(\d{1,3}\.){3}\d{1,3}$/, patternMessage: 'Enter IP address' }), type: S.oneOf(['face', 'fingerprint', 'both'], { default: 'both' }), location: S.str({ max: 80 }),
  };

  router.get('/v3/biohub/devices', { perm: 'devices.read' }, (ctx) => ctx.col('devices').all().map(view));
  router.get('/v3/biohub/devices/:id', { perm: 'devices.read' }, (ctx) => view(find(ctx, ctx.params.id)));
  router.post('/v3/biohub/devices', { perm: 'devices.write' }, (ctx) => {
    const b = validate(DEV, ctx.body);
    const taken = store.get(`SELECT 1 FROM docs WHERE collection = 'devices' AND deleted_at IS NULL AND json_extract(data, '$.serialNumber') = ?`, b.serialNumber);
    if (taken) throw conflict('This device is already registered');
    const key = randomBytes(24).toString('base64url');
    const d = ctx.col('devices').insert({ ...b, keyHash: sha(key), lastPingAt: null });
    // The device key is shown exactly once; the device stores it and sends it as x-device-key.
    return created({ ...view(d), deviceKey: key });
  });
  router.patch('/v3/biohub/devices/:id', { perm: 'devices.write' }, (ctx) => view(ctx.col('devices').update(find(ctx, ctx.params.id).id, validate(DEV, ctx.body, { partial: true }))));
  router.delete('/v3/biohub/devices/:id', { perm: 'devices.write' }, (ctx) => { find(ctx, ctx.params.id); ctx.col('devices').remove(ctx.params.id); return noContent(); });
  router.post('/v3/biohub/devices/:id/rotate-key', { perm: 'devices.write' }, (ctx) => {
    const d = find(ctx, ctx.params.id);
    const key = randomBytes(24).toString('base64url');
    ctx.col('devices').update(d.id, { keyHash: sha(key) });
    return { deviceKey: key };
  });

  router.post('/v5/biohub/force-sync', { perm: 'devices.write' }, (ctx) => {
    const devices = ctx.col('devices').all();
    if (!devices.length) throw invalid('Add a device first');
    for (const d of devices) ctx.col('devices').update(d.id, { lastSyncRequestedAt: nowIso() });
    return { requested: devices.length };
  });
  router.post('/v5/biohub/members/sync', { perm: 'devices.write' }, (ctx) => {
    let n = 0;
    for (const m of ctx.col('members').all()) { ctx.col('members').update(m.id, { biometricSyncedAt: nowIso() }); n++; }
    return { synced: n };
  });
  router.post('/v5/biohub/reset', { perm: 'devices.write' }, (ctx) => {
    for (const e of ctx.col('enrollments').all()) ctx.col('enrollments').remove(e.id);
    for (const m of ctx.col('members').all()) if (m.biometricSyncedAt) ctx.col('members').update(m.id, { biometricSyncedAt: undefined });
    return { reset: true };
  });

  router.post('/v5/biohub/member/:id/enroll', { perm: 'devices.write' }, (ctx) => {
    const m = ctx.col('members').get(ctx.params.id);
    if (!m) throw notFound('Member not found');
    const b = validate({ type: S.oneOf(['face', 'fingerprint'], { required: true }), deviceId: S.str({ required: true }) }, ctx.body);
    const d = find(ctx, b.deviceId);
    if (d.type !== 'both' && d.type !== b.type) throw invalid(`This device does not support ${b.type} enrolment`);
    return created(ctx.col('enrollments').insert({ memberId: m.id, deviceId: d.id, type: b.type, status: 'pending', requestedById: ctx.user.id }));
  });
  router.get('/v5/biohub/member/:id/enrollments', { perm: 'devices.read' }, (ctx) => ctx.col('enrollments').find((e) => e.memberId === ctx.params.id));
  router.post('/v5/biohub/member/:id/block', { perm: 'devices.write' }, (ctx) => {
    const m = ctx.col('members').get(ctx.params.id);
    if (!m) throw notFound('Member not found');
    return { biometricBlocked: !!ctx.col('members').update(m.id, { biometricBlocked: true }).biometricBlocked };
  });
  router.post('/v5/biohub/member/:id/unblock', { perm: 'devices.write' }, (ctx) => {
    const m = ctx.col('members').get(ctx.params.id);
    if (!m) throw notFound('Member not found');
    ctx.col('members').update(m.id, { biometricBlocked: false });
    return { biometricBlocked: false };
  });

  // ---- logs -----------------------------------------------------------------------------------------------------------------
  const logs = (ctx) => {
    const members = new Map(ctx.col('members').all().map((m) => [m.id, m]));
    const devs = new Map(ctx.col('devices').all().map((d) => [d.id, d]));
    const range = ctx.query.date ? { from: ctx.query.date, to: ctx.query.date } : ctx.query.from && ctx.query.to ? { from: ctx.query.from, to: ctx.query.to } : null;
    return ctx.col('biometricLogs').all().filter((l) => inRange(l.date, range)).filter((l) => !ctx.query.memberId || l.memberId === ctx.query.memberId)
      .map((l) => ({ ...l, member: members.get(l.memberId) ? { id: l.memberId, name: members.get(l.memberId).name } : null, deviceName: devs.get(l.deviceId)?.name ?? null }))
      .sort((a, b) => b.at.localeCompare(a.at));
  };
  router.get('/v5/biohub/logs', { perm: 'devices.read' }, (ctx) => logs(ctx));
  router.get('/v5/biohub/logs/calendar', { perm: 'devices.read' }, (ctx) => {
    const month = /^\d{4}-\d{2}$/.test(ctx.query.month ?? '') ? ctx.query.month : ctx.today().slice(0, 7);
    const r = { from: `${month}-01`, to: monthEnd(`${month}-01`) };
    const counts = {};
    for (const l of ctx.col('biometricLogs').all().filter((x) => inRange(x.date, r))) counts[l.date] = (counts[l.date] ?? 0) + 1;
    return { month, counts };
  });
  router.get('/v5/biohub/logs/export', { perm: 'devices.read' }, (ctx) => raw(200, 'text/csv; charset=utf-8', toCsv(logs(ctx), [
    { header: 'Time', value: (l) => l.at }, { header: 'Member', value: (l) => l.member?.name }, { header: 'Device', value: (l) => l.deviceName }, { header: 'Result', value: (l) => l.result }, { header: 'Reason', value: (l) => l.reason },
  ]), { 'content-disposition': `attachment; filename="biometric-logs-${ctx.today()}.csv"` }));

  // ---- device callback API (x-device-key) ----------------------------------------------------------------------------------
  function deviceCtx(ctx) {
    const key = ctx.req.headers['x-device-key'];
    if (typeof key !== 'string' || key.length < 16) throw unauthorized('Device key required');
    const row = store.get(`SELECT id, gym_id, data FROM docs WHERE collection = 'devices' AND deleted_at IS NULL AND json_extract(data, '$.keyHash') = ?`, sha(key));
    if (!row) throw unauthorized('Unknown device');
    const gym = loadGym(store, row.gym_id);
    const col = (n) => store.col(row.gym_id, n);
    const g = { store, gymId: row.gym_id, gym, col, user: null, today: () => new Date().toLocaleDateString('en-CA', { timeZone: gym.timezone }), role: 'device' };
    return { g, device: col('devices').get(row.id) };
  }
  router.post('/v5/biohub/device/heartbeat', { auth: 'none' }, (ctx) => {
    const { g, device } = deviceCtx(ctx);
    g.col('devices').update(device.id, { lastPingAt: nowIso() });
    return { ok: true, serverTime: nowIso(), syncRequested: !!device.lastSyncRequestedAt };
  });
  router.get('/v5/biohub/device/members', { auth: 'none' }, (ctx) => {
    const { g } = deviceCtx(ctx);
    return g.col('members').all().map((m) => ({ admissionNo: m.admissionNo, name: m.name, allowed: !m.blocked && !m.biometricBlocked }));
  });
  router.post('/v5/biohub/device/events', { auth: 'none' }, (ctx) => {
    const { g, device } = deviceCtx(ctx);
    const b = validate({ events: S.list(S.obj({ admissionNo: S.int({ required: true, min: 1 }), type: S.oneOf(['checkin', 'enroll'], { default: 'checkin' }), biometricType: S.oneOf(['face', 'fingerprint']), timestamp: S.dt() }), { required: true, min: 1, max: 200 }) }, ctx.body);
    g.col('devices').update(device.id, { lastPingAt: nowIso() });
    const results = [];
    for (const ev of b.events) {
      const member = g.col('members').findOne((m) => m.admissionNo === ev.admissionNo);
      const at = ev.timestamp ? new Date(ev.timestamp) : new Date();
      const log = { deviceId: device.id, memberId: member?.id ?? null, admissionNo: ev.admissionNo, type: ev.type, at: at.toISOString(), date: g.today() };
      if (!member) { g.col('biometricLogs').insert({ ...log, result: 'denied', reason: 'Member not found' }); results.push({ admissionNo: ev.admissionNo, result: 'denied', reason: 'Member not found' }); continue; }
      if (ev.type === 'enroll') {
        const e = g.col('enrollments').findOne((x) => x.memberId === member.id && x.deviceId === device.id && x.status === 'pending' && (!ev.biometricType || x.type === ev.biometricType));
        if (e) g.col('enrollments').update(e.id, { status: 'completed', completedAt: nowIso() });
        g.col('biometricLogs').insert({ ...log, result: e ? 'allowed' : 'denied', reason: e ? 'Enrolled successfully' : 'No pending enrolment' });
        results.push({ admissionNo: ev.admissionNo, result: e ? 'allowed' : 'denied' });
        continue;
      }
      try {
        if (member.biometricBlocked) throw forbidden('Biometric access blocked');
        checkIn(g, { memberId: member.id, source: 'biometric', at });
        g.col('biometricLogs').insert({ ...log, result: 'allowed', reason: null });
        results.push({ admissionNo: ev.admissionNo, result: 'allowed' });
      } catch (e) {
        if (!(e instanceof ApiError)) throw e;
        g.col('biometricLogs').insert({ ...log, result: 'denied', reason: e.message });
        results.push({ admissionNo: ev.admissionNo, result: 'denied', reason: e.message });
      }
    }
    return { results };
  });
}
