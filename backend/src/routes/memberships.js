// Memberships: purchase / renew / upgrade / extend / freeze / end + session-based plans.
import { randomUUID } from 'node:crypto';
import { S, validate } from '../validate.js';
import { conflict, forbidden, invalid, notFound } from '../errors.js';
import { created } from '../http.js';
import { addDays, diffDays } from '../domain/dates.js';
import { quote, checkReceived, round2 } from '../domain/pricing.js';
import {
  balanceOf, currentMembership, endDateFor, membershipStatus, overlaps, sessionsLeft,
} from '../domain/membership.js';
import { defaultTax, nextInvoiceNo, normalisePayments, recordPayments } from '../domain/ledger.js';
import { PAYMENT_TYPES } from '../helpers.js';
import { sendAutomated } from '../domain/notify.js';

const DISCOUNT = S.obj({ type: S.oneOf(['amount', 'percent'], { default: 'amount' }), value: S.num({ required: true, min: 0, max: 10_000_000 }) });
const PAYMENT = S.obj({ paymentType: S.oneOf(PAYMENT_TYPES, { required: true }), amount: S.num({ required: true, min: 0.01, max: 10_000_000 }) });

export const PURCHASE_SCHEMA = {
  planId: S.str({ required: true, max: 64 }),
  startDate: S.date(),
  discount: DISCOUNT,
  payments: S.list(PAYMENT, { max: 5 }),
  amountReceived: S.num({ min: 0, max: 10_000_000 }),
  paymentType: S.oneOf(PAYMENT_TYPES),
  notes: S.str({ max: 500 }),
  kind: S.oneOf(['new', 'renewal', 'upcoming'], { default: 'new' }),
};

export const view = (m, today) => ({
  ...m, status: membershipStatus(m, today), balance: balanceOf(m), sessionsLeft: sessionsLeft(m),
  daysLeft: ['active', 'paused'].includes(membershipStatus(m, today)) ? diffDays(today, m.endDate) : null,
});

/** Core purchase flow, shared by POST /v5/memberships, member creation and upgrades. */
export function createMembership(ctx, memberId, input, { kind, previousMembershipId = null, skipOverlap = false } = {}) {
  const member = ctx.col('members').get(memberId);
  if (!member) throw notFound('Member not found');
  const plan = ctx.col('plans').get(input.planId);
  if (!plan) throw invalid('Please select a plan');
  if (plan.active === false) throw invalid('This plan is disabled. Enable it to sell it.');
  const today = ctx.today();
  const existing = ctx.col('memberships').find((m) => m.memberId === memberId);
  const live = existing.filter((m) => !m.endedAt);
  const lastEnd = live.reduce((acc, m) => (m.endDate > acc ? m.endDate : acc), '');
  let startDate = input.startDate;
  const eff = kind ?? input.kind ?? 'new';
  if (!startDate) startDate = lastEnd && lastEnd >= today ? addDays(lastEnd, 1) : today;
  if (eff === 'upcoming' && !live.some((m) => m.endDate >= today)) {
    throw invalid('Member has no running membership. Add a new membership instead.');
  }
  const endDate = endDateFor(startDate, plan.durationDays);
  if (!skipOverlap) {
    const clash = overlaps(existing, startDate, endDate);
    if (clash) throw conflict(`Membership overlaps with ${clash.planName} (${clash.startDate} to ${clash.endDate}). Choose a later start date.`);
  }
  const q = quote({ price: plan.price, discount: input.discount ? { type: input.discount.type ?? 'amount', value: input.discount.value } : null, tax: defaultTax(ctx) });
  const payments = normalisePayments(ctx, input);
  const paid = round2(payments.reduce((s, p) => s + p.amount, 0));
  checkReceived(paid, q.total);
  const invoiceNo = nextInvoiceNo(ctx);
  const doc = ctx.col('memberships').insert({
    memberId, planId: plan.id, planName: plan.name, planPrice: plan.price, durationDays: plan.durationDays,
    sessions: plan.sessions?.count ? { total: plan.sessions.count } : null, sessionLogs: [],
    startDate, endDate, kind: eff, previousMembershipId, discount: { type: q.discountType, value: q.discountValue, amount: q.discountAmount },
    tax: { name: q.taxName, rate: q.taxRate, included: q.taxIncluded, amount: q.taxAmount, taxableValue: q.taxableValue },
    subtotal: q.price, total: q.total, amountReceived: 0, writtenOff: 0, pausedDays: 0, extensions: [], notes: input.notes ?? null,
    invoiceNo, createdById: ctx.user.id,
  });
  recordPayments(ctx, { kind: 'membership', parentCollection: 'memberships', parent: doc, memberId, payments, date: today, invoiceNo });
  const fresh = ctx.col('memberships').get(doc.id);
  const isFirst = existing.length === 0;
  sendAutomated(ctx, isFirst ? 'MEMBER_WELCOME_SMS' : 'MEMBERSHIP_RENEWAL_SUCCESS_SMS', member, { planName: plan.name, endDate, invoiceNo, amount: paid });
  return fresh;
}

export function registerMembershipRoutes({ router }) {
  const find = (ctx, id) => {
    const m = ctx.col('memberships').get(id);
    if (!m) throw notFound('Membership not found');
    return m;
  };
  const notifyMember = (ctx, m, key, vars = {}) => {
    const member = ctx.col('members').get(m.memberId);
    sendAutomated(ctx, key, member, { planName: m.planName, endDate: m.endDate, ...vars });
  };

  router.get('/v5/memberships', { perm: 'members.read' }, (ctx) => {
    const today = ctx.today();
    return ctx.col('memberships').find((m) => (!ctx.query.memberId || m.memberId === ctx.query.memberId))
      .map((m) => view(m, today)).filter((m) => !ctx.query.status || m.status === ctx.query.status)
      .sort((a, b) => b.startDate.localeCompare(a.startDate));
  });

  router.get('/v5/memberships/:id', { perm: 'members.read' }, (ctx) => view(find(ctx, ctx.params.id), ctx.today()));

  // Pricing preview used by the renew/add-membership screens ("Price Breakdown", "Tax Breakdown").
  router.post('/v5/memberships/quote', { perm: 'members.read' }, (ctx) => {
    const b = validate({ planId: S.str({ required: true }), discount: DISCOUNT, memberId: S.str(), startDate: S.date() }, ctx.body);
    const plan = ctx.col('plans').get(b.planId);
    if (!plan) throw invalid('Please select a plan');
    const q = quote({ price: plan.price, discount: b.discount ? { type: b.discount.type ?? 'amount', value: b.discount.value } : null, tax: defaultTax(ctx) });
    let startDate = b.startDate;
    if (!startDate && b.memberId) {
      const lastEnd = ctx.col('memberships').find((m) => m.memberId === b.memberId && !m.endedAt).reduce((a, m) => (m.endDate > a ? m.endDate : a), '');
      startDate = lastEnd && lastEnd >= ctx.today() ? addDays(lastEnd, 1) : ctx.today();
    }
    startDate ??= ctx.today();
    return { ...q, startDate, endDate: endDateFor(startDate, plan.durationDays), plan: { id: plan.id, name: plan.name, durationDays: plan.durationDays, sessions: plan.sessions ?? null } };
  });

  router.post('/v5/memberships', { perm: 'members.write' }, (ctx) => {
    const b = validate({ memberId: S.str({ required: true }), ...PURCHASE_SCHEMA }, ctx.body);
    const doc = ctx.store.tx(() => createMembership(ctx, b.memberId, b, { kind: b.kind }));
    return created(view(doc, ctx.today()));
  });

  router.post('/v5/memberships/:id/extend', { perm: 'members.write' }, (ctx) => {
    const m = find(ctx, ctx.params.id);
    const b = validate({ days: S.int({ required: true, min: 1, max: 365 }), reason: S.str({ max: 200 }) }, ctx.body);
    if (m.endedAt) throw invalid('Membership ended. Start a new membership instead.');
    const next = addDays(m.endDate, b.days);
    const doc = ctx.col('memberships').update(m.id, {
      endDate: next, extensions: [...(m.extensions ?? []), { days: b.days, from: m.endDate, to: next, reason: b.reason ?? null, at: new Date().toISOString(), byId: ctx.user.id }],
    });
    notifyMember(ctx, doc, 'MEMBERSHIP_STATUS_EXTEND_SMS');
    return view(doc, ctx.today());
  });

  router.post('/v5/memberships/:id/freeze', { perm: 'members.write' }, (ctx) => {
    const m = find(ctx, ctx.params.id);
    const b = validate({ date: S.date() }, ctx.body);
    const s = membershipStatus(m, ctx.today());
    if (s === 'paused') throw conflict('This membership is Paused');
    if (s !== 'active') throw invalid(s === 'expired' ? 'This membership has expired.' : 'Only a running membership can be frozen');
    const date = b.date ?? ctx.today();
    if (date < m.startDate || date > m.endDate) throw invalid('Pause date must fall within the membership period');
    const doc = ctx.col('memberships').update(m.id, { pausedAt: date });
    notifyMember(ctx, doc, 'MEMBERSHIP_PAUSE_SMS', { date });
    return view(doc, ctx.today());
  });

  router.post('/v5/memberships/:id/resume', { perm: 'members.write' }, (ctx) => {
    const m = find(ctx, ctx.params.id);
    if (!m.pausedAt) throw invalid('This membership is not paused');
    const days = Math.max(0, diffDays(m.pausedAt, ctx.today()));
    const doc = ctx.col('memberships').update(m.id, { pausedAt: undefined, pausedDays: (m.pausedDays ?? 0) + days, endDate: addDays(m.endDate, days) });
    notifyMember(ctx, doc, 'MEMBERSHIP_RESUME_SMS');
    return view(doc, ctx.today());
  });

  router.post('/v5/memberships/:id/end', { perm: 'members.write' }, (ctx) => {
    const m = find(ctx, ctx.params.id);
    const b = validate({ reason: S.str({ max: 200 }) }, ctx.body);
    const today = ctx.today();
    const s = membershipStatus(m, today);
    if (s === 'ended') throw conflict('Membership already ended');
    if (s === 'expired') throw invalid('This membership has already expired');
    const doc = ctx.col('memberships').update(m.id, { endedAt: today, endDate: s === 'upcoming' ? m.startDate : today, endReason: b.reason ?? null, pausedAt: undefined });
    return view(doc, today);
  });

  // "Start Membership Now?" — pulls an upcoming membership forward to today.
  router.post('/v5/memberships/:id/start', { perm: 'members.write' }, (ctx) => {
    const m = find(ctx, ctx.params.id);
    const today = ctx.today();
    if (membershipStatus(m, today) !== 'upcoming') throw invalid('Only an upcoming membership can be started now');
    const endDate = endDateFor(today, m.durationDays);
    const clash = overlaps(ctx.col('memberships').find((x) => x.memberId === m.memberId), today, endDate, m.id);
    if (clash) throw conflict('Starting now would overlap with a running membership. End or extend it first.');
    return view(ctx.col('memberships').update(m.id, { startDate: today, endDate }), today);
  });

  router.post('/v5/memberships/:id/upgrade', { perm: 'members.write' }, (ctx) => {
    const b = validate({ ...PURCHASE_SCHEMA }, ctx.body);
    const m = find(ctx, ctx.params.id);
    const today = ctx.today();
    const s = membershipStatus(m, today);
    if (!['active', 'paused'].includes(s)) throw invalid('Only a running membership can be upgraded');
    if (m.planId === b.planId) throw invalid('Member is already on this plan');
    const doc = ctx.store.tx(() => {
      ctx.col('memberships').update(m.id, { endedAt: today, endDate: today, pausedAt: undefined, upgradedAt: today });
      return createMembership(ctx, m.memberId, { ...b, startDate: today }, { kind: 'new', previousMembershipId: m.id, skipOverlap: true });
    });
    ctx.col('memberships').update(doc.id, { kind: 'upgrade', previousPlanName: m.planName });
    return created(view(ctx.col('memberships').get(doc.id), today));
  });

  // ---- sessions ("Mark Session", only for session-based plans) ------------------------------------
  router.post('/v5/memberships/:id/sessions', { perm: ['members.write', 'trainer.self'] }, (ctx) => {
    const m = find(ctx, ctx.params.id);
    const b = validate({ date: S.date(), note: S.str({ max: 300 }) }, ctx.body);
    const today = ctx.today();
    const s = membershipStatus(m, today);
    if (!m.sessions) throw invalid('Member has no active session plan with sessions left.');
    if (s === 'expired') throw invalid('This membership has expired. Renew the plan to mark sessions.');
    if (s === 'paused') throw invalid('This membership is Paused');
    if (s === 'ended') throw invalid('This membership has ended');
    if (s === 'upcoming') throw invalid(`You can mark sessions only after ${m.startDate}`);
    if (sessionsLeft(m) <= 0) throw invalid('Member has no active session plan with sessions left.');
    const date = b.date ?? today;
    if (date > today) throw invalid('Selected date and time cannot be in the future.');
    if (date < m.startDate || date > m.endDate) throw invalid('Selected date is outside the membership period');
    const log = { id: randomUUID(), date, note: b.note ?? null, markedById: ctx.user.id, at: new Date().toISOString() };
    const doc = ctx.col('memberships').update(m.id, { sessionLogs: [...(m.sessionLogs ?? []), log] });
    notifyMember(ctx, doc, 'MEMBERSHIP_SESSION_MARKED_SMS', { sessionsLeft: sessionsLeft(doc) });
    return created(view(doc, today));
  });

  router.delete('/v5/memberships/:id/sessions/:logId', { perm: 'members.write' }, (ctx) => {
    const m = find(ctx, ctx.params.id);
    if (!m.sessionLogs?.some((l) => l.id === ctx.params.logId)) throw notFound('Session not found');
    return view(ctx.col('memberships').update(m.id, { sessionLogs: m.sessionLogs.filter((l) => l.id !== ctx.params.logId) }), ctx.today());
  });
}

export { currentMembership };
