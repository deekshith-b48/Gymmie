// V-14: money that arrives wrong is flagged and an operator is told; messages stuck in 'sending' are settled safely, once.
import { test, after, before } from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { boot, data } from './helpers.js';
import { fulfilOrder } from '../src/domain/fulfilment.js';
import { processOutbox, recoverStuckMessages } from '../src/domain/delivery.js';
import { Messenger } from '../src/messenger.js';

const SECRET = 'whsec_recovery';
let h; let alerts = []; let n = 0;
const alertFetch = async (url, init) => { alerts.push(JSON.parse(init.body).text); return { ok: true }; };
const fakeFetch = async (url, init) => { const b = JSON.parse(init.body); n++; return { ok: true, status: 200, json: async () => ({ id: `plink_${n}`, short_url: `https://rzp.io/i/${b.reference_id.slice(0, 6)}` }) }; };
const gymRow = (id) => JSON.parse(h.store.get('SELECT data FROM gyms WHERE id = ?', id).data);
const setCredits = (id, v) => h.store.run('UPDATE gyms SET data = ? WHERE id = ?', JSON.stringify({ ...gymRow(id), creditBalance: v }), id);
const hook = async (order, amountPaise) => {
  const payload = JSON.stringify({ event: 'payment_link.paid', payload: { payment_link: { entity: { id: 'plink_x', reference_id: order.id } }, payment: { entity: { id: 'pay_mismatch_1', amount: amountPaise, currency: 'INR', status: 'captured' } } } });
  return (await fetch(`${h.base}/v5/payments/webhooks/razorpay`, { method: 'POST', headers: { 'content-type': 'application/json', 'x-razorpay-signature': createHmac('sha256', SECRET).update(payload).digest('hex') }, body: payload })).status;
};

before(async () => { h = await boot({ devPayments: false, razorpayKeyId: 'rzp_test_x', razorpayKeySecret: 'secret', razorpayWebhookSecret: SECRET, paymentsFetch: fakeFetch, alertWebhookUrl: 'https://alerts.example.test/h', alertFetch }); });
after(async () => { await h.close(); });

test('a payment of the wrong amount delivers nothing, is flagged, and the operator is alerted without secrets', async () => {
  const o = await h.owner({ phone: '+919876644001', gymName: 'Mismatch Gym' });
  const order = data(await o.as('POST', '/v5/payments/orders/credit-packs', { packId: 'pack-500' }));
  const before = gymRow(o.gym).creditBalance ?? 0;
  alerts = []; h.app.ops.last.clear();
  assert.equal(await hook(order, 100), 200);
  await new Promise((r) => setImmediate(r));
  assert.equal(gymRow(o.gym).creditBalance ?? 0, before, 'no credits for a payment that does not match');
  const stored = data(await o.as('GET', `/v5/payments/orders/${order.id}`));
  assert.equal(stored.status, 'mismatch');
  assert.equal(stored.paymentId, 'pay_mismatch_1', 'the payment id is kept so it can be found in Razorpay');
  assert.equal(alerts.length, 1);
  assert.match(alerts[0], /payment_amount_mismatch/);
  assert.match(alerts[0], new RegExp(order.id));
  assert.doesNotMatch(alerts[0], /whsec|secret/i);
  const ev = h.store.get("SELECT * FROM security_events WHERE kind = 'payment_amount_mismatch' ORDER BY id DESC");
  assert.equal(JSON.parse(ev.detail).paidPaise, 100);
  // Razorpay retrying the same event neither delivers nor spams
  await hook(order, 100);
  assert.equal(alerts.length, 1, 'one alert per kind per ten minutes');
  assert.equal(gymRow(o.gym).creditBalance ?? 0, before);
});

test('after the operator has checked the money, applying a mismatched order delivers it exactly once', async () => {
  const o = await h.owner({ phone: '+919876644002', gymName: 'Apply Gym' });
  const order = data(await o.as('POST', '/v5/payments/orders/credit-packs', { packId: 'pack-500' }));
  await hook(order, 100);
  const before = gymRow(o.gym).creditBalance ?? 0;
  // the normal path refuses to touch it
  assert.equal(fulfilOrder(h.store, o.gym, order.id).status, 'mismatch');
  for (let i = 0; i < 4; i++) fulfilOrder(h.store, o.gym, order.id, { from: ['mismatch'] });
  assert.equal(gymRow(o.gym).creditBalance - before, 500, 'five applications, one delivery');
  assert.equal(data(await o.as('GET', `/v5/payments/orders/${order.id}`)).status, 'paid');
  // and a late genuine webhook for the same order cannot deliver it again
  await hook(order, 50000);
  assert.equal(gymRow(o.gym).creditBalance - before, 500);
});

// ---- messages ---------------------------------------------------------------------------------------------------
const outbox = (gym, extra = {}) => h.store.col(gym, 'outbox').insert({ key: 'BROADCAST', to: '+919900000001', body: 'hello', channel: 'whatsapp', credits: 1, status: 'recorded', ...extra });
const messenger = (transport) => new Messenger({ messaging: { transport } });

test('a message stuck in sending is failed and refunded once, never re-sent, and recovery can run as often as you like', async () => {
  const o = await h.owner({ phone: '+919876644003', gymName: 'Stuck Gym' });
  setCredits(o.gym, 10);
  const stuck = outbox(o.gym, { status: 'sending', sendingAt: Date.now() - 30 * 60_000 });
  const fresh = outbox(o.gym, { status: 'sending', sendingAt: Date.now() - 60_000 });
  const done = outbox(o.gym, { status: 'sent' });
  alerts = []; h.app.ops.last.clear();
  assert.equal(recoverStuckMessages(h.store, { ops: h.app.ops }), 1);
  for (let i = 0; i < 3; i++) recoverStuckMessages(h.store, { ops: h.app.ops });
  const col = h.store.col(o.gym, 'outbox');
  assert.deepEqual([col.get(stuck.id).status, col.get(stuck.id).failureReason], ['failed', 'interrupted']);
  assert.equal(gymRow(o.gym).creditBalance, 11, 'refunded exactly once');
  assert.equal(col.get(fresh.id).status, 'sending', 'a message still being sent is left alone');
  assert.equal(col.get(done.id).status, 'sent');
  await new Promise((r) => setImmediate(r));
  assert.ok(alerts.some((a) => /outbox_stuck_recovered/.test(a)), 'the operator hears about it');
  // not re-sent: the delivery loop only picks 'recorded' rows
  const sent = [];
  const r = await processOutbox(h.store, messenger({ async sendText(m) { sent.push(m); return { providerId: 'x' }; } }));
  assert.equal(sent.length, 0);
  assert.deepEqual([r.sent, r.failed], [0, 0]);
});

test('if the provider answers after recovery gave up, nothing is charged or refunded a second time', async () => {
  const o = await h.owner({ phone: '+919876644004', gymName: 'Late Gym' });
  setCredits(o.gym, 10);
  const m = outbox(o.gym);
  let release; const gate = new Promise((r) => { release = r; });
  const slow = messenger({ async sendText() { await gate; return { providerId: 'late-1' }; } });
  const run = processOutbox(h.store, slow);
  await new Promise((r) => setImmediate(r));
  assert.equal(h.store.col(o.gym, 'outbox').get(m.id).status, 'sending');
  recoverStuckMessages(h.store, { olderThanMs: 0 });            // the process "died": recovery settles it
  assert.equal(gymRow(o.gym).creditBalance, 11);
  release();                                                     // ... but the provider call actually finished
  await run;
  const after = h.store.col(o.gym, 'outbox').get(m.id);
  assert.equal(after.status, 'failed');
  assert.equal(after.sentAfterRecovery, true, 'recorded for the operator');
  assert.equal(gymRow(o.gym).creditBalance, 11, 'the refund stands and is not repeated');
});

test('a provider failure after recovery cannot refund again either', async () => {
  const o = await h.owner({ phone: '+919876644005', gymName: 'Failing Gym' });
  setCredits(o.gym, 10);
  const m = outbox(o.gym);
  let fail; const gate = new Promise((_, rej) => { fail = rej; });
  const run = processOutbox(h.store, messenger({ async sendText() { await gate; } }));
  await new Promise((r) => setImmediate(r));
  recoverStuckMessages(h.store, { olderThanMs: 0 });
  fail(new Error('provider down'));
  await run;
  assert.equal(gymRow(o.gym).creditBalance, 11);
  assert.equal(h.store.col(o.gym, 'outbox').get(m.id).refunded, true);
});

test('two delivery loops running at once send each message once and refund each failure once', async () => {
  const o = await h.owner({ phone: '+919876644006', gymName: 'Parallel Gym' });
  setCredits(o.gym, 10);
  for (let i = 0; i < 6; i++) outbox(o.gym, { to: `+91990000010${i}` });
  const seen = [];
  const tr = messenger({ async sendText(m) { seen.push(m.to); if (m.to.endsWith('3')) throw new Error('boom'); return { providerId: m.to }; } });
  await Promise.all([processOutbox(h.store, tr), processOutbox(h.store, tr), processOutbox(h.store, tr)]);
  assert.equal(seen.length, 6);
  assert.equal(new Set(seen).size, 6, 'no message sent twice');
  assert.equal(gymRow(o.gym).creditBalance, 11, 'the one failure was refunded once');
});

test('a second, different payment for an order that is already settled is reported, and changes nothing', async () => {
  const o = await h.owner({ phone: '+919876644007', gymName: 'Double Payer' });
  const order = data(await o.as('POST', '/v5/payments/orders/credit-packs', { packId: 'pack-500' }));
  const payload = (payId, amount) => JSON.stringify({ event: 'payment_link.paid', payload: { payment_link: { entity: { id: 'plink_x', reference_id: order.id } }, payment: { entity: { id: payId, amount, currency: 'INR', status: 'captured' } } } });
  const send = async (b) => (await fetch(`${h.base}/v5/payments/webhooks/razorpay`, { method: 'POST', headers: { 'content-type': 'application/json', 'x-razorpay-signature': createHmac('sha256', SECRET).update(b).digest('hex') }, body: b })).status;
  assert.equal(await send(payload('pay_first', 50000)), 200);
  const credits = gymRow(o.gym).creditBalance;
  alerts = []; h.app.ops.last.clear();
  assert.equal(await send(payload('pay_second', 50000)), 200);
  await new Promise((r) => setImmediate(r));
  assert.equal(gymRow(o.gym).creditBalance, credits, 'not delivered twice');
  assert.equal(data(await o.as('GET', `/v5/payments/orders/${order.id}`)).status, 'paid', 'a paid order stays paid, even for a wrong-amount repeat');
  assert.ok(alerts.some((a) => /payment_for_settled_order/.test(a)), 'possible double payment is reported');
  await send(payload('pay_third', 100));
  assert.equal(data(await o.as('GET', `/v5/payments/orders/${order.id}`)).status, 'paid');
});

test('a production-mode server refuses a gym\'s test keys unless a staging switch is on', async () => {
  const sentOtps = [];
  const transport = { async sendOtp(m) { sentOtps.push(m); return { providerId: 'o' }; }, async sendText() { return { providerId: 't' }; } };
  const keysFetch = async () => ({ ok: true, status: 200, json: async () => ({}) }); // Razorpay "keys are good"
  for (const [allow, expected] of [[false, 422], [true, 200]]) {
    const hh = await boot({ env: 'production', devOtp: false, devPayments: false, fixedOtp: '', otpResendSec: 0, messagingTransport: transport, jwtSecret: 'j'.repeat(40), allowTestPaymentKeys: allow, paymentsFetch: keysFetch });
    try {
      const reg = await hh.call('POST', '/v5/register/partner', { body: { name: 'Stage Owner', phone: '+919876655500' } });
      const v = await hh.call('POST', '/v5/register/partner/verify', { body: { requestId: data(reg).requestId, otp: sentOtps.at(-1).code } });
      const token = data(v).accessToken;
      const g = await hh.call('POST', '/v5/register/partner/gym', { token, body: { name: 'Stage Gym', address: '12 MG Road, Bengaluru', pincode: '560001' } });
      const r = await hh.call('PUT', '/v5/gyms/payment-setup', { token, gym: data(g).gym.id, body: { provider: 'razorpay', keyId: 'rzp_test_stagingkey1', keySecret: 'staging-secret-1', webhookSecret: 'staging-webhook-1' } });
      assert.equal(r.status, expected, JSON.stringify(r.body));
    } finally { await hh.close(); }
  }
});
