// Buying plans: renewals, upgrades, downgrades, trial conversion and simultaneous purchases. The rules live in domain/subscription.js;
// these tests also go through the real order and signed-webhook path so the amounts come from the confirmed payment, never the client.
import { test, after, before } from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { boot, data } from './helpers.js';
import { addDays, diffDays } from '../src/domain/dates.js';
import { applyPurchase, rollQueue } from '../src/domain/subscription.js';
import { SUBSCRIPTION_PLANS } from '../src/domain/catalog.js';

const SECRET = 'whsec_plan_arithmetic';
let h; let n = 0;
const fakeFetch = async (url, init) => { const body = JSON.parse(init.body); n++; return { ok: true, status: 200, json: async () => ({ id: `plink_${n}`, short_url: `https://rzp.io/i/${body.reference_id.slice(0, 6)}` }) }; };
const gymRow = (id) => JSON.parse(h.store.get('SELECT data FROM gyms WHERE id = ?', id).data);
const patchGym = (id, patch) => h.store.run('UPDATE gyms SET data = ? WHERE id = ?', JSON.stringify({ ...gymRow(id), ...patch }), id);
// the gyms in these tests are in India: "today" is the Indian date, which differs from the UTC date for 5.5 hours every day
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Kolkata' });
const sub = (o) => data(h.store && { data: gymRow(o.gym) }).subscription;
let phone = 919876600000;
const newGym = async (name) => {
  const o = await h.owner({ phone: `+${phone++}`, gymName: name });
  patchGym(o.gym, { subscription: { plan: 'NONE', startsAt: addDays(today(), -60), endsAt: addDays(today(), -30), limits: { plans: 10, staff: 3, members: 150 } } });
  return o;
};
async function webhook(order, { amountPaise } = {}) {
  const payload = JSON.stringify({ event: 'payment_link.paid', payload: {
    payment_link: { entity: { id: order.providerRef ?? 'plink_x', reference_id: order.id, amount: Math.round(order.amount * 100), status: 'paid' } },
    payment: { entity: { id: `pay_${order.id.slice(0, 8)}`, amount: amountPaise ?? Math.round(order.amount * 100), currency: 'INR', status: 'captured' } },
  } });
  const res = await fetch(`${h.base}/v5/payments/webhooks/razorpay`, { method: 'POST', headers: { 'content-type': 'application/json', 'x-razorpay-signature': createHmac('sha256', SECRET).update(payload).digest('hex') }, body: payload });
  return res.status;
}
const order = async (o, planId) => { const r = await o.as('POST', '/v5/payments/orders/renewal-link', { planId }); assert.equal(r.status, 201, JSON.stringify(r.body)); return data(r); };
const buy = async (o, planId) => { const od = await order(o, planId); assert.equal(await webhook(od), 200); return od; };

before(async () => { h = await boot({ devPayments: false, razorpayKeyId: 'rzp_test_abc', razorpayKeySecret: 'secret', razorpayWebhookSecret: SECRET, paymentsFetch: fakeFetch, graceDays: 7 }); });
after(async () => { await h.close(); });

// ---- the rules, without a database -------------------------------------------------------------------------------------
const T = '2026-10-20';
const P = (id) => { const p = SUBSCRIPTION_PLANS.find((x) => x.id === id); return { plan: p.plan, days: p.durationDays, limits: p.limits, price: p.price }; };
const run = (s, id) => applyPurchase(s, P(id), T);

test('nothing running: the plan starts today', () => {
  const { subscription, effect } = run(null, 'GROWTH_30');
  assert.equal(effect, 'started');
  assert.deepEqual([subscription.plan, subscription.startsAt, subscription.endsAt], ['GROWTH', T, addDays(T, 30)]);
});

test('yearly then monthly of the same tier is a renewal: days add up, the tier does not change', () => {
  const a = run(null, 'GROWTH_365').subscription;
  const { subscription, effect } = run(a, 'GROWTH_30');
  assert.equal(effect, 'renewed');
  assert.equal(subscription.plan, 'GROWTH');
  assert.equal(subscription.endsAt, addDays(T, 395));
});

test('monthly then yearly of the same tier is a renewal too', () => {
  const a = run(null, 'PRO_30').subscription;
  const b = run(a, 'PRO_365').subscription;
  assert.equal(b.plan, 'PRO');
  assert.equal(b.endsAt, addDays(T, 395));
});

test('an upgrade is credited only with what was paid: a year of Growth plus one Pro month is nowhere near a year of Pro', () => {
  const growth = run(null, 'GROWTH_365').subscription;
  const { subscription, effect } = run(growth, 'PRO_30');
  assert.equal(effect, 'upgraded');
  assert.equal(subscription.plan, 'PRO');
  const days = diffDays(T, subscription.endsAt);
  assert.ok(days >= 175 && days <= 182, `Pro for ${days} days`);
  // value check: the Pro days granted are worth no more than the money put in (Growth year + Pro month)
  const paid = 9990 + 1999;
  const proDayPrice = 1999 / 30;
  assert.ok(days * proDayPrice <= paid + 1, `${days} Pro days at ${proDayPrice.toFixed(2)} each exceed the ${paid} paid`);
  assert.ok(days * proDayPrice >= paid - proDayPrice, 'and the customer is not short-changed by more than a day');
});

test('a downgrade never shortens or lowers what was paid for: the cheaper plan is queued and starts when the higher one ends', () => {
  const pro = run(null, 'PRO_365').subscription;
  const { subscription, effect } = run(pro, 'STARTER_30');
  assert.equal(effect, 'queued');
  assert.equal(subscription.plan, 'PRO');
  assert.equal(subscription.endsAt, addDays(T, 365));
  assert.equal(subscription.queued.length, 1);
  // before the Pro year ends it is still Pro; the day after, Starter runs for its 30 days from the old end
  assert.equal(rollQueue(subscription, addDays(T, 365)).plan, 'PRO');
  const later = rollQueue(subscription, addDays(T, 366));
  assert.deepEqual([later.plan, later.endsAt, later.queued], ['STARTER', addDays(T, 395), undefined]);
  assert.equal(later.limits.members, 150);
});

test('queued plans are credited into a later upgrade, and several queued plans roll in order', () => {
  let s = run(null, 'PRO_30').subscription;
  s = run(s, 'STARTER_30').subscription;
  s = run(s, 'GROWTH_30').subscription;
  assert.deepEqual(s.queued.map((q) => q.plan), ['STARTER', 'GROWTH']);
  const rolled = rollQueue(s, addDays(T, 62));
  assert.equal(rolled.plan, 'GROWTH');
  assert.equal(rolled.endsAt, addDays(T, 90));
  // an upgrade carries the value of what is queued as well as what is left of the running plan
  let g = run(null, 'GROWTH_30').subscription;
  g = run(g, 'STARTER_30').subscription;
  const up = run(g, 'PRO_30');
  assert.equal(up.effect, 'upgraded');
  const days = diffDays(T, up.subscription.endsAt);
  assert.ok(days >= 50 && days <= 53, `Pro days ${days}: 30 bought plus about 22 for the Growth and Starter months already paid`);
  assert.equal(up.subscription.queued, undefined);
});

test('a running free trial is converted: the paid plan starts now and the unused trial days are a bonus on top', () => {
  const trial = { plan: 'TRIAL', startsAt: T, endsAt: addDays(T, 10), limits: {} };
  const { subscription, effect } = run(trial, 'STARTER_30');
  assert.equal(effect, 'trial-converted');
  assert.deepEqual([subscription.plan, subscription.endsAt], ['STARTER', addDays(T, 40)]);
});

test('a lapsed plan is replaced, not extended', () => {
  const old = { plan: 'PRO', startsAt: addDays(T, -400), endsAt: addDays(T, -5), limits: {}, dailyRate: 50 };
  const { subscription, effect } = run(old, 'STARTER_30');
  assert.equal(effect, 'started');
  assert.deepEqual([subscription.plan, subscription.endsAt], ['STARTER', addDays(T, 30)]);
});

// ---- through orders and the signed webhook -------------------------------------------------------------------------------------
test('end to end: a year of Growth, then a month of Pro, is a prorated upgrade', async () => {
  const o = await newGym('Upgrade Gym');
  await buy(o, 'GROWTH_365');
  assert.equal(gymRow(o.gym).subscription.endsAt, addDays(today(), 365));
  const od = await buy(o, 'PRO_30');
  const s = gymRow(o.gym).subscription;
  assert.equal(s.plan, 'PRO');
  const days = diffDays(today(), s.endsAt);
  assert.ok(days > 170 && days < 190, `Pro days ${days}`);
  assert.equal(data(await o.as('GET', `/v5/payments/orders/${od.id}`)).subscriptionEffect, 'upgraded');
});

test('end to end: a cheaper plan bought on top of a long higher plan waits its turn', async () => {
  const o = await newGym('Downgrade Gym');
  await buy(o, 'PRO_365');
  await buy(o, 'STARTER_30');
  const s = gymRow(o.gym).subscription;
  assert.equal(s.plan, 'PRO');
  assert.equal(s.endsAt, addDays(today(), 365));
  assert.equal(s.queued.length, 1);
  // time passes: the Pro year ended yesterday, so Starter is running now, for 30 days from that end date
  patchGym(o.gym, { subscription: { ...s, endsAt: addDays(today(), -1) } });
  const view = data(await o.as('GET', '/v5/billings/subscriptions'));
  assert.equal(view.current.plan, 'STARTER');
  assert.equal(view.current.endsAt, addDays(today(), 29));
  assert.equal(view.state.status, 'active');
});

test('end to end: paying during the trial converts it', async () => {
  const o = await h.owner({ phone: `+${phone++}`, gymName: 'Trial Payer' });
  const trialEnd = gymRow(o.gym).subscription.endsAt;
  await buy(o, 'STARTER_30');
  const s = gymRow(o.gym).subscription;
  assert.equal(s.plan, 'STARTER');
  assert.equal(s.endsAt, addDays(trialEnd, 30));
});

test('simultaneous purchases and duplicate deliveries each count once', async () => {
  const o = await newGym('Busy Gym');
  const orders = [];
  for (let i = 0; i < 5; i++) orders.push(await order(o, 'GROWTH_30'));
  const results = await Promise.all(orders.flatMap((od) => [webhook(od), webhook(od)]));
  assert.ok(results.every((r) => r === 200));
  const s = gymRow(o.gym).subscription;
  assert.equal(s.endsAt, addDays(today(), 150), 'five months, not ten');
  const paid = (await Promise.all(orders.map(async (od) => data(await o.as('GET', `/v5/payments/orders/${od.id}`))))).filter((x) => x.status === 'paid');
  assert.equal(paid.length, 5);
  assert.equal(new Set(paid.map((x) => x.invoiceNo)).size, 5, 'one invoice number per order');
});

test('simultaneous purchases of different tiers settle in a consistent state', async () => {
  const o = await newGym('Mixed Gym');
  const a = await order(o, 'GROWTH_30'); const b = await order(o, 'PRO_30'); const c = await order(o, 'STARTER_30');
  await Promise.all([webhook(a), webhook(b), webhook(c), webhook(a), webhook(b), webhook(c)]);
  const s = gymRow(o.gym).subscription;
  assert.ok(['GROWTH', 'PRO', 'STARTER'].includes(s.plan));
  const total = diffDays(today(), s.endsAt) + (s.queued ?? []).reduce((x, q) => x + q.days, 0);
  assert.ok(total >= 30 && total <= 90, `total paid days held: ${total}`);
  const orders = await Promise.all([a, b, c].map(async (od) => data(await o.as('GET', `/v5/payments/orders/${od.id}`))));
  assert.ok(orders.every((x) => x.status === 'paid'));
});

test('what was sold is what is delivered, even if the catalogue changes before the payment arrives', async () => {
  const o = await newGym('Price Change Gym');
  const od = await order(o, 'GROWTH_30');
  const entry = SUBSCRIPTION_PLANS.find((p) => p.id === 'GROWTH_30');
  const was = entry.durationDays; entry.durationDays = 5;
  try { assert.equal(await webhook(od), 200); } finally { entry.durationDays = was; }
  assert.equal(gymRow(o.gym).subscription.endsAt, addDays(today(), 30));
});

test('a wrong-amount confirmation extends nothing', async () => {
  const o = await newGym('Short Payer');
  const od = await order(o, 'PRO_365');
  await webhook(od, { amountPaise: 100 });
  assert.equal(gymRow(o.gym).subscription.plan, 'NONE');
});
