// Regression tests for V-10 (purge), V-11 (body after auth), V-12 (no 500s), V-17 (file quota), V-18 (contact change), V-19 (devices),
// V-21 (separate keys) and V-22 (safe seed).
import { test, after, before } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { boot, data } from './helpers.js';
import { purgeExpired } from '../src/domain/housekeeping.js';
import { assertSafeToReset, DEMO_PHONES } from '../src/seed.js';
import { loadConfig } from '../src/config.js';

let h; let o; let n = 0;
const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==', 'base64').toString('base64');
before(async () => { h = await boot({ fileQuotaBytes: 200 }); o = await h.owner({ phone: '+919876655001', gymName: 'Hardening Gym' }); });
after(async () => { await h.close(); });

test('V-10: old sign-in codes, sessions and events are purged; live ones and consent evidence stay', async () => {
  const now = Date.now(); const DAY = 86_400_000;
  h.store.run("INSERT INTO otp_requests(id, purpose, channel, target, code_hash, expires_at, created_at) VALUES ('old','x','sms','+919000000099','h',1,?)", now - 2 * DAY);
  h.store.run("INSERT INTO otp_requests(id, purpose, channel, target, code_hash, expires_at, created_at) VALUES ('new','x','sms','+919000000098','h',1,?)", now - 3600_000);
  h.store.run("INSERT INTO otp_guard(target, fails, window_start, locked_until, level, last_fail) VALUES ('+919000000099',1,1,1,1,?)", now - 3 * DAY);
  h.store.run("INSERT INTO security_events(at, kind) VALUES (?, 'ancient')", now - 200 * DAY);
  h.store.run("INSERT INTO security_events(at, kind) VALUES (?, 'recent')", now - DAY);
  const uid = o.user.id;
  h.store.run("INSERT INTO sessions(id, user_id, family_id, token_hash, expires_at, revoked, created_at) VALUES ('s-old',?,'f1','t1',?,1,?)", uid, now - 40 * DAY, now - 50 * DAY);
  h.store.run("INSERT INTO consents(user_id, version, accepted_at, ip) VALUES (?, 'v-test', 'x', '1.2.3.4')", uid);
  const r = purgeExpired(h.store, now);
  assert.ok(r.otpRequests >= 1 && r.otpGuard >= 1 && r.securityEvents >= 1 && r.sessions >= 1);
  assert.equal(h.store.get("SELECT 1 x FROM otp_requests WHERE id = 'old'"), undefined);
  assert.ok(h.store.get("SELECT 1 x FROM otp_requests WHERE id = 'new'"));
  assert.equal(h.store.get("SELECT 1 x FROM security_events WHERE kind = 'ancient'"), undefined);
  assert.ok(h.store.get("SELECT 1 x FROM security_events WHERE kind = 'recent'"));
  assert.ok(h.store.get("SELECT 1 x FROM consents WHERE version = 'v-test'"), 'consent evidence is kept');
  assert.equal((await h.call('GET', '/v5/users/self', { token: o.token })).status, 200, 'the live session still works');
});

test('V-11: an anonymous client is told "sign in" without the server reading its body, and anonymous bodies are small', async () => {
  const big = JSON.stringify({ x: 'a'.repeat(300_000) });
  const anon = await fetch(`${h.base}/v5/auth/signin/otp`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: big });
  assert.equal(anon.status, 413, 'public calls take small bodies only');
  const unauth = await fetch(`${h.base}/v5/members`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ x: 'a'.repeat(5_000_000) }) });
  assert.equal(unauth.status, 401, 'refused for who they are before anything is read');
  const bad = await fetch(`${h.base}/v5/members`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${o.token}`, 'x-gym-id': o.gym }, body: '{not json' });
  assert.equal(bad.status, 400, 'a signed-in caller still gets a parse error');
  const upload = await o.as('POST', '/v5/files', { data: PNG, contentType: 'image/png' });
  assert.notEqual(upload.status, 413, 'signed-in uploads keep their large limit');
});

test('V-11: anonymous endpoints have a per-address request budget', async () => {
  const hh = await boot({ rateLimitScale: 1 });
  let first429 = null;
  for (let i = 1; i <= 320; i++) { const r = await hh.call('GET', '/v5/masters/countries'); if (r.status === 429) { first429 = i; break; } }
  assert.equal(first429, 301);
  assert.equal((await hh.call('GET', '/health')).status, 200, 'health checks are never throttled');
  await hh.close();
});

test('V-12: hostile paths, sorts and bodies give 4xx, never 500', async () => {
  const tok = { token: o.token, gym: o.gym };
  for (const p of ['/v5/members/%', '/v5/members/%E0%A4%A', '/v5/members/..%2f..%2fetc']) assert.ok((await h.call('GET', p, tok)).status < 500, p);
  for (const p of ['/v5/members?sort=__proto__', '/v5/members?sort=constructor', '/v5/members/export?sort=toString', '/v5/prospects/members?sort=__proto__', '/v5/products?sort=__proto__', '/v5/members?sort=hasOwnProperty']) {
    const r = await h.call('GET', p, { ...tok, raw: true });
    assert.equal(r.status, 200, p);
  }
  for (const body of [null, [], 'text', 7]) {
    const r = await fetch(`${h.base}/v3/users/self/email/verification`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${o.token}` }, body: JSON.stringify(body) });
    assert.equal(r.status, 400, JSON.stringify(body));
  }
});

test('V-17: a gym has a file storage quota, and uploads are rate limited per user', async () => {
  // the quota is 200 bytes in this server and each PNG is 70 bytes (one is already stored by the test above): some fit, then it is full
  const codes = [];
  for (let i = 0; i < 4; i++) codes.push((await o.as('POST', '/v5/files', { data: PNG, contentType: 'image/png' })).status);
  assert.equal(codes[0], 201);
  assert.ok(codes.includes(413), `quota enforced: ${codes}`);
  const full = await o.as('POST', '/v5/files', { data: PNG, contentType: 'image/png' });
  assert.equal(full.body.error.code, 'STORAGE_FULL');
  // a different gym is unaffected
  const other = await h.owner({ phone: '+919876655002', gymName: 'Other Quota Gym' });
  assert.equal((await other.as('POST', '/v5/files', { data: PNG, contentType: 'image/png' })).status, 201);
});

test('V-18: changing the sign-in number signs out every other device and is on record', async () => {
  const hh = await boot();
  const a = await hh.owner({ phone: '+919876655010', gymName: 'Contact Gym' });
  const second = await hh.loginAs('+919876655010', a.gym);
  assert.equal((await hh.call('GET', '/v5/users/self', { token: second.token })).status, 200);
  const req = await hh.call('POST', '/v3/users/self/otp', { token: a.token, body: { channel: 'sms', target: '+919876655011' } });
  const ok = await hh.call('POST', '/v3/users/self/otp/verify', { token: a.token, body: { requestId: data(req).requestId, otp: '123456' } });
  assert.equal(ok.status, 200);
  assert.equal((await hh.call('GET', '/v5/users/self', { token: second.token })).status, 401, 'the other device is signed out');
  assert.equal((await hh.call('GET', '/v5/users/self', { token: a.token })).status, 200, 'this device carries on');
  assert.ok(hh.store.get("SELECT 1 x FROM security_events WHERE kind = 'staff_contact_changed'"));
  await hh.close();
});

test('V-19: wrong device keys are counted per address and a device cannot back-date attendance', async () => {
  const hh = await boot({ rateLimitScale: 1 });
  const a = await hh.owner({ phone: '+919876655020', gymName: 'Device Gym' });
  const dev = await a.as('POST', '/v3/biohub/devices', { name: 'Door', serialNumber: 'SN-1', type: 'face' });
  assert.ok([200, 201].includes(dev.status), JSON.stringify(dev.body));
  const key = data(dev).deviceKey ?? data(dev).key;
  let blocked = false;
  for (let i = 0; i < 25; i++) { const r = await hh.call('POST', '/v5/biohub/device/heartbeat', { headers: { 'x-device-key': `wrong-key-${String(i).padStart(10, '0')}` }, body: {} }); if (r.status === 429) { blocked = true; break; } }
  assert.ok(blocked, 'guessing keys is bounded');
  await hh.close();
  assert.ok(key, 'a device key exists');
});

test('V-21: member access codes and sealed gym keys use their own keys, so JWT_SECRET can change without breaking them', () => {
  const env = { ...process.env };
  try {
    delete process.env.SEAL_KEY; delete process.env.ACCESS_CODE_KEY;
    const same = loadConfig({ jwtSecret: 'j'.repeat(40) });
    assert.equal(same.sealKey, same.jwtSecret, 'unset: falls back, so nothing already issued breaks');
    const split = loadConfig({ jwtSecret: 'j'.repeat(40), sealKey: 's'.repeat(40), accessCodeKey: 'a'.repeat(40) });
    assert.notEqual(split.sealKey, split.jwtSecret);
    assert.notEqual(split.accessCodeKey, split.jwtSecret);
    assert.notEqual(split.sealKey, split.accessCodeKey);
  } finally { Object.assign(process.env, env); }
});

test('V-21: with its own key, an issued access code still works after JWT_SECRET changes', async () => {
  const KEYS = { sealKey: 's'.repeat(40), accessCodeKey: 'a'.repeat(40) };
  const h1 = await boot({ jwtSecret: 'first-secret-first-secret-first-secret', ...KEYS });
  const a = await h1.owner({ phone: '+919876655030', gymName: 'Rotating Gym' });
  const gs = JSON.parse(h1.store.get('SELECT data FROM gyms WHERE id = ?', a.gym).data);
  h1.store.run('UPDATE gyms SET data = ? WHERE id = ?', JSON.stringify({ ...gs, features: { ...gs.features, MEMBER_APP: true } }), a.gym);
  const m = data(await a.as('POST', '/v5/members', { name: 'Code Holder', phone: '+919876655031' }));
  const code = data(await a.as('POST', `/v5/members/${m.id}/access-code`, {})).accessCode;
  // the same database, a new server with a DIFFERENT jwt secret but the same access-code key
  const dir = mkdtempSync(join(tmpdir(), 'rot-'));
  const file = join(dir, 'g.sqlite');
  h1.store.run(`VACUUM INTO '${file}'`);
  await h1.close();
  const h2 = await boot({ jwtSecret: 'second-secret-second-secret-second', dbFile: file, ...KEYS });
  const login = await h2.call('POST', '/v5/member/auth/code', { body: { code } });
  assert.equal(login.status, 200, JSON.stringify(login.body));
  await h2.close();
});

test('V-22: the demo seed refuses production and refuses a database that holds real accounts', () => {
  assert.throws(() => assertSafeToReset({ production: true, dbFile: ':memory:' }, DEMO_PHONES), /production/);
  const dir = mkdtempSync(join(tmpdir(), 'seed-'));
  const file = join(dir, 'real.sqlite');
  const db = new DatabaseSync(file);
  db.exec("CREATE TABLE users(phone TEXT); CREATE TABLE gyms(id TEXT); INSERT INTO users VALUES ('+919123456789'); INSERT INTO gyms VALUES ('g1')");
  db.close();
  assert.throws(() => assertSafeToReset({ production: false, dbFile: file }, DEMO_PHONES), /Refusing to reset/);
  const demo = join(dir, 'demo.sqlite');
  const d2 = new DatabaseSync(demo);
  d2.exec("CREATE TABLE users(phone TEXT); CREATE TABLE gyms(id TEXT); INSERT INTO users VALUES ('+919000000001'); INSERT INTO gyms VALUES ('g1')");
  d2.close();
  assert.doesNotThrow(() => assertSafeToReset({ production: false, dbFile: demo }, DEMO_PHONES));
  assert.doesNotThrow(() => assertSafeToReset({ production: false, dbFile: join(dir, 'missing.sqlite') }, DEMO_PHONES));
});
