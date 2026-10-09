// Members: list/filter/sort, create (optionally with first membership), detail, health, labels, block, export.
import { S, validate } from '../validate.js';
import { conflict, forbidden, invalid, notFound } from '../errors.js';
import { created, noContent, raw } from '../http.js';
import { diffDays, monthStart, monthEnd, addDays } from '../domain/dates.js';
import { atRiskReasons, buildIndex, memberSummary } from '../domain/views.js';
import { membershipStatus, balanceOf } from '../domain/membership.js';
import { createMembership, PURCHASE_SCHEMA, view as membershipView } from './memberships.js';
import { storeFile } from './auth.js';
import { toCsv, FEATURE_CATALOG } from '../helpers.js';
import { sendAutomated } from '../domain/notify.js';
import { round2 } from '../domain/pricing.js';

export const BLOOD_GROUPS = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
export const HEALTH_CONDITIONS = [
  'High BP', 'Heart Problem', 'Diabetes', 'Asthma', 'Back Pain', 'Knee Pain', 'Neck Pain', 'Shoulder Pain', 'Hip Pain', 'Ankle Pain',
  'Joint Pain', 'Muscle Injury', 'Weak Bones', 'Fatty Liver', 'Immune Problem', 'Breathing Problem', 'Dizziness / balance', 'Chest pain',
  'Chronic Pain', 'Recent surgery / injury', 'Stroke History', 'Blood pressure meds', 'Family history',
];

const MEMBER = {
  name: S.str({ required: true, min: 2, max: 80 }),
  phone: S.phone({ required: true }),
  email: S.email(),
  gender: S.oneOf(['male', 'female', 'other']),
  birthDate: S.date(),
  bloodGroup: S.oneOf(BLOOD_GROUPS),
  address: S.str({ max: 250 }),
  notes: S.str({ max: 500 }),
  joinedAt: S.date(),
  labelIds: S.list(S.str({ max: 64 }), { max: 20 }),
  trainerId: S.str({ max: 64, nullable: true }),
  referredBy: S.str({ max: 64, nullable: true }),
  referralCode: S.str({ max: 40 }),
  heightCm: S.num({ min: 50, max: 260 }),
  weightKg: S.num({ min: 10, max: 500 }),
  emergencyContact: S.obj({ name: S.str({ max: 80 }), phone: S.phone() }),
  photo: S.obj({ data: S.str({ required: true, max: 8_000_000 }), contentType: S.str({ max: 60 }) }),
  idCard: S.obj({ data: S.str({ required: true, max: 8_000_000 }), contentType: S.str({ max: 60 }) }),
};

const SORTS = {
  nameAsc: (a, b) => a.name.localeCompare(b.name), nameDesc: (a, b) => b.name.localeCompare(a.name),
  joiningDateAsc: (a, b) => a.joinedAt.localeCompare(b.joinedAt), joiningDateDesc: (a, b) => b.joinedAt.localeCompare(a.joinedAt),
  admissionNoAsc: (a, b) => a.admissionNo - b.admissionNo, admissionNoDesc: (a, b) => b.admissionNo - a.admissionNo,
  membershipExpiryAsc: (a, b) => (a.membership?.endDate ?? '9999').localeCompare(b.membership?.endDate ?? '9999'),
  membershipExpiryDesc: (a, b) => (b.membership?.endDate ?? '').localeCompare(a.membership?.endDate ?? ''),
  createdAtAsc: (a, b) => a.createdAt.localeCompare(b.createdAt), createdAtDesc: (a, b) => b.createdAt.localeCompare(a.createdAt),
};

/** Status filter keys match the labels in the app's filter sheet. */
export function statusPredicate(status, query, idx, members) {
  const t = idx.today;
  const m = (s) => s.membership;
  const expiredAgo = (s) => (m(s) && m(s).status === 'expired' ? diffDays(m(s).endDate, t) : null);
  const left = (s) => (m(s) && ['active', 'paused'].includes(m(s).status) ? m(s).daysLeft : null);
  switch (status) {
    case 'active': return (s) => m(s)?.status === 'active';
    case 'upcoming': return (s) => m(s)?.status === 'upcoming';
    case 'paused': return (s) => m(s)?.status === 'paused';
    case 'expired': return (s) => ['expired', 'ended'].includes(m(s)?.status);
    case 'noMembership': return (s) => !m(s);
    case 'expiring10': return (s) => left(s) !== null && left(s) <= 10;
    case 'expiring30': return (s) => left(s) !== null && left(s) <= 30;
    case 'expiringCustom': { const d = Math.max(1, Math.min(365, parseInt(query.days ?? '15', 10) || 15)); return (s) => left(s) !== null && left(s) <= d; }
    case 'expiredIn10': return (s) => expiredAgo(s) !== null && expiredAgo(s) <= 10;
    case 'expiredIn30': return (s) => expiredAgo(s) !== null && expiredAgo(s) <= 30;
    case 'expiredBetween30and60': return (s) => expiredAgo(s) !== null && expiredAgo(s) > 30 && expiredAgo(s) <= 60;
    case 'expiredBetween60and90': return (s) => expiredAgo(s) !== null && expiredAgo(s) > 60 && expiredAgo(s) <= 90;
    case 'expiredBetween90and120': return (s) => expiredAgo(s) !== null && expiredAgo(s) > 90 && expiredAgo(s) <= 120;
    case 'withBalance': return (s) => s.balance > 0;
    case 'blocked': return (s) => s.blocked;
    case 'birthdayToday': return (s) => !!s.birthDate && s.birthDate.slice(5) === t.slice(5);
    case 'newThisMonth': return (s) => s.joinedAt >= monthStart(t) && s.joinedAt <= monthEnd(t);
    case 'atRisk': return (s) => atRiskIds(members, idx).has(s.id);
    default: return () => true;
  }
}

let _risk = new WeakMap();
function atRiskIds(members, idx) {
  if (_risk.has(idx)) return _risk.get(idx);
  const ids = new Set(members.filter((mm) => atRiskReasons(mm, idx).length).map((mm) => mm.id));
  _risk.set(idx, ids);
  return ids;
}

export function listMembers(ctx, { restrictTrainerId } = {}) {
  const idx = buildIndex(ctx);
  const q = (ctx.query.q ?? '').trim().toLowerCase();
  const labelIds = (ctx.query.labelIds ?? '').split(',').filter(Boolean);
  const raws = ctx.col('members').all();
  const items = raws
    .filter((mm) => (restrictTrainerId ? mm.trainerId === restrictTrainerId : true))
    .filter((mm) => !ctx.query.trainerId || mm.trainerId === ctx.query.trainerId)
    .filter((mm) => !ctx.query.gender || mm.gender === ctx.query.gender)
    .filter((mm) => !labelIds.length || labelIds.some((l) => mm.labelIds?.includes(l)))
    .filter((mm) => !q || mm.name.toLowerCase().includes(q) || mm.phone.replace(/\D/g, '').includes(q.replace(/\D/g, '') || '\u0000') || String(mm.admissionNo) === q)
    .map((mm) => memberSummary(mm, idx));
  const pred = statusPredicate(ctx.query.status ?? 'all', ctx.query, idx, raws);
  const filtered = items.filter(pred).filter((s) => !ctx.query.planId || s.membership?.planId === ctx.query.planId);
  filtered.sort(SORTS[ctx.query.sort] ?? SORTS.createdAtDesc);
  return { filtered, idx, raws };
}

export function registerMemberRoutes({ router, store }) {
  const findMember = (ctx, id) => {
    const m = ctx.col('members').get(id);
    if (!m) throw notFound('Member not found');
    return m;
  };
  // A trainer may only see members assigned to them.
  const assertVisible = (ctx, m) => {
    if (ctx.role === 'trainer' && m.trainerId !== ctx.user.id) throw forbidden('Member is not assigned to this trainer.');
  };
  const assertTrainer = (ctx, trainerId) => {
    if (!trainerId) return;
    // An invited trainer (has not signed in yet) is already part of the roster and may be assigned members.
    const row = ctx.store.get("SELECT role FROM gym_users WHERE gym_id = ? AND user_id = ? AND status IN ('active', 'invited')", ctx.gymId, trainerId);
    if (!row || row.role !== 'trainer') throw invalid('Signed-in user is not a trainer in this gym.');
  };
  const checkLabels = (ctx, ids) => {
    for (const id of ids ?? []) if (!ctx.col('tags').get(id)) throw invalid('Unknown label');
  };
  const phoneTaken = (ctx, phone, ignoreId) => ctx.col('members').findOne((m) => m.phone === phone && m.id !== ignoreId);

  router.get('/v5/members', { perm: 'members.read' }, (ctx) => {
    const { filtered } = listMembers(ctx, { restrictTrainerId: ctx.role === 'trainer' ? ctx.user.id : undefined });
    const page = Math.max(1, parseInt(ctx.query.page ?? '1', 10) || 1);
    const limit = Math.min(200, Math.max(1, parseInt(ctx.query.limit ?? '20', 10) || 20));
    return {
      __envelope: true, status: 200,
      body: { data: filtered.slice((page - 1) * limit, page * limit), meta: { page, limit, total: filtered.length, totalPages: Math.max(1, Math.ceil(filtered.length / limit)) } },
    };
  });

  router.post('/v5/members', { perm: 'members.write' }, (ctx) => {
    const b = validate({ ...MEMBER, membership: S.obj(PURCHASE_SCHEMA) }, ctx.body);
    if (phoneTaken(ctx, b.phone)) throw conflict('Member Contact Already Exists');
    const limit = ctx.gym.subscription?.limits?.members;
    if (limit && ctx.col('members').count() >= limit) throw forbidden('You are running out of limits for your membership plan');
    checkLabels(ctx, b.labelIds);
    assertTrainer(ctx, b.trainerId);
    if (b.referredBy && !ctx.col('members').get(b.referredBy)) throw invalid('Referral member not found');
    const { photo, idCard, membership, ...rest } = b;
    const doc = store.tx(() => {
      const patch = { ...rest, joinedAt: rest.joinedAt ?? ctx.today(), admissionNo: store.nextCounter(ctx.gymId, 'admission'), labelIds: rest.labelIds ?? [], blocked: false };
      if (photo) patch.photoFileId = storeFile(store, { gymId: ctx.gymId, ownerId: ctx.user.id, data: photo.data, declared: photo.contentType }).id;
      if (idCard) patch.idCardFileId = storeFile(store, { gymId: ctx.gymId, ownerId: ctx.user.id, data: idCard.data, declared: idCard.contentType }).id;
      const member = ctx.col('members').insert(patch);
      if (membership) createMembership(ctx, member.id, membership, { kind: 'new' });
      return member;
    });
    if (!membership) sendAutomated(ctx, 'MEMBER_ONBOARD_SMS', doc);
    const idx = buildIndex(ctx);
    return created(memberSummary(ctx.col('members').get(doc.id), idx));
  });

  router.get('/v5/members/export', { perm: 'members.read' }, (ctx) => {
    const { filtered } = listMembers(ctx);
    const csv = toCsv(filtered, [
      { header: 'Admission No', value: (m) => m.admissionNo }, { header: 'Name', value: (m) => m.name }, { header: 'Phone', value: (m) => m.phone },
      { header: 'Email', value: (m) => m.email }, { header: 'Gender', value: (m) => m.gender }, { header: 'Birth Date', value: (m) => m.birthDate },
      { header: 'Joined', value: (m) => m.joinedAt }, { header: 'Plan', value: (m) => m.membership?.planName }, { header: 'Status', value: (m) => m.membership?.status ?? 'none' },
      { header: 'Start', value: (m) => m.membership?.startDate }, { header: 'End', value: (m) => m.membership?.endDate }, { header: 'Balance', value: (m) => m.balance },
      { header: 'Blocked', value: (m) => (m.blocked ? 'yes' : 'no') }, { header: 'Last Attended', value: (m) => m.lastAttendedAt },
    ]);
    return raw(200, 'text/csv; charset=utf-8', csv, { 'content-disposition': `attachment; filename="members-${ctx.today()}.csv"` });
  });

  router.get('/v5/masters/health-conditions', { auth: 'none' }, () => HEALTH_CONDITIONS);

  router.get('/v5/members/:id', { perm: 'members.read' }, (ctx) => {
    const m = findMember(ctx, ctx.params.id);
    assertVisible(ctx, m);
    const idx = buildIndex(ctx);
    const memberships = (idx.byMember.get(m.id) ?? []).map((x) => membershipView(x, idx.today)).sort((a, b) => b.startDate.localeCompare(a.startDate));
    const txns = ctx.col('transactions').find((t) => t.memberId === m.id).sort((a, b) => b.createdAt.localeCompare(a.createdAt)).slice(0, 20);
    const visits = idx.visits.get(m.id) ?? [];
    const health = healthSummary(ctx, m);
    return {
      ...memberSummary(m, idx), address: m.address ?? null, notes: m.notes ?? null, emergencyContact: m.emergencyContact ?? null,
      referredBy: m.referredBy ?? null, idCardUrl: m.idCardFileId ? `/v5/files/${m.idCardFileId}` : null,
      memberships, recentTransactions: txns, health,
      attendance: { last30Days: visits.filter((d) => diffDays(d, idx.today) <= 29).length, total: visits.length, lastAttendedAt: idx.lastAttended.get(m.id) ?? null },
      atRisk: atRiskReasons(m, idx),
    };
  });

  router.patch('/v5/members/:id', { perm: 'members.write' }, (ctx) => {
    const m = findMember(ctx, ctx.params.id);
    const schema = { ...MEMBER };
    const b = validate(schema, ctx.body, { partial: true });
    if (b.phone && b.phone !== m.phone && phoneTaken(ctx, b.phone, m.id)) throw conflict('Member Contact Already Exists');
    if (b.labelIds) checkLabels(ctx, b.labelIds);
    if (b.trainerId) assertTrainer(ctx, b.trainerId);
    const { photo, idCard, ...rest } = b;
    const patch = { ...rest };
    if (photo) patch.photoFileId = storeFile(store, { gymId: ctx.gymId, ownerId: ctx.user.id, data: photo.data, declared: photo.contentType }).id;
    if (idCard) patch.idCardFileId = storeFile(store, { gymId: ctx.gymId, ownerId: ctx.user.id, data: idCard.data, declared: idCard.contentType }).id;
    if (b.trainerId === null) patch.trainerId = undefined;
    ctx.col('members').update(m.id, patch);
    return memberSummary(ctx.col('members').get(m.id), buildIndex(ctx));
  });

  router.delete('/v5/members/:id', { perm: 'settings.write' }, (ctx) => {
    findMember(ctx, ctx.params.id);
    ctx.col('members').remove(ctx.params.id);
    return noContent();
  });

  router.post('/v5/members/:id/block', { perm: 'members.write' }, (ctx) => {
    const m = findMember(ctx, ctx.params.id);
    const b = validate({ reason: S.str({ max: 200 }) }, ctx.body);
    ctx.col('members').update(m.id, { blocked: true, blockedReason: b.reason ?? null });
    return memberSummary(ctx.col('members').get(m.id), buildIndex(ctx));
  });
  router.post('/v5/members/:id/unblock', { perm: 'members.write' }, (ctx) => {
    const m = findMember(ctx, ctx.params.id);
    ctx.col('members').update(m.id, { blocked: false, blockedReason: undefined });
    return memberSummary(ctx.col('members').get(m.id), buildIndex(ctx));
  });

  router.put('/v5/members/:id/labels', { perm: 'members.write' }, (ctx) => {
    const m = findMember(ctx, ctx.params.id);
    const b = validate({ labelIds: S.list(S.str({ max: 64 }), { required: true, max: 20 }) }, ctx.body);
    checkLabels(ctx, b.labelIds);
    ctx.col('members').update(m.id, { labelIds: [...new Set(b.labelIds)] });
    return memberSummary(ctx.col('members').get(m.id), buildIndex(ctx));
  });

  router.put('/v5/members/:id/trainer', { perm: 'members.write' }, (ctx) => {
    const m = findMember(ctx, ctx.params.id);
    const b = validate({ trainerId: S.str({ nullable: true, required: true }) }, ctx.body);
    assertTrainer(ctx, b.trainerId);
    ctx.col('members').update(m.id, { trainerId: b.trainerId ?? undefined });
    return memberSummary(ctx.col('members').get(m.id), buildIndex(ctx));
  });

  // ---- health --------------------------------------------------------------------------------------
  function healthSummary(ctx, m) {
    const recs = ctx.col('health').find((r) => r.memberId === m.id).sort((a, b) => a.date.localeCompare(b.date) || a.createdAt.localeCompare(b.createdAt));
    const weights = recs.filter((r) => r.type === 'weight');
    const heights = recs.filter((r) => r.type === 'height');
    const weight = weights.at(-1)?.value ?? m.weightKg ?? null;
    const height = heights.at(-1)?.value ?? m.heightCm ?? null;
    const bmi = weight && height ? round2(weight / ((height / 100) ** 2)) : null;
    const bmiCategory = bmi === null ? null : bmi < 18.5 ? 'Underweight' : bmi < 25 ? 'Normal' : bmi < 30 ? 'Overweight' : 'Obese';
    return {
      weightKg: weight, heightCm: height, bmi, bmiCategory, weightTrend: weights.map((r) => ({ date: r.date, value: r.value })),
      conditions: ctx.col('conditions').find((c) => c.memberId === m.id), parqSignedAt: m.parqSignedAt ?? null,
    };
  }

  router.get('/v5/members/:id/health', { perm: 'members.read' }, (ctx) => {
    const m = findMember(ctx, ctx.params.id);
    assertVisible(ctx, m);
    return healthSummary(ctx, m);
  });
  router.post('/v5/members/:id/health', { perm: 'members.write' }, (ctx) => {
    const m = findMember(ctx, ctx.params.id);
    const b = validate({ type: S.oneOf(['weight', 'height'], { required: true }), value: S.num({ required: true, min: 1, max: 600 }), date: S.date() }, ctx.body);
    if (b.type === 'weight' && (b.value < 10 || b.value > 500)) throw invalid('Please enter a valid weight.');
    if (b.type === 'height' && (b.value < 50 || b.value > 260)) throw invalid('Please enter a valid height.');
    ctx.col('health').insert({ memberId: m.id, type: b.type, value: b.value, date: b.date ?? ctx.today() });
    return created(healthSummary(ctx, m));
  });
  router.post('/v5/members/:id/conditions', { perm: 'members.write' }, (ctx) => {
    const m = findMember(ctx, ctx.params.id);
    const b = validate({ name: S.str({ required: true, max: 80 }), notes: S.str({ max: 300 }) }, ctx.body);
    return created(ctx.col('conditions').insert({ memberId: m.id, ...b }));
  });
  router.patch('/v5/members/:id/conditions/:cid', { perm: 'members.write' }, (ctx) => {
    const c = ctx.col('conditions').get(ctx.params.cid);
    if (!c || c.memberId !== ctx.params.id) throw notFound('Condition not found');
    return ctx.col('conditions').update(c.id, validate({ name: S.str({ max: 80 }), notes: S.str({ max: 300 }) }, ctx.body, { partial: true }));
  });
  router.delete('/v5/members/:id/conditions/:cid', { perm: 'members.write' }, (ctx) => {
    const c = ctx.col('conditions').get(ctx.params.cid);
    if (!c || c.memberId !== ctx.params.id) throw notFound('Condition not found');
    ctx.col('conditions').remove(c.id);
    return noContent();
  });

  // ---- birthdays & at-risk (dashboard lists) --------------------------------------------------------
  router.get('/v5/members/insights/at-risk', { perm: 'members.read' }, (ctx) => {
    const idx = buildIndex(ctx);
    return ctx.col('members').all().map((m) => ({ m, reasons: atRiskReasons(m, idx) })).filter((x) => x.reasons.length)
      .map((x) => ({ ...memberSummary(x.m, idx), reasons: x.reasons }));
  });
}
