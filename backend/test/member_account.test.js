// Member self-service (profile, phone, devices, account closure, requests, privacy, notifications) and the gym's side of it,
// with the people who must be kept apart: two members, the owner, a manager, the front desk, a trainer, and another gym.
import { test, after, before } from 'node:test';
import assert from 'node:assert/strict';
import { boot, data } from './helpers.js';
import { processExpiryReminders } from '../src/routes/messaging.js';

let h; let A; let B; let manager; let desk; let trainer; let otherTrainer;
let gold; let silver; let short;
let alice; let bob; let carol; let bobTrainerless;
const TODAY = () => new Date().toISOString().slice(0, 10);
const PNG = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
const PDF = Buffer.from('%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF').toString('base64');

const gymData = (gym, patch) => {
  const row = h.store.get('SELECT data FROM gyms WHERE id = ?', gym);
  const d = { ...JSON.parse(row.data), ...patch };
  h.store.run('UPDATE gyms SET data = ? WHERE id = ?', JSON.stringify(d), gym);
};
const enable = (gym) => {
  const d = JSON.parse(h.store.get('SELECT data FROM gyms WHERE id = ?', gym).data);
  gymData(gym, { features: { ...d.features, MEMBER_APP: true } });
};

async function memberLogin(phone, extra = {}) {
  const r = await h.call('POST', '/v5/member/auth/otp', { body: { phone, ...extra } });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  const v = await h.call('POST', '/v5/member/auth/otp/verify', { body: { requestId: r.body.data.requestId, otp: '123456' } });
  assert.equal(v.status, 200, JSON.stringify(v.body));
  return data(v);
}
const asMember = (token) => (method, path, body) => h.call(method, path, { body, token });

let a; let b; let c; // a = alice's client, b = bob's, c = carol's (other gym)
let aTok;

before(async () => {
  h = await boot();
  A = await h.owner({ phone: '+919876509701', gymName: 'Gym A' });
  B = await h.owner({ phone: '+919876509702', gymName: 'Gym B' });
  enable(A.gym); enable(B.gym);
  const staff = async (name, phone, role) => {
    assert.equal((await A.as('POST', '/v5/gyms/staffs', { name, phone, role })).status, 201);
    return { ...(await h.loginAs(phone, A.gym)), phone };
  };
  manager = await staff('Mona Manager', '+919222290001', 'manager');
  desk = await staff('Dev Desk', '+919222290002', 'staff');
  trainer = await staff('Tina Trainer', '+919222290003', 'trainer');
  otherTrainer = await staff('Omar Other', '+919222290004', 'trainer');
  const plan = async (o, name, price, durationDays, extra = {}) => data(await o.as('POST', '/v5/memberships/plans', { name, price, durationDays, ...extra }));
  gold = await plan(A, 'Gold', 1500, 30, { benefits: ['Locker', 'Towel'] });
  silver = await plan(A, 'Silver', 900, 30);
  short = await plan(A, 'Short', 100, 3);
  const trainerId = (await A.as('GET', '/v5/gyms/staffs')).body.data.find((s) => s.role === 'trainer' && s.phone === '+919222290003').userId;
  alice = data(await A.as('POST', '/v5/members', { name: 'Alice Member', phone: '+919900009701', email: 'alice@example.com', birthDate: '1990-05-05', address: '1 Park Lane', emergencyContact: { name: 'Ann', phone: '+919900009799' }, notes: 'staff only note', trainerId, membership: { planId: gold.id, amountReceived: 1000 } }));
  bob = data(await A.as('POST', '/v5/members', { name: 'Bob Member', phone: '+919900009702', email: 'bob@example.com', membership: { planId: silver.id, amountReceived: 900 } }));
  bobTrainerless = bob;
  const planB = await plan(B, 'B Plan', 500, 30);
  carol = data(await B.as('POST', '/v5/members', { name: 'Carol Member', phone: '+919900009703', membership: { planId: planB.id, amountReceived: 500 } }));
  const al = await memberLogin('+919900009701');
  aTok = al.accessToken;
  a = asMember(al.accessToken);
  b = asMember((await memberLogin('+919900009702')).accessToken);
  c = asMember((await memberLogin('+919900009703')).accessToken);
});
after(async () => { await h.close(); });

// ---- own profile ---------------------------------------------------------------------------------------------------------
test('profile: the member reads and edits their own details; the age is worked out', async () => {
  const g = data(await a('GET', '/v5/member/me/account'));
  assert.equal(g.name, 'Alice Member');
  assert.equal(g.email, 'alice@example.com');
  assert.ok(g.age >= 30);
  assert.ok(g.editable.includes('email') && !g.editable.includes('phone') && !g.editable.includes('trainerId'));
  const r = await a('PATCH', '/v5/member/me/account', {
    name: 'Alice M', email: 'alice.new@example.com', gender: 'female', heightCm: 168, weightKg: 61.5, bloodGroup: 'O+',
    fitness: { goal: 'build_muscle', level: 'beginner', daysPerWeek: 4, notes: 'knee: careful' },
  });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(data(r).fitness.goal, 'build_muscle');
  // a partial fitness update keeps the rest
  const r2 = data(await a('PATCH', '/v5/member/me/account', { fitness: { level: 'intermediate' } }));
  assert.deepEqual([r2.fitness.goal, r2.fitness.level, r2.fitness.daysPerWeek], ['build_muscle', 'intermediate', 4]);
  // null clears
  const r3 = data(await a('PATCH', '/v5/member/me/account', { address: null, email: null }));
  assert.equal(r3.address, null);
  assert.equal(r3.email, null);
  await a('PATCH', '/v5/member/me/account', { email: 'alice@example.com', address: '1 Park Lane' });
  // the gym sees the change
  const seen = data(await A.as('GET', `/v5/members/${alice.id}`));
  assert.equal(seen.name, 'Alice M');
  assert.equal(seen.bloodGroup, 'O+');
});

test('profile: validation says what is wrong, and nothing half-applies', async () => {
  const before = data(await a('GET', '/v5/member/me/account'));
  for (const bad of [{ email: 'nope' }, { name: 'A' }, { birthDate: '2999-01-01' }, { birthDate: new Date(Date.now() - 2 * 365 * 864e5).toISOString().slice(0, 10) },
    { birthDate: '1700-01-01' }, { heightCm: 10 }, { weightKg: 900 }, { gender: 'x' }, { fitness: { goal: 'fly' } }, { fitness: { daysPerWeek: 9 } }, { emergencyContact: { phone: 'abc' } }]) {
    const r = await a('PATCH', '/v5/member/me/account', { name: 'Should Not Apply', ...bad });
    assert.equal(r.status, 422, JSON.stringify(bad));
  }
  assert.equal(data(await a('GET', '/v5/member/me/account')).name, before.name);
});

test('profile: a member cannot change what belongs to the gym, whatever the request says', async () => {
  const r = await a('PATCH', '/v5/member/me/account', {
    name: 'Alice Same', phone: '+919911111111', trainerId: 'someone', blocked: true, blockedReason: 'x', labelIds: ['x'], notes: 'hacked', joinedAt: '2000-01-01',
    admissionNo: 999, role: 'owner', gymId: B.gym, memberId: bob.id, id: bob.id, membership: { planId: silver.id }, privacy: { shareTraining: 'gym' }, appClosedAt: 'x', balance: 0,
    parqSignedAt: '2020-01-01', photoFileId: 'x', communication: { broadcasts: false },
  });
  assert.equal(r.status, 200);
  const m = data(await A.as('GET', `/v5/members/${alice.id}`));
  assert.equal(m.name, 'Alice Same');
  assert.equal(m.phone, '+919900009701');
  assert.equal(m.blocked, false);
  assert.equal(m.notes, 'staff only note');
  assert.equal(m.admissionNo, alice.admissionNo);
  assert.equal(m.joinedAt, alice.joinedAt);
  assert.equal(m.memberApp.broadcasts, true);
  assert.equal(data(await A.as('GET', `/v5/members/${bob.id}`)).name, 'Bob Member', 'nothing leaked to another member');
  assert.equal(data(await a('GET', '/v5/member/me/privacy')).shareTraining, 'off');
  await a('PATCH', '/v5/member/me/account', { name: 'Alice Member' });
});

test('photo: the member sets their own, staff see it, a non-image is refused, and nobody reads another member\'s', async () => {
  assert.equal((await a('PUT', '/v5/member/me/photo', { data: PDF })).status, 422);
  assert.equal(h.store.get("SELECT COUNT(*) AS n FROM files WHERE mime = 'application/pdf'").n, 0, 'the refused file is not kept');
  const put = await a('PUT', '/v5/member/me/photo', { data: PNG, contentType: 'image/png' });
  assert.equal(put.status, 200, JSON.stringify(put.body));
  assert.equal(data(put).photoUrl, '/v5/member/me/photo');
  const img = await h.call('GET', '/v5/member/me/photo', { token: aTok, raw: true });
  assert.equal(img.status, 200);
  assert.equal(img.headers.get('content-type'), 'image/png');
  assert.equal((await b('GET', '/v5/member/me/photo')).status, 404, 'Bob has no photo, and cannot reach Alice\'s');
  const list = data(await A.as('GET', '/v5/members?q=Alice'));
  assert.ok(list[0].photoUrl.startsWith('/v5/files/'));
  assert.equal((await A.as('GET', list[0].photoUrl, undefined, { raw: true })).status, 200);
  // replacing it deletes the old file
  const before = h.store.get('SELECT COUNT(*) AS n FROM files WHERE gym_id = ?', A.gym).n;
  await a('PUT', '/v5/member/me/photo', { data: PNG });
  assert.equal(h.store.get('SELECT COUNT(*) AS n FROM files WHERE gym_id = ?', A.gym).n, before);
  assert.equal((await a('DELETE', '/v5/member/me/photo')).status, 204);
  assert.equal((await a('GET', '/v5/member/me/photo')).status, 404);
});

// ---- phone number --------------------------------------------------------------------------------------------------------------
test('phone: the new number is proven with a code, every other phone is signed out, and sign-in moves to the new number', async () => {
  const dave = data(await A.as('POST', '/v5/members', { name: 'Dave Phone', phone: '+919900009710' }));
  const d1 = await memberLogin('+919900009710');
  const d2 = await memberLogin('+919900009710');
  const phone1 = asMember(d1.accessToken); const phone2 = asMember(d2.accessToken);
  assert.equal((await phone1('POST', '/v5/member/me/phone/otp', { phone: '+919900009710' })).status, 422, 'already your number');
  const otp = await phone1('POST', '/v5/member/me/phone/otp', { phone: '+919900009711' });
  assert.equal(otp.status, 200, JSON.stringify(otp.body));
  assert.equal((await phone1('POST', '/v5/member/me/phone/verify', { requestId: data(otp).requestId, otp: '000000' })).status, 422);
  const ok = await phone1('POST', '/v5/member/me/phone/verify', { requestId: data(otp).requestId, otp: '123456' });
  assert.equal(ok.status, 200, JSON.stringify(ok.body));
  assert.equal(data(ok).phone, '+919900009711');
  assert.equal(data(await A.as('GET', `/v5/members/${dave.id}`)).phone, '+919900009711', 'the gym sees the new number');
  assert.equal((await phone1('GET', '/v5/member/me')).status, 200, 'this phone carries on');
  assert.equal((await phone2('GET', '/v5/member/me')).status, 401, 'the other phone is signed out');
  assert.equal((await h.call('POST', '/v5/member/auth/refresh', { body: { refreshToken: d1.refreshToken } })).status, 200, 'and this one can still refresh');
  // the old number is no longer a way in; the new one is
  const old = await h.call('POST', '/v5/member/auth/otp', { body: { phone: '+919900009710' } });
  assert.equal((await h.call('POST', '/v5/member/auth/otp/verify', { body: { requestId: old.body.data.requestId, otp: '123456' } })).status, 422, 'no code was sent: the same answer as for any non-member');
  assert.ok((await memberLogin('+919900009711')).accessToken);
});

test('phone: a number someone else has answers the same, and a code asked for by another member is no use', async () => {
  const free = await a('POST', '/v5/member/me/phone/otp', { phone: '+919900009750' });
  const taken = await a('POST', '/v5/member/me/phone/otp', { phone: bob.phone });
  assert.equal(taken.status, 200);
  assert.deepEqual(Object.keys(data(taken)).filter((k) => k !== 'devOtp').sort(), Object.keys(data(free)).filter((k) => k !== 'devOtp').sort());
  assert.equal((await a('POST', '/v5/member/me/phone/verify', { requestId: data(taken).requestId, otp: '123456' })).status, 422, 'no code was ever sent for it');
  // Bob asks for a code; Alice cannot use it
  const bobsOtp = await b('POST', '/v5/member/me/phone/otp', { phone: '+919900009751' });
  assert.equal((await a('POST', '/v5/member/me/phone/verify', { requestId: data(bobsOtp).requestId, otp: '123456' })).status, 403);
  assert.equal(data(await A.as('GET', `/v5/members/${bob.id}`)).phone, '+919900009702');
});

// ---- devices ---------------------------------------------------------------------------------------------------------------------
test('devices: list your own, sign one out, sign out the others; never someone else\'s', async () => {
  const e = await memberLogin('+919900009702');
  const e2 = asMember(e.accessToken);
  const list = data(await e2('GET', '/v5/member/me/sessions'));
  assert.ok(list.length >= 2);
  assert.equal(list.filter((s) => s.current).length, 1);
  const bobsFamilies = list.map((s) => s.id);
  // Alice cannot see or end Bob's devices (his ids look like missing ones)
  const aliceList = data(await a('GET', '/v5/member/me/sessions'));
  assert.ok(aliceList.every((s) => !bobsFamilies.includes(s.id)));
  assert.equal((await a('DELETE', `/v5/member/me/sessions/${bobsFamilies[0]}`)).status, 404);
  assert.equal((await e2('GET', '/v5/member/me')).status, 200);
  const other = list.find((s) => !s.current);
  assert.equal((await e2('DELETE', `/v5/member/me/sessions/${other.id}`)).status, 204);
  assert.ok(!data(await e2('GET', '/v5/member/me/sessions')).some((s) => s.id === other.id));
  const f = asMember((await memberLogin('+919900009702')).accessToken);
  assert.equal((await e2('POST', '/v5/member/me/sessions/revoke-others')).status, 204);
  assert.equal((await f('GET', '/v5/member/me')).status, 401, 'the others are out');
  assert.equal((await e2('GET', '/v5/member/me')).status, 200, 'this one stays');
  b = e2;
  assert.equal((await h.call('GET', '/v5/member/me/sessions')).status, 401);
});

// ---- closing the app account ----------------------------------------------------------------------------------------------------
test('deleting the app account: confirmed with a code, personal and training data erased, the gym keeps its records, the gym can reopen it', async () => {
  const erin = data(await A.as('POST', '/v5/members', { name: 'Erin Erase', phone: '+919900009720', email: 'erin@example.com', birthDate: '1995-01-01', address: 'Somewhere', membership: { planId: gold.id, amountReceived: 700 } }));
  const e = asMember((await memberLogin('+919900009720')).accessToken);
  await e('PUT', '/v5/member/data', { state: { workouts: [], routines: [], unit: 'lb' } });
  await e('PUT', '/v5/member/me/photo', { data: PNG });
  await e('PATCH', '/v5/member/me/account', { fitness: { goal: 'stay_fit' }, heightCm: 170 });
  await e('PUT', '/v5/member/me/privacy', { shareTraining: 'gym' });
  const req = data(await e('POST', '/v5/member/me/requests', { type: 'cancel' }));
  // wrong confirmation, wrong code, someone else's code
  const otp = data(await e('POST', '/v5/member/me/account/delete-otp'));
  assert.equal((await e('DELETE', '/v5/member/me/account', { requestId: otp.requestId, otp: otp.devOtp, confirm: 'delete' })).status, 422);
  assert.equal((await e('DELETE', '/v5/member/me/account', { requestId: otp.requestId, otp: '000000', confirm: 'DELETE' })).status, 422);
  const aliceOtp = data(await a('POST', '/v5/member/me/account/delete-otp'));
  assert.equal((await e('DELETE', '/v5/member/me/account', { requestId: aliceOtp.requestId, otp: aliceOtp.devOtp, confirm: 'DELETE' })).status, 403, 'a code for another account');
  assert.equal((await a('GET', '/v5/member/me/account')).status, 200, 'and Alice is untouched');
  // the real thing
  const fresh = data(await e('POST', '/v5/member/me/account/delete-otp'));
  const del = await e('DELETE', '/v5/member/me/account', { requestId: fresh.requestId, otp: fresh.devOtp, confirm: 'DELETE' });
  assert.equal(del.status, 204, JSON.stringify(del.body));
  assert.equal((await e('GET', '/v5/member/me')).status, 401);
  assert.equal(h.store.get('SELECT COUNT(*) AS n FROM member_state WHERE member_id = ?', erin.id).n, 0);
  assert.equal(h.store.get('SELECT COUNT(*) AS n FROM files WHERE owner_id = ?', erin.id).n, 0);
  // signing in again is refused, with the same answer an unknown number gets
  const again = await h.call('POST', '/v5/member/auth/otp', { body: { phone: '+919900009720' } });
  assert.equal(again.status, 200);
  assert.equal((await h.call('POST', '/v5/member/auth/otp/verify', { body: { requestId: again.body.data.requestId, otp: '123456' } })).status, 422, 'no code was sent, as for any non-member');
  // what the gym keeps, and what is gone
  const m = data(await A.as('GET', `/v5/members/${erin.id}`));
  assert.equal(m.name, 'Erin Erase');
  assert.equal(m.phone, '+919900009720');
  assert.equal(m.memberships.length, 1, 'membership and payments are kept');
  assert.ok(m.recentTransactions.length >= 1);
  assert.equal(m.email, null);
  assert.equal(m.birthDate, null);
  assert.equal(m.address, null);
  assert.equal(m.photoUrl, null);
  assert.ok(m.memberApp.closedAt);
  assert.equal(data(await A.as('GET', `/v5/membership-requests/${req.id}`)).status, 'withdrawn', 'a pending request is withdrawn');
  // the gym can switch it back on; the member starts fresh
  assert.equal((await trainer.as('POST', `/v5/members/${erin.id}/member-app/reopen`)).status, 403);
  assert.equal((await A.as('POST', `/v5/members/${erin.id}/member-app/reopen`)).status, 200);
  assert.equal((await A.as('POST', `/v5/members/${erin.id}/member-app/reopen`)).status, 409);
  const back = asMember((await memberLogin('+919900009720')).accessToken);
  assert.equal(data(await back('GET', '/v5/member/data')).state, null);
  assert.equal(data(await back('GET', '/v5/member/me/privacy')).shareTraining, 'off');
});

// ---- membership requests -----------------------------------------------------------------------------------------------------
test('requests: a member asks; only the gym\'s owner or manager decides; nothing about the membership changes', async () => {
  const before = data(await A.as('GET', `/v5/members/${bob.id}`)).memberships[0];
  assert.equal((await b('POST', '/v5/member/me/requests', { type: 'bogus' })).status, 422);
  assert.equal((await b('POST', '/v5/member/me/requests', { type: 'change_plan' })).status, 422, 'a plan is needed');
  assert.equal((await b('POST', '/v5/member/me/requests', { type: 'change_plan', planId: silver.id })).status, 422, 'already on it');
  assert.equal((await b('POST', '/v5/member/me/requests', { type: 'change_plan', planId: 'nope' })).status, 422);
  const otherGymPlan = data(await B.as('GET', '/v5/memberships/plans'))[0].id;
  assert.equal((await b('POST', '/v5/member/me/requests', { type: 'renew', planId: otherGymPlan })).status, 422, 'another gym\'s plan does not exist here');
  const q = await b('POST', '/v5/member/me/requests', { type: 'change_plan', planId: gold.id, note: 'I want the locker', memberId: alice.id, status: 'approved' });
  assert.equal(q.status, 201, JSON.stringify(q.body));
  assert.equal(data(q).status, 'pending', 'a member cannot approve their own request');
  assert.equal((await b('POST', '/v5/member/me/requests', { type: 'change_plan', planId: gold.id })).status, 409, 'one open request of a kind');
  assert.ok((await b('POST', '/v5/member/me/requests', { type: 'cancel' })).status === 201);
  const mine = data(await b('GET', '/v5/member/me/requests'));
  assert.equal(mine.length, 2);
  assert.ok(mine.every((x) => x.status === 'pending'));
  assert.equal(data(await a('GET', '/v5/member/me/requests')).filter((x) => x.planName === 'Gold' && x.note === 'I want the locker').length, 0, 'it is Bob\'s, not Alice\'s');

  // who may see and decide
  const list = await A.as('GET', '/v5/membership-requests?status=pending');
  assert.equal(list.status, 200);
  const row = list.body.data.find((x) => x.note === 'I want the locker');
  assert.equal(row.member.name, 'Bob Member');
  assert.equal(row.currentMembership.planName, 'Silver');
  assert.ok(list.body.meta.pending >= 2);
  for (const who of [manager, desk]) assert.equal((await who.as('GET', '/v5/membership-requests')).status, 200);
  assert.equal((await trainer.as('GET', '/v5/membership-requests')).status, 403);
  assert.equal((await desk.as('POST', `/v5/membership-requests/${row.id}/decision`, { decision: 'approve' })).status, 403, 'the front desk can read, not decide');
  assert.equal((await trainer.as('POST', `/v5/membership-requests/${row.id}/decision`, { decision: 'approve' })).status, 403);
  assert.equal((await B.as('POST', `/v5/membership-requests/${row.id}/decision`, { decision: 'approve' })).status, 404, 'another gym\'s owner cannot even see it');
  assert.equal((await B.as('GET', '/v5/membership-requests')).body.data.length, 0);
  assert.ok([401, 403].includes((await b('POST', `/v5/membership-requests/${row.id}/decision`, { decision: 'approve' })).status), 'a member token is not a staff token');
  assert.equal((await manager.as('POST', `/v5/membership-requests/${row.id}/decision`, { decision: 'maybe' })).status, 422);
  const decided = await manager.as('POST', `/v5/membership-requests/${row.id}/decision`, { decision: 'approve', note: 'Come to the desk to pay the difference.' });
  assert.equal(decided.status, 200, JSON.stringify(decided.body));
  assert.equal(data(decided).status, 'approved');
  assert.equal((await A.as('POST', `/v5/membership-requests/${row.id}/decision`, { decision: 'reject' })).status, 409, 'decided once');
  // the member sees the answer; their membership did not move
  const seen = data(await b('GET', '/v5/member/me/requests')).find((x) => x.id === row.id);
  assert.equal(seen.status, 'approved');
  assert.equal(seen.decisionNote, 'Come to the desk to pay the difference.');
  const after = data(await A.as('GET', `/v5/members/${bob.id}`)).memberships[0];
  assert.deepEqual([after.planName, after.endDate, after.total, after.amountReceived], [before.planName, before.endDate, before.total, before.amountReceived]);
  // rejecting the other, and withdrawing
  const cancel = mine.find((x) => x.type === 'cancel');
  assert.equal((await A.as('POST', `/v5/membership-requests/${cancel.id}/decision`, { decision: 'reject', note: 'Please stay!' })).status, 200);
  assert.equal((await b('DELETE', `/v5/member/me/requests/${cancel.id}`)).status, 409, 'already decided');
  const again = data(await b('POST', '/v5/member/me/requests', { type: 'renew' }));
  assert.equal((await a('DELETE', `/v5/member/me/requests/${again.id}`)).status, 404, 'Alice cannot withdraw Bob\'s request');
  assert.equal((await b('DELETE', `/v5/member/me/requests/${again.id}`)).status, 204);
  assert.equal(data(await A.as('GET', `/v5/membership-requests/${again.id}`)).status, 'withdrawn');
});

test('requests: cancel needs a membership to cancel; a member with none can still ask to join a plan', async () => {
  const faye = data(await A.as('POST', '/v5/members', { name: 'Faye NoPlan', phone: '+919900009730' }));
  const f = asMember((await memberLogin('+919900009730')).accessToken);
  assert.equal((await f('POST', '/v5/member/me/requests', { type: 'cancel' })).status, 409);
  assert.equal((await f('POST', '/v5/member/me/requests', { type: 'renew' })).status, 422, 'no plan to renew: choose one');
  const q = await f('POST', '/v5/member/me/requests', { type: 'renew', planId: gold.id });
  assert.equal(q.status, 201);
  assert.equal(data(await A.as('GET', `/v5/members/${faye.id}`)).memberApp.pendingRequests, 1);
});

// ---- privacy -----------------------------------------------------------------------------------------------------------------------
test('privacy: what a trainer sees follows the member\'s choices; everyone else keeps their usual access', async () => {
  // by default a trainer sees what they always have
  const t0 = data(await trainer.as('GET', `/v5/members/${alice.id}`));
  assert.equal(t0.email, 'alice@example.com');
  assert.equal(t0.address, '1 Park Lane');
  // Alice hides some details from trainers
  const put = await a('PUT', '/v5/member/me/privacy', { trainerCanSee: { email: false, birthDate: false, health: false, emergencyContact: false, address: false } });
  assert.equal(put.status, 200);
  assert.equal(data(put).trainerCanSee.email, false);
  const t1 = data(await trainer.as('GET', `/v5/members/${alice.id}`));
  assert.deepEqual([t1.email, t1.birthDate, t1.address, t1.emergencyContact, t1.health, t1.bloodGroup], [null, null, null, null, null, null]);
  assert.deepEqual(t1.hiddenByMember.sort(), ['address', 'birthDate', 'email', 'emergencyContact', 'health']);
  assert.equal(t1.name, 'Alice Member', 'the trainer still knows who they are training');
  const listed = (await trainer.as('GET', '/v5/members')).body.data.find((x) => x.id === alice.id);
  assert.equal(listed.email, null);
  assert.equal((await trainer.as('GET', `/v5/members/${alice.id}/health`)).status, 403);
  // the owner, manager and front desk are not affected
  for (const who of [A, manager, desk]) {
    const full = data(await who.as('GET', `/v5/members/${alice.id}`));
    assert.equal(full.email, 'alice@example.com');
    assert.equal(full.address, '1 Park Lane');
    assert.ok(full.health);
  }
  assert.equal((await A.as('GET', `/v5/members/${alice.id}/health`)).status, 200);
  // putting it back
  await a('PUT', '/v5/member/me/privacy', { trainerCanSee: { email: true, birthDate: true, health: true, emergencyContact: true, address: true } });
  assert.equal(data(await trainer.as('GET', `/v5/members/${alice.id}`)).email, 'alice@example.com');
  assert.equal((await a('PUT', '/v5/member/me/privacy', { shareTraining: 'everyone' })).status, 422);
  assert.equal((await a('PUT', '/v5/member/me/privacy', { trainerCanSee: { salary: false } })).status, 200, 'unknown keys are dropped');
  assert.equal(data(await a('GET', '/v5/member/me/privacy')).trainerCanSee.salary, undefined);
});

test('privacy: a trainer reads only their own members\' memberships and health answers', async () => {
  const bobsMembership = data(await A.as('GET', `/v5/memberships?memberId=${bob.id}`))[0];
  assert.equal(data(await trainer.as('GET', '/v5/memberships')).every((m) => m.memberId === alice.id), true);
  assert.equal(data(await trainer.as('GET', `/v5/memberships?memberId=${bob.id}`)).length, 0);
  assert.equal((await trainer.as('GET', `/v5/memberships/${bobsMembership.id}`)).status, 404);
  assert.equal((await trainer.as('GET', `/v5/members/${bob.id}`)).status, 403, 'Bob is not Tina\'s member');
  assert.equal((await A.as('GET', `/v5/memberships/${bobsMembership.id}`)).status, 200);
  assert.equal(bobTrainerless.id, bob.id);
});

test('privacy: the training summary reaches only the people the member chose', async () => {
  const day = (n) => new Date(Date.now() - n * 864e5).toISOString().slice(0, 10);
  const w = (i, n, mins) => ({ id: `w${i}`, d: day(n), start: Date.parse(`${day(n)}T10:00:00Z`), end: Date.parse(`${day(n)}T10:00:00Z`) + mins * 60000, name: `Session ${i}`, entries: [{ id: '0025', sets: [{ w: 100, r: 5, done: true }] }] });
  const put = await a('PUT', '/v5/member/data', { state: { workouts: [w(1, 1, 40), w(2, 3, 50), w(3, 9, 60)], routines: [] } });
  assert.equal(put.status, 200, JSON.stringify(put.body));
  // private by default: nobody, not even the owner
  for (const who of [A, manager, desk, trainer]) assert.equal((await who.as('GET', `/v5/members/${alice.id}/training`)).status, 403, 'private by default');
  await a('PUT', '/v5/member/me/privacy', { shareTraining: 'trainer' });
  const t = await trainer.as('GET', `/v5/members/${alice.id}/training`);
  assert.equal(t.status, 200, JSON.stringify(t.body));
  assert.equal(data(t).totalWorkouts, 3);
  assert.equal(data(t).last30Days, 3);
  assert.equal(data(t).lastWorkoutAt, day(1));
  assert.equal(data(t).averageMinutes, 50);
  assert.equal(data(t).recent[0].name, 'Session 1');
  assert.equal(JSON.stringify(data(t)).includes('"w":100'), false, 'a summary, never the sets');
  assert.equal((await A.as('GET', `/v5/members/${alice.id}/training`)).status, 200);
  assert.equal((await manager.as('GET', `/v5/members/${alice.id}/training`)).status, 200);
  assert.equal((await desk.as('GET', `/v5/members/${alice.id}/training`)).status, 403, '"trainer" is not "everyone at the gym"');
  assert.equal((await otherTrainer.as('GET', `/v5/members/${alice.id}/training`)).status, 403, 'a trainer who is not hers');
  await a('PUT', '/v5/member/me/privacy', { shareTraining: 'gym' });
  assert.equal((await desk.as('GET', `/v5/members/${alice.id}/training`)).status, 200);
  assert.equal((await otherTrainer.as('GET', `/v5/members/${alice.id}/training`)).status, 403, 'still only her own trainer');
  assert.equal((await B.as('GET', `/v5/members/${alice.id}/training`)).status, 404, 'another gym');
  await a('PUT', '/v5/member/me/privacy', { shareTraining: 'off' });
  assert.equal((await A.as('GET', `/v5/members/${alice.id}/training`)).status, 403);
  // Bob shared nothing and has no log
  assert.equal((await A.as('GET', `/v5/members/${bob.id}/training`)).status, 403);
});

// ---- notifications ---------------------------------------------------------------------------------------------------------------------
test('notifications: optional notices can be switched off; the mandatory ones are listed and cannot be', async () => {
  const n0 = data(await a('GET', '/v5/member/me/notifications'));
  assert.deepEqual([n0.announcements.on, n0.membershipExpiry.on, n0.membershipExpiry.daysBefore], [true, true, 7]);
  assert.ok(n0.mandatory.length >= 3);
  assert.equal((await a('PUT', '/v5/member/me/notifications', { membershipExpiry: { daysBefore: 0 } })).status, 422);
  assert.equal((await a('PUT', '/v5/member/me/notifications', { membershipExpiry: { daysBefore: 31 } })).status, 422);
  const n1 = data(await a('PUT', '/v5/member/me/notifications', { announcements: { on: false }, membershipExpiry: { daysBefore: 3 }, mandatory: [], otp: false }));
  assert.deepEqual([n1.announcements.on, n1.membershipExpiry.on, n1.membershipExpiry.daysBefore], [false, true, 3]);
  assert.equal(n1.mandatory.length, n0.mandatory.length, 'mandatory notices cannot be edited');
  // one source of truth with the older preferences endpoint and with what the owner sees
  assert.equal(data(await a('GET', '/v5/member/me/preferences')).broadcasts, false);
  assert.equal(data(await A.as('GET', `/v5/members/${alice.id}`)).memberApp.broadcasts, false);
  await a('PUT', '/v5/member/me/notifications', { announcements: { on: true } });
  assert.equal(data(await a('GET', '/v5/member/me/notifications')).membershipExpiry.daysBefore, 3, 'a partial update keeps the rest');
  await a('PUT', '/v5/member/me/notifications', { membershipExpiry: { daysBefore: 7 } });
});

test('expiry alerts: each membership is warned once, on the member\'s own schedule, and never when they opted out', async () => {
  gymData(A.gym, { whatsapp: { enabled: true, status: 'connected' }, creditBalance: 100 });
  const mk = async (name, phone) => data(await A.as('POST', '/v5/members', { name, phone, membership: { planId: short.id, amountReceived: 100 } }));
  const soon = await mk('Soon Member', '+919900009741');
  const quiet = await mk('Quiet Member', '+919900009742');
  const early = await mk('Early Member', '+919900009743');
  const sq = asMember((await memberLogin(quiet.phone)).accessToken);
  const se = asMember((await memberLogin(early.phone)).accessToken);
  await sq('PUT', '/v5/member/me/notifications', { membershipExpiry: { on: false } });
  await se('PUT', '/v5/member/me/notifications', { membershipExpiry: { daysBefore: 1 } }); // a 3-day plan has more than 1 day left
  const sent = processExpiryReminders(h.store);
  assert.ok(sent >= 1);
  const sentTo = (member) => h.store.all("SELECT data FROM docs WHERE gym_id = ? AND collection = 'outbox'", A.gym).map((r) => JSON.parse(r.data))
    .filter((o) => o.memberId === member.id && o.key === 'MEMBERSHIP_EXPIRING_REMINDER_SMS').length;
  assert.equal(sentTo(soon), 1, 'default: 7 days ahead, so a 3-day membership is warned');
  assert.equal(sentTo(quiet), 0, 'opted out');
  assert.equal(sentTo(early), 0, 'asked for 1 day ahead');
  assert.equal(processExpiryReminders(h.store), 0, 'nobody is warned twice');
  assert.equal(sentTo(soon), 1);
});

// ---- inviting ---------------------------------------------------------------------------------------------------------------------------
test('invitations: the front desk can invite a member to the app, a trainer cannot, and the gym needs messaging on', async () => {
  const gina = data(await A.as('POST', '/v5/members', { name: 'Gina Invite', phone: '+919900009760' }));
  assert.equal((await trainer.as('POST', `/v5/members/${gina.id}/app-invite`)).status, 403);
  const ok = await desk.as('POST', `/v5/members/${gina.id}/app-invite`);
  assert.equal(ok.status, 200, JSON.stringify(ok.body));
  assert.ok(data(ok).invitedAt);
  const sent = h.store.all("SELECT data FROM docs WHERE gym_id = ? AND collection = 'outbox'", A.gym).map((r) => JSON.parse(r.data)).filter((o) => o.key === 'MEMBER_APP_INVITE' && o.memberId === gina.id);
  assert.equal(sent.length, 1);
  assert.ok(sent[0].body.includes('+919900009760') && sent[0].body.includes('Gym A'));
  assert.equal((await B.as('POST', `/v5/members/${gina.id}/app-invite`)).status, 404, 'another gym');
  gymData(B.gym, { whatsapp: { enabled: false } });
  assert.equal((await B.as('POST', `/v5/members/${carol.id}/app-invite`)).status, 409, 'messaging is off');
  assert.ok([401, 403].includes((await b('POST', `/v5/members/${gina.id}/app-invite`)).status));
});

// ---- payments and the gym ---------------------------------------------------------------------------------------------------------------
test('the gym profile shows the member\'s own payments and invoices, the plan\'s benefits, and what the gym offers; nothing of anyone else\'s', async () => {
  const p = data(await a('GET', '/v5/member/me/profile'));
  assert.ok(p.payments.length >= 1);
  assert.equal(p.payments[0].amount, 1000);
  assert.equal(p.payments[0].planName, 'Gold');
  assert.ok(p.payments[0].invoiceNo);
  assert.deepEqual(p.memberships[0].benefits, ['Locker', 'Towel']);
  assert.equal(typeof p.gym.features.workoutPlans, 'boolean');
  const text = JSON.stringify(p);
  for (const secret of ['createdById', 'staff only note', 'Bob Member', '+919900009702']) assert.ok(!text.includes(secret), secret);
  const bp = data(await b('GET', '/v5/member/me/profile'));
  assert.ok(bp.payments.every((x) => x.amount === 900), 'Bob sees Bob\'s');
});

test('a member cannot reach gym or platform settings, and a closed or blocked member is out at once', async () => {
  for (const [method, path] of [['GET', '/v5/gyms/current'], ['PATCH', '/v5/gyms/preferences'], ['GET', '/v5/gyms/staffs'], ['POST', '/v5/memberships/plans'], ['GET', '/v5/members'], ['GET', '/v5/membership-requests'], ['GET', '/v5/admin/gyms']]) {
    const r = await a(method, path, method === 'GET' ? undefined : {});
    assert.ok([401, 403, 404].includes(r.status), `${method} ${path} → ${r.status}`);
    assert.notEqual(r.status, 200, `${method} ${path}`);
  }
  const hank = data(await A.as('POST', '/v5/members', { name: 'Hank Blocked', phone: '+919900009770' }));
  const hk = asMember((await memberLogin(hank.phone)).accessToken);
  assert.equal((await hk('GET', '/v5/member/me/account')).status, 200);
  await A.as('POST', `/v5/members/${hank.id}/block`, { reason: 'x' });
  for (const p of ['/v5/member/me/account', '/v5/member/me/sessions', '/v5/member/me/requests', '/v5/member/me/privacy', '/v5/member/me/notifications']) {
    assert.ok([401, 403].includes((await hk('GET', p)).status), p); // blocking ends the session at once
  }
});

test('client-supplied identity is never trusted: ids in the URL, query or body do not change whose data is read or written', async () => {
  const viaQuery = data(await a('GET', `/v5/member/me/account?memberId=${bob.id}&gymId=${B.gym}`));
  assert.equal(viaQuery.id, alice.id);
  const q = data(await a('POST', '/v5/member/me/requests', { type: 'renew', planId: gold.id, memberId: bob.id, gymId: B.gym }));
  assert.equal(h.store.get("SELECT json_extract(data, '$.memberId') AS m FROM docs WHERE id = ?", q.id).m, alice.id);
  await a('DELETE', `/v5/member/me/requests/${q.id}`);
  const wrongHeader = await h.call('GET', '/v5/member/me/account', { token: aTok, gym: B.gym });
  assert.equal(data(wrongHeader).id, alice.id, 'the x-gym-id header is ignored');
});
