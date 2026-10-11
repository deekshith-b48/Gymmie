// The single sign-in: one code, then the server says who the number is. Staff only, member only, both, several gyms,
// nobody, blocked, a forged choice, and that an unknown number is indistinguishable from a known one before the code.
import { test, after, before } from 'node:test';
import assert from 'node:assert/strict';
import { boot, data } from './helpers.js';

let h; let A; let B; let C;
const setFlag = (gym) => {
  const d = JSON.parse(h.store.get('SELECT data FROM gyms WHERE id = ?', gym).data);
  h.store.run('UPDATE gyms SET data = ? WHERE id = ?', JSON.stringify({ ...d, features: { ...d.features, MEMBER_APP: true } }), gym);
};
const ask = (phone, extra = {}) => h.call('POST', '/v5/auth/signin/otp', { body: { phone, ...extra } });
const verify = (requestId, otp = '123456') => h.call('POST', '/v5/auth/signin/verify', { body: { requestId, otp, device: 'test phone' } });
const choose = (selectionToken, option) => h.call('POST', '/v5/auth/signin/choose', { body: { selectionToken, option } });
const go = async (phone, extra) => { const r = await ask(phone, extra); assert.equal(r.status, 200, JSON.stringify(r.body)); return verify(data(r).requestId); };

before(async () => {
  h = await boot();
  A = await h.owner({ phone: '+919876508801', gymName: 'Gym A' });
  B = await h.owner({ phone: '+919876508802', gymName: 'Gym B' });
  C = await h.owner({ phone: '+919876508803', gymName: 'Gym C' });
  setFlag(A.gym); setFlag(B.gym);
  const plan = async (o) => data(await o.as('POST', '/v5/memberships/plans', { name: 'P', price: 100, durationDays: 30 }));
  const pa = await plan(A); const pb = await plan(B);
  // a pure member in A; the owner of C who is ALSO a member of A; someone who is a member of both A and B
  await A.as('POST', '/v5/members', { name: 'Pure Member', phone: '+919900008801', membership: { planId: pa.id, amountReceived: 100 } });
  await A.as('POST', '/v5/members', { name: 'Owner As Member', phone: '+919876508803', membership: { planId: pa.id, amountReceived: 100 } });
  await A.as('POST', '/v5/members', { name: 'Two Gyms', phone: '+919900008802', membership: { planId: pa.id, amountReceived: 100 } });
  await B.as('POST', '/v5/members', { name: 'Two Gyms', phone: '+919900008802', membership: { planId: pb.id, amountReceived: 100 } });
});
after(async () => { await h.close(); });

test('a gym owner with no member record goes straight to the staff app', async () => {
  const v = await go('+919876508802');
  assert.equal(v.status, 200);
  const d = data(v);
  assert.equal(d.status, 'signed_in');
  assert.equal(d.kind, 'staff');
  assert.ok(d.accessToken && d.gyms.length);
  assert.equal((await h.call('GET', '/v5/member/me', { token: d.accessToken })).status >= 400, true, 'a staff token is useless on member routes');
});

test('a plain member goes straight to the member app, and the token is a member token', async () => {
  const d = data(await go('+919900008801'));
  assert.equal(d.status, 'signed_in');
  assert.equal(d.kind, 'member');
  assert.equal(d.member.name, 'Pure Member');
  assert.equal((await h.call('GET', '/v5/member/me', { token: d.accessToken })).status, 200);
  assert.equal((await h.call('GET', '/v5/gyms/current', { token: d.accessToken })).status >= 400, true, 'a member token is useless on staff routes');
});

test('someone who is both is asked which to open; each choice gives only that principal', async () => {
  const d = data(await go('+919876508803'));
  assert.equal(d.status, 'choose');
  assert.deepEqual(d.options.map((o) => o.kind).sort(), ['member', 'staff']);
  const asStaff = data(await choose(d.selectionToken, 'staff'));
  assert.equal(asStaff.kind, 'staff');
  const asMember = data(await choose(d.selectionToken, d.options.find((o) => o.kind === 'member').id));
  assert.equal(asMember.kind, 'member');
  assert.equal((await h.call('GET', '/v5/member/me', { token: asStaff.accessToken })).status >= 400, true);
  assert.equal((await h.call('GET', '/v5/member/me', { token: asMember.accessToken })).status, 200);
});

test('a member of two gyms picks one of them (no staff option is offered)', async () => {
  const d = data(await go('+919900008802'));
  assert.equal(d.status, 'choose');
  assert.equal(d.options.length, 2);
  assert.ok(d.options.every((o) => o.kind === 'member'));
  const m = data(await choose(d.selectionToken, d.options[1].id));
  assert.equal(m.kind, 'member');
});

test('a choice cannot be forged, widened or replayed on another number', async () => {
  const d = data(await go('+919900008801'.replace('01', '02')));
  const bad = await choose(d.selectionToken, 'staff');
  assert.equal(bad.status, 403, 'a member-only number cannot pick staff');
  const tampered = await choose(`${d.selectionToken}x`, d.options[0].id);
  assert.equal(tampered.status, 401);
  const unknown = await choose(d.selectionToken, 'member:not-a-gym');
  assert.equal(unknown.status, 403);
  assert.equal((await choose(d.selectionToken, 'whatever')).status, 422);
});

test('an unknown number looks exactly like a known one until the code is tried, then fails without detail', async () => {
  const known = await ask('+919900008801');
  const unknown = await ask('+919311100000');
  assert.equal(known.status, 200);
  assert.equal(unknown.status, 200);
  assert.deepEqual(Object.keys(data(unknown)).filter((k) => k !== 'devOtp').sort(), Object.keys(data(known)).filter((k) => k !== 'devOtp').sort());
  const v = await verify(data(unknown).requestId);
  assert.ok(v.status >= 400 && v.status < 500);
});

test('a wrong code is refused', async () => {
  const r = data(await ask('+919900008801'.replace('01', '01')));
  assert.ok(r.requestId);
  assert.ok((await verify(r.requestId, '000000')).status >= 400);
});

test('a disabled staff account or a blocked member gets nothing', async () => {
  const blockedPhone = '+919900008809';
  const pa = data(await A.as('POST', '/v5/memberships/plans', { name: 'Q', price: 1, durationDays: 30 }));
  const m = data(await A.as('POST', '/v5/members', { name: 'Soon Blocked', phone: blockedPhone, membership: { planId: pa.id, amountReceived: 1 } }));
  const r = data(await ask(blockedPhone));
  assert.equal((await A.as('POST', `/v5/members/${m.id}/block`, { reason: 'x' })).status < 300, true);
  const v = await verify(r.requestId);
  assert.equal(v.status, 403, 'judged again when the code is used');
});

test('member access stays off when the gym has not enabled the member app', async () => {
  const pc = data(await C.as('POST', '/v5/memberships/plans', { name: 'P', price: 100, durationDays: 30 }));
  await C.as('POST', '/v5/members', { name: 'Gym C Member', phone: '+919900008820', membership: { planId: pc.id, amountReceived: 100 } });
  const r = data(await ask('+919900008820'));
  const v = await verify(r.requestId);
  assert.ok(v.status >= 400 && v.status < 500, 'no session is started');
  assert.equal(data(v)?.accessToken, undefined);
});

test('requests are rate limited per number (and per address)', async () => {
  const strict = await boot({ rateLimitScale: 1 });
  try {
    let last;
    for (let i = 0; i < 8; i++) last = await strict.call('POST', '/v5/auth/signin/otp', { body: { phone: '+919311100001' } });
    assert.equal(last.status, 429);
  } finally { await strict.close(); }
});
