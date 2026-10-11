#!/usr/bin/env node
/* End-to-end check of the member app across both servers (no emulator needed).
 *
 *   node member-app/scripts/e2e-sso.mjs
 *
 * Starts the real Gymmie backend (seeded in memory) and the real openGym API in SSO-only mode, then
 * does what the app does: member OTP login -> launch -> POST the assertion to openGym -> use the
 * openGym session -> staff blocks the member -> both sessions are dead. Exit code 0 means every
 * step behaved. */
import { spawn } from 'node:child_process';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..', '..');
const SSO = 'e2e-secret-'.padEnd(48, 'x');
const children = [];
const data = mkdtempSync(join(tmpdir(), 'og-e2e-'));
writeFileSync(join(data, 'secret'), 'a'.repeat(64), { mode: 0o600 });

function start(cmd, args, opts) {
  const c = spawn(cmd, args, { stdio: ['ignore', 'pipe', 'pipe'], ...opts });
  children.push(c);
  let log = '';
  c.stdout.on('data', (d) => { log += d; });
  c.stderr.on('data', (d) => { log += d; });
  return { c, log: () => log };
}
const until = async (fn, what, ms = 20000) => {
  const t = Date.now();
  while (Date.now() - t < ms) { const v = fn(); if (v) return v; await new Promise((r) => setTimeout(r, 50)); }
  throw new Error(`timed out waiting for ${what}`);
};
const cleanup = () => { for (const c of children) c.kill('SIGKILL'); rmSync(data, { recursive: true, force: true }); };
process.on('exit', cleanup);

try {
  const og = start(process.execPath, ['server.js'], {
    cwd: join(root, 'member-app/opengym/api'),
    env: { ...process.env, PORT: '0', DATA_DIR: data, ORIGIN: 'http://127.0.0.1', RP_ID: 'localhost',
      GYMMIE_SSO_SECRET: SSO, GYMMIE_SSO_ONLY: '1', SESSION_DAYS: '1' },
  });
  const ogPort = (await until(() => /gym-api on :(\d+)/.exec(og.log()), 'openGym API'))[1];
  const OG = `http://127.0.0.1:${ogPort}`;

  const gy = start(process.execPath, ['--input-type=module', '-e', `
    import { startServer } from './src/server.js';
    const s = await startServer({ port: 0, host: '127.0.0.1', dbFile: ':memory:', jwtSecret: 'j'.repeat(40), fixedOtp: '123456', devOtp: true, devPayments: true, otpResendSec: 0, rateLimitScale: 1000,
      openGymPublicUrl: '${OG}', openGymApiUrl: '${OG}', openGymSsoSecret: '${SSO}' });
    console.log('READY ' + s.port);
    globalThis.__s = s;
    // a staff user, a gym with MEMBER_APP on, and one member
    const call = async (m, p, body, token, gym) => { const r = await fetch('http://127.0.0.1:' + s.port + p, { method: m, headers: { 'content-type': 'application/json', ...(token ? { authorization: 'Bearer ' + token } : {}), ...(gym ? { 'x-gym-id': gym } : {}) }, body: body ? JSON.stringify(body) : undefined }); return (await r.json()).data; };
    const reg = await call('POST', '/v5/register/partner', { name: 'Owner One', phone: '+919876500777' });
    const ver = await call('POST', '/v5/register/partner/verify', { requestId: reg.requestId, otp: '123456' });
    const g = await call('POST', '/v5/register/partner/gym', { name: 'E2E Gym', address: '12 MG Road, Bengaluru', pincode: '560001' }, ver.accessToken);
    const gid = g.gym.id;
    const row = JSON.parse(s.store.get('SELECT data FROM gyms WHERE id = ?', gid).data); row.features.MEMBER_APP = true;
    s.store.run('UPDATE gyms SET data = ? WHERE id = ?', JSON.stringify(row), gid);
    const m = await call('POST', '/v5/members', { name: 'Eve Member', phone: '+919900000555' }, ver.accessToken, gid);
    console.log('SEED ' + JSON.stringify({ owner: ver.accessToken, gid, mid: m.id }));
  `], { cwd: join(root, 'backend') });
  const gyPort = (await until(() => /READY (\d+)/.exec(gy.log()), 'Gymmie backend'))[1];
  const seed = JSON.parse((await until(() => /SEED (.*)/.exec(gy.log()), 'seed'))[1]);
  const GY = `http://127.0.0.1:${gyPort}`;
  const call = async (base, method, path, { body, token, headers = {} } = {}) => {
    const r = await fetch(base + path, { method, redirect: 'manual', headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}), ...headers }, body: body ? JSON.stringify(body) : undefined });
    const t = await r.text();
    return { status: r.status, headers: r.headers, body: t ? (() => { try { return JSON.parse(t); } catch { return t; } })() : null };
  };
  const step = (s) => console.log('  ok  ' + s);

  // 1. member signs in at Gymmie
  const otp = await call(GY, 'POST', '/v5/member/auth/otp', { body: { phone: '+919900000555' } });
  const ver = await call(GY, 'POST', '/v5/member/auth/otp/verify', { body: { requestId: otp.body.data.requestId, otp: '123456' } });
  assert.equal(ver.status, 200); const token = ver.body.data.accessToken;
  step('member signed in at Gymmie');

  // 2. launch -> redeem at openGym (what the WebView does), following the 303 to /
  const launch = (await call(GY, 'POST', '/v5/member/opengym/launch', { token })).body.data;
  assert.equal(launch.redeemUrl, `${OG}/api/sso/redeem`);
  const red = await call(launch.redeemUrl.replace(OG, OG), 'POST', '', { body: { assertion: launch.assertion, redirect: true } });
  assert.equal(red.status, 303); assert.equal(red.headers.get('location'), '/');
  const cookie = red.headers.getSetCookie().map((c) => c.split(';')[0]).find((c) => c.startsWith('gymsid='));
  assert.ok(cookie); step('openGym redeemed the assertion (303 + session cookie)');

  // 3. the openGym session works, and the assertion is single use
  const me = await call(OG, 'GET', '/api/me', { headers: { cookie } });
  assert.equal(me.status, 200); assert.equal(me.body.user.name, 'Eve Member');
  const again = await call(launch.redeemUrl, 'POST', '', { body: { assertion: launch.assertion } });
  assert.equal(again.status, 401); step('openGym session works; replaying the assertion is refused');

  // 4. member data round trip in openGym (their own log)
  const put = await call(OG, 'PUT', '/api/data', { headers: { cookie }, body: { state: { unit: 'kg', routines: [], workouts: [], bodyweight: [{ d: '2026-10-01', w: 70 }], week: {}, dayPlan: {}, exWeights: {}, customEx: [] } } });
  assert.ok([200, 204].includes(put.status), 'PUT /api/data -> ' + put.status);
  const got = await call(OG, 'GET', '/api/data', { headers: { cookie } });
  assert.equal(got.status, 200);
  assert.equal(JSON.stringify(got.body).includes('2026-10-01'), true);
  step('member log saved and read back in openGym');

  // 5. no other door into openGym
  for (const p of ['/api/register/options', '/api/login/password', '/api/pair/redeem']) assert.equal((await call(OG, 'POST', p, { body: {} })).status, 404, p);
  step('passkey, password and pairing doors are closed');

  // 6. staff blocks the member: Gymmie access and the openGym session both end
  const blk = await call(GY, 'POST', `/v5/members/${seed.mid}/block`, { token: seed.owner, headers: { 'x-gym-id': seed.gid }, body: { reason: 'e2e' } });
  assert.equal(blk.status, 200);
  assert.equal((await call(GY, 'GET', '/v5/member/me', { token })).status, 401);
  await until(() => true, 'revoke', 1); await new Promise((r) => setTimeout(r, 300));
  assert.equal((await call(OG, 'GET', '/api/me', { headers: { cookie } })).status, 401);
  step('blocking the member ended both sessions');
  console.log('\nPASS: member app end to end');
} catch (e) {
  console.error('\nFAIL:', e.message);
  process.exitCode = 1;
} finally {
  cleanup();
  process.exit(process.exitCode ?? 0);
}
