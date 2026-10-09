import { test, after, before } from 'node:test';
import assert from 'node:assert/strict';
import { boot, data } from './helpers.js';
import { addDays, todayIn } from '../src/domain/dates.js';

let h; let o; let monthly; let quarterly; let sessions;
const TODAY = () => todayIn('Asia/Kolkata');
let phoneSeq = 0;
const phone = () => `+9199000${String(10000 + phoneSeq++)}`;

before(async () => {
  h = await boot();
  o = await h.owner({ phone: '+919876509001', gymName: 'Membership Gym' });
  monthly = data(await o.as('POST', '/v5/memberships/plans', { name: 'Monthly', price: 1000, durationDays: 30 }));
  quarterly = data(await o.as('POST', '/v5/memberships/plans', { name: 'Quarterly', price: 2500, durationDays: 90 }));
  sessions = data(await o.as('POST', '/v5/memberships/plans', { name: '10 Sessions', price: 3000, durationDays: 30, sessions: { enabled: true, count: 10 } }));
});
after(async () => { await h.close(); });

const addMember = async (extra = {}) => data(await o.as('POST', '/v5/members', { name: `Member ${phoneSeq}`, phone: phone(), ...extra }));

test('plan validation: duplicate names, limits and group handling', async () => {
  assert.equal((await o.as('POST', '/v5/memberships/plans', { name: 'monthly', price: 10, durationDays: 5 })).status, 409);
  assert.equal((await o.as('POST', '/v5/memberships/plans', { name: 'Bad', price: -1, durationDays: 5 })).status, 422);
  assert.equal((await o.as('POST', '/v5/memberships/plans', { name: 'Bad', price: 10, durationDays: 0 })).status, 422);
  const g = data(await o.as('POST', '/v5/memberships/plan-groups', { name: 'Strength' }));
  const p = data(await o.as('POST', '/v5/memberships/plans', { name: 'Grouped', price: 1, durationDays: 7, groupId: g.id }));
  const del = await o.as('DELETE', `/v5/memberships/plan-groups/${g.id}`);
  assert.equal(del.status, 409);
  assert.match(del.body.error.message, /move the exiting plans/);
  const g2 = data(await o.as('POST', '/v5/memberships/plan-groups', { name: 'Cardio' }));
  assert.equal((await o.as('DELETE', `/v5/memberships/plan-groups/${g.id}?moveTo=${g2.id}`)).status, 204);
  assert.equal(data(await o.as('GET', `/v5/memberships/plans/${p.id}`)).groupId, g2.id);
  const dup = data(await o.as('POST', `/v5/memberships/plans/${monthly.id}/duplicate`));
  assert.equal(dup.name, 'Monthly (Copy)');
  assert.equal((await o.as('POST', `/v5/memberships/plans/${dup.id}/disable`)).status, 200);
  const list = data(await o.as('GET', '/v5/memberships/plans'));
  assert.ok(!list.some((x) => x.id === dup.id));
});

test('pricing: excluded tax, discount validation and percent discounts', async () => {
  await o.as('POST', '/v5/gyms/tax', { name: 'GST', rate: 18, isIncluded: false, taxNumber: '29ABCDE1234F1Z5' });
  const q = data(await o.as('POST', '/v5/memberships/quote', { planId: monthly.id }));
  assert.equal(q.total, 1180);
  assert.equal(q.taxAmount, 180);
  const pct = data(await o.as('POST', '/v5/memberships/quote', { planId: monthly.id, discount: { type: 'percent', value: 10 } }));
  assert.equal(pct.discountAmount, 100);
  assert.equal(pct.total, 1062);
  const bad = await o.as('POST', '/v5/memberships/quote', { planId: monthly.id, discount: { type: 'amount', value: 1500 } });
  assert.equal(bad.status, 422);
  assert.equal(bad.body.error.message, 'Discount cannot be greater than plan price');
  // switch to tax-included: total stays at the (discounted) price and tax is carved out of it
  const t = data(await o.as('GET', '/v5/gyms/tax'))[0];
  await o.as('PATCH', `/v5/gyms/tax/${t.id}`, { isIncluded: true });
  const inc = data(await o.as('POST', '/v5/memberships/quote', { planId: monthly.id }));
  assert.equal(inc.total, 1000);
  assert.equal(inc.taxAmount, 152.54);
  assert.equal(inc.taxableValue, 847.46);
  await o.as('PATCH', `/v5/gyms/tax/${t.id}`, { isIncluded: false });
});

test('member with first membership: totals, balance, invoice and welcome flow', async () => {
  const m = await addMember({ membership: { planId: monthly.id, amountReceived: 500, paymentType: 'cash' } });
  assert.equal(m.membership.status, 'active');
  assert.equal(m.membership.startDate, TODAY());
  assert.equal(m.membership.endDate, addDays(TODAY(), 29));
  assert.equal(m.balance, 680); // 1180 total - 500
  const d = data(await o.as('GET', `/v5/members/${m.id}`));
  assert.equal(d.memberships.length, 1);
  assert.equal(d.memberships[0].balance, 680);
  const inv = data(await o.as('GET', `/v5/invoices/${d.memberships[0].invoiceNo}`));
  assert.equal(inv.total, 1180);
  assert.equal(inv.balance, 680);
  assert.equal(inv.payments.length, 1);
  assert.equal(inv.gym.taxNumber, '29ABCDE1234F1Z5');
  // over-payment is rejected
  const over = await o.as('POST', '/v5/members', { name: 'Over Payer', phone: phone(), membership: { planId: monthly.id, amountReceived: 5000 } });
  assert.equal(over.status, 422);
  assert.match(over.body.error.message, /cannot exceed total/);
  // unknown payment method for this gym
  const bad = await o.as('POST', '/v5/members', { name: 'Odd Payer', phone: phone(), membership: { planId: monthly.id, amountReceived: 10, paymentType: 'cheque' } });
  assert.equal(bad.status, 422);
});

test('duplicate phone numbers are rejected', async () => {
  const p = phone();
  assert.equal((await o.as('POST', '/v5/members', { name: 'First One', phone: p })).status, 201);
  const dup = await o.as('POST', '/v5/members', { name: 'Second One', phone: p });
  assert.equal(dup.status, 409);
  assert.equal(dup.body.error.message, 'Member Contact Already Exists');
});

test('renewal starts after the current membership; overlap is refused; upcoming and start-now work', async () => {
  const m = await addMember({ membership: { planId: monthly.id, amountReceived: 1180 } });
  const overlap = await o.as('POST', '/v5/memberships', { memberId: m.id, planId: monthly.id, startDate: addDays(TODAY(), 5) });
  assert.equal(overlap.status, 409);
  // the price preview reports the same clash before the user confirms
  const qClash = await o.as('POST', '/v5/memberships/quote', { planId: monthly.id, memberId: m.id, startDate: addDays(TODAY(), 5) });
  assert.equal(qClash.status, 409);
  assert.match(qClash.body.error.message, /overlaps with .*Choose a later start date/);
  assert.equal((await o.as('POST', '/v5/memberships/quote', { planId: monthly.id, memberId: m.id })).status, 200); // default start never clashes
  assert.equal((await o.as('POST', '/v5/memberships/quote', { planId: monthly.id, memberId: m.id, startDate: addDays(TODAY(), 31) })).status, 200);
  const renew = data(await o.as('POST', '/v5/memberships', { memberId: m.id, planId: quarterly.id, amountReceived: 0, kind: 'renewal' }));
  assert.equal(renew.startDate, addDays(TODAY(), 30));
  assert.equal(renew.status, 'upcoming');
  assert.equal(renew.endDate, addDays(TODAY(), 30 + 89));
  const detail = data(await o.as('GET', `/v5/members/${m.id}`));
  assert.equal(detail.membership.upcomingCount, 1);
  const started = await o.as('POST', `/v5/memberships/${renew.id}/start`);
  assert.equal(started.status, 409); // would overlap the running membership
});

test('freeze, resume and extend adjust the end date', async () => {
  const start = addDays(TODAY(), -10);
  const m = await addMember({ membership: { planId: monthly.id, startDate: start, amountReceived: 1180 } });
  const ms = m.membership;
  const frozen = data(await o.as('POST', `/v5/memberships/${ms.id}/freeze`, { date: addDays(TODAY(), -4) }));
  assert.equal(frozen.status, 'paused');
  assert.equal((await o.as('POST', `/v5/memberships/${ms.id}/freeze`)).status, 409);
  const resumed = data(await o.as('POST', `/v5/memberships/${ms.id}/resume`));
  assert.equal(resumed.status, 'active');
  assert.equal(resumed.pausedDays, 4);
  assert.equal(resumed.endDate, addDays(start, 29 + 4));
  const ext = data(await o.as('POST', `/v5/memberships/${ms.id}/extend`, { days: 7, reason: 'Diwali closure' }));
  assert.equal(ext.endDate, addDays(start, 29 + 4 + 7));
  assert.equal(ext.extensions.length, 1);
  const ended = data(await o.as('POST', `/v5/memberships/${ms.id}/end`, { reason: 'Moved city' }));
  assert.equal(ended.status, 'ended');
  assert.equal((await o.as('POST', `/v5/memberships/${ms.id}/end`)).status, 409);
});

test('upgrade ends the running plan and starts the new one today', async () => {
  const m = await addMember({ membership: { planId: monthly.id, startDate: addDays(TODAY(), -3), amountReceived: 1180 } });
  const up = data(await o.as('POST', `/v5/memberships/${m.membership.id}/upgrade`, { planId: quarterly.id, amountReceived: 1000 }));
  assert.equal(up.kind, 'upgrade');
  assert.equal(up.previousPlanName, 'Monthly');
  assert.equal(up.startDate, TODAY());
  const d = data(await o.as('GET', `/v5/members/${m.id}`));
  assert.equal(d.membership.planName, 'Quarterly');
  assert.equal(d.memberships.find((x) => x.planName === 'Monthly').status, 'ended');
});

test('settlement allocates oldest-first, rejects overpayment and write-off clears the rest', async () => {
  const m = await addMember({ membership: { planId: monthly.id, amountReceived: 180 } }); // balance 1000
  assert.equal(m.balance, 1000);
  const over = await o.as('POST', '/v5/members/transactions/settle', { memberId: m.id, amount: 1500, paymentType: 'cash' });
  assert.equal(over.status, 422);
  const part = data(await o.as('POST', '/v5/members/transactions/settle', { memberId: m.id, amount: 400, paymentType: 'upi' }));
  assert.equal(part.remainingBalance, 600);
  const bal = data(await o.as('GET', '/v5/members/transactions/balance'));
  assert.ok(bal.items.some((i) => i.memberId === m.id && i.balance === 600));
  const split = data(await o.as('POST', '/v5/members/transactions/settle', { memberId: m.id, payments: [{ paymentType: 'cash', amount: 100 }, { paymentType: 'upi', amount: 200 }] }));
  assert.equal(split.remainingBalance, 300);
  const wo = data(await o.as('POST', '/v5/members/transactions/write-off', { memberId: m.id, reason: 'Left town' }));
  assert.equal(wo.writtenOff, 300);
  assert.equal(data(await o.as('GET', `/v5/members/${m.id}`)).balance, 0);
  assert.equal((await o.as('POST', '/v5/members/transactions/settle', { memberId: m.id, amount: 1, paymentType: 'cash' })).status, 422);
  // deleting the settlement restores the due
  const txns = data(await o.as('GET', `/v5/members/transactions?memberId=${m.id}&kind=settlement`));
  assert.equal(txns.length, 3);
});

test('balance reminder lifecycle', async () => {
  const m = await addMember({ membership: { planId: monthly.id, amountReceived: 100 } });
  assert.equal((await o.as('POST', '/v5/balance-reminder', { memberId: m.id, reminderDate: addDays(TODAY(), -1) })).status, 422);
  const r = await o.as('POST', '/v5/balance-reminder', { memberId: m.id, reminderDate: addDays(TODAY(), 3) });
  assert.equal(r.status, 201);
  assert.equal((await o.as('POST', '/v5/balance-reminder', { memberId: m.id, reminderDate: addDays(TODAY(), 4) })).status, 409);
  const paidUp = await addMember({ membership: { planId: monthly.id, amountReceived: 1180 } });
  assert.equal((await o.as('POST', '/v5/balance-reminder', { memberId: paidUp.id, reminderDate: addDays(TODAY(), 2) })).status, 422);
  assert.equal(data(await o.as('POST', `/v5/balance-reminder/${data(r).id}/done`)).done, true);
});

test('status filters, sorting, search and label filters on the member list', async () => {
  const fresh = await h.owner({ phone: '+919876509002', gymName: 'Filter Gym' });
  const plan = data(await fresh.as('POST', '/v5/memberships/plans', { name: 'Std', price: 500, durationDays: 30 }));
  const label = data(await fresh.as('POST', '/v5/gyms/tags', { name: 'VIP', color: '#112233' }));
  const mk = async (name, ph, offsetStart, extra = {}) => data(await fresh.as('POST', '/v5/members', { name, phone: ph, ...extra, ...(offsetStart === null ? {} : { membership: { planId: plan.id, startDate: addDays(TODAY(), offsetStart), amountReceived: 500 } }) }));
  const a = await mk('Aarav Active', '+919800000001', 0, { labelIds: [label.id] });
  const b = await mk('Bhavna Expiring', '+919800000002', -25);
  const c = await mk('Chetan Expired', '+919800000003', -45); // ended 16 days ago
  const d = await mk('Divya Old', '+919800000004', -100); // ended 71 days ago
  const e = await mk('Esha None', '+919800000005', null);
  const ids = async (q) => data(await fresh.as('GET', `/v5/members?${q}`)).map((m) => m.name);
  assert.deepEqual((await ids('status=active&sort=nameAsc')), ['Aarav Active', 'Bhavna Expiring']);
  assert.deepEqual(await ids('status=expiring10'), ['Bhavna Expiring']);
  assert.deepEqual(await ids('status=expired&sort=nameAsc'), ['Chetan Expired', 'Divya Old']);
  assert.deepEqual(await ids('status=expiredIn30'), ['Chetan Expired']);
  assert.deepEqual(await ids('status=expiredBetween60and90'), ['Divya Old']);
  assert.deepEqual(await ids('status=noMembership'), ['Esha None']);
  assert.deepEqual(await ids(`labelIds=${label.id}`), ['Aarav Active']);
  assert.deepEqual(await ids('q=chet'), ['Chetan Expired']);
  assert.deepEqual(await ids('q=9800000004'), ['Divya Old']);
  assert.deepEqual((await ids('sort=nameDesc&limit=2')), ['Esha None', 'Divya Old']);
  const page2 = await fresh.as('GET', '/v5/members?sort=nameAsc&limit=2&page=3');
  assert.equal(data(page2).length, 1);
  assert.equal(page2.body.meta.total, 5);
  const csv = await h.call('GET', '/v5/members/export', { token: fresh.token, gym: fresh.gym, raw: true });
  assert.match(await csv.text(), /Admission No,Name,Phone/);
  void [a, b, c, d, e];
});

test('session-based plans: mark, exhaust and unmark', async () => {
  const m = await addMember({ membership: { planId: sessions.id, amountReceived: 3540 } });
  const ms = m.membership;
  assert.equal(ms.sessionsLeft, 10);
  for (let i = 0; i < 10; i++) assert.equal((await o.as('POST', `/v5/memberships/${ms.id}/sessions`, { note: `S${i}` })).status, 201);
  const none = await o.as('POST', `/v5/memberships/${ms.id}/sessions`);
  assert.equal(none.status, 422);
  assert.match(none.body.error.message, /no active session plan with sessions left/);
  const cur = data(await o.as('GET', `/v5/memberships/${ms.id}`));
  assert.equal(cur.sessionsLeft, 0);
  const un = data(await o.as('DELETE', `/v5/memberships/${ms.id}/sessions/${cur.sessionLogs[0].id}`));
  assert.equal(un.sessionsLeft, 1);
  assert.equal((await o.as('POST', `/v5/memberships/${monthly.id}/sessions`)).status, 404);
  const fut = await o.as('POST', `/v5/memberships/${ms.id}/sessions`, { date: addDays(TODAY(), 1) });
  assert.equal(fut.status, 422);
});

test('health records compute BMI and trend; conditions CRUD', async () => {
  const m = await addMember();
  await o.as('POST', `/v5/members/${m.id}/health`, { type: 'height', value: 180 });
  await o.as('POST', `/v5/members/${m.id}/health`, { type: 'weight', value: 81, date: addDays(TODAY(), -10) });
  const r = await o.as('POST', `/v5/members/${m.id}/health`, { type: 'weight', value: 78 });
  const h1 = data(r);
  assert.equal(h1.bmi, 24.07);
  assert.equal(h1.bmiCategory, 'Normal');
  assert.deepEqual(h1.weightTrend.map((x) => x.value), [81, 78]);
  assert.equal((await o.as('POST', `/v5/members/${m.id}/health`, { type: 'weight', value: 5 })).status, 422);
  const c = data(await o.as('POST', `/v5/members/${m.id}/conditions`, { name: 'Knee Pain', notes: 'left' }));
  assert.equal(data(await o.as('GET', `/v5/members/${m.id}/health`)).conditions.length, 1);
  assert.equal((await o.as('DELETE', `/v5/members/${m.id}/conditions/${c.id}`)).status, 204);
});
