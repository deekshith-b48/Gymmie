#!/usr/bin/env node
// Post-deploy smoke test against a running server. It proves the production switches really are off and the
// edges are closed; it does not create data. Usage:
//   node scripts/smoke.js https://api.example.com
//   SMOKE_PHONE=+91XXXXXXXXXX node scripts/smoke.js https://api.example.com   # also checks sign-in (sends ONE real code to that phone)
const base = (process.argv[2] ?? process.env.BASE_URL ?? '').replace(/\/+$/, '');
if (!base) { console.error('usage: node scripts/smoke.js https://your-api-host'); process.exit(2); }

const results = [];
async function check(name, fn) {
  try { const note = await fn(); results.push({ name, ok: true, note }); }
  catch (e) { results.push({ name, ok: false, note: e.message }); }
}
const expect = (cond, msg) => { if (!cond) throw new Error(msg); };
const json = async (res) => res.json().catch(() => ({}));

await check('served over HTTPS', async () => { expect(base.startsWith('https://'), 'use the public https:// address'); });

await check('/ready says ready', async () => {
  const r = await fetch(`${base}/ready`); const b = await json(r);
  expect(r.ok && b.data?.status === 'ready', `status ${r.status} ${JSON.stringify(b).slice(0, 120)}`);
  return `db ok, ${r.headers.get('x-request-id') ? 'request ids on' : 'no request id header'}`;
});

await check('plain HTTP is redirected to HTTPS', async () => {
  if (!base.startsWith('https://')) return 'skipped';
  const r = await fetch(base.replace('https://', 'http://') + '/ready', { redirect: 'manual' }).catch(() => null);
  if (!r) return 'port 80 closed (acceptable)';
  expect([301, 302, 307, 308].includes(r.status), `got ${r.status}`);
});

await check('no framework banner', async () => {
  const r = await fetch(`${base}/health`);
  expect(!r.headers.get('x-powered-by') && !r.headers.get('server'), `leaks ${r.headers.get('x-powered-by') ?? r.headers.get('server')}`);
});

await check('CORS is not open to every origin', async () => {
  const r = await fetch(`${base}/v5/apps/configs/settings`, { headers: { origin: 'https://evil.example' } });
  expect(r.headers.get('access-control-allow-origin') !== '*', 'access-control-allow-origin is *: set CORS_ORIGIN');
});

await check('payment webhook rejects a forged signature', async () => {
  const r = await fetch(`${base}/v5/payments/webhooks/razorpay`, { method: 'POST', headers: { 'content-type': 'application/json', 'x-razorpay-signature': 'forged' }, body: '{"event":"payment_link.paid"}' });
  expect(r.status === 401 || r.status === 400, `expected 401, got ${r.status} (is RAZORPAY_WEBHOOK_SECRET set?)`);
});

await check('private routes need a token', async () => {
  const r = await fetch(`${base}/v5/members`);
  expect(r.status === 401 || r.status === 403, `got ${r.status}`);
});

await check('oversized body is refused', async () => {
  const r = await fetch(`${base}/v5/auth/signin/otp`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ x: 'a'.repeat(20 * 1024 * 1024) }) }).catch(() => ({ status: 0 }));
  expect([0, 400, 413].includes(r.status), `got ${r.status}`);
});

if (process.env.SMOKE_PHONE) {
  await check('sign-in code is not exposed in the response', async () => {
    const r = await fetch(`${base}/v5/auth/signin/otp`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ phone: process.env.SMOKE_PHONE, channel: 'sms' }) });
    const t = await r.text();
    expect(r.ok, `status ${r.status}: ${t.slice(0, 120)}`);
    expect(!/devOtp/.test(t), 'devOtp is in the response: DEV_EXPOSE_OTP must be off');
    return 'a real code was sent to that phone, check that it arrived';
  });
}

let failed = 0;
for (const r of results) { if (!r.ok) failed++; console.log(`${r.ok ? 'PASS' : 'FAIL'}  ${r.name}${r.note ? `  (${r.note})` : ''}`); }
console.log(failed ? `\n${failed} check(s) failed` : '\nall checks passed');
process.exit(failed ? 1 : 0);
