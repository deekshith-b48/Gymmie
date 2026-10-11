import { test, after, before } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { boot, data } from './helpers.js';
import { openDb, SCHEMA_VERSION } from '../src/db.js';
// The contract test: openGym's own verifier must accept what Gymmie signs.
import { verifyAssertion } from '../../member-app/opengym/api/sso.js';

const SSO = 's'.repeat(40);
let h; let o; let og; const ogCalls = [];
let alice; let bob;

function fakeOpenGym() {
  return new Promise((resolve) => {
    const srv = http.createServer((req, res) => {
      let body = '';
      req.on('data', (d) => { body += d; });
      req.on('end', () => { ogCalls.push({ url: req.url, auth: req.headers.authorization, body: JSON.parse(body || '{}') }); res.writeHead(200, { 'content-type': 'application/json' }); res.end('{"ok":true}'); });
    });
    srv.listen(0, '127.0.0.1', () => resolve(srv));
  });
}

const enable = (gym, on = true) => {
  const row = h.store.get('SELECT data FROM gyms WHERE id = ?', gym);
  const d = JSON.parse(row.data);
  d.features = { ...d.features, MEMBER_APP: on };
  h.store.run('UPDATE gyms SET data = ? WHERE id = ?', JSON.stringify(d), gym);
};

async function memberLogin(phone, extra = {}) {
  const r = await h.call('POST', '/v5/member/auth/otp', { body: { phone, ...extra } });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  const v = await h.call('POST', '/v5/member/auth/otp/verify', { body: { requestId: r.body.data.requestId, otp: '123456' } });
  return v;
}
const asMember = (token) => (method, path, body) => h.call(method, path, { body, token });

before(async () => {
  og = await fakeOpenGym();
  h = await boot({ openGymPublicUrl: 'https://og.example.test', openGymApiUrl: `http://127.0.0.1:${og.address().port}`, openGymSsoSecret: SSO });
  o = await h.owner({ phone: '+919876509101', gymName: 'Member Gym' });
  enable(o.gym);
  alice = data(await o.as('POST', '/v5/members', { name: 'Alice Member', phone: '+919900000101', notes: 'staff only note' }));
  bob = data(await o.as('POST', '/v5/members', { name: 'Bob Member', phone: '+919900000102' }));
});
after(async () => { await h.close(); og.close(); });

test('migration: a version-1 database upgrades in place and keeps its data', () => {
  const dir = mkdtempSync(join(tmpdir(), 'mig-'));
  const file = join(dir, 't.sqlite');
  try {
    const a = openDb(file);
    a.run("INSERT INTO gyms(id, code, data, created_at, updated_at) VALUES ('g','111111','{}','x','x')");
    a.db.exec('DROP TABLE member_state; DROP TABLE member_sessions; DROP INDEX idx_docs_member_phone; PRAGMA user_version = 0');
    a.close();
    const b = openDb(file);
    assert.equal(b.get('PRAGMA user_version').user_version, SCHEMA_VERSION);
    assert.ok(b.get("SELECT name FROM sqlite_master WHERE name = 'member_sessions'"));
    assert.equal(b.get("SELECT code FROM gyms WHERE id = 'g'").code, '111111');
    b.close();
    openDb(file).close(); // second open is a no-op
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('a member signs in with phone + OTP and sees only their own, whitelisted data', async () => {
  const v = await memberLogin('+919900000101');
  assert.equal(v.status, 200, JSON.stringify(v.body));
  const d = data(v);
  assert.equal(d.member.name, 'Alice Member');
  assert.equal(d.gym.name, 'Member Gym');
  const me = await asMember(d.accessToken)('GET', '/v5/member/me');
  assert.equal(me.status, 200);
  const text = JSON.stringify(me.body);
  assert.equal(data(me).member.id, alice.id);
  assert.ok(!text.includes('staff only note'), 'staff notes are never exposed');
  assert.ok(!text.includes('blockedReason') && !text.includes('labelIds') && !text.includes('+919900000101'));
  assert.equal(data(me).qrPayload, `gymmie://member/${data(me).gym.code}/${alice.id}`);
});

test('an unknown number gets the same answer as a member (no member enumeration)', async () => {
  const real = await h.call('POST', '/v5/member/auth/otp', { body: { phone: '+919900000102' } });
  const fake = await h.call('POST', '/v5/member/auth/otp', { body: { phone: '+919900099999' } });
  assert.equal(real.status, 200); assert.equal(fake.status, 200);
  const keys = (r) => Object.keys(data(r)).filter((k) => k !== 'devOtp').sort();
  assert.deepEqual(keys(real), keys(fake));
  const v = await h.call('POST', '/v5/member/auth/otp/verify', { body: { requestId: data(fake).requestId, otp: '123456' } });
  assert.equal(v.status, 422, 'a made-up request id fails like an expired code');
});

test('staff phone numbers are not members, and member numbers do not sign in as staff', async () => {
  const r = await h.call('POST', '/v5/member/auth/otp', { body: { phone: '+919876509101' } });
  const v = await h.call('POST', '/v5/member/auth/otp/verify', { body: { requestId: data(r).requestId, otp: '123456' } });
  assert.notEqual(v.status, 200);
  const s = await h.call('POST', '/v5/auth/login/otp', { body: { phone: '+919900000101' } });
  assert.equal(s.status, 404);
});

test('route sweep: a member token is refused by every non-member route, a staff token by every member route', async () => {
  const mt = data(await memberLogin('+919900000101')).accessToken;
  let checked = 0;
  for (const r of h.app.router.routes) {
    const path = r.path.replace(/:[A-Za-z0-9_]+/g, 'x');
    const body = ['POST', 'PUT', 'PATCH', 'DELETE'].includes(r.method) ? {} : undefined;
    if (r.opts.auth === 'member') {
      const res = await h.call(r.method, path, { body, token: o.token, gym: o.gym });
      assert.equal(res.status, 403, `${r.method} ${r.path} must refuse a staff token`);
    } else if (r.opts.auth !== 'none') {
      const res = await h.call(r.method, path, { body, token: mt, gym: o.gym });
      assert.ok([401, 403].includes(res.status), `${r.method} ${r.path} answered ${res.status} to a member token`);
    } else continue;
    checked++;
  }
  assert.ok(checked > 200, `swept ${checked} routes`);
});

test('refresh rotates; replaying an old refresh token ends the session family', async () => {
  const d = data(await memberLogin('+919900000101'));
  const r1 = await h.call('POST', '/v5/member/auth/refresh', { body: { refreshToken: d.refreshToken } });
  assert.equal(r1.status, 200);
  const next = data(r1);
  assert.equal((await asMember(next.accessToken)('GET', '/v5/member/me')).status, 200);
  assert.equal((await h.call('POST', '/v5/member/auth/refresh', { body: { refreshToken: d.refreshToken } })).status, 401);
  assert.equal((await asMember(next.accessToken)('GET', '/v5/member/me')).status, 401, 'the family is revoked');
});

test('the launch assertion is accepted by openGym once, carries no phone number, and is member-bound', async () => {
  const d = data(await memberLogin('+919900000101'));
  const l = await asMember(d.accessToken)('POST', '/v5/member/opengym/launch');
  assert.equal(l.status, 200, JSON.stringify(l.body));
  const L = data(l);
  assert.equal(L.redeemUrl, 'https://og.example.test/api/sso/redeem');
  assert.ok(!L.assertion.includes('9900000101'));
  const claims = verifyAssertion(SSO, L.assertion);
  assert.equal(claims.mid, alice.id);
  assert.equal(claims.gid, o.gym);
  assert.equal(claims.name, 'Alice Member');
  assert.equal(verifyAssertion('t'.repeat(40), L.assertion), null);
  assert.equal((await h.call('POST', '/v5/member/opengym/launch')).status, 401);
});

test('launch says so when openGym is not configured', async () => {
  const h2 = await boot();
  try {
    const o2 = await h2.owner({ phone: '+919876509102', gymName: 'Plain Gym' });
    const row = JSON.parse(h2.store.get('SELECT data FROM gyms WHERE id = ?', o2.gym).data);
    row.features.MEMBER_APP = true;
    h2.store.run('UPDATE gyms SET data = ? WHERE id = ?', JSON.stringify(row), o2.gym);
    await o2.as('POST', '/v5/members', { name: 'Cy', phone: '+919900000201' });
    const r = await h2.call('POST', '/v5/member/auth/otp', { body: { phone: '+919900000201' } });
    const v = await h2.call('POST', '/v5/member/auth/otp/verify', { body: { requestId: data(r).requestId, otp: '123456' } });
    const l = await h2.call('POST', '/v5/member/opengym/launch', { token: data(v).accessToken });
    assert.equal(l.status, 501);
  } finally { await h2.close(); }
});

test('blocking a member ends the app at once and tells openGym', async () => {
  const d = data(await memberLogin('+919900000102'));
  const t = asMember(d.accessToken);
  assert.equal((await t('GET', '/v5/member/me')).status, 200);
  ogCalls.length = 0;
  assert.equal((await o.as('POST', `/v5/members/${bob.id}/block`, { reason: 'unpaid' })).status, 200);
  assert.equal((await t('GET', '/v5/member/me')).status, 401, 'sessions were revoked');
  assert.equal((await h.call('POST', '/v5/member/auth/refresh', { body: { refreshToken: d.refreshToken } })).status, 401);
  await new Promise((r) => setTimeout(r, 100));
  assert.deepEqual(ogCalls.map((c) => [c.url, c.auth, c.body]), [['/api/sso/revoke', `Bearer ${SSO}`, { gid: o.gym, mid: bob.id }]]);
  const again = await memberLogin('+919900000102');
  assert.equal(again.status, 422, 'a blocked member gets no code (and nobody learns why)');
  await o.as('POST', `/v5/members/${bob.id}/unblock`);
  assert.equal((await memberLogin('+919900000102')).status, 200);
});

test('changing a member’s phone ends the old number’s access', async () => {
  const d = data(await memberLogin('+919900000101'));
  const t = asMember(d.accessToken);
  assert.equal((await t('GET', '/v5/member/me')).status, 200);
  const p = await o.as('PATCH', `/v5/members/${alice.id}`, { phone: '+919900000111' });
  assert.equal(p.status, 200, JSON.stringify(p.body));
  assert.equal((await t('GET', '/v5/member/me')).status, 401);
  assert.equal((await memberLogin('+919900000111')).status, 200);
});

test('switching MEMBER_APP off closes the app for that gym, and back on reopens it', async () => {
  const d = data(await memberLogin('+919900000111'));
  enable(o.gym, false);
  try {
    assert.equal((await asMember(d.accessToken)('GET', '/v5/member/me')).status, 403);
    assert.equal((await memberLogin('+919900000111')).status, 422);
  } finally { enable(o.gym, true); }
  assert.equal((await memberLogin('+919900000111')).status, 200);
});

test('deleting a member removes access', async () => {
  const c = data(await o.as('POST', '/v5/members', { name: 'Dee Gone', phone: '+919900000301' }));
  const d = data(await memberLogin('+919900000301'));
  assert.equal((await o.as('DELETE', `/v5/members/${c.id}`)).status, 204);
  assert.equal((await asMember(d.accessToken)('GET', '/v5/member/me')).status, 401);
});

test('a number that is a member of two gyms picks one; the gym code can narrow it', async () => {
  const o2 = await h.owner({ phone: '+919876509103', gymName: 'Second Gym' });
  enable(o2.gym);
  await o2.as('POST', '/v5/members', { name: 'Alice At Two', phone: '+919900000111' });
  const v = await memberLogin('+919900000111');
  assert.equal(v.status, 200);
  assert.equal(data(v).status, 'select_gym');
  assert.equal(data(v).gyms.length, 2);
  assert.equal(data(v).accessToken, undefined);
  const pick = await h.call('POST', '/v5/member/auth/select-gym', { body: { selectionToken: data(v).selectionToken, gymId: o2.gym } });
  assert.equal(pick.status, 200, JSON.stringify(pick.body));
  assert.equal(data(pick).gym.name, 'Second Gym');
  const me = await asMember(data(pick).accessToken)('GET', '/v5/member/me');
  assert.equal(data(me).member.name, 'Alice At Two');
  const bad = await h.call('POST', '/v5/member/auth/select-gym', { body: { selectionToken: data(v).selectionToken, gymId: 'not-a-gym' } });
  assert.equal(bad.status, 403);
  const forged = await h.call('POST', '/v5/member/auth/select-gym', { body: { selectionToken: data(v).selectionToken.slice(0, -3) + 'abc', gymId: o2.gym } });
  assert.equal(forged.status, 401);
  const code = h.store.get('SELECT code FROM gyms WHERE id = ?', o2.gym).code;
  const narrowed = await memberLogin('+919900000111', { gymCode: code });
  assert.equal(data(narrowed).gym.name, 'Second Gym');
});

test('sign-out ends the session and ends it in openGym', async () => {
  const d = data(await memberLogin('+919900000111', { gymCode: h.store.get('SELECT code FROM gyms WHERE id = ?', o.gym).code }));
  ogCalls.length = 0;
  assert.equal((await asMember(d.accessToken)('POST', '/v5/member/auth/logout')).status, 204);
  assert.equal((await asMember(d.accessToken)('GET', '/v5/member/me')).status, 401);
  await new Promise((r) => setTimeout(r, 100));
  assert.equal(ogCalls[0]?.url, '/api/sso/revoke');
});

// ---- training data document -----------------------------------------------------------------------------------------
const stateOf = (over = {}) => ({ unit: 'kg', routines: [], workouts: [], bodyweight: [{ d: '2026-10-01', w: 70 }], ...over });

test('member data: empty at first, saved with a revision, read back, and private to the member', async () => {
  const a = asMember(data(await memberLogin('+919900000111', { gymCode: h.store.get('SELECT code FROM gyms WHERE id = ?', o.gym).code })).accessToken);
  const first = await a('GET', '/v5/member/data');
  assert.deepEqual(data(first), { rev: 0, wid: null, state: null });
  const put = await a('PUT', '/v5/member/data', { state: stateOf(), baseRev: 0 });
  assert.equal(put.status, 200, JSON.stringify(put.body));
  assert.equal(data(put).rev, 1);
  const got = data(await a('GET', '/v5/member/data'));
  assert.equal(got.rev, 1);
  assert.equal(got.state.bodyweight[0].w, 70);
  // another member of the same gym sees nothing of it
  const b = asMember(data(await memberLogin('+919900000102')).accessToken);
  assert.equal(data(await b('GET', '/v5/member/data')).state, null);
});

test('member data: a stale baseRev is refused with the current document so the app can merge', async () => {
  const code = h.store.get('SELECT code FROM gyms WHERE id = ?', o.gym).code;
  const a = asMember(data(await memberLogin('+919900000111', { gymCode: code })).accessToken);
  const cur = data(await a('GET', '/v5/member/data'));
  assert.equal((await a('PUT', '/v5/member/data', { state: stateOf({ unit: 'lb' }), baseRev: cur.rev })).status, 200);
  const stale = await a('PUT', '/v5/member/data', { state: stateOf({ unit: 'kg' }), baseRev: cur.rev });
  assert.equal(stale.status, 409);
  assert.equal(stale.body.error.details.state.unit, 'lb');
  assert.equal(stale.body.error.details.rev, cur.rev + 1);
  assert.equal((await a('PUT', '/v5/member/data', { state: stateOf({ unit: 'kg' }) })).status, 200, 'no baseRev overwrites, as openGym does');
});

test('member data: bad documents are refused, an unfinished workout is never stored, size is capped', async () => {
  const code = h.store.get('SELECT code FROM gyms WHERE id = ?', o.gym).code;
  const a = asMember(data(await memberLogin('+919900000111', { gymCode: code })).accessToken);
  for (const bad of [{}, { state: [] }, { state: {} }, { state: { workouts: 'x' } }, { state: stateOf(), baseRev: 'one' }]) {
    assert.equal((await a('PUT', '/v5/member/data', bad)).status, 422, JSON.stringify(bad).slice(0, 40));
  }
  await a('PUT', '/v5/member/data', { state: stateOf({ active: { id: 'x', entries: [] }, _rev: 99 }) });
  const got = data(await a('GET', '/v5/member/data'));
  assert.equal(got.state.active, undefined);
  assert.equal(got.state._rev, undefined);
  const huge = await a('PUT', '/v5/member/data', { state: stateOf({ blob: 'x'.repeat(2 * 1024 * 1024 + 10) }) });
  assert.ok([413, 422].includes(huge.status), 'oversize is ' + huge.status);
  assert.equal((await h.call('GET', '/v5/member/data')).status, 401);
});

test('member data: "delete everything" and member removal clear the log', async () => {
  const code = h.store.get('SELECT code FROM gyms WHERE id = ?', o.gym).code;
  const a = asMember(data(await memberLogin('+919900000111', { gymCode: code })).accessToken);
  await a('PUT', '/v5/member/data', { state: stateOf() });
  assert.equal((await a('DELETE', '/v5/member/data')).status, 204);
  assert.equal(data(await a('GET', '/v5/member/data')).state, null);
  const c = data(await o.as('POST', '/v5/members', { name: 'Eli Erase', phone: '+919900000401' }));
  const t = asMember(data(await memberLogin('+919900000401')).accessToken);
  await t('PUT', '/v5/member/data', { state: stateOf() });
  await o.as('DELETE', `/v5/members/${c.id}`);
  assert.equal(h.store.get('SELECT 1 AS x FROM member_state WHERE member_id = ?', c.id), undefined);
});

// ---- gym profile, attendance, assigned plans, owner view, exercise library ----------------------------------------------
test('profile: the member reads their own record, the gym and its plans, with no staff-only fields', async () => {
  const plan = data(await o.as('POST', '/v5/memberships/plans', { name: 'Gold Monthly', price: 1500, durationDays: 30, description: 'All access', benefits: ['Free towel', 'Steam room'] }));
  const bad = await o.as('POST', '/v5/memberships/plans', { name: 'Bad Benefits', price: 1, durationDays: 30, benefits: ['x'.repeat(81)] });
  assert.equal(bad.status, 422, 'over-long benefit is refused');
  const m = data(await o.as('POST', '/v5/members', {
    name: 'Pia Profile', phone: '+919900000601', notes: 'INTERNAL: pays late', birthDate: '1995-04-02', bloodGroup: 'O+',
    membership: { planId: plan.id, amountReceived: 1000 },
  }));
  await o.as('POST', `/v5/members/${m.id}/block`, { reason: 'x' });
  await o.as('POST', `/v5/members/${m.id}/unblock`);
  const t = asMember(data(await memberLogin('+919900000601')).accessToken);
  const r = await t('GET', '/v5/member/me/profile');
  assert.equal(r.status, 200, JSON.stringify(r.body));
  const p = data(r);
  assert.equal(p.member.name, 'Pia Profile');
  assert.equal(p.member.bloodGroup, 'O+');
  assert.equal(p.gym.name, 'Member Gym');
  assert.equal(p.memberships.length, 1);
  assert.equal(p.memberships[0].planName, 'Gold Monthly');
  assert.equal(p.memberships[0].status, 'active');
  assert.equal(p.memberships[0].balance, 500);
  assert.deepEqual(p.memberships[0].benefits, ['Free towel', 'Steam room']);
  assert.deepEqual(p.gymPlans.find((x) => x.name === 'Gold Monthly').benefits, ['Free towel', 'Steam room']);
  assert.ok(p.gymPlans.some((x) => x.name === 'Gold Monthly' && x.price === 1500));
  const text = JSON.stringify(r.body);
  for (const secret of ['INTERNAL', 'blockedReason', 'labelIds', 'createdById']) assert.ok(!text.includes(secret), secret);
});

test('attendance: own visits, counts and streak; never another member’s', async () => {
  const a = data(await o.as('POST', '/v5/memberships/plans', { name: 'Att Plan', price: 100, durationDays: 30 }));
  const m1 = data(await o.as('POST', '/v5/members', { name: 'Att One', phone: '+919900000611', membership: { planId: a.id } }));
  const m2 = data(await o.as('POST', '/v5/members', { name: 'Att Two', phone: '+919900000612', membership: { planId: a.id } }));
  assert.equal((await o.as('POST', '/v5/attendance/mark', { memberId: m1.id })).status, 201);
  assert.equal((await o.as('POST', '/v5/attendance/mark', { memberId: m2.id })).status, 201);
  const t = asMember(data(await memberLogin('+919900000611')).accessToken);
  const r = data(await t('GET', '/v5/member/me/attendance?days=30'));
  assert.equal(r.visits.length, 1);
  assert.equal(r.total, 1);
  assert.equal(r.last30, 1);
  assert.equal(r.streakDays, 1);
  assert.equal(r.visits[0].source, 'manual');
  assert.equal(JSON.stringify(r).includes(m2.id), false);
  assert.equal(data(await t('GET', '/v5/member/me/attendance?days=9999')).days, 365);
});

test('plans: the workout and diet the trainer assigned appear for that member only', async () => {
  const m = data(await o.as('POST', '/v5/members', { name: 'Plan Pat', phone: '+919900000621' }));
  const other = data(await o.as('POST', '/v5/members', { name: 'Plan Other', phone: '+919900000622' }));
  const wp = data(await o.as('POST', '/v5/workout/plans', { name: 'Push/Pull', days: [{ name: 'Day 1', exercises: [{ name: 'Barbell Bench Press', exerciseId: 'og:0025', sets: 4, reps: '8-10' }] }] }));
  assert.equal((await o.as('POST', `/v5/workout/plans/${wp.id}/assign`, { memberId: m.id })).status, 201);
  const t = asMember(data(await memberLogin('+919900000621')).accessToken);
  const p = data(await t('GET', '/v5/member/me/plans'));
  assert.equal(p.workout.name, 'Push/Pull');
  assert.equal(p.workout.days[0].exercises[0].exerciseId, 'og:0025');
  assert.equal(p.workout.createdById, undefined);
  assert.equal(p.diet, null);
  const t2 = asMember(data(await memberLogin('+919900000622')).accessToken);
  assert.equal(data(await t2('GET', '/v5/member/me/plans')).workout, null);
  void other;
});

test('owner view: a member’s detail says whether and when they used the app', async () => {
  const m = data(await o.as('POST', '/v5/members', { name: 'Seen Sam', phone: '+919900000631' }));
  let d = data(await o.as('GET', `/v5/members/${m.id}`));
  assert.deepEqual(d.memberApp, { enabled: true, lastSeenAt: null, signIns: 0, broadcasts: true, closedAt: null, invitedAt: null, pendingRequests: 0 });
  await memberLogin('+919900000631');
  d = data(await o.as('GET', `/v5/members/${m.id}`));
  assert.equal(d.memberApp.signIns, 1);
  assert.ok(Date.parse(d.memberApp.lastSeenAt) > Date.now() - 60000);
});

test('exercise library: openGym’s catalogue is part of the default exercises, paged and searchable', async () => {
  const all = await o.as('GET', '/v5/exercises');
  assert.equal(all.status, 200);
  assert.equal(all.body.data.length, 300);
  assert.ok(all.body.meta.total > 5000, `total ${all.body.meta.total}`);
  assert.ok(all.body.data.every((e) => e.builtIn === true));
  const bench = data(await o.as('GET', '/v5/exercises?q=bench%20press&limit=1000'));
  assert.ok(bench.some((e) => e.id === 'og:0025' || e.id.startsWith('og:')), 'openGym entries are found');
  assert.ok(bench.some((e) => e.id.startsWith('lib:')), 'Gymmie’s own entries remain');
  const og = bench.find((e) => e.id.startsWith('og:'));
  assert.ok(['Chest', 'Back', 'Shoulders', 'Arms', 'Legs', 'Core', 'Cardio'].includes(og.category));
  assert.ok(og.equipment.length >= 1);
  assert.match(og.name, /^[A-Z0-9]/);
  const chest = data(await o.as('GET', '/v5/exercises?category=Chest&limit=1000'));
  assert.ok(chest.every((e) => e.category === 'Chest'));
  assert.equal((await o.as('POST', '/v5/exercises', { name: 'Archer Push Up', category: 'Chest' })).status, 409, 'cannot shadow a built-in name');
});

// ---- settings, communication preference, sign out everywhere ----------------------------------------------------------
test('settings: the member keeps their settings in the log; wrong types are refused, openGym keys survive', async () => {
  const m = data(await o.as('POST', '/v5/members', { name: 'Sam Settings', phone: '+919900000701' }));
  const t = asMember(data(await memberLogin('+919900000701')).accessToken);
  for (const bad of [{ restSec: 'abc' }, { restSec: -1 }, { restSec: 99999 }, { theme: { x: 1 } }, { weekStart: 9 }, { sound: 'yes' },
    { equipProfiles: 'home' }, { accentCustom: '#12345678' }, { wdec: 0 }]) {
    const r = await t('PUT', '/v5/member/data', { state: { workouts: [], routines: [], ...bad } });
    assert.equal(r.status, 422, `${JSON.stringify(bad)} → ${r.status}`);
  }
  const good = {
    workouts: [], routines: [], unit: 'lb', restSec: 0, theme: 'light', accent: 'custom', accentCustom: '#ff8800', weekStart: 0, wdec: 2,
    sound: false, vibrate: true, timerFlash: true, weighIn: false, effort: null, heatmapMetric: 'vol', body: 'female',
    equipProfiles: [{ id: 'p1', name: 'Home', eq: ['dumbbell'] }], wc: { steppers: false }, someOpenGymKey: { keep: 'me' },
  };
  assert.equal((await t('PUT', '/v5/member/data', { state: good })).status, 200);
  const got = data(await t('GET', '/v5/member/data')).state;
  assert.equal(got.unit, 'lb');
  assert.equal(got.restSec, 0);
  assert.equal(got.accentCustom, '#ff8800');
  assert.deepEqual(got.someOpenGymKey, { keep: 'me' });
  // private to the member: nothing in a staff-readable member record carries the settings
  const detail = JSON.stringify(data(await o.as('GET', `/v5/members/${m.id}`)));
  assert.ok(!detail.includes('heatmapMetric') && !detail.includes('#ff8800'));
});

test('preferences: the member chooses, the owner sees it, broadcasts respect it, staff cannot change it', async () => {
  const m = data(await o.as('POST', '/v5/members', { name: 'Pat Prefs', phone: '+919900000711' }));
  const t = asMember(data(await memberLogin('+919900000711')).accessToken);
  assert.equal(data(await t('GET', '/v5/member/me/preferences')).broadcasts, true, 'on by default');
  assert.equal(data(await o.as('GET', `/v5/members/${m.id}`)).memberApp.broadcasts, true);
  const before = data(await o.as('POST', '/v5/broadcasts/recipients/preview', { filter: {} }));
  assert.equal((await t('PUT', '/v5/member/me/preferences', { broadcasts: 'no' })).status, 422);
  assert.equal((await t('PUT', '/v5/member/me/preferences', {})).status, 422);
  const r = await t('PUT', '/v5/member/me/preferences', { broadcasts: false });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(data(r).broadcasts, false);
  assert.equal(data(await t('GET', '/v5/member/me/preferences')).broadcasts, false, 'persisted');
  // the owner's dashboard follows at once
  assert.equal(data(await o.as('GET', `/v5/members/${m.id}`)).memberApp.broadcasts, false);
  const after = data(await o.as('POST', '/v5/broadcasts/recipients/preview', { filter: {} }));
  assert.equal(after.count, before.count - 1, 'an opted-out member is not a recipient');
  assert.equal(after.optedOut, before.optedOut + 1);
  // staff cannot flip it: not through the member record, not through the member route
  await o.as('PATCH', `/v5/members/${m.id}`, { communication: { broadcasts: true }, name: 'Pat Prefs' });
  assert.equal(data(await t('GET', '/v5/member/me/preferences')).broadcasts, false);
  assert.equal((await o.as('PUT', '/v5/member/me/preferences', { broadcasts: true })).status, 403);
  assert.equal((await h.call('GET', '/v5/member/me/preferences')).status, 401);
  // and back on
  assert.equal(data(await t('PUT', '/v5/member/me/preferences', { broadcasts: true })).broadcasts, true);
  assert.equal(data(await o.as('POST', '/v5/broadcasts/recipients/preview', { filter: {} })).count, before.count);
});

test('sign out everywhere: every session of that member ends, other members are untouched', async () => {
  const m = data(await o.as('POST', '/v5/members', { name: 'Una Everywhere', phone: '+919900000721' }));
  const other = data(await o.as('POST', '/v5/members', { name: 'Otto Other', phone: '+919900000722' }));
  const first = data(await memberLogin('+919900000721'));
  const second = data(await memberLogin('+919900000721')); // a second phone signed in as the same member
  const phone2 = asMember(second.accessToken);
  const otherToken = asMember(data(await memberLogin('+919900000722')).accessToken);
  assert.equal((await phone2('GET', '/v5/member/me')).status, 200);
  const out = await asMember(first.accessToken)('POST', '/v5/member/auth/logout-all');
  assert.equal(out.status, 204);
  assert.equal((await phone2('GET', '/v5/member/me')).status, 401);
  const refreshed = await h.call('POST', '/v5/member/auth/refresh', { body: { refreshToken: first.refreshToken } });
  assert.ok([401, 403].includes(refreshed.status), 'the refresh token died with the sessions: ' + refreshed.status);
  assert.equal((await otherToken('GET', '/v5/member/me')).status, 200, 'someone else is unaffected');
  assert.ok(m.id && other.id);
});
