// How buying a plan changes a gym's subscription. One pure place, so the rules can be tested without a database.
//
// A subscription is { plan, startsAt, endsAt, limits, dailyRate, queued: [{ plan, days, limits, rate, orderId }] }.
// `dailyRate` is what the running plan costs per day (money actually paid / days bought); it is what an upgrade is credited at.
//
// The rules, for a purchase of plan P (rank p, `days`, price paid) by a gym whose running plan is Q (rank q) with R days left:
//   * nothing running (expired, locked, never paid)      -> P starts today for `days`.
//   * running on the free TRIAL                           -> P starts now; the unused trial days are added on top (they were free anyway).
//   * same tier (renewal, yearly <-> monthly)             -> `days` are added after the current end; the plan and its entitlements do not change.
//   * higher tier (upgrade)                               -> P starts today. What is left of Q (and of anything queued) is converted to P days at
//                                                            the value actually paid for it, so nobody gets a higher tier for time they did not pay for.
//   * lower tier (downgrade)                              -> Q keeps running untouched; P is queued and starts when Q ends, so paid entitlements
//                                                            are never silently removed and cheaper plans never shorten higher ones.
// Entitlements follow the plan that is running on that day. Money values come from the order (what Razorpay confirmed), not from the catalogue.
import { addDays, diffDays } from './dates.js';
import { PLAN_RANK } from './billing.js';

const rankOf = (plan) => PLAN_RANK[plan] ?? 0;
const round4 = (n) => Math.round(n * 10000) / 10000;
const isPaid = (plan) => ['STARTER', 'GROWTH', 'PRO'].includes(plan);

/** Moves a subscription whose current plan has ended on to the next queued plan (several, if several have passed). Pure. */
export function rollQueue(sub, today) {
  if (!sub?.queued?.length) return sub;
  let cur = sub;
  while (cur.queued?.length && cur.endsAt < today) {
    const [next, ...rest] = cur.queued;
    cur = { ...cur, plan: next.plan, startsAt: cur.endsAt, endsAt: addDays(cur.endsAt, next.days), limits: next.limits, dailyRate: next.rate, queued: rest };
  }
  if (!cur.queued?.length) { const { queued: _q, ...clean } = cur; return clean; }
  return cur;
}

/**
 * The subscription after a verified purchase. `purchase` = { plan, days, limits, price } where price is the amount really paid.
 * Returns { subscription, effect } with effect one of 'started' | 'trial-converted' | 'renewed' | 'upgraded' | 'queued'.
 */
export function applyPurchase(subscription, purchase, today) {
  const sub = rollQueue(subscription, today);
  const rate = round4(purchase.price / purchase.days);
  const fresh = (days) => ({ plan: purchase.plan, startsAt: today, endsAt: addDays(today, days), limits: purchase.limits, dailyRate: rate });
  const running = !!sub && sub.endsAt >= today;
  if (!running) return { subscription: fresh(purchase.days), effect: 'started' };

  if (!isPaid(sub.plan)) {
    // free trial still running: the paid plan starts now, unused trial days are a bonus on top
    return { subscription: { ...fresh(purchase.days), endsAt: addDays(sub.endsAt, purchase.days), startsAt: today }, effect: 'trial-converted' };
  }

  const q = rankOf(sub.plan);
  const p = rankOf(purchase.plan);
  const left = diffDays(today, sub.endsAt);

  if (p === q) {
    const blended = round4(((left * (sub.dailyRate ?? 0)) + (purchase.days * rate)) / (left + purchase.days));
    return { subscription: { ...sub, endsAt: addDays(sub.endsAt, purchase.days), limits: purchase.limits, dailyRate: blended }, effect: 'renewed' };
  }

  if (p > q) {
    const credit = (left * (sub.dailyRate ?? 0)) + (sub.queued ?? []).reduce((s, x) => s + x.days * (x.rate ?? 0), 0);
    const bonusDays = rate > 0 ? Math.floor(credit / rate) : 0;
    return { subscription: fresh(purchase.days + bonusDays), effect: 'upgraded' };
  }

  const queued = [...(sub.queued ?? []), { plan: purchase.plan, days: purchase.days, limits: purchase.limits, rate, orderId: purchase.orderId ?? null }];
  return { subscription: { ...sub, queued }, effect: 'queued' };
}
