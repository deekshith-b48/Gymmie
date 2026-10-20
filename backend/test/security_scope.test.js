// Regression tests for the trainer-scope, privacy and trial fixes (V-01, V-03, V-07, V-08).
import { test, after, before } from 'node:test';
import assert from 'node:assert/strict';
import { boot, data } from './helpers.js';

let h; let o; let trainer; let trainerId; let mine; let other;
const gym = () => JSON.parse(h.store.get('SELECT data FROM gyms WHERE id = ?', o.gym).data);
const text = async (token, path) => { const r = await h.call('GET', path, { token, gym: o.gym, raw: true }); return { status: r.status, text: await r.text() }; };

before(async () => {
  h = await boot();
  o = await h.owner({ phone: '+919876611001', gymName: 'Scope Gym' });
  const st = data(await o.as('POST', '/v5/gyms/staffs', { name: 'Tina Trainer', phone: '+919876611002', role: 'trainer' }));
  trainerId = st.userId;
  trainer = await h.loginAs('+919876611002', o.gym);
  const plan = data(await o.as('POST', '/v5/memberships/plans', { name: 'Monthly', price: 1000, durationDays: 30 }));
  mine = data(await o.as('POST', '/v5/members', { name: 'Assigned Alice', phone: '+919876611011', email: 'alice@example.com', trainerId, membership: { planId: plan.id, amountReceived: 400, paymentType: 'cash' } }));
  other = data(await o.as('POST', '/v5/members', { name: 'Unassigned Ursula', phone: '+919876611012', email: 'ursula-secret@example.com', birthDate: '1990-05-05', membership: { planId: plan.id, amountReceived: 100, paymentType: 'cash' } }));
});
after(async () => { await h.close(); });

test('V-01: a trainer exports only their own members, without the money column', async () => {
  const r = await text(trainer.token, '/v5/members/export');
  assert.equal(r.status, 200);
  assert.match(r.text, /Assigned Alice/);
  assert.doesNotMatch(r.text, /Unassigned Ursula|ursula-secret|919876611012/);
  const lines = r.text.split('\n');
  const balanceCol = lines[0].split(',').indexOf('Balance');
  assert.ok(balanceCol >= 0);
  assert.equal(lines[1].split(',')[balanceCol], '', 'a trainer has no finance rights, so no balances');
});

test('V-01: a trainer export also honours what the member hid from trainers', async () => {
  h.store.col(o.gym, 'members').update(mine.id, { privacy: { trainerCanSee: { email: false, birthDate: false } } });
  const r = await text(trainer.token, '/v5/members/export');
  assert.match(r.text, /Assigned Alice/);
  assert.doesNotMatch(r.text, /alice@example\.com/);
  h.store.col(o.gym, 'members').update(mine.id, { privacy: undefined });
});

test('V-01: the owner still exports everyone in their own gym, and only theirs', async () => {
  const r = await text(o.token, '/v5/members/export');
  assert.match(r.text, /Assigned Alice/);
  assert.match(r.text, /Unassigned Ursula/);
  const stranger = await h.owner({ phone: '+919876611099', gymName: 'Other Gym' });
  await stranger.as('POST', '/v5/members', { name: 'Stranger Sam', phone: '+919876611098' });
  const again = await text(o.token, '/v5/members/export');
  assert.doesNotMatch(again.text, /Stranger Sam/);
  const crossed = await h.call('GET', '/v5/members/export', { token: o.token, gym: stranger.gym, raw: true });
  assert.equal(crossed.status, 403, "another gym's header is refused");
});

test('V-08: a trainer\'s dashboard has no gym-wide money, billing or other members\' names', async () => {
  const r = data(await trainer.as('GET', '/v5/dashboards/gyms/summary'));
  assert.equal(r.balance.total, null);
  assert.deepEqual(r.balanceReminders, []);
  assert.equal(r.subscription, null);
  assert.equal(r.credits, null);
  assert.ok(r.tiles.allMembers >= 2, 'plain counts remain');
  const owner = data(await o.as('GET', '/v5/dashboards/gyms/summary'));
  assert.ok(owner.balance.total > 0, 'the owner still sees the dues');
});

test('V-07: workout and diet generators refuse a member who is not the trainer\'s', async () => {
  for (const p of ['/v5/workout/generate', '/v5/diet/generate']) {
    const r = await trainer.as('POST', p, { memberId: other.id });
    assert.equal(r.status, 403, p);
  }
  assert.equal((await trainer.as('POST', '/v5/workout/generate', { memberId: mine.id })).status, 200);
});

test('V-07: what a member hid from trainers never shapes a generated plan', async () => {
  h.store.col(o.gym, 'conditions').insert({ memberId: mine.id, name: 'Heart Problem' });
  const visible = JSON.stringify((await trainer.as('POST', '/v5/workout/generate', { memberId: mine.id })).body);
  assert.match(visible, /heart|cardiac/i, 'with health shared, the draft is adapted to it');
  h.store.col(o.gym, 'members').update(mine.id, { privacy: { trainerCanSee: { health: false } } });
  const hidden = JSON.stringify((await trainer.as('POST', '/v5/workout/generate', { memberId: mine.id })).body);
  assert.doesNotMatch(hidden, /heart|cardiac/i);
  const diet = JSON.stringify((await trainer.as('POST', '/v5/diet/generate', { memberId: mine.id })).body);
  assert.doesNotMatch(diet, /heart|cardiac/i);
  // the owner is not restricted by the member's trainer setting
  const ownerView = JSON.stringify((await o.as('POST', '/v5/workout/generate', { memberId: mine.id })).body);
  assert.match(ownerView, /heart|cardiac/i);
  h.store.col(o.gym, 'members').update(mine.id, { privacy: undefined });
});

// ---- V-03 -----------------------------------------------------------------------------------------------------
test('V-03: one owner cannot collect free trials by creating gyms; extra gyms are allowed but wait for a plan', async () => {
  const owner = await h.owner({ phone: '+919876611201', gymName: 'First Gym' });
  const first = JSON.parse(h.store.get('SELECT data FROM gyms WHERE id = ?', owner.gym).data);
  assert.equal(first.trial.status, 'pending');
  assert.equal(first.subscription.plan, 'TRIAL');
  const ids = [];
  for (const name of ['Second Gym', 'Third Gym', 'Fourth Gym']) {
    const r = await h.call('POST', '/v5/register/partner/gym', { token: owner.token, body: { name, address: '14 MG Road, Bengaluru', pincode: '560001' } });
    assert.equal(r.status, 201);
    ids.push(data(r).gym.id);
    const g = JSON.parse(h.store.get('SELECT data FROM gyms WHERE id = ?', data(r).gym.id).data);
    assert.equal(g.trial.status, 'unavailable', name);
    assert.equal(g.subscription.plan, 'NONE', 'no free full-feature time');
    assert.ok(g.subscription.endsAt < new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Kolkata' }), 'already ended: the gym is locked until a plan is bought');
  }
  // the same through the add-another-gym route, and finishing setup changes nothing
  const viaGyms = await h.call('POST', '/v5/gyms', { token: owner.token, body: { name: 'Fifth Gym', address: '15 MG Road, Bengaluru' } });
  assert.equal(viaGyms.status, 201);
  const done = await h.call('POST', '/v5/register/partner/complete', { token: owner.token, gym: ids[0] });
  assert.equal(done.status, 200, 'setup can still be finished on a locked gym');
  assert.equal(data(done).trial.status, 'unavailable');
  assert.equal(data(done).subscription.plan, 'NONE');
  // and it can be paid for like any other
  assert.equal(JSON.parse(h.store.get('SELECT data FROM gyms WHERE id = ?', owner.gym).data).trial.status, 'pending', 'the first gym keeps its trial');
});

test('V-03: deleting the first gym does not hand the owner a new trial', async () => {
  const owner = await h.owner({ phone: '+919876611202', gymName: 'Vanishing Gym' });
  h.store.run('DELETE FROM docs WHERE gym_id = ?', owner.gym);
  h.store.run('DELETE FROM gym_users WHERE gym_id = ?', owner.gym);
  h.store.run('DELETE FROM gyms WHERE id = ?', owner.gym);
  const r = await h.call('POST', '/v5/register/partner/gym', { token: owner.token, body: { name: 'Fresh Start', address: '14 MG Road, Bengaluru', pincode: '560001' } });
  assert.equal(r.status, 201);
  const g = JSON.parse(h.store.get('SELECT data FROM gyms WHERE id = ?', data(r).gym.id).data);
  assert.equal(g.trial.status, 'unavailable');
});

test('V-03: an account can own only a bounded number of gyms', async () => {
  const hh = await boot({ maxGymsPerOwner: 3 });
  const owner = await hh.owner({ phone: '+919876611203', gymName: 'Gym 1' });
  const make = (n) => hh.call('POST', '/v5/gyms', { token: owner.token, body: { name: `Gym ${n}`, address: '14 MG Road, Bengaluru' } });
  assert.equal((await make(2)).status, 201);
  assert.equal((await make(3)).status, 201);
  assert.equal((await make(4)).status, 409);
  await hh.close();
});

test('V-03: a referral code of your own gym earns nothing', async () => {
  const owner = await h.owner({ phone: '+919876611204', gymName: 'Self Referrer' });
  const code = h.store.get('SELECT code FROM gyms WHERE id = ?', owner.gym).code;
  const r = await h.call('POST', '/v5/register/partner/gym', { token: owner.token, body: { name: 'Second Self', address: '14 MG Road, Bengaluru', referralCode: code } });
  const g = JSON.parse(h.store.get('SELECT data FROM gyms WHERE id = ?', data(r).gym.id).data);
  assert.equal(g.referralCode, null);
});
