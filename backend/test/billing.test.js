// Getting paid: the subscription is enforced on the server, paid features follow the plan, Razorpay payments are
// delivered by a signed webhook exactly once, and the referrer is rewarded. No real network: Razorpay is a fake fetch.
import { test, after, before } from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { boot, data } from './helpers.js';
import { loadConfig } from '../src/config.js';
import { addDays } from '../src/domain/dates.js';

const SECRET = 'whsec_test_secret';
let h; let created = [];
const fakeFetch = async (url, init) => {
  const body = JSON.parse(init.body);
  created.push({ url, body, auth: init.headers.authorization });
  return { ok: true, status: 200, json: async () => ({ id: `plink_${created.length}`, short_url: `https://rzp.io/i/${body.reference_id.slice(0, 6)}` }) };
};
const sign = (raw) => createHmac('sha256', SECRET).update(raw).digest('hex');
const gymRow = (id) => JSON.parse(h.store.get('SELECT data FROM gyms WHERE id = ?', id).data);
const patchGym = (id, patch) => h.store.run('UPDATE gyms SET data = ? WHERE id = ?', JSON.stringify({ ...gymRow(id), ...patch }), id);
const setSub = (id, patch) => patchGym(id, { subscription: { ...gymRow(id).subscription, ...patch } });
const today = () => new Date().toISOString().slice(0, 10);

async function webhook(order, { amountPaise, secret = SECRET, event = 'payment_link.paid', sig } = {}) {
  const payload = JSON.stringify({
    event, payload: {
      payment_link: { entity: { id: order.providerRef ?? 'plink_x', reference_id: order.id, amount: Math.round(order.amount * 100), status: 'paid' } },
      payment: { entity: { id: 'pay_123', amount: amountPaise ?? Math.round(order.amount * 100), currency: 'INR', status: 'captured' } },
    },
  });
  const res = await fetch(`${h.base}/v5/payments/webhooks/razorpay`, {
    method: 'POST', headers: { 'content-type': 'application/json', 'x-razorpay-signature': sig ?? createHmac('sha256', secret).update(payload).digest('hex') }, body: payload,
  });
  return { status: res.status, payload };
}

before(async () => {
  h = await boot({ devPayments: false, razorpayKeyId: 'rzp_test_abc', razorpayKeySecret: 'secret', razorpayWebhookSecret: SECRET, paymentsFetch: fakeFetch, graceDays: 7 });
});
after(async () => { await h.close(); });

test('a paid plan decides which add-ons an owner can switch on, on the server', async () => {
  const o = await h.owner({ phone: '+919876507001', gymName: 'Starter Gym', features: false });
  setSub(o.gym, { plan: 'STARTER', endsAt: addDays(today(), 20), limits: { plans: 10, staff: 3, members: 150 } });
  const denied = await o.as('PUT', '/v5/gyms/features/WHATSAPP_INTEGRATION', { enabled: true });
  assert.equal(denied.status, 402);
  assert.equal(denied.body.error.code, 'PLAN_UPGRADE_REQUIRED');
  const list = data(await o.as('GET', '/v5/gyms/features'));
  assert.equal(list.find((f) => f.key === 'WHATSAPP_INTEGRATION').locked, true);
  assert.equal(list.find((f) => f.key === 'MEMBER_APP').requiredPlan, 'GROWTH');
  setSub(o.gym, { plan: 'GROWTH' });
  assert.equal((await o.as('PUT', '/v5/gyms/features/WHATSAPP_INTEGRATION', { enabled: true })).status, 200);
  assert.equal((await o.as('PUT', '/v5/gyms/features/AI_INSIGHTS', { enabled: true })).status, 402, 'Pro-only');
});

test('a feature that was already on stops working when the plan no longer includes it', async () => {
  const o = await h.owner({ phone: '+919876507002', gymName: 'Downgraded Gym', features: true });
  assert.equal((await o.as('GET', '/v5/products')).status, 200, 'trial: everything works');
  setSub(o.gym, { plan: 'STARTER', endsAt: addDays(today(), 20) });
  const r = await o.as('GET', '/v5/products');
  assert.equal(r.status, 402);
  assert.equal(r.body.error.code, 'PLAN_UPGRADE_REQUIRED');
  assert.equal((await o.as('GET', '/v5/members')).status, 200, 'core features are untouched');
});

test('an ended subscription is read-only for a week, then only billing works', async () => {
  const o = await h.owner({ phone: '+919876507003', gymName: 'Lapsed Gym' });
  const plan = data(await o.as('POST', '/v5/memberships/plans', { name: 'P', price: 100, durationDays: 30 }));
  assert.ok(plan.id);
  setSub(o.gym, { endsAt: addDays(today(), -2) });
  assert.equal((await o.as('GET', '/v5/members')).status, 200, 'grace: reading works');
  const w = await o.as('POST', '/v5/members', { name: 'Late Member', phone: '+919900007001' });
  assert.equal(w.status, 402);
  assert.equal(w.body.error.code, 'SUBSCRIPTION_READ_ONLY');
  assert.equal((await o.as('GET', '/v5/billings/subscriptions')).status, 200, 'billing is always reachable');
  setSub(o.gym, { endsAt: addDays(today(), -30) });
  const locked = await o.as('GET', '/v5/members');
  assert.equal(locked.status, 402);
  assert.equal(locked.body.error.code, 'SUBSCRIPTION_EXPIRED');
  assert.equal((await o.as('GET', '/v5/billings/subscriptions')).status, 200);
  assert.equal((await o.as('GET', '/v5/users/self')).status, 200, 'the owner can still see their account');
  const order = await o.as('POST', '/v5/payments/orders/renewal-link', { planId: 'GROWTH_30' });
  assert.equal(order.status, 201, 'and can pay to get back in');
});

test('paying creates a Razorpay checkout; nothing changes until the signed webhook arrives', async () => {
  const o = await h.owner({ phone: '+919876507004', gymName: 'Paying Gym' });
  setSub(o.gym, { plan: 'STARTER', endsAt: addDays(today(), 3) });
  const before = gymRow(o.gym).subscription.endsAt;
  const r = await o.as('POST', '/v5/payments/orders/renewal-link', { planId: 'GROWTH_30' });
  assert.equal(r.status, 201);
  const order = data(r);
  assert.match(order.paymentUrl, /^https:\/\/rzp\.io\//);
  const sent = created.at(-1);
  assert.equal(sent.body.amount, 99900, 'paise');
  assert.equal(sent.body.reference_id, order.id);
  assert.match(sent.auth, /^Basic /);
  assert.equal(gymRow(o.gym).subscription.endsAt, before, 'creating a link does not extend anything');
  assert.equal(data(await o.as('GET', `/v5/payments/orders/${order.id}`)).status, 'created');

  const ok = await webhook(order);
  assert.equal(ok.status, 200);
  const sub = gymRow(o.gym).subscription;
  assert.equal(sub.plan, 'GROWTH');
  assert.equal(sub.endsAt, addDays(before, 30));
  assert.equal(sub.limits.members, 800);
  const paid = data(await o.as('GET', `/v5/payments/orders/${order.id}`));
  assert.equal(paid.status, 'paid');
  assert.match(paid.invoiceNo, /^GYM-\d{4}-\d{5}$/);
  assert.equal(paid.tax.gst + paid.tax.taxable, 999);
  assert.equal(paid.tax.rate, 18);

  // the same event again (Razorpay retries) changes nothing
  await webhook(order);
  assert.equal(gymRow(o.gym).subscription.endsAt, addDays(before, 30));
});

test('a forged, unsigned or wrong-amount webhook delivers nothing', async () => {
  const o = await h.owner({ phone: '+919876507005', gymName: 'Careful Gym' });
  const order = data(await o.as('POST', '/v5/payments/orders/credit-packs', { packId: 'pack-1000' }));
  const credits = () => gymRow(o.gym).creditBalance ?? 0;
  const start = credits();
  assert.equal((await webhook(order, { secret: 'attacker' })).status, 401);
  assert.equal((await webhook(order, { sig: 'deadbeef' })).status, 401);
  const none = await fetch(`${h.base}/v5/payments/webhooks/razorpay`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' });
  assert.equal(none.status, 401);
  assert.equal(credits(), start);
  assert.equal((await webhook(order, { amountPaise: 100 })).status, 200, 'signed, but the amount is wrong');
  assert.equal(credits(), start, 'a short payment delivers nothing');
  assert.equal(data(await o.as('GET', `/v5/payments/orders/${order.id}`)).status, 'mismatch');
});

test('a credit pack is delivered once even if the event is sent three times', async () => {
  const o = await h.owner({ phone: '+919876507006', gymName: 'Credit Gym' });
  const order = data(await o.as('POST', '/v5/payments/orders/credit-packs', { packId: 'pack-1000' }));
  const start = gymRow(o.gym).creditBalance ?? 0;
  await webhook(order); await webhook(order); await webhook(order);
  assert.equal(gymRow(o.gym).creditBalance, start + 1100);
  const ledger = data(await o.as('GET', '/v5/credits/transactions'));
  assert.equal((Array.isArray(ledger) ? ledger : ledger.items ?? []).filter((t) => t.reference === `order:${order.id}`).length, 1);
});

test("one gym cannot pay into, or read, another gym's order", async () => {
  const a = await h.owner({ phone: '+919876507007', gymName: 'Gym Eh' });
  const b = await h.owner({ phone: '+919876507008', gymName: 'Gym Bee' });
  const order = data(await a.as('POST', '/v5/payments/orders/credit-packs', { packId: 'pack-500' }));
  assert.equal((await b.as('GET', `/v5/payments/orders/${order.id}`)).status, 404);
});

test('a smaller plan cannot be bought while the gym is over its limits', async () => {
  const o = await h.owner({ phone: '+919876507009', gymName: 'Big Gym' });
  const sub = gymRow(o.gym).subscription;
  patchGym(o.gym, { subscription: { ...sub, limits: { ...sub.limits, members: 9999 } } });
  const plan = data(await o.as('POST', '/v5/memberships/plans', { name: 'P', price: 100, durationDays: 30 }));
  for (let i = 0; i < 3; i++) assert.equal((await o.as('POST', '/v5/members', { name: `M${i} Test`, phone: `+91990000710${i}`, membership: { planId: plan.id, amountReceived: 100 } })).status, 201);
  const { SUBSCRIPTION_PLANS } = await import('../src/domain/catalog.js');
  SUBSCRIPTION_PLANS.push({ id: 'TINY_30', plan: 'STARTER', name: 'Tiny', price: 1, currency: 'INR', durationDays: 30, limits: { plans: 10, staff: 3, members: 2 } });
  try {
    const res = await o.as('POST', '/v5/payments/orders/renewal-link', { planId: 'TINY_30' });
    assert.equal(res.status, 409);
    assert.match(res.body.error.message, /3 members \(limit 2\)/);
    assert.equal((await o.as('POST', '/v5/payments/orders/renewal-link', { planId: 'STARTER_30' })).status, 201, 'a plan the gym fits is fine');
  } finally { SUBSCRIPTION_PLANS.pop(); }
});

test("the referrer gets free days and credits when the referred gym first pays, once", async () => {
  const referrer = await h.owner({ phone: '+919876507010', gymName: 'Referrer Gym' });
  const code = gymRow(referrer.gym) && h.store.get('SELECT code FROM gyms WHERE id = ?', referrer.gym).code;
  const friend = await h.owner({ phone: '+919876507011', gymName: 'Friend Gym' });
  patchGym(friend.gym, { referralCode: code });
  const endBefore = gymRow(referrer.gym).subscription.endsAt;
  const credBefore = gymRow(referrer.gym).creditBalance ?? 0;
  const o1 = data(await friend.as('POST', '/v5/payments/orders/renewal-link', { planId: 'STARTER_30' }));
  await webhook(o1);
  assert.equal(gymRow(referrer.gym).subscription.endsAt, addDays(endBefore, 30));
  assert.equal(gymRow(referrer.gym).creditBalance, credBefore + 100);
  const o2 = data(await friend.as('POST', '/v5/payments/orders/renewal-link', { planId: 'STARTER_30' }));
  await webhook(o2);
  assert.equal(gymRow(referrer.gym).subscription.endsAt, addDays(endBefore, 30), 'rewarded once only');
});

test('production refuses Razorpay keys without a webhook secret and refuses the dev provider', () => {
  const env = { ...process.env };
  try {
    process.env.NODE_ENV = 'production'; process.env.JWT_SECRET = 'x'.repeat(40);
    delete process.env.DEV_PAYMENTS; delete process.env.DEV_EXPOSE_OTP; delete process.env.DEV_FIXED_OTP;
    assert.throws(() => loadConfig({ razorpayKeyId: 'rzp_live_x' }), /RAZORPAY_WEBHOOK_SECRET/);
    assert.doesNotThrow(() => loadConfig({ razorpayKeyId: 'rzp_live_x', razorpayWebhookSecret: 's' }));
    process.env.DEV_PAYMENTS = '1';
    assert.throws(() => loadConfig(), /DEV_/);
  } finally { process.env = env; }
});

test('staff can close their own account with a code; an owner is told to contact support', async () => {
  const o = await h.owner({ phone: '+919876507020', gymName: 'Owner Deleting' });
  const ask = await o.as('POST', '/v5/users/self/delete-otp');
  assert.equal(ask.status, 409, 'an owner of a gym is not deleted by a tap');
  const staffPhone = '+919222290777';
  assert.equal((await o.as('POST', '/v5/gyms/staffs', { name: 'Leaving Staff', phone: staffPhone, role: 'staff' })).status, 201);
  const { loginAs } = h;
  const st = await loginAs(staffPhone, o.gym);
  const code = data(await st.as('POST', '/v5/users/self/delete-otp'));
  assert.ok(code.requestId);
  assert.equal((await st.as('DELETE', '/v5/users/self', { requestId: code.requestId, otp: '123456', confirm: 'nope' })).status, 422);
  const code2 = data(await st.as('POST', '/v5/users/self/delete-otp'));
  assert.equal((await st.as('DELETE', '/v5/users/self', { requestId: code2.requestId, otp: '123456', confirm: 'DELETE' })).status, 204);
  assert.equal((await st.as('GET', '/v5/users/self')).status >= 400, true, 'signed out everywhere');
  const row = h.store.get('SELECT * FROM users WHERE phone = ?', staffPhone);
  assert.equal(row, undefined, 'the phone number is gone from the account');
  assert.equal(h.store.get('SELECT COUNT(*) c FROM gym_users WHERE gym_id = ? AND role = ?', o.gym, 'staff').c, 0);
});

test('signing up records which terms version was accepted', async () => {
  const r = await h.call('POST', '/v5/register/partner', { body: { name: 'Consent Person', phone: '+919876507030', consentVersion: '2026-10' } });
  const v = await h.call('POST', '/v5/register/partner/verify', { body: { requestId: data(r).requestId, otp: '123456' } });
  const row = h.store.get('SELECT * FROM consents WHERE user_id = ?', data(v).user.id);
  assert.equal(row.version, '2026-10');
  assert.ok(row.accepted_at);
});
