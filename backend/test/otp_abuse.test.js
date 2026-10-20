// Sign-in code abuse (V-04), text-message cost abuse (V-05) and account enumeration (V-06).
// The request limiters are loose while accounts are set up and switched to the real production values (scale 1) inside the tests that
// measure them; time is moved by editing the guard rows, never by sleeping.
import { test, after, before } from 'node:test';
import assert from 'node:assert/strict';
import { boot, data } from './helpers.js';

let h; let alerts; let challengeCalls; let challengeOk = true;
const alertFetch = async (url, init) => { alerts.push(JSON.parse(init.body)); return { ok: true }; };
const challengeFetch = async (url, init) => { challengeCalls.push(String(init.body)); if (challengeOk === 'throw') throw new Error('down'); return { ok: true, json: async () => ({ success: challengeOk === true }) }; };
const strict = (on) => { h.config.rateLimitScale = on ? 1 : 1000; h.app.limiter.scale = on ? 1 : 1000; };
const strictTest = (name, fn) => test(name, async () => { strict(true); try { await fn(); } finally { strict(false); } });
const events = (kind) => h.store.all('SELECT * FROM security_events WHERE kind = ?', kind);
const guard = (phone) => h.store.get('SELECT * FROM otp_guard WHERE target = ?', phone);
let n = 0; const phone = () => `+9198766${String(20000 + n++).padStart(5, '0')}`;
const signin = (p, extra = {}) => h.call('POST', '/v5/auth/signin/otp', { body: { phone: p, ...extra } });
const verify = (requestId, otp) => h.call('POST', '/v5/auth/signin/verify', { body: { requestId, otp } });

before(async () => {
  alerts = []; challengeCalls = [];
  h = await boot({ rateLimitScale: 1000, otpResendSec: 0, alertWebhookUrl: 'https://alerts.example.test/hook', alertFetch, turnstileSecret: '', challengeFetch });
});
after(async () => { await h.close(); });

// ---- V-04 -----------------------------------------------------------------------------------------------------------
test('V-04: five wrong answers lock the PHONE, whichever codes they were tried against', async () => {
  const p = phone();
  await h.owner({ phone: p, gymName: 'Lock Gym' });
  const codes = [];
  for (let i = 0; i < 3; i++) { codes.push(data(await signin(p)).requestId); }
  // 2 wrong on the first code, 2 on the second, 1 on the third: five in all, spread over three codes
  const spread = [[0, 2], [1, 2], [2, 1]];
  const statuses = [];
  for (const [ix, times] of spread) for (let t = 0; t < times; t++) statuses.push((await verify(codes[ix], '000000')).status);
  assert.deepEqual(statuses, [422, 422, 422, 422, 422]);
  assert.ok(guard(p).locked_until > Date.now(), 'the phone is locked');
  // even the right code on a fresh, unused request is refused while locked
  const right = await verify(codes[2], '123456');
  assert.equal(right.status, 429);
  assert.equal(events('otp_lockout').length >= 1, true, 'the lockout is on record');
});

test('V-04: while locked no new code is sent, and the answer is indistinguishable from an unknown number', async () => {
  const p = phone();
  await h.owner({ phone: p, gymName: 'Quiet Gym' });
  const first = data(await signin(p)).requestId;
  for (let i = 0; i < 5; i++) await verify(first, '000000');
  const sentBefore = h.store.get('SELECT COUNT(*) c FROM otp_requests WHERE target = ?', p).c;
  const again = await signin(p);
  const unknown = await signin(phone());
  assert.equal(again.status, 200);
  assert.equal(h.store.get('SELECT COUNT(*) c FROM otp_requests WHERE target = ?', p).c, sentBefore, 'nothing was sent');
  const shape = (r) => Object.keys(data(r)).sort().join();
  assert.equal(shape(again), shape(unknown));
  assert.equal(data(again).devOtp, undefined);
  // ... and the made-up request fails exactly like a real one, including the cap after five tries
  const real = await verify(first, '000000');   // the real one is exhausted
  const fakeStatuses = [];
  for (let i = 0; i < 6; i++) fakeStatuses.push((await verify(data(again).requestId, '123456')).status);
  assert.deepEqual(fakeStatuses, [422, 422, 422, 422, 422, 429]);
  assert.ok([422, 429].includes(real.status));
});

test('V-04: the lock escalates, then forgives, and a legitimate user recovers when it ends', async () => {
  const p = phone();
  await h.owner({ phone: p, gymName: 'Escalating Gym' });
  const hit = async () => { const id = data(await signin(p)).requestId; for (let i = 0; i < 5; i++) await verify(id, '000000'); };
  await hit();
  const first = guard(p);
  assert.equal(first.level, 1);
  const lock1 = first.locked_until - Date.now();
  assert.ok(lock1 > 14 * 60_000 && lock1 <= 15 * 60_000, `first lock ${lock1} ms`);
  // the cooldown passes
  h.store.run('UPDATE otp_guard SET locked_until = ? WHERE target = ?', Date.now() - 1, p);
  await hit();
  const second = guard(p);
  assert.equal(second.level, 2);
  assert.ok(second.locked_until - Date.now() > 29 * 60_000, 'twice as long the second time');
  // a day without trouble resets it; the real owner can then sign in with the right code
  h.store.run('UPDATE otp_guard SET locked_until = ?, last_fail = ? WHERE target = ?', Date.now() - 1, Date.now() - 25 * 3600_000, p);
  const id = data(await signin(p)).requestId;
  const ok = await verify(id, '123456');
  assert.equal(ok.status, 200);
  assert.equal(guard(p), undefined, 'a successful sign-in clears the record');
});

test('V-04: the number of guesses an attacker gets in a day is a small fixed bound', async () => {
  const p = phone();
  await h.owner({ phone: p, gymName: 'Budget Gym' });
  let guesses = 0;
  for (let round = 0; round < 8; round++) {
    const r = await signin(p);
    if (r.status !== 200) break;
    const id = data(r).requestId;
    for (let g = 0; g < 8; g++) {
      const v = await verify(id, String(100000 + guesses));
      if (v.status === 422) guesses++;
      if (v.status === 429) break;
    }
    // let each lock lapse at once: the attacker waits only as long as the guard says, so this is the BEST case for the attacker
    const lock = guard(p);
    if (lock?.locked_until > Date.now()) h.store.run('UPDATE otp_guard SET locked_until = ? WHERE target = ?', Date.now() - 1, p);
  }
  assert.ok(guesses <= 40, `${guesses} guesses over 8 rounds even with no waiting between locks`);
});

test('V-04: a made-up request id, an expired code and a used code all read like a wrong code', async () => {
  const p = phone();
  await h.owner({ phone: p, gymName: 'Wording Gym' });
  const id = data(await signin(p)).requestId;
  const wrong = await verify(id, '000000');
  const made = await verify('00000000-0000-0000-0000-000000000000', '123456');
  h.store.run('UPDATE otp_requests SET expires_at = ? WHERE id = ?', Date.now() - 1, id);
  const expired = await verify(id, '123456');
  assert.equal(new Set([wrong.body.error.message, made.body.error.message, expired.body.error.message]).size, 1);
  assert.deepEqual([wrong.status, made.status, expired.status], [422, 422, 422]);
});

test('V-04: an operator is alerted when one number keeps being attacked', async () => {
  const p = phone();
  await h.owner({ phone: p, gymName: 'Alert Gym' });
  alerts.length = 0;
  h.app.ops.last.clear();
  for (let round = 0; round < 3; round++) {
    const id = data(await signin(p)).requestId;
    for (let i = 0; i < 5; i++) await verify(id, '000000');
    h.store.run('UPDATE otp_guard SET locked_until = ? WHERE target = ?', Date.now() - 1, p);
  }
  await new Promise((r) => setImmediate(r));
  assert.ok(alerts.some((a) => /otp_lockout/.test(a.text)), 'level 3 pages the operator');
  assert.doesNotMatch(JSON.stringify(alerts), /\+9198766/, 'the alert never carries a full phone number');
});

// ---- V-05 -----------------------------------------------------------------------------------------------------------
const sends = (extra = {}) => ({ purpose: 'signin', channel: 'sms', ...extra });

strictTest('V-05: one phone can be texted only so often per hour, then nothing is sent', () => {
  const p = phone();
  const auth = h.app.auth;
  const out = [];
  for (let i = 0; i < 7; i++) out.push(auth.createOtp(sends({ target: p, ip: '10.1.1.1', quiet: true })));
  assert.equal(out.filter((o) => !o.decoy).length, 5);
  assert.equal(h.store.get('SELECT COUNT(*) c FROM otp_requests WHERE target = ?', p).c, 5);
  assert.ok(events('sms_budget_exhausted').length >= 1);
  assert.throws(() => auth.createOtp(sends({ target: p, quiet: false })), (e) => e.status === 429);
});

strictTest('V-05: one address can trigger only so many texts per hour, whichever numbers it names', () => {
  const auth = h.app.auth;
  let sent = 0;
  for (let i = 0; i < 30; i++) if (!auth.createOtp(sends({ target: phone(), ip: '10.2.2.2' })).decoy) sent++;
  assert.equal(sent, 20);
});

strictTest('V-05: one signed-in account can ask for only so many codes a day', () => {
  const auth = h.app.auth;
  let sent = 0;
  for (let i = 0; i < 20; i++) if (!auth.createOtp(sends({ target: phone(), userId: 'user-x', ip: `10.3.3.${i}` })).decoy) sent++;
  assert.equal(sent, 12);
});

strictTest('V-05: one gym\'s public QR can cause only so many texts a day', () => {
  const auth = h.app.auth;
  const was = h.config.sendBudget.scopePerDay;
  h.config.sendBudget.scopePerDay = 3;
  try {
    let sent = 0;
    for (let i = 0; i < 8; i++) if (!auth.createOtp(sends({ purpose: 'portal', target: phone(), ip: `10.4.4.${i}`, scope: 'gym:abc' })).decoy) sent++;
    assert.equal(sent, 3);
  } finally { h.config.sendBudget.scopePerDay = was; }
});

strictTest('V-05: a global ceiling caps the whole service and warns the operator before it is reached', () => {
  const auth = h.app.auth;
  const c = h.config.sendBudget;
  const used = h.store.get('SELECT COUNT(*) c FROM otp_requests WHERE created_at > ?', Date.now() - 3600_000).c;
  const was = c.globalPerHour;
  c.globalPerHour = used + 5;
  alerts.length = 0; h.app.ops.last.clear();
  try {
    let sent = 0;
    for (let i = 0; i < 9; i++) if (!auth.createOtp(sends({ target: phone(), ip: `10.5.5.${i}` })).decoy) sent++;
    assert.equal(sent, 5, 'no more than the ceiling');
    assert.ok(alerts.some((a) => /sms_budget_80_percent|sms_budget_exhausted/.test(a.text)), 'the operator was told');
  } finally { c.globalPerHour = was; }
});

strictTest('V-05: email codes cost nothing like SMS and are not held to the SMS budgets', () => {
  const auth = h.app.auth;
  let sent = 0;
  const email = 'someone@example.test';
  for (let i = 0; i < 8; i++) if (!auth.createOtp({ purpose: 'login', channel: 'email', target: email, ip: '10.6.6.6' }).decoy) sent++;
  assert.equal(sent, 8);
});

test('V-05: the public endpoints texting arbitrary numbers are tightly limited per address', async () => {
  const owner = await h.owner({ phone: phone(), gymName: 'Portal Gym' });
  const code = h.store.get('SELECT code FROM gyms WHERE id = ?', owner.gym).code;
  // fresh counters for this test's address, then the real limits
  h.app.limiter.hits.clear();
  strict(true);
  try {
  const statuses = [];
  for (let i = 0; i < 8; i++) statuses.push((await h.call('POST', `/v5/portal/${code}/otp`, { body: { phone: phone() } })).status);
  assert.deepEqual(statuses, [200, 200, 200, 200, 200, 429, 429, 429]);
  const reg = [];
  for (let i = 0; i < 6; i++) reg.push((await h.call('POST', '/v5/register/partner', { body: { name: 'Spam Target', phone: phone() }, headers: { 'x-forwarded-for': '' } })).status);
  assert.ok(reg.filter((s) => s === 200).length <= 4, `registration texts per address per hour: ${reg}`);
  assert.ok(reg.includes(429));
  } finally { strict(false); }
});

test('V-05: a bot challenge is demanded on those endpoints once it is configured, and a broken checker does not open the door', async () => {
  const hh = await boot({ rateLimitScale: 1000, turnstileSecret: 'turnstile-secret', challengeFetch });
  try {
  hh.config.challenge.secret = ''; // set the gym up first, then switch the check on
  const owner = await hh.owner({ phone: '+919876622001', gymName: 'Challenge Gym' });
  hh.config.challenge.secret = 'turnstile-secret';
  const code = hh.store.get('SELECT code FROM gyms WHERE id = ?', owner.gym).code;
  const ask = (body) => hh.call('POST', `/v5/portal/${code}/otp`, { body: { phone: '+919876622002', ...body } });
  challengeCalls.length = 0;
  assert.equal((await ask({})).status, 403, 'no token');
  challengeOk = true;
  assert.equal((await ask({ challengeToken: 'valid-token-123456' })).status, 200);
  assert.match(challengeCalls.at(-1), /secret=turnstile-secret/);
  challengeOk = false;
  assert.equal((await ask({ challengeToken: 'bad-token-1234567' })).status, 403);
  challengeOk = 'throw';
  assert.equal((await ask({ challengeToken: 'any-token-12345678' })).status, 403);
  challengeOk = true;
  const reg = await hh.call('POST', '/v5/register/partner', { body: { name: 'Needs Check', phone: '+919876622003' } });
  assert.equal(reg.status, 403);
  } finally { await hh.close(); }
});

// ---- V-06 -----------------------------------------------------------------------------------------------------------
test('V-06: every way in answers a known and an unknown number alike, including the resend timer', async () => {
  const hh = await boot({ rateLimitScale: 1, otpResendSec: 30 });
  try {
  const known = '+919876633001';
  await hh.owner({ phone: known, gymName: 'Same Answer Gym' });
  const unknown = '+919876633002';
  for (const [path, mk] of [
    ['/v5/auth/signin/otp', (p) => ({ phone: p })],
    ['/v5/auth/login/otp', (p) => ({ phone: p })],
    ['/v5/member/auth/otp', (p) => ({ phone: p })],
  ]) {
    const a1 = await hh.call('POST', path, { body: mk(known) });
    const b1 = await hh.call('POST', path, { body: mk(unknown) });
    const a2 = await hh.call('POST', path, { body: mk(known) });
    const b2 = await hh.call('POST', path, { body: mk(unknown) });
    assert.equal(a1.status, b1.status, `${path} first`);
    assert.equal(a2.status, b2.status, `${path} second, inside the resend window`);
    assert.equal(a2.status, 429);
    const keys = (r) => Object.keys(r.body.data ?? {}).filter((k) => k !== 'devOtp').sort().join();
    assert.equal(keys(a1), keys(b1), `${path} shape`);
  }
  } finally { await hh.close(); }
});
