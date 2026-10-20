// ALLOW_TEST_PAYMENT_KEYS is a STAGING-only switch. These tests pin down what it does and, as important, what it must never do.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHmac } from 'node:crypto';
import { boot, data } from './helpers.js';
import { loadConfig } from '../src/config.js';
import { openDb } from '../src/db.js';
import { startServer } from '../src/server.js';
import { seal } from '../src/secrets.js';

const J = 'j'.repeat(40);
// Unmistakably synthetic Razorpay-shaped ids. The mode word is joined at run time so the source never contains a complete `rzp_live_...` literal.
const KEY = (mode, tag) => `rzp_${mode}_SYNTHETIC${tag}TESTONLY`;
const withEnv = (vars, fn) => {
  const saved = {};
  for (const k of Object.keys(vars)) { saved[k] = process.env[k]; if (vars[k] === undefined) delete process.env[k]; else process.env[k] = vars[k]; }
  try { return fn(); } finally { for (const [k, v] of Object.entries(saved)) { if (v === undefined) delete process.env[k]; else process.env[k] = v; } }
};

test('it is OFF by default and only the documented words turn it on', () => {
  withEnv({ ALLOW_TEST_PAYMENT_KEYS: undefined }, () => assert.equal(loadConfig({ jwtSecret: J }).allowTestPaymentKeys, false));
  for (const off of ['', '0', 'false', 'no', 'off', 'maybe', ' ']) withEnv({ ALLOW_TEST_PAYMENT_KEYS: off }, () => assert.equal(loadConfig({ jwtSecret: J }).allowTestPaymentKeys, false, `"${off}"`));
  for (const on of ['1', 'true', 'yes', 'on', 'TRUE']) withEnv({ ALLOW_TEST_PAYMENT_KEYS: on }, () => assert.equal(loadConfig({ jwtSecret: J }).allowTestPaymentKeys, true, `"${on}"`));
  assert.match(String(process.env.ALLOW_TEST_PAYMENT_KEYS ?? ''), /^$/, 'not set in this test process');
});

test('the shipped example config leaves it commented out', async () => {
  const { readFileSync } = await import('node:fs');
  const lines = readFileSync(new URL('../../deploy/.env.example', import.meta.url), 'utf8').split('\n').filter((l) => /ALLOW_TEST_PAYMENT_KEYS/.test(l));
  assert.ok(lines.length >= 1);
  assert.ok(lines.every((l) => l.trim().startsWith('#')), `only commented mentions: ${lines.join(' | ')}`);
});

// ---- behaviour of the gym "connect your Razorpay account" step in a production-mode server ----------------------------------------
const sentOtps = [];
const transport = { async sendOtp(m) { sentOtps.push(m); return { providerId: 'o' }; }, async sendText() { return { providerId: 't' }; } };
let phoneSeq = 919876688000;
async function connect({ allow, keyId, razorpayAccepts = true, keySecret = 'staging-secret-1', webhookSecret = 'staging-webhook-1' }) {
  const calls = [];
  const fetchImpl = async (url) => { calls.push(url); return razorpayAccepts ? { ok: true, status: 200, json: async () => ({}) } : { ok: false, status: 401, json: async () => ({}) }; };
  const hh = await boot({ env: 'production', devOtp: false, devPayments: false, fixedOtp: '', otpResendSec: 0, messagingTransport: transport, jwtSecret: J, allowTestPaymentKeys: allow, paymentsFetch: fetchImpl });
  try {
    const phone = `+${phoneSeq++}`;
    const reg = await hh.call('POST', '/v5/register/partner', { body: { name: 'Stage Owner', phone } });
    const v = await hh.call('POST', '/v5/register/partner/verify', { body: { requestId: data(reg).requestId, otp: sentOtps.at(-1).code } });
    const token = data(v).accessToken;
    const g = await hh.call('POST', '/v5/register/partner/gym', { token, body: { name: 'Stage Gym', address: '12 MG Road, Bengaluru', pincode: '560001' } });
    const r = await hh.call('PUT', '/v5/gyms/payment-setup', { token, gym: data(g).gym.id, body: { provider: 'razorpay', keyId, keySecret, webhookSecret } });
    const row = hh.store.get('SELECT secret_sealed, key_id FROM gym_payment_accounts');
    return { status: r.status, message: r.body?.error?.message, razorpayCalls: calls.length, stored: !!row, sealedLooksSealed: row ? /^v1\./.test(row.secret_sealed) && !row.secret_sealed.includes(keySecret) : null };
  } finally { await hh.close(); }
}

test('default (off): production takes live keys and refuses test keys, and Razorpay is never even asked about a test key', async () => {
  const t = await connect({ allow: false, keyId: KEY('test', 'A') });
  assert.equal(t.status, 422); assert.match(t.message, /live keys/); assert.equal(t.razorpayCalls, 0); assert.equal(t.stored, false);
  const l = await connect({ allow: false, keyId: KEY('live', 'B') });
  assert.equal(l.status, 200); assert.equal(l.razorpayCalls, 1, 'live keys are still checked with Razorpay'); assert.equal(l.stored, true); assert.equal(l.sealedLooksSealed, true);
});

test('default (off): live validation is unchanged: Razorpay rejecting a live key still refuses it, and nothing is stored', async () => {
  const bad = await connect({ allow: false, keyId: KEY('live', 'C'), razorpayAccepts: false });
  assert.equal(bad.status, 422); assert.match(bad.message, /did not accept/); assert.equal(bad.stored, false);
});

test('opt-in (staging): test keys are accepted, still checked with Razorpay, sealed, and live keys are refused', async () => {
  const t = await connect({ allow: true, keyId: KEY('test', 'A') });
  assert.equal(t.status, 200); assert.equal(t.razorpayCalls, 1); assert.equal(t.stored, true); assert.equal(t.sealedLooksSealed, true);
  const l = await connect({ allow: true, keyId: KEY('live', 'B') });
  assert.equal(l.status, 422); assert.match(l.message, /staging server/); assert.equal(l.razorpayCalls, 0, 'a staging server never calls Razorpay with live keys'); assert.equal(l.stored, false);
});

test('opt-in does not relax any other check: a bad key, a malformed id and short secrets are refused as before', async () => {
  assert.equal((await connect({ allow: true, keyId: KEY('test', 'C'), razorpayAccepts: false })).status, 422);
  assert.equal((await connect({ allow: true, keyId: 'not-a-razorpay-key' })).status, 422);
  assert.equal((await connect({ allow: true, keyId: KEY('test', 'A'), keySecret: 'short' })).status, 422);
  assert.equal((await connect({ allow: true, keyId: KEY('test', 'A'), webhookSecret: 'short' })).status, 422);
});

// ---- it cannot reach production money or production data ------------------------------------------------------------------------
test('a staging server refuses to start with LIVE platform Razorpay keys', () => {
  assert.throws(() => loadConfig({ jwtSecret: J, allowTestPaymentKeys: true, razorpayKeyId: KEY('live', 'D'), razorpayWebhookSecret: 'w' }), /staging switch/);
  withEnv({ ALLOW_TEST_PAYMENT_KEYS: '1', RAZORPAY_KEY_ID: KEY('live', 'D'), RAZORPAY_WEBHOOK_SECRET: 'w' }, () => assert.throws(() => loadConfig({ jwtSecret: J }), /staging switch/));
  assert.doesNotThrow(() => loadConfig({ jwtSecret: J, allowTestPaymentKeys: true, razorpayKeyId: KEY('test', 'D'), razorpayWebhookSecret: 'w' }));
  assert.doesNotThrow(() => loadConfig({ jwtSecret: J, allowTestPaymentKeys: false, razorpayKeyId: KEY('live', 'D'), razorpayWebhookSecret: 'w' }), 'production with live keys and no switch is fine');
});

test('a staging server refuses to start on a database that holds live gym payment accounts (production data)', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'stg-'));
  const file = join(dir, 'prod-copy.sqlite');
  const db = openDb(file);
  db.run("INSERT INTO gyms(id, code, data, created_at, updated_at) VALUES ('g1','123456','{}','x','x')");
  db.run("INSERT INTO gym_payment_accounts(gym_id, provider, key_id, secret_sealed, webhook_secret_sealed, status, created_at, updated_at) VALUES ('g1','razorpay',?,?,?,'active','x','x')", KEY('live', 'E'), seal(J, 'a'), seal(J, 'b'));
  db.close();
  let refused = null; let accidentallyStarted = null;
  try { accidentallyStarted = await startServer({ port: 0, host: '127.0.0.1', dbFile: file, jwtSecret: J, allowTestPaymentKeys: true, logRequests: false }); } catch (e) { refused = e; }
  if (accidentallyStarted) await accidentallyStarted.close(); // never leave a server running if the guard is ever removed
  assert.match(String(refused?.message), /live payment accounts/, 'staging must refuse production data');
  // the same file starts normally without the switch (this is what production does), and a test-only database starts with it
  const prod = await startServer({ port: 0, host: '127.0.0.1', dbFile: file, jwtSecret: J, logRequests: false });
  await prod.close();
  const f2 = join(dir, 'staging.sqlite');
  const d2 = openDb(f2);
  d2.run("INSERT INTO gyms(id, code, data, created_at, updated_at) VALUES ('g1','123456','{}','x','x')");
  d2.run("INSERT INTO gym_payment_accounts(gym_id, provider, key_id, secret_sealed, webhook_secret_sealed, status, created_at, updated_at) VALUES ('g1','razorpay',?,?,?,'active','x','x')", KEY('test', 'F'), seal(J, 'a'), seal(J, 'b'));
  d2.close();
  const stg = await startServer({ port: 0, host: '127.0.0.1', dbFile: f2, jwtSecret: J, allowTestPaymentKeys: true, logRequests: false });
  await stg.close();
});

test('another environment\'s secrets do not work: staging cannot read production\'s sealed keys, tokens or webhooks', async () => {
  // production sealed a gym key with ITS key; a staging server with a different SEAL_KEY cannot unseal it
  const sealedByProd = seal('production-seal-key-production-seal-key', 'rzp-live-secret-value');
  const { unseal } = await import('../src/secrets.js');
  assert.throws(() => unseal('staging-seal-key-staging-seal-key-xx', sealedByProd));
  assert.equal(unseal('production-seal-key-production-seal-key', sealedByProd), 'rzp-live-secret-value');
  // a production access token is not valid on a staging server with its own JWT secret
  const prod = await boot({ jwtSecret: 'p'.repeat(40) });
  const owner = await prod.owner({ phone: '+919876699001', gymName: 'Prod Gym' });
  const staging = await boot({ jwtSecret: 's'.repeat(40) });
  assert.equal((await staging.call('GET', '/v5/users/self', { token: owner.token })).status, 401);
  // and a webhook signed with production's webhook secret is refused on staging
  const body = JSON.stringify({ event: 'payment_link.paid', payload: {} });
  const res = await fetch(`${staging.base}/v5/payments/webhooks/razorpay`, { method: 'POST', headers: { 'content-type': 'application/json', 'x-razorpay-signature': createHmac('sha256', 'production-webhook-secret').update(body).digest('hex') }, body });
  assert.equal(res.status, 401);
  await prod.close(); await staging.close();
});
