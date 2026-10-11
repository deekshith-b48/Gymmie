/* Gymmie single sign-on (sso.js + the two /api/sso routes). The pure module first, then the real
   server.js in a child: redeem makes a profile and a session, a replay and a forgery get the same
   401, SSO_ONLY closes the other doors, and revoke ends the session. */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { boundPort } from './helpers.mjs';
import { createReplayGuard, externalId, signAssertion, verifyAssertion } from '../sso.js';

const API = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const SECRET = 'x'.repeat(40);
const claims = (over = {}, now = Date.now()) => ({ gid: 'g1', mid: 'm1', name: 'Asha Rao', iat: now, exp: now + 60000, jti: crypto.randomBytes(9).toString('base64url'), ...over });

test('a good assertion verifies and carries the member, not a phone number', () => {
  const c = verifyAssertion(SECRET, signAssertion(SECRET, claims()));
  assert.equal(c.gid, 'g1'); assert.equal(c.mid, 'm1'); assert.equal(c.name, 'Asha Rao');
  assert.equal(externalId(c.gid, c.mid), 'gymmie:g1:m1');
});

test('forged, tampered, expired, future, long-lived and malformed assertions are refused', () => {
  const now = Date.now();
  const good = signAssertion(SECRET, claims({}, now));
  assert.ok(verifyAssertion(SECRET, good, { now }));
  assert.equal(verifyAssertion('y'.repeat(40), good, { now }), null, 'other secret');
  assert.equal(verifyAssertion(SECRET, good.slice(0, -2) + 'AA', { now }), null, 'bad mac');
  const [p, m] = good.split('.');
  const evil = Buffer.from(JSON.stringify({ ...JSON.parse(Buffer.from(p, 'base64url')), mid: 'm2' })).toString('base64url');
  assert.equal(verifyAssertion(SECRET, evil + '.' + m, { now }), null, 'claims swapped under the old mac');
  assert.equal(verifyAssertion(SECRET, good, { now: now + 61000 }), null, 'expired');
  assert.equal(verifyAssertion(SECRET, signAssertion(SECRET, claims({}, now + 120000)), { now }), null, 'issued in the future');
  assert.equal(verifyAssertion(SECRET, signAssertion(SECRET, claims({ exp: now + 3600000 }, now)), { now }), null, 'lives too long');
  assert.equal(verifyAssertion(SECRET, signAssertion(SECRET, claims({ mid: '../x' }, now)), { now }), null, 'bad id');
  for (const junk of ['', 'x', 'a.b', null, 5, 'a'.repeat(3000)]) assert.equal(verifyAssertion(SECRET, junk), null);
  assert.equal(verifyAssertion('short', good), null, 'a short secret never verifies');
});

test('an assertion is accepted once', () => {
  const guard = createReplayGuard();
  const a = signAssertion(SECRET, claims());
  assert.ok(verifyAssertion(SECRET, a, { guard }));
  assert.equal(verifyAssertion(SECRET, a, { guard }), null);
});

async function start(t, env = {}) {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'gym-sso-'));
  fs.writeFileSync(path.join(dataDir, 'secret'), 'a'.repeat(64), { mode: 0o600 });
  const child = spawn(process.execPath, ['server.js'], {
    cwd: API, stdio: ['ignore', 'pipe', 'pipe'],
    env: { ...process.env, PORT: '0', DATA_DIR: dataDir, ORIGIN: 'http://localhost:8080', RP_ID: 'localhost', ...env }
  });
  let log = '';
  child.stdout.on('data', d => log += d); child.stderr.on('data', d => log += d);
  t.after(() => { child.kill('SIGKILL'); fs.rmSync(dataDir, { recursive: true, force: true }); });
  const port = await boundPort(child, () => log);
  const base = `http://127.0.0.1:${port}`;
  const post = (p, body, headers = {}) => fetch(base + p, { method: 'POST', redirect: 'manual', headers: { 'Content-Type': 'application/json', ...headers }, body: JSON.stringify(body) });
  return { base, post, dataDir, log: () => log };
}
const cookieOf = r => (r.headers.getSetCookie?.() || []).map(c => c.split(';')[0]).find(c => c.startsWith('gymsid=')) || '';

test('without GYMMIE_SSO_SECRET the routes do not exist', async t => {
  const s = await start(t);
  assert.equal((await s.post('/api/sso/redeem', { assertion: 'x' })).status, 404);
  assert.equal((await s.post('/api/sso/revoke', { gid: 'g', mid: 'm' })).status, 404);
});

test('redeem creates the profile, sets a session, refuses a replay, and keeps the same profile next time', async t => {
  const s = await start(t, { GYMMIE_SSO_SECRET: SECRET });
  const r1 = await s.post('/api/sso/redeem', { assertion: signAssertion(SECRET, claims()), redirect: true });
  assert.equal(r1.status, 303);
  assert.equal(r1.headers.get('location'), '/');
  const ck = cookieOf(r1);
  assert.ok(ck, 'a session cookie');
  const me = await fetch(s.base + '/api/me', { headers: { Cookie: ck } });
  assert.equal(me.status, 200);
  const u1 = (await me.json()).user;
  assert.equal(u1.name, 'Asha Rao');
  assert.ok(!u1.admin, 'an SSO profile is never an admin');

  const a = signAssertion(SECRET, claims());
  assert.equal((await s.post('/api/sso/redeem', { assertion: a })).status, 200);
  assert.equal((await s.post('/api/sso/redeem', { assertion: a })).status, 401, 'replay');

  const r3 = await s.post('/api/sso/redeem', { assertion: signAssertion(SECRET, claims()) });
  assert.equal((await r3.json()).user.id, u1.id, 'same member, same profile');
});

test('two members with the same name are two profiles', async t => {
  const s = await start(t, { GYMMIE_SSO_SECRET: SECRET });
  const a = await (await s.post('/api/sso/redeem', { assertion: signAssertion(SECRET, claims({ mid: 'mAAAAAA' })) })).json();
  const b = await (await s.post('/api/sso/redeem', { assertion: signAssertion(SECRET, claims({ mid: 'mBBBBBB' })) })).json();
  assert.notEqual(a.user.id, b.user.id);
});

test('a bad assertion is a plain 401 and writes nothing', async t => {
  const s = await start(t, { GYMMIE_SSO_SECRET: SECRET });
  const r = await s.post('/api/sso/redeem', { assertion: signAssertion('z'.repeat(40), claims()) });
  assert.equal(r.status, 401);
  assert.equal(cookieOf(r), '');
  const file = path.join(s.dataDir, 'db.json');
  const users = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf8')).users : [];
  assert.equal(users.length, 0);
});

test('GYMMIE_SSO_ONLY closes passkeys, passwords, pairing and guest mode', async t => {
  const s = await start(t, { GYMMIE_SSO_SECRET: SECRET, GYMMIE_SSO_ONLY: '1', PASSWORD_LOGIN: '1' });
  for (const p of ['/api/register/options', '/api/login/options', '/api/register/password', '/api/login/password', '/api/pair/redeem', '/api/device-link/verify']) {
    assert.equal((await s.post(p, {})).status, 404, p);
  }
  const cfg = await (await fetch(s.base + '/api/config')).json();
  assert.equal(cfg.sso_only, true);
  assert.equal(cfg.allow_guest, false);
  assert.equal((await s.post('/api/sso/redeem', { assertion: signAssertion(SECRET, claims()) })).status, 200, 'SSO itself still works');
});

test('revoke needs the secret and ends the member’s sessions', async t => {
  const s = await start(t, { GYMMIE_SSO_SECRET: SECRET });
  const r = await s.post('/api/sso/redeem', { assertion: signAssertion(SECRET, claims()) });
  const ck = cookieOf(r);
  assert.equal((await fetch(s.base + '/api/me', { headers: { Cookie: ck } })).status, 200);
  assert.equal((await s.post('/api/sso/revoke', { gid: 'g1', mid: 'm1' })).status, 401);
  assert.equal((await s.post('/api/sso/revoke', { gid: 'g1', mid: 'm1' }, { Authorization: 'Bearer ' + 'q'.repeat(40) })).status, 401);
  const ok = await s.post('/api/sso/revoke', { gid: 'g1', mid: 'm1' }, { Authorization: 'Bearer ' + SECRET });
  assert.equal(ok.status, 200);
  assert.equal((await ok.json()).revoked, true);
  assert.equal((await fetch(s.base + '/api/me', { headers: { Cookie: ck } })).status, 401, 'the old cookie no longer works');
  assert.equal((await s.post('/api/sso/redeem', { assertion: signAssertion(SECRET, claims()) })).status, 200, 'a fresh assertion still signs in');
});

test('redeem works from a WebView-style request: Origin null, no Sec-Fetch-Site', async t => {
  const s = await start(t, { GYMMIE_SSO_SECRET: SECRET });
  const r = await s.post('/api/sso/redeem', { assertion: signAssertion(SECRET, claims()), redirect: true }, { Origin: 'null' });
  assert.equal(r.status, 303);
});

test('a cross-site browser POST with a bad assertion is still just a 401, and other routes still check the origin', async t => {
  const s = await start(t, { GYMMIE_SSO_SECRET: SECRET });
  assert.equal((await s.post('/api/sso/redeem', { assertion: 'x' }, { Origin: 'https://evil.example', 'Sec-Fetch-Site': 'cross-site' })).status, 401);
  assert.equal((await s.post('/api/logout', {}, { Origin: 'https://evil.example', 'Sec-Fetch-Site': 'cross-site' })).status, 403);
});
