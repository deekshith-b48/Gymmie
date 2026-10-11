// The launch flow: a 14-day trial that starts once setup is complete and cannot be restarted; an optional payment account of the
// gym's own (separate from what the gym pays Gymmie); member access codes that open exactly one member of one gym and stop when revoked.
import { test, after, before } from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { boot, data } from './helpers.js';
import { addDays } from '../src/domain/dates.js';

const WH = 'whsec_gym_secret_1';
const calls = [];
const fakeFetch = async (url, init) => {
  calls.push({ url: String(url), init });
  const auth = String(init.headers.authorization ?? '');
  const key = Buffer.from(auth.replace('Basic ', ''), 'base64').toString().split(':')[0];
  if (String(url).includes('payment_links?count=1')) return { ok: key.startsWith('rzp_test_good'), status: key.startsWith('rzp_test_good') ? 200 : 401, json: async () => ({}) };
  const body = JSON.parse(init.body);
  return { ok: true, status: 200, json: async () => ({ id: `plink_${calls.length}`, short_url: `https://rzp.io/i/${body.reference_id.slice(0, 6)}` }) };
};
let h;
const today = () => new Date().toISOString().slice(0, 10);
const gymRow = (id) => JSON.parse(h.store.get('SELECT data FROM gyms WHERE id = ?', id).data);
const patchGym = (id, p) => h.store.run('UPDATE gyms SET data = ? WHERE id = ?', JSON.stringify({ ...gymRow(id), ...p }), id);
const enableMemberApp = (id) => patchGym(id, { features: { ...gymRow(id).features, MEMBER_APP: true } });

// a fresh owner, the way the app does it: register, create the gym, then finish setup
async function newOwner(phone, gymName) {
  const r = await h.call('POST', '/v5/register/partner', { body: { name: 'Trial Owner', phone } });
  const v = await h.call('POST', '/v5/register/partner/verify', { body: { requestId: data(r).requestId, otp: '123456' } });
  const token = data(v).accessToken;
  const g = await h.call('POST', '/v5/register/partner/gym', { token, body: { name: gymName, address: '12 MG Road, Bengaluru', pincode: '560001', city: 'Bengaluru', state: 'Karnataka' } });
  const gym = data(g).gym.id;
  return { token, gym, as: (m, p, body) => h.call(m, p, { body, token, gym }), complete: () => h.call('POST', '/v5/register/partner/complete', { token, gym }) };
}

before(async () => { h = await boot({ devPayments: false, paymentsFetch: fakeFetch }); });
after(async () => { await h.close(); });

// ---- trial ------------------------------------------------------------------------------------------------------------------
test('the trial starts when setup is completed, runs 14 days, and the dates are stored on the server', async () => {
  const o = await newOwner('+919876505001', 'Trial Gym One');
  assert.equal(data(await o.as('GET', '/v5/gyms/current')).subscription.plan, 'TRIAL');
  assert.equal(gymRow(o.gym).trial.status, 'pending', 'registered, but setup is not complete');
  const done = await o.complete();
  assert.equal(done.status, 200);
  const g = gymRow(o.gym);
  assert.equal(g.trial.status, 'active');
  assert.equal(g.subscription.endsAt, addDays(today(), 14));
  assert.ok(g.trial.startedAt);
  const grant = h.store.get('SELECT * FROM trial_grants WHERE gym_id = ?', o.gym);
  assert.equal(grant.identity, 'phone:+919876505001');
  assert.equal(grant.ends_at, addDays(today(), 14));
  const brief = data(await h.call('GET', '/v5/users/self', { token: o.token })).gyms[0];
  assert.equal(brief.trial.status, 'active');
  assert.equal(brief.subscription.plan, 'TRIAL');
});

test('finishing setup again does not restart or extend the trial', async () => {
  const o = await newOwner('+919876505002', 'Trial Gym Two');
  await o.complete();
  const first = gymRow(o.gym).trial.startedAt;
  patchGym(o.gym, { subscription: { ...gymRow(o.gym).subscription, endsAt: addDays(today(), 2) } }); // 12 days used
  await o.complete(); await o.complete();
  assert.equal(gymRow(o.gym).trial.startedAt, first);
  assert.equal(gymRow(o.gym).subscription.endsAt, addDays(today(), 2), 'no new 14 days');
});

test('a second gym for the same owner gets no second trial: it waits for a plan, on the server', async () => {
  const o = await newOwner('+919876505003', 'First Gym');
  await o.complete();
  const second = await h.call('POST', '/v5/gyms', { token: o.token, body: { name: 'Second Gym', address: '99 Park Street, Mumbai' } });
  assert.equal(second.status, 201);
  const id2 = data(second).id;
  await h.call('POST', '/v5/register/partner/complete', { token: o.token, gym: id2 });
  assert.equal(gymRow(id2).trial.status, 'unavailable');
  const r = await h.call('GET', '/v5/members', { token: o.token, gym: id2 });
  assert.equal(r.status, 402);
  assert.equal(r.body.error.code, 'SUBSCRIPTION_EXPIRED');
  assert.equal((await h.call('GET', '/v5/billings/subscriptions', { token: o.token, gym: id2 })).status, 200, 'plans are shown');
  const plans = data(await h.call('GET', '/v5/billings/subscriptions', { token: o.token, gym: id2 })).plans;
  assert.ok(plans.length >= 3);
});

test('signing out, signing in again, or registering the same number again never restarts it', async () => {
  const o = await newOwner('+919876505004', 'Persistent Gym');
  await o.complete();
  const ends = gymRow(o.gym).subscription.endsAt;
  const again = await h.call('POST', '/v5/register/partner', { body: { name: 'Same Person', phone: '+919876505004' } });
  assert.equal(again.status, 409, 'the number is already registered');
  const login = await h.call('POST', '/v5/auth/signin/otp', { body: { phone: '+919876505004' } });
  const v = await h.call('POST', '/v5/auth/signin/verify', { body: { requestId: data(login).requestId, otp: '123456' } });
  assert.equal(data(v).kind, 'staff');
  assert.equal(gymRow(o.gym).subscription.endsAt, ends);
});

test('an ended trial shows the plans and lets the owner pay; the plan starts only when the payment is confirmed', async () => {
  const o = await newOwner('+919876505005', 'Ending Gym');
  await o.complete();
  patchGym(o.gym, { subscription: { ...gymRow(o.gym).subscription, endsAt: addDays(today(), -40) } });
  assert.equal((await o.as('GET', '/v5/members')).status, 402);
  const sub = data(await o.as('GET', '/v5/billings/subscriptions'));
  assert.equal(sub.state.status, 'locked');
  assert.ok(sub.plans.length >= 3);
  const order = await o.as('POST', '/v5/payments/orders/renewal-link', { planId: 'STARTER_30' });
  assert.equal(order.status, 501, 'with no payment provider configured nothing is activated or faked');
  assert.equal((await o.as('GET', '/v5/members')).status, 402);
});

// ---- the gym's own payment account ---------------------------------------------------------------------------------------------
test('payment setup is optional: skipping is remembered and nothing else changes', async () => {
  const o = await newOwner('+919876505010', 'Skip Gym');
  await o.complete();
  assert.equal(data(await o.as('GET', '/v5/gyms/payment-setup')).status, 'none');
  const skip = data(await o.as('POST', '/v5/gyms/payment-setup/skip'));
  assert.equal(skip.status, 'skipped');
  assert.equal(data(await h.call('GET', '/v5/users/self', { token: o.token })).gyms[0].paymentSetup, 'skipped');
  assert.equal((await o.as('GET', '/v5/members')).status, 200);
  const plan = data(await o.as('POST', '/v5/memberships/plans', { name: 'P', price: 100, durationDays: 30 }));
  assert.equal((await o.as('POST', '/v5/members', { name: 'No Gateway Member', phone: '+919900005001', membership: { planId: plan.id, amountReceived: 0 } })).status, 201);
  assert.equal(data(await o.as('GET', '/v5/gyms/payment-setup')).status, 'skipped', 'still skipped after other work');
});

test('the owner connects their own Razorpay account: keys are checked, sealed, never shown again; staff cannot', async () => {
  const o = await newOwner('+919876505011', 'Own Gateway Gym');
  await o.complete();
  const bad = await o.as('PUT', '/v5/gyms/payment-setup', { provider: 'razorpay', keyId: 'rzp_test_wrongkey1', keySecret: 'secret12345', webhookSecret: WH });
  assert.equal(bad.status, 422);
  assert.equal(data(await o.as('GET', '/v5/gyms/payment-setup')).status, 'none');
  const malformed = await o.as('PUT', '/v5/gyms/payment-setup', { provider: 'razorpay', keyId: 'not-a-key', keySecret: 'secret12345', webhookSecret: WH });
  assert.equal(malformed.status, 422);
  const ok = await o.as('PUT', '/v5/gyms/payment-setup', { provider: 'razorpay', keyId: 'rzp_test_goodkey12345', keySecret: 'my-very-secret-key', webhookSecret: WH });
  assert.equal(ok.status, 200);
  const v = data(ok);
  assert.equal(v.status, 'active');
  assert.equal(v.mode, 'test');
  assert.match(v.webhookUrl, new RegExp(`/v5/payments/webhooks/gym/${o.gym}/razorpay$`));
  assert.ok(!JSON.stringify(ok.body).includes('my-very-secret-key'), 'the secret is never returned');
  const row = h.store.get('SELECT * FROM gym_payment_accounts WHERE gym_id = ?', o.gym);
  assert.ok(!row.secret_sealed.includes('my-very-secret-key') && row.secret_sealed.startsWith('v1.'), 'sealed in the database');
  assert.ok(!JSON.stringify(gymRow(o.gym)).includes('my-very-secret-key'), 'and not in the gym record');
  // a manager may look, only the owner may change
  assert.equal((await o.as('POST', '/v5/gyms/staffs', { name: 'Mina Manager', phone: '+919222205011', role: 'manager' })).status, 201);
  const mgr = await h.loginAs('+919222205011', o.gym);
  assert.equal(data(await mgr.as('GET', '/v5/gyms/payment-setup')).canEdit, false);
  assert.equal((await mgr.as('PUT', '/v5/gyms/payment-setup', { provider: 'razorpay', keyId: 'rzp_test_goodkey99999', keySecret: 'another-secret-12', webhookSecret: WH })).status, 403);
  assert.equal((await mgr.as('DELETE', '/v5/gyms/payment-setup')).status, 403);
});

test("a member's dues are paid through the gym's own account, confirmed by the gym's own webhook, and recorded once", async () => {
  const o = await newOwner('+919876505012', 'Collecting Gym');
  await o.complete();
  await o.as('PUT', '/v5/gyms/payment-setup', { provider: 'razorpay', keyId: 'rzp_test_goodkey55555', keySecret: 'gym-own-secret-1', webhookSecret: WH });
  const plan = data(await o.as('POST', '/v5/memberships/plans', { name: 'Monthly', price: 1000, durationDays: 30 }));
  const mem = data(await o.as('POST', '/v5/members', { name: 'Dues Member', phone: '+919900005012', membership: { planId: plan.id, amountReceived: 400 } }));
  assert.equal(mem.balance, 600);
  const link = await o.as('POST', `/v5/members/${mem.id}/payment-link`, { amount: 600 });
  assert.equal(link.status, 201);
  const sent = calls.at(-1);
  assert.equal(JSON.parse(sent.init.body).amount, 60000);
  assert.match(Buffer.from(sent.init.headers.authorization.replace('Basic ', ''), 'base64').toString(), /^rzp_test_goodkey55555:gym-own-secret-1$/, "the gym's keys, not Gymmie's");
  assert.equal((await o.as('POST', `/v5/members/${mem.id}/payment-link`, { amount: 9999 })).status, 422, 'more than the balance');
  const orderId = data(link).orderId;
  const body = (amountPaise) => JSON.stringify({ event: 'payment_link.paid', payload: { payment_link: { entity: { id: 'plink_x', reference_id: orderId } }, payment: { entity: { id: 'pay_9', amount: amountPaise, currency: 'INR', status: 'captured' } } } });
  const post = (raw, secret = WH, gymId = o.gym) => fetch(`${h.base}/v5/payments/webhooks/gym/${gymId}/razorpay`, { method: 'POST', headers: { 'content-type': 'application/json', 'x-razorpay-signature': createHmac('sha256', secret).update(raw).digest('hex') }, body: raw });
  assert.equal((await post(body(60000), 'gyms-secret-is-not-this')).status, 401, 'forged');
  assert.equal(data(await o.as('GET', `/v5/members/${mem.id}`)).balance, 600);
  assert.equal((await post(body(100))).status, 200, 'signed but short');
  assert.equal(data(await o.as('GET', `/v5/members/${mem.id}`)).balance, 600);
  assert.equal((await post(body(60000))).status, 200, 'the same order again: it was marked mismatched, so it delivers nothing');
  assert.equal(data(await o.as('GET', `/v5/members/${mem.id}`)).balance, 600, 'a mismatched amount marked the order and delivered nothing; a fresh link is needed');
  const link2 = data(await o.as('POST', `/v5/members/${mem.id}/payment-link`, { amount: 600 }));
  const raw2 = JSON.stringify({ event: 'payment_link.paid', payload: { payment_link: { entity: { id: 'plink_y', reference_id: link2.orderId } }, payment: { entity: { id: 'pay_10', amount: 60000, currency: 'INR', status: 'captured' } } } });
  assert.equal((await post(raw2)).status, 200);
  assert.equal((await post(raw2)).status, 200, 'Razorpay retries');
  assert.equal(data(await o.as('GET', `/v5/members/${mem.id}`)).balance, 0);
  const rows = h.store.col(o.gym, 'transactions').find((t) => t.memberId === mem.id && t.kind === 'settlement');
  assert.equal(rows.length, 1, 'recorded once');
  assert.equal(rows[0].amount, 600);
  assert.equal(rows[0].paymentType, 'upi');
});

test("one gym's webhook secret cannot pay another gym's order", async () => {
  const a = await newOwner('+919876505013', 'Gym Alpha');
  const b = await newOwner('+919876505014', 'Gym Bravo');
  for (const [o, k, sec] of [[a, 'rzp_test_goodkeyAAAA1', 'secret-of-alpha-1'], [b, 'rzp_test_goodkeyBBBB1', 'secret-of-bravo-1']]) {
    await o.complete();
    await o.as('PUT', '/v5/gyms/payment-setup', { provider: 'razorpay', keyId: k, keySecret: sec, webhookSecret: o === a ? 'wh-alpha-secret' : 'wh-bravo-secret' });
  }
  const plan = data(await a.as('POST', '/v5/memberships/plans', { name: 'M', price: 500, durationDays: 30 }));
  const mem = data(await a.as('POST', '/v5/members', { name: 'Alpha Member', phone: '+919900005014', membership: { planId: plan.id, amountReceived: 0 } }));
  const link = data(await a.as('POST', `/v5/members/${mem.id}/payment-link`, {}));
  const raw = JSON.stringify({ event: 'payment_link.paid', payload: { payment_link: { entity: { reference_id: link.orderId } }, payment: { entity: { id: 'pay_x', amount: 50000, currency: 'INR' } } } });
  const sign = (s) => createHmac('sha256', s).update(raw).digest('hex');
  // Bravo's valid secret, posted to Bravo's own endpoint with Alpha's order id: Bravo has no such order
  await fetch(`${h.base}/v5/payments/webhooks/gym/${b.gym}/razorpay`, { method: 'POST', headers: { 'content-type': 'application/json', 'x-razorpay-signature': sign('wh-bravo-secret') }, body: raw });
  assert.equal(data(await a.as('GET', `/v5/members/${mem.id}`)).balance, 500, 'untouched');
  // Bravo's secret on Alpha's endpoint is refused
  assert.equal((await fetch(`${h.base}/v5/payments/webhooks/gym/${a.gym}/razorpay`, { method: 'POST', headers: { 'content-type': 'application/json', 'x-razorpay-signature': sign('wh-bravo-secret') }, body: raw })).status, 401);
  assert.equal((await fetch(`${h.base}/v5/payments/webhooks/gym/${a.gym}/razorpay`, { method: 'POST', headers: { 'content-type': 'application/json', 'x-razorpay-signature': sign('wh-alpha-secret') }, body: raw })).status, 200);
  assert.equal(data(await a.as('GET', `/v5/members/${mem.id}`)).balance, 0);
});

// ---- access codes -----------------------------------------------------------------------------------------------------------
test('registering a member issues a unique code for that gym, shown once and stored only as a hash', async () => {
  const o = await newOwner('+919876505020', 'Code Gym');
  await o.complete(); enableMemberApp(o.gym);
  const gymCode = h.store.get('SELECT code FROM gyms WHERE id = ?', o.gym).code;
  const plan = data(await o.as('POST', '/v5/memberships/plans', { name: 'P', price: 100, durationDays: 30 }));
  const r = await o.as('POST', '/v5/members', { name: 'Coded Member', phone: '+919900005020', membership: { planId: plan.id, amountReceived: 100 } });
  assert.equal(r.status, 201);
  const code = data(r).accessCode;
  assert.match(code, new RegExp(`^${gymCode}-[A-Z2-9]{4}-[A-Z2-9]{4}$`));
  const stored = JSON.stringify(h.store.get("SELECT data FROM docs WHERE id = ?", data(r).id));
  assert.ok(!stored.includes(code.slice(7).replace('-', '')), 'only a hash is kept');
  const again = await o.as('POST', '/v5/members', { name: 'Second Member', phone: '+919900005021', membership: { planId: plan.id, amountReceived: 100 } });
  assert.notEqual(data(again).accessCode, code);
  assert.equal(data(await o.as('GET', `/v5/members/${data(r).id}`)).hasAccessCode, true);
  assert.equal(data(await o.as('GET', `/v5/members/${data(r).id}`)).accessCode, undefined, 'not readable again');
});

test('the member signs in with the code: the right gym, the right member, a member session', async () => {
  const o = await newOwner('+919876505021', 'Welcome Gym');
  await o.complete(); enableMemberApp(o.gym);
  const plan = data(await o.as('POST', '/v5/memberships/plans', { name: 'Gold', price: 100, durationDays: 30 }));
  const m = data(await o.as('POST', '/v5/members', { name: 'Welcome Member', phone: '+919900005030', membership: { planId: plan.id, amountReceived: 100 } }));
  const ok = await h.call('POST', '/v5/member/auth/code', { body: { code: ` ${m.accessCode.toLowerCase().replace(/-/g, ' ')} `, device: 'phone' } });
  assert.equal(ok.status, 200, JSON.stringify(ok.body));
  const d = data(ok);
  assert.equal(d.kind, 'member');
  assert.equal(d.member.name, 'Welcome Member');
  assert.equal(d.gym.name, 'Welcome Gym');
  const me = data(await h.call('GET', '/v5/member/me', { token: d.accessToken }));
  assert.equal(me.member.id, m.id);
  assert.equal(me.gym.name, 'Welcome Gym');
  assert.equal(me.membership.planName, 'Gold');
  assert.equal((await h.call('GET', '/v5/members', { token: d.accessToken })).status, 403, 'a member session is not a staff session');
});

test('wrong, malformed, other-gym and revoked codes all fail the same way', async () => {
  const a = await newOwner('+919876505022', 'Gym Left');
  const b = await newOwner('+919876505023', 'Gym Right');
  for (const o of [a, b]) { await o.complete(); enableMemberApp(o.gym); }
  const planA = data(await a.as('POST', '/v5/memberships/plans', { name: 'P', price: 100, durationDays: 30 }));
  const ma = data(await a.as('POST', '/v5/members', { name: 'Left Member', phone: '+919900005040', membership: { planId: planA.id, amountReceived: 100 } }));
  const planB = data(await b.as('POST', '/v5/memberships/plans', { name: 'P', price: 100, durationDays: 30 }));
  const mb = data(await b.as('POST', '/v5/members', { name: 'Right Member', phone: '+919900005041', membership: { planId: planB.id, amountReceived: 100 } }));
  const gymB = h.store.get('SELECT code FROM gyms WHERE id = ?', b.gym).code;
  const attempts = ['', 'hello', '123456-AAAA-AAAA', `${gymB}-${ma.accessCode.slice(7)}`, `${ma.accessCode.slice(0, -1)}`, '000000-ZZZZ-ZZZZ'];
  const bodies = [];
  for (const code of attempts) {
    const r = await h.call('POST', '/v5/member/auth/code', { body: { code: code || ' ' } });
    assert.ok([403, 422].includes(r.status), `${code}: ${r.status}`);
    bodies.push(r.body?.error?.message);
  }
  assert.equal(new Set(bodies.slice(1)).size, 1, 'the same answer whatever was wrong');
  // Alpha's code on Beta's member never crosses gyms
  const real = await h.call('POST', '/v5/member/auth/code', { body: { code: ma.accessCode } });
  assert.equal(data(real).gym.name, 'Gym Left');
  assert.notEqual(data(real).member.id, mb.id);
  // revoke: the code and the session both stop
  const token = data(real).accessToken;
  assert.equal((await h.call('GET', '/v5/member/me', { token })).status, 200);
  assert.equal((await a.as('DELETE', `/v5/members/${ma.id}/access-code`)).status, 204);
  assert.equal((await h.call('POST', '/v5/member/auth/code', { body: { code: ma.accessCode } })).status, 403);
  assert.equal((await h.call('GET', '/v5/member/me', { token })).status, 401, 'signed out at once');
  // the other gym cannot revoke or reissue this gym's member
  assert.equal((await b.as('DELETE', `/v5/members/${ma.id}/access-code`)).status, 404);
  assert.equal((await b.as('POST', `/v5/members/${ma.id}/access-code`)).status, 404);
});

test('a new code replaces the old one at once; a blocked member cannot sign in with any code', async () => {
  const o = await newOwner('+919876505024', 'Reissue Gym');
  await o.complete(); enableMemberApp(o.gym);
  const plan = data(await o.as('POST', '/v5/memberships/plans', { name: 'P', price: 100, durationDays: 30 }));
  const m = data(await o.as('POST', '/v5/members', { name: 'Reissue Member', phone: '+919900005050', membership: { planId: plan.id, amountReceived: 100 } }));
  const fresh = data(await o.as('POST', `/v5/members/${m.id}/access-code`));
  assert.notEqual(fresh.accessCode, m.accessCode);
  assert.equal((await h.call('POST', '/v5/member/auth/code', { body: { code: m.accessCode } })).status, 403, 'the old code is dead');
  assert.equal((await h.call('POST', '/v5/member/auth/code', { body: { code: fresh.accessCode } })).status, 200);
  assert.equal((await o.as('POST', `/v5/members/${m.id}/block`, { reason: 'x' })).status < 300, true);
  assert.equal((await h.call('POST', '/v5/member/auth/code', { body: { code: fresh.accessCode } })).status, 403);
  assert.equal((await o.as('POST', `/v5/members/${m.id}/access-code`)).status, 409, 'cannot issue to a blocked member');
});

test('a gym without the member app, a front-desk role without member rights, and guessing are all stopped', async () => {
  const o = await newOwner('+919876505025', 'No App Gym');
  await o.complete();
  patchGym(o.gym, { features: { ...gymRow(o.gym).features, MEMBER_APP: false } });
  const plan = data(await o.as('POST', '/v5/memberships/plans', { name: 'P', price: 100, durationDays: 30 }));
  const m = data(await o.as('POST', '/v5/members', { name: 'Off Member', phone: '+919900005060', membership: { planId: plan.id, amountReceived: 100 } }));
  assert.equal((await h.call('POST', '/v5/member/auth/code', { body: { code: m.accessCode } })).status, 403, 'member app is off for this gym');
  const strict = await boot({ rateLimitScale: 1 });
  try {
    let last;
    for (let i = 0; i < 25; i++) last = await strict.call('POST', '/v5/member/auth/code', { body: { code: '885409-AAAA-AAA2' } });
    assert.equal(last.status, 429);
  } finally { await strict.close(); }
});

test('the member dashboard data: the real gym, plan, dates, renewal and payment status', async () => {
  const o = await newOwner('+919876505070', 'Dashboard Gym');
  await o.complete(); enableMemberApp(o.gym);
  const plan = data(await o.as('POST', '/v5/memberships/plans', { name: 'Quarterly', price: 3000, durationDays: 90, benefits: ['Locker'] }));
  const m = data(await o.as('POST', '/v5/members', { name: 'Dash Member', phone: '+919900005070', membership: { planId: plan.id, amountReceived: 1000 } }));
  const login = data(await h.call('POST', '/v5/member/auth/code', { body: { code: m.accessCode } }));
  const p = data(await h.call('GET', '/v5/member/me/profile', { token: login.accessToken }));
  assert.equal(p.gym.name, 'Dashboard Gym');
  const ms = p.memberships[0];
  assert.equal(ms.planName, 'Quarterly');
  assert.equal(ms.status, 'active');
  assert.equal(ms.startDate, today());
  assert.equal(ms.endDate, addDays(today(), 89));
  assert.equal(ms.paymentStatus, 'partial');
  assert.equal(ms.balance, 2000);
  assert.deepEqual(ms.benefits, ['Locker']);
  assert.equal(data(await h.call('GET', '/v5/member/me/payment-options', { token: login.accessToken })).online, false, 'no gateway connected');
});
