import { test, after, before } from 'node:test';
import assert from 'node:assert/strict';
import { boot, data } from './helpers.js';
import { addDays, todayIn } from '../src/domain/dates.js';
import { processDueBroadcasts } from '../src/routes/messaging.js';

let h; let o; let plan;
const TODAY = () => todayIn('Asia/Kolkata');
let seq = 0;
const phone = () => `+9198111${String(10000 + seq++)}`;
const PNG = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

before(async () => {
  h = await boot();
  o = await h.owner({ phone: '+919876509100', gymName: 'Ops Gym' });
  plan = data(await o.as('POST', '/v5/memberships/plans', { name: 'Monthly', price: 1000, durationDays: 30 }));
});
after(async () => { await h.close(); });

const member = async (extra = {}, withPlan = true) => data(await o.as('POST', '/v5/members', {
  name: `Person ${seq}`, phone: phone(), ...(withPlan ? { membership: { planId: plan.id, amountReceived: 1000 } } : {}), ...extra,
}));

test('leads: filter sheet options, snooze presets, disable and convert to member', async () => {
  const mk = (n, extra) => o.as('POST', '/v5/prospects/members', { name: n, phone: phone(), ...extra });
  const a = data(await mk('Lead Alpha', { source: 'Walk-in', chanceOfJoining: 'High', followUpDate: TODAY() }));
  const b = data(await mk('Lead Beta', { source: 'Social Media', chanceOfJoining: 'Low', followUpDate: addDays(TODAY(), -1) }));
  data(await mk('Lead Gamma', { source: 'Google', chanceOfJoining: 'Medium' }));
  const names = async (q) => data(await o.as('GET', `/v5/prospects/members?${q}`)).map((l) => l.name);
  assert.deepEqual(await names('followUp=today'), ['Lead Alpha']);
  assert.deepEqual(await names('followUp=overdue'), ['Lead Beta']);
  assert.deepEqual(await names('source=Google'), ['Lead Gamma']);
  assert.deepEqual(await names('chance=High'), ['Lead Alpha']);
  assert.deepEqual(await names('sort=chanceOfJoiningDesc'), ['Lead Alpha', 'Lead Gamma', 'Lead Beta']);
  assert.equal((await mk('Dup', { phone: a.phone })).status, 409);
  const sn = data(await o.as('POST', `/v5/prospects/members/${b.id}/snooze`, { preset: 'nextMonth' }));
  assert.ok(sn.followUpDate > TODAY());
  assert.equal((await o.as('POST', `/v5/prospects/members/${b.id}/snooze`, { preset: 'custom', date: addDays(TODAY(), -2) })).status, 422);
  await o.as('POST', `/v5/prospects/members/${b.id}/disable`);
  assert.ok(!(await names('status=active')).includes('Lead Beta'));
  assert.deepEqual(await names('status=disabled'), ['Lead Beta']);
  const conv = await o.as('POST', `/v5/prospects/members/${a.id}/convert`, { membership: { planId: plan.id, amountReceived: 1000 } });
  assert.equal(conv.status, 201);
  assert.ok(!(await names('status=active')).includes('Lead Alpha'));
  const m = data(await o.as('GET', `/v5/members/${data(conv).memberId}`));
  assert.equal(m.name, 'Lead Alpha');
  assert.equal(m.membership.status, 'active');
});

test('attendance: expired, blocked, duplicate and QR rules; summaries', async () => {
  const live = await member();
  const expired = await member({ membership: { planId: plan.id, startDate: addDays(TODAY(), -60), amountReceived: 1000 } });
  const none = await member({}, false);
  assert.equal((await o.as('POST', '/v5/attendance/mark', { memberId: live.id })).status, 201);
  const dup = await o.as('POST', '/v5/attendance/mark', { memberId: live.id });
  assert.equal(dup.status, 409);
  const exp = await o.as('POST', '/v5/attendance/mark', { memberId: expired.id });
  assert.equal(exp.status, 422);
  assert.equal(exp.body.error.message, 'Membership Expired');
  assert.equal((await o.as('POST', '/v5/attendance/mark', { memberId: none.id })).status, 422);
  assert.equal((await o.as('POST', '/v5/attendance/mark', { memberId: expired.id, allowExpired: true })).status, 201);
  await o.as('POST', `/v5/members/${live.id}/block`, { reason: 'Misconduct' });
  const second = await member();
  const blockedTry = await o.as('POST', '/v5/attendance/mark', { memberId: live.id, at: addDays(TODAY(), 0) + 'T00:30:00.000Z' });
  assert.equal(blockedTry.status, 403);
  assert.equal((await o.as('POST', '/v5/attendance/mark', { memberId: second.id, at: new Date(Date.now() + 3600_000).toISOString() })).status, 422);
  const gym = data(await o.as('GET', '/v5/gyms/current'));
  const qr = await o.as('POST', '/v5/attendance/mark-by-qr', { payload: `dgymbook://member/${gym.code}/${second.id}` });
  assert.equal(qr.status, 201);
  assert.equal((await o.as('POST', '/v5/attendance/mark-by-qr', { payload: `dgymbook://member/000000/${second.id}` })).status, 403);
  assert.equal((await o.as('POST', '/v5/attendance/mark-by-qr', { payload: 'hello' })).status, 422);
  const sum = data(await o.as('GET', '/v5/attendance/summary?period=thisWeek'));
  assert.ok(sum.total >= 3);
  const todayRow = sum.days.find((d) => d.date === TODAY());
  assert.ok(todayRow.count >= 3);
  const logs = data(await o.as('GET', `/v5/attendance?date=${TODAY()}`));
  assert.ok(logs.length >= 3);
  assert.equal((await o.as('POST', `/v5/attendance/${data(qr).id}/checkout`)).status, 200);
  assert.equal((await o.as('POST', `/v5/attendance/${data(qr).id}/checkout`)).status, 409);
});

test('products: stock tracking, sales decrement stock, oversell is refused, delete reverses', async () => {
  const p = data(await o.as('POST', '/v5/products', { name: 'Whey 1kg', category: 'Supplements', price: 2500, costPrice: 1800, trackStock: true, openingStock: 5, lowStockThreshold: 2, barcode: '8901234567890' }));
  assert.equal(p.quantity, 5);
  assert.equal((await o.as('POST', '/v5/products', { name: 'Clone', price: 1, barcode: '8901234567890' })).status, 409);
  const buyer = await member();
  const sale = await o.as('POST', '/v5/product-sales', { memberId: buyer.id, items: [{ productId: p.id, quantity: 2 }], payments: [{ paymentType: 'cash', amount: 3000 }] });
  assert.equal(sale.status, 201);
  const s = data(sale);
  assert.equal(s.total, 5000);
  assert.equal(s.balance, 2000);
  assert.equal(data(await o.as('GET', `/v5/products/${p.id}`)).quantity, 3);
  assert.equal(data(await o.as('GET', `/v5/members/${buyer.id}`)).balance, 2000);
  const over = await o.as('POST', '/v5/product-sales', { memberId: buyer.id, items: [{ productId: p.id, quantity: 4 }], payments: [{ paymentType: 'cash', amount: 100 }] });
  assert.equal(over.status, 422);
  assert.match(over.body.error.message, /Stock limit exceeded for Whey 1kg/);
  const walkin = await o.as('POST', '/v5/product-sales', { guestName: 'Walk In', items: [{ productId: p.id, quantity: 1 }], payments: [{ paymentType: 'cash', amount: 100 }] });
  assert.equal(walkin.status, 422);
  assert.equal(data(await o.as('GET', '/v5/products/low-stock')).length, 0);
  await o.as('POST', `/v5/products/${p.id}/stock/damage`, { quantity: 1, reason: 'Expired' });
  assert.equal(data(await o.as('GET', '/v5/products/low-stock')).length, 1);
  assert.equal((await o.as('POST', `/v5/products/${p.id}/stock/damage`, { quantity: 9, reason: 'x' })).status, 422);
  await o.as('POST', `/v5/products/${p.id}/stock/receive`, { quantity: 10, totalCost: 15000, logAsExpense: true });
  const exp = data(await o.as('GET', '/v5/expenses?period=thisMonth'));
  assert.ok(exp.some((e) => e.category === 'Stock Purchase' && e.amount === 15000));
  assert.equal(data(await o.as('GET', `/v5/products/${p.id}`)).quantity, 12); // 5 - 2 sold - 1 damaged + 10 received
  assert.equal((await o.as('DELETE', `/v5/product-sales/${s.id}`)).status, 204);
  assert.equal(data(await o.as('GET', `/v5/products/${p.id}`)).quantity, 14); // sale reversed
  const hist = data(await o.as('GET', `/v5/products/${p.id}/stock/history`));
  assert.deepEqual(hist.map((x) => x.type).sort(), ['damage', 'opening', 'receive', 'sale', 'sale-reversal']);
  assert.equal((await o.as('POST', `/v5/products/${p.id}/stock/track`, { openingCount: 3 })).status, 409);
  assert.equal(data(await o.as('POST', `/v5/products/${p.id}/stock/untrack`)).trackStock, false);
});

test('expenses validate dates and feed the quick report', async () => {
  assert.equal((await o.as('POST', '/v5/expenses', { category: 'Rent', amount: 20000, date: addDays(TODAY(), 2) })).status, 422);
  assert.equal((await o.as('POST', '/v5/expenses', { category: 'Rent', amount: 0 })).status, 422);
  assert.equal((await o.as('POST', '/v5/expenses', { category: 'Rent', amount: 20000, paymentType: 'upi' })).status, 201);
  const r = data(await o.as('GET', '/v5/dashboards/gyms/reports/transactions?period=thisMonth'));
  assert.ok(r.expenses >= 20000);
  assert.equal(r.net, Math.round((r.revenue - r.expenses) * 100) / 100);
  assert.ok(r.membershipsByPlan.some((x) => x.plan === 'Monthly'));
  assert.equal((await o.as('GET', '/v5/dashboards/gyms/reports/transactions?period=custom&from=2026-01-01')).status, 422);
});

test('trainer bookings: working hours, assignment, session budget and cancellation', async () => {
  const sess = data(await o.as('POST', '/v5/memberships/plans', { name: '3 Sessions', price: 900, durationDays: 30, sessions: { enabled: true, count: 3 } }));
  const t = await o.as('POST', '/v5/gyms/staffs', { name: 'Tara Trainer', phone: '+919333300001', role: 'trainer' });
  const trainerId = data(t).userId;
  const m = data(await o.as('POST', '/v5/members', { name: 'Booked Member', phone: phone(), trainerId, membership: { planId: sess.id, amountReceived: 900 } }));
  const tr = await h.loginAs('+919333300001', o.gym);
  const date = addDays(TODAY(), 2);
  const slot = (start, end, d = date) => ({ date: d, start, end });
  // no working hours yet
  const noHours = data(await tr.as('POST', '/v5/trainers/me/bookings/preview', { memberId: m.id, slots: [slot('10:00', '11:00')] }));
  assert.equal(noHours.valid, false);
  assert.match(noHours.results[0].reason, /outside your enabled working hours/);
  const days = Array.from({ length: 7 }, (_, day) => ({ day, enabled: true, start: '06:00', end: '20:00' }));
  assert.equal((await tr.as('PUT', '/v5/trainers/me/work-hours', { days })).status, 200);
  assert.equal((await tr.as('PUT', '/v5/trainers/me/work-hours', { days: [{ day: 1, enabled: true, start: '10:00', end: '09:00' }] })).status, 422);
  const ok = await tr.as('POST', '/v5/trainers/me/bookings', { memberId: m.id, slots: [slot('10:00', '11:00'), slot('11:00', '12:00')] });
  assert.equal(ok.status, 201);
  const dupe = await tr.as('POST', '/v5/trainers/me/bookings', { memberId: m.id, slots: [slot('10:30', '11:30')] });
  assert.equal(dupe.status, 422);
  assert.match(dupe.body.error.message, /Duplicate slot/);
  const tooMany = await tr.as('POST', '/v5/trainers/me/bookings', { memberId: m.id, slots: [slot('14:00', '15:00'), slot('15:00', '16:00')] });
  assert.equal(tooMany.status, 422);
  assert.match(tooMany.body.error.message, /session budget/);
  const past = await tr.as('POST', '/v5/trainers/me/bookings', { memberId: m.id, slots: [slot('10:00', '11:00', addDays(TODAY(), -1))] });
  assert.equal(past.status, 422);
  const stranger = data(await o.as('POST', '/v5/members', { name: 'Not Mine', phone: phone(), membership: { planId: sess.id, amountReceived: 900 } }));
  assert.equal((await tr.as('POST', '/v5/trainers/me/bookings', { memberId: stranger.id, slots: [slot('16:00', '17:00')] })).status, 403);
  const day = data(await tr.as('GET', `/v5/trainers/me/bookings?date=${date}`));
  assert.equal(day.length, 2);
  assert.equal((await tr.as('DELETE', `/v5/trainers/me/bookings/${day[0].id}`)).status, 204);
  assert.equal((await tr.as('DELETE', `/v5/trainers/me/bookings/${day[0].id}`)).status, 409);
  const cleared = data(await tr.as('POST', '/v5/trainers/me/bookings/clear', { memberId: m.id }));
  assert.equal(cleared.cancelled, 1);
  // trainer sees only own members
  const mine = data(await tr.as('GET', '/v5/members'));
  assert.deepEqual(mine.map((x) => x.id), [m.id]);
  assert.equal((await tr.as('GET', `/v5/members/${stranger.id}`)).status, 403);
  // trainer cannot be removed while members are assigned
  assert.equal((await o.as('DELETE', `/v5/gyms/staffs/${trainerId}`)).status, 409);
});

test('credits: broadcast needs credits; dev payment order tops up; scheduled broadcast refunds on cancel', async () => {
  const a = await member(); const b = await member();
  void [a, b];
  const noCredit = await o.as('POST', '/v5/broadcasts', { name: 'Holiday', body: 'Hi {{memberName}}, gym closed tomorrow. - {{gymName}}', filter: { status: 'all' } });
  assert.equal(noCredit.status, 402);
  assert.equal(noCredit.body.error.code, 'INSUFFICIENT_CREDITS');
  const pre = data(await o.as('POST', '/v5/broadcasts/recipients/preview', { filter: {} }));
  assert.ok(pre.count > 2);
  // buy credits through the DEV payment provider
  const order = data(await o.as('POST', '/v5/payments/orders/credit-packs', { packId: 'pack-1000' }));
  assert.match(order.paymentUrl, /\/dev\/pay\//);
  const page = await h.call('GET', new URL(order.paymentUrl).pathname, { raw: true });
  assert.equal(page.status, 200);
  assert.match(await page.text(), /DEVELOPMENT PAYMENT PROVIDER/);
  const done = await h.call('POST', `${new URL(order.paymentUrl).pathname}/complete`, { raw: true, headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: undefined });
  assert.equal(done.status, 200);
  const again = await fetch(`${h.base}${new URL(order.paymentUrl).pathname}/complete`, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: 'result=success' });
  assert.equal(again.status, 200);
  assert.match(await again.text(), /dgymbook:\/\/payments\?status=/);
  assert.equal(data(await o.as('GET', `/v5/payments/orders/${order.id}`)).status, 'failed'); // first (empty) POST == failure; link is single-use
  const order2 = data(await o.as('POST', '/v5/payments/orders/credit-packs', { packId: 'pack-1000' }));
  const ok = await fetch(`${h.base}${new URL(order2.paymentUrl).pathname}/complete`, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: 'result=success' });
  assert.match(await ok.text(), /status=success/);
  const stats = data(await o.as('GET', '/v5/credits/stats'));
  assert.equal(stats.balance, 1100); // 1000 + 100 bonus
  // enable integration, send immediately
  assert.equal((await o.as('POST', '/v5/integrations/whatsapp/enable')).status, 200);
  const bc = data(await o.as('POST', '/v5/broadcasts', { name: 'Holiday', body: 'Hi {{memberName}}, closed tomorrow - {{gymName}}', filter: {} }));
  assert.equal(bc.status, 'sent');
  const detail = data(await o.as('GET', `/v5/broadcasts/${bc.id}`));
  assert.equal(detail.delivered, bc.recipientCount);
  assert.equal(data(await o.as('GET', '/v5/credits/stats')).balance, 1100 - bc.recipientCount);
  const msgs = data(await o.as('GET', '/v5/messages?limit=5'));
  assert.match(msgs[0].body, /closed tomorrow - Ops Gym/);
  // scheduled: reserved, cancelled -> refunded
  const when = new Date(Date.now() + 3600_000).toISOString();
  const sch = data(await o.as('POST', '/v5/broadcasts', { name: 'Later', body: 'Hello {{memberName}}', filter: {}, scheduleAt: when }));
  assert.equal(sch.status, 'scheduled');
  const reserved = data(await o.as('GET', '/v5/credits/stats')).balance;
  assert.equal(reserved, 1100 - bc.recipientCount - sch.recipientCount);
  assert.equal(data(await o.as('POST', `/v5/broadcasts/${sch.id}/cancel`)).status, 'cancelled');
  assert.equal(data(await o.as('GET', '/v5/credits/stats')).balance, 1100 - bc.recipientCount);
  const sch2 = data(await o.as('POST', '/v5/broadcasts', { name: 'Soon', body: 'Hello {{memberName}}', filter: {}, scheduleAt: new Date(Date.now() + 1000).toISOString() }));
  assert.equal(processDueBroadcasts(h.store, new Date(Date.now() + 5000)), 1);
  assert.equal(data(await o.as('GET', `/v5/broadcasts/${sch2.id}`)).status, 'sent');
});

test('automated messages are metered per template and can be disabled / customised', async () => {
  const before = data(await o.as('GET', '/v5/credits/stats')).balance;
  await member(); // MEMBER_WELCOME_SMS is automated by default
  assert.equal(data(await o.as('GET', '/v5/credits/stats')).balance, before - 1);
  await o.as('PATCH', '/v5/message-templates/notifications/MEMBER_WELCOME_SMS', { auto: false });
  await member();
  assert.equal(data(await o.as('GET', '/v5/credits/stats')).balance, before - 1);
  assert.equal((await o.as('PATCH', '/v5/message-templates/notifications/MEMBER_WELCOME_SMS', { body: 'Hi {{nope}}' })).status, 422);
  const t = data(await o.as('PATCH', '/v5/message-templates/notifications/MEMBER_WELCOME_SMS', { body: 'Welcome {{memberName}} to {{gymName}}' }));
  assert.equal(t.isCustom, true);
  const reset = data(await o.as('POST', '/v5/message-templates/notifications/MEMBER_WELCOME_SMS/reset'));
  assert.equal(reset.isCustom, false);
});

test('PAR-Q: default form, signing, risk flags, major vs minor versions', async () => {
  const form = data(await o.as('GET', '/v5/parq-form'));
  assert.equal(form.version, '1.0');
  const qs = form.widgets.filter((w) => w.type === 'question');
  assert.equal(qs.length, 7);
  const m = await member();
  const answers = (yes) => qs.map((q, i) => ({ widgetId: q.id, answer: i === 1 && yes ? 'yes' : 'no' }));
  assert.equal((await o.as('POST', `/v5/members/${m.id}/parq/sign`, { answers: answers(false).slice(1), signature: PNG, agreed: true })).status, 422);
  assert.equal((await o.as('POST', `/v5/members/${m.id}/parq/sign`, { answers: answers(false), signature: Buffer.from('nope').toString('base64'), agreed: true })).status, 422);
  const sub = data(await o.as('POST', `/v5/members/${m.id}/parq/sign`, { answers: answers(true), signature: PNG, agreed: true }));
  assert.equal(sub.riskLevel, 'high');
  assert.equal(sub.flagged.length, 1);
  assert.equal(data(await o.as('GET', `/v5/members/${m.id}`)).parqSigned, true);
  const minor = data(await o.as('PUT', '/v5/parq-form', { title: form.title, widgets: form.widgets, consent: form.consent, changeType: 'minor' }));
  assert.equal(minor.version, '1.1');
  assert.equal(data(await o.as('GET', '/v5/parq/status')).needsResign, 0);
  const major = data(await o.as('PUT', '/v5/parq-form', { title: form.title, widgets: form.widgets, consent: form.consent, changeType: 'major' }));
  assert.equal(major.version, '2.0');
  assert.equal(data(await o.as('GET', '/v5/parq/status')).needsResign, 1);
  const gen = data(await o.as('POST', '/v5/parq-form/generate', { areas: ['Heart / cardiovascular', 'Bone or joint'] }));
  assert.equal(gen.widgets.filter((w) => w.type === 'question').length, 7 + 4);
  assert.equal(gen.generator, 'rule-based-dev');
  assert.equal((await o.as('PUT', '/v5/parq-form', { title: 'x', widgets: [{ type: 'heading', text: 'Only heading' }], changeType: 'minor' })).status, 422);
});

test('generators respect injuries, equipment, diet preference and allergies; plans assign to members', async () => {
  const m = await member({ gender: 'male', birthDate: '1995-05-05', heightCm: 175, weightKg: 80 });
  await o.as('POST', `/v5/members/${m.id}/conditions`, { name: 'Knee Pain' });
  const w = data(await o.as('POST', '/v5/workout/generate', { memberId: m.id, goal: 'Build Muscle', level: 'Intermediate', daysPerWeek: 4, equipment: ['Dumbbells', 'Bodyweight Only'] }));
  assert.equal(w.days.length, 4);
  const names = w.days.flatMap((d) => d.exercises.map((e) => e.name));
  for (const banned of ['Barbell Back Squat', 'Walking Lunge', 'Goblet Squat', 'Leg Press', 'Bodyweight Squat']) assert.ok(!names.includes(banned), `${banned} must be excluded for knee pain`);
  assert.ok(w.warnings.some((x) => /knee/.test(x)));
  assert.ok(!names.includes('Barbell Row'));
  const d = data(await o.as('POST', '/v5/diet/generate', { memberId: m.id, goal: 'Build Muscle', dietaryPreference: 'Vegan', mealsPerDay: 5, allergies: ['nuts', 'soy'] }));
  assert.equal(d.meals.length, 5);
  const foods = d.meals.flatMap((x) => x.items.map((i) => i.name));
  for (const banned of ['Almonds', 'Peanuts (roasted)', 'Tofu stir-fry', 'Soy milk', 'Grilled chicken breast', 'Boiled egg', 'Curd', 'Greek yogurt']) assert.ok(!foods.includes(banned), `${banned} must be excluded`);
  assert.ok(d.calorieTarget >= 2000, `calorie target derived from stats, got ${d.calorieTarget}`);
  // save as template and assign
  const saved = await o.as('POST', '/v5/workout/plans', { name: w.name, goal: w.goal, level: w.level, days: w.days });
  assert.equal(saved.status, 201);
  assert.equal((await o.as('POST', '/v5/workout/plans', { name: w.name, days: w.days })).status, 409);
  const asg = await o.as('POST', `/v5/workout/plans/${data(saved).id}/assign`, { memberId: m.id });
  assert.equal(asg.status, 201);
  const mine = data(await o.as('GET', `/v5/workout/members/${m.id}`));
  assert.equal(mine.ownerType, 'member');
  assert.equal(mine.days.length, 4);
  assert.equal((await o.as('DELETE', `/v5/workout/plans/${data(asg).id}`)).status, 422);
  assert.equal((await o.as('DELETE', `/v5/workout/members/${m.id}`)).status, 204);
  assert.equal(data(await o.as('GET', `/v5/workout/members/${m.id}`)), null);
});

test('feature flags gate server behaviour', async () => {
  const g = await h.owner({ phone: '+919876509101', gymName: 'Flag Gym', features: false });
  assert.equal((await g.as('GET', '/v5/workout/plans')).status, 403);
  assert.equal((await g.as('POST', '/v5/workout/generate', { goal: 'Lose Fat' })).status, 403);
  assert.equal((await g.as('GET', '/v5/dashboards/gyms/reports/transactions')).status, 200); // QUICK_REPORTS defaults on
  assert.equal((await g.as('GET', '/v5/dashboards/gyms/insights')).status, 403);
  const on = await g.as('PUT', '/v5/gyms/features/WORKOUT_PLANS', { enabled: true });
  assert.equal(on.status, 200);
  assert.equal((await g.as('GET', '/v5/workout/plans')).status, 200);
  // hidden/admin-only flags cannot be toggled by the gym owner
  assert.equal((await g.as('PUT', '/v5/gyms/features/WHATSAPP_INTEGRATION', { enabled: true })).status, 404);
});

test('attendance, members-in-gym and biometrics are off by default and the owner can switch them on', async () => {
  const g = await h.owner({ phone: '+919876509190', gymName: 'Optional Modules Gym', features: false });
  const list = (await g.as('GET', '/v5/gyms/features')).body.data;
  for (const key of ['ATTENDANCE', 'MEMBERS_IN_GYM', 'BIOMETRICS']) {
    const f = list.find((x) => x.key === key);
    assert.ok(f, `${key} is in the catalog`);
    assert.equal(f.enabled, false, `${key} defaults to off`);
    assert.equal(f.adminEnabled, true, `${key} can be enabled by the admin`);
    const on = await g.as('PUT', `/v5/gyms/features/${key}`, { enabled: true });
    assert.equal(on.status, 200);
    assert.equal(on.body.data.find((x) => x.key === key).enabled, true);
  }
});

test('biometric device API: key auth, check-in, denial for expired, enrolment and blocking', async () => {
  const dev = data(await o.as('POST', '/v3/biohub/devices', { name: 'Front Door', serialNumber: 'SN-1001', ip: '192.168.1.50', type: 'both' }));
  assert.ok(dev.deviceKey);
  assert.equal((await o.as('POST', '/v3/biohub/devices', { name: 'Dup', serialNumber: 'SN-1001' })).status, 409);
  const call = (method, path, body, key = dev.deviceKey) => h.call(method, path, { body, headers: key ? { 'x-device-key': key } : {} });
  assert.equal((await call('POST', '/v5/biohub/device/heartbeat', {}, 'wrong-key-wrong-key-123')).status, 401);
  assert.equal((await call('POST', '/v5/biohub/device/heartbeat', {})).status, 200);
  assert.equal(data(await o.as('GET', `/v3/biohub/devices/${dev.id}`)).status, 'connected');
  const good = await member();
  const lapsed = await member({ membership: { planId: plan.id, startDate: addDays(TODAY(), -90), amountReceived: 1000 } });
  const r = data(await call('POST', '/v5/biohub/device/events', { events: [{ admissionNo: good.admissionNo }, { admissionNo: lapsed.admissionNo }, { admissionNo: 99999 }] }));
  assert.deepEqual(r.results.map((x) => x.result), ['allowed', 'denied', 'denied']);
  assert.equal(r.results[1].reason, 'Membership Expired');
  const logs = data(await o.as('GET', `/v5/biohub/logs?date=${TODAY()}`));
  assert.ok(logs.length >= 3);
  // overdue balance reminder blocks device check-in
  const debtor = await member({ membership: { planId: plan.id, amountReceived: 100 } });
  await o.as('POST', '/v5/balance-reminder', { memberId: debtor.id, reminderDate: addDays(TODAY(), 1) });
  const rem = data(await o.as('GET', `/v5/balance-reminder/member/${debtor.id}`));
  // backdate the reminder to simulate an overdue one
  h.store.col(o.gym, 'balanceReminders').update(rem.id, { reminderDate: addDays(TODAY(), -1) });
  const blocked = data(await call('POST', '/v5/biohub/device/events', { events: [{ admissionNo: debtor.admissionNo }] }));
  assert.match(blocked.results[0].reason, /overdue balance reminder/);
  // enrolment completion via device callback
  const enr = await o.as('POST', `/v5/biohub/member/${good.id}/enroll`, { type: 'face', deviceId: dev.id });
  assert.equal(enr.status, 201);
  const done = data(await call('POST', '/v5/biohub/device/events', { events: [{ admissionNo: good.admissionNo, type: 'enroll', biometricType: 'face' }] }));
  assert.equal(done.results[0].result, 'allowed');
  assert.equal(data(await o.as('GET', `/v5/biohub/member/${good.id}/enrollments`))[0].status, 'completed');
  await o.as('POST', `/v5/biohub/member/${good.id}/block`);
  const again = data(await call('POST', '/v5/biohub/device/events', { events: [{ admissionNo: good.admissionNo }] }));
  assert.equal(again.results[0].result, 'denied');
  assert.equal(data(await o.as('GET', '/v5/dashboards/gyms/occupancy')).hasBiometricDevice, true);
});

test('dashboard summary, insights and occupancy are consistent with the data', async () => {
  const s = data(await o.as('GET', '/v5/dashboards/gyms/summary'));
  assert.ok(s.tiles.allMembers >= 10);
  assert.ok(s.tiles.activeMembers >= 5);
  assert.equal(typeof s.balance.total, 'number');
  assert.equal(s.occupancy.liveCount >= 1, true);
  const ins = data(await o.as('GET', '/v5/dashboards/gyms/insights'));
  assert.equal(ins.engine, 'rule-based');
  assert.ok(Array.isArray(ins.insights));
});

test('public portal: OTP-verified feedback and self-registration', async () => {
  const gym = data(await o.as('GET', '/v5/gyms/current'));
  const info = data(await h.call('GET', `/v5/portal/${gym.code}`));
  assert.equal(info.gym.name, 'Ops Gym');
  assert.ok(info.plans.length >= 1);
  const ph = '+919444400001';
  assert.equal((await h.call('POST', `/v5/portal/${gym.code}/feedback`, { body: { portalToken: 'x.y', rating: 5 } })).status, 403);
  const otp = data(await h.call('POST', `/v5/portal/${gym.code}/otp`, { body: { phone: ph } }));
  const ver = data(await h.call('POST', `/v5/portal/${gym.code}/verify`, { body: { requestId: otp.requestId, otp: '123456' } }));
  const fb = await h.call('POST', `/v5/portal/${gym.code}/feedback`, { body: { portalToken: ver.portalToken, rating: 4, comment: 'Clean gym', category: 'Cleanliness' } });
  assert.equal(fb.status, 201);
  assert.equal((await h.call('POST', `/v5/portal/${gym.code}/feedback`, { body: { portalToken: ver.portalToken, rating: 5 } })).status, 409);
  const stats = data(await o.as('GET', '/v5/feedbacks/stats'));
  assert.equal(stats.total, 1);
  assert.equal(stats.average, 4);
  assert.equal(data(await o.as('GET', '/v5/feedbacks/latest-unseen')).comment, 'Clean gym');
  assert.equal((await o.as('POST', `/v5/feedbacks/${data(fb).id}/favorite`, { isFavorite: true })).status, 200);
  const reg = await h.call('POST', `/v5/portal/${gym.code}/register`, { body: { portalToken: ver.portalToken, name: 'Portal Person', interestedPlanName: 'Monthly' } });
  assert.equal(reg.status, 201);
  assert.ok(data(await o.as('GET', '/v5/prospects/members')).some((l) => l.phone === ph && l.notes === 'Self-registered via gym QR'));
  // token is bound to its gym
  const other = await h.owner({ phone: '+919876509102', gymName: 'Portal Other' });
  const og = data(await other.as('GET', '/v5/gyms/current'));
  assert.equal((await h.call('POST', `/v5/portal/${og.code}/feedback`, { body: { portalToken: ver.portalToken, rating: 5 } })).status, 403);
});

test('misc: video links, documents, FCM token registration and announcements', async () => {
  assert.equal((await o.as('POST', '/v5/video-links', { title: 'Squat form', url: 'javascript:alert(1)' })).status, 422);
  assert.equal((await o.as('POST', '/v5/video-links', { title: 'Squat form', url: 'https://youtube.com/watch?v=abc' })).status, 201);
  const m = await member();
  const doc = await o.as('POST', `/v5/members/${m.id}/documents`, { title: 'Medical cert', type: 'file', file: { data: PNG, contentType: 'image/png' } });
  assert.equal(doc.status, 201);
  assert.equal((await o.as('POST', `/v5/members/${m.id}/documents`, { title: 'Link', type: 'url' })).status, 422);
  const tok = 'fcm-token-'.padEnd(40, 'x');
  assert.equal((await o.as('POST', '/v5/notifiers', { fcmToken: tok, platform: 'android', deviceId: 'dev-1' })).status, 201);
  assert.equal((await o.as('POST', '/v5/notifiers', { fcmToken: 'short' })).status, 422);
  const anns = data(await o.as('GET', '/v5/me/feature-announcements'));
  assert.equal(anns[0].seen, false);
  await o.as('POST', `/v5/me/feature-announcements/${anns[0].id}/seen`);
  assert.equal(data(await o.as('GET', '/v5/me/feature-announcements'))[0].seen, true);
  const cfg = data(await h.call('GET', '/v5/apps/configs/settings'));
  assert.equal(cfg.maintenanceMode, false);
  assert.equal(cfg.featureCatalog.length, 18);
});
