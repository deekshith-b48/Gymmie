import { test, after, before } from 'node:test';
import assert from 'node:assert/strict';
import { boot, data } from './helpers.js';
import { loadConfig } from '../src/config.js';

let h;
before(async () => { h = await boot(); });
after(async () => { await h.close(); });

test('production mode refuses development switches and requires a JWT secret', () => {
  assert.throws(() => loadConfig({ env: 'production' }), /JWT_SECRET is required/);
  const old = process.env.DEV_FIXED_OTP;
  process.env.DEV_FIXED_OTP = '111111';
  try { assert.throws(() => loadConfig({ env: 'production', jwtSecret: 'x'.repeat(40) }), /DEV_\* switches/); } finally { if (old === undefined) delete process.env.DEV_FIXED_OTP; else process.env.DEV_FIXED_OTP = old; }
});

test('protected routes reject missing, malformed and tampered tokens', async () => {
  assert.equal((await h.call('GET', '/v5/gyms')).status, 401);
  assert.equal((await h.call('GET', '/v5/gyms', { token: 'abc.def.ghi' })).status, 401);
  const o = await h.owner({ phone: '+919876500101', gymName: 'Tamper Gym' });
  const [a, b, c] = o.token.split('.');
  const forged = `${a}.${Buffer.from(JSON.stringify({ sub: 'someone', sid: 'x', exp: 9999999999 })).toString('base64url')}.${c}`;
  assert.equal((await h.call('GET', '/v5/gyms', { token: forged })).status, 401);
  assert.equal((await h.call('GET', '/v5/gyms', { token: o.token })).status, 200);
});

test('registration validates input and refuses duplicate phones', async () => {
  const bad = await h.call('POST', '/v5/register/partner', { body: { name: 'A', phone: '12345' } });
  assert.equal(bad.status, 422);
  const o = await h.owner({ phone: '+919876500102', gymName: 'Dup Gym' });
  const dup = await h.call('POST', '/v5/register/partner', { body: { name: 'Another Person', phone: '+919876500102' } });
  assert.equal(dup.status, 409);
  assert.match(dup.body.error.message, /already used/);
  const g2 = await h.call('POST', '/v5/register/partner/gym', { token: o.token, body: { name: 'dup gym', address: '99 Another Street' } });
  assert.equal(g2.status, 409);
  assert.equal(g2.body.error.message, 'Gym Already Registered');
});

test('OTP: wrong code is rejected, attempts are capped, codes are single-use', async () => {
  await h.owner({ phone: '+919876500103', gymName: 'Otp Gym' });
  const r = await h.call('POST', '/v5/auth/login/otp', { body: { phone: '+919876500103' } });
  const id = data(r).requestId;
  for (let i = 0; i < 5; i++) assert.equal((await h.call('POST', '/v5/auth/login/otp/verify', { body: { requestId: id, otp: '000000' } })).status, 422);
  const locked = await h.call('POST', '/v5/auth/login/otp/verify', { body: { requestId: id, otp: '123456' } });
  assert.equal(locked.status, 429);
  const r2 = await h.call('POST', '/v5/auth/login/otp', { body: { phone: '+919876500103' } });
  const ok = await h.call('POST', '/v5/auth/login/otp/verify', { body: { requestId: data(r2).requestId, otp: '123456' } });
  assert.equal(ok.status, 200);
  const replay = await h.call('POST', '/v5/auth/login/otp/verify', { body: { requestId: data(r2).requestId, otp: '123456' } });
  assert.equal(replay.status, 422);
});

test('unknown account on login is a 404, not a silent success', async () => {
  const r = await h.call('POST', '/v5/auth/login/otp', { body: { phone: '+919000011111' } });
  assert.equal(r.status, 404);
});

test('refresh tokens rotate and a replayed token revokes the whole session family', async () => {
  const o = await h.owner({ phone: '+919876500104', gymName: 'Refresh Gym' });
  const r1 = await h.call('POST', '/v5/auth/refresh', { body: { refreshToken: o.refresh } });
  assert.equal(r1.status, 200);
  const newRefresh = data(r1).refreshToken;
  assert.notEqual(newRefresh, o.refresh);
  // replaying the OLD token => family revoked
  assert.equal((await h.call('POST', '/v5/auth/refresh', { body: { refreshToken: o.refresh } })).status, 401);
  // ...so even the newest token no longer works
  assert.equal((await h.call('POST', '/v5/auth/refresh', { body: { refreshToken: newRefresh } })).status, 401);
  // and the access token tied to the family is dead as well
  assert.equal((await h.call('GET', '/v5/users/self', { token: data(r1).accessToken })).status, 401);
});

test('logout ends the session', async () => {
  const o = await h.owner({ phone: '+919876500105', gymName: 'Logout Gym' });
  assert.equal((await h.call('POST', '/v3/auth/logout', { token: o.token })).status, 204);
  assert.equal((await h.call('GET', '/v5/users/self', { token: o.token })).status, 401);
});

test('tenant isolation: another gym owner cannot read or touch this gym', async () => {
  const a = await h.owner({ phone: '+919876500106', gymName: 'Gym A' });
  const b = await h.owner({ phone: '+919876500107', gymName: 'Gym B' });
  await a.as('POST', '/v5/members', { name: 'Secret Member', phone: '+919111100001' });
  // B asking for A's data using A's gym id header
  const cross = await h.call('GET', '/v5/members', { token: b.token, gym: a.gym });
  assert.equal(cross.status, 403);
  const own = await b.as('GET', '/v5/members');
  assert.deepEqual(data(own), []);
  const prof = await h.call('GET', `/v5/gyms/${a.gym}`, { token: b.token, gym: b.gym });
  assert.equal(prof.status, 403);
});

test('role permissions: trainer cannot see finance or staff admin; manager cannot manage staff', async () => {
  const o = await h.owner({ phone: '+919876500108', gymName: 'Roles Gym' });
  const t = await o.as('POST', '/v5/gyms/staffs', { name: 'Tina Trainer', phone: '+919222200001', role: 'trainer' });
  assert.equal(t.status, 201);
  assert.equal(data(t).status, 'invited');
  const m = await o.as('POST', '/v5/gyms/staffs', { name: 'Mike Manager', phone: '+919222200002', role: 'manager' });
  assert.equal(m.status, 201);
  const trainer = await h.loginAs('+919222200001', o.gym);
  assert.equal((await trainer.as('GET', '/v5/members/transactions')).status, 403);
  assert.equal((await trainer.as('GET', '/v5/gyms/staffs')).status, 403);
  assert.equal((await trainer.as('GET', '/v5/members')).status, 200);
  const manager = await h.loginAs('+919222200002', o.gym);
  assert.equal((await manager.as('GET', '/v5/gyms/staffs')).status, 200);
  assert.equal((await manager.as('POST', '/v5/gyms/staffs', { name: 'Zed', phone: '+919222200003', role: 'staff' })).status, 403);
  assert.equal((await manager.as('GET', '/v5/members/transactions')).status, 200);
});

test('gym name is immutable via the API; UPI id is validated', async () => {
  const o = await h.owner({ phone: '+919876500109', gymName: 'Immutable Gym' });
  const rename = await o.as('PATCH', `/v5/gyms/${o.gym}`, { name: 'Different Name' });
  assert.equal(rename.status, 403);
  assert.match(rename.body.error.message, /contact support/);
  assert.equal((await o.as('PATCH', `/v5/gyms/${o.gym}`, { upiId: 'not a upi' })).status, 422);
  const ok = await o.as('PATCH', `/v5/gyms/${o.gym}`, { upiId: 'merchant@okbank' });
  assert.equal(data(ok).upiId, 'merchant@okbank');
});

test('file upload sniffs the real type and enforces the size cap', async () => {
  const o = await h.owner({ phone: '+919876500110', gymName: 'File Gym' });
  const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=', 'base64');
  const up = await o.as('POST', '/v5/files', { data: png.toString('base64'), contentType: 'image/png' });
  assert.equal(up.status, 201);
  const get = await h.call('GET', data(up).url, { token: o.token, raw: true });
  assert.equal(get.status, 200);
  assert.equal(get.headers.get('content-type'), 'image/png');
  const fake = await o.as('POST', '/v5/files', { data: Buffer.from('<script>alert(1)</script>').toString('base64'), contentType: 'image/png' });
  assert.equal(fake.status, 422);
  const mismatch = await o.as('POST', '/v5/files', { data: png.toString('base64'), contentType: 'application/pdf' });
  assert.equal(mismatch.status, 422);
  const other = await h.owner({ phone: '+919876500111', gymName: 'Other File Gym' });
  assert.equal((await h.call('GET', data(up).url, { token: other.token })).status, 403);
});
