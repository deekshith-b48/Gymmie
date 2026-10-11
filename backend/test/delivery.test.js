// Real delivery: sign-in codes and gym messages leave through a provider, the provider's calls have the right shape,
// a failed message gives its credit back, and without a provider production still refuses to pretend.
import { test, after, before } from 'node:test';
import assert from 'node:assert/strict';
import { boot, data } from './helpers.js';
import { Messenger } from '../src/messenger.js';
import { processOutbox } from '../src/domain/delivery.js';

const sentOtps = []; const sentTexts = []; let failNext = false;
const transport = {
  async sendOtp(m) { sentOtps.push(m); return { providerId: 'o1' }; },
  async sendText(m) { if (failNext) { failNext = false; throw new Error('boom'); } sentTexts.push(m); return { providerId: `t${sentTexts.length}` }; },
};
let h; let o;
const gym = () => JSON.parse(h.store.get('SELECT data FROM gyms WHERE id = ?', o.gym).data);

before(async () => {
  // production-like: the code is NOT exposed in responses and is random
  h = await boot({ devOtp: false, fixedOtp: '', devPayments: false, messagingTransport: transport });
  // register through the provider path (the code comes from the transport, as it would on a phone)
  const r = await h.call('POST', '/v5/register/partner', { body: { name: 'Prod Owner', phone: '+919876508101' } });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(data(r).devOtp, undefined, 'the code is never in the response');
  const code = sentOtps.at(-1).code;
  const v = await h.call('POST', '/v5/register/partner/verify', { body: { requestId: data(r).requestId, otp: code } });
  assert.equal(v.status, 200, JSON.stringify(v.body));
  const token = data(v).accessToken;
  const g = await h.call('POST', '/v5/register/partner/gym', { token, body: { name: 'Prod Gym', address: '12 MG Road, Bengaluru', pincode: '560001', city: 'Bengaluru', state: 'Karnataka' } });
  const gymId = data(g).gym.id;
  o = { gym: gymId, as: (m, p, body) => h.call(m, p, { body, token, gym: gymId }) };
});
after(async () => { await h.close(); });

test('a sign-in code is delivered to the phone, and only that code works', async () => {
  const r = await h.call('POST', '/v5/auth/signin/otp', { body: { phone: '+919876508101', channel: 'whatsapp' } });
  assert.equal(r.status, 200);
  assert.equal(data(r).devOtp, undefined);
  await new Promise((res) => setImmediate(res));
  const m = sentOtps.at(-1);
  assert.deepEqual([m.channel, m.to], ['whatsapp', '+919876508101']);
  assert.match(m.code, /^\d{6}$/);
  const bad = await h.call('POST', '/v5/auth/signin/verify', { body: { requestId: data(r).requestId, otp: m.code === '000000' ? '111111' : '000000' } });
  assert.ok(bad.status >= 400);
  const good = await h.call('POST', '/v5/auth/signin/verify', { body: { requestId: data(r).requestId, otp: m.code } });
  assert.equal(good.status, 200);
  assert.equal(data(good).kind, 'staff');
});

test('an unknown number sends nothing at all', async () => {
  const before = sentOtps.length;
  const r = await h.call('POST', '/v5/auth/signin/otp', { body: { phone: '+919311109999' } });
  assert.equal(r.status, 200);
  assert.equal(sentOtps.length, before, 'no code is sent, and the answer looks the same');
});

test('recorded messages are sent, marked sent, and a failed one is refunded', async () => {
  h.store.run('UPDATE gyms SET data = ? WHERE id = ?', JSON.stringify({ ...gym(), creditBalance: 10, features: { ...gym().features, WHATSAPP_INTEGRATION: true } }), o.gym);
  const col = h.store.col(o.gym, 'outbox');
  const a = col.insert({ key: 'BROADCAST', to: '+919900008881', body: 'Hello A', channel: 'whatsapp', credits: 1, status: 'recorded' });
  const b = col.insert({ key: 'BROADCAST', to: '+919900008882', body: 'Hello B', channel: 'whatsapp', credits: 1, status: 'recorded' });
  failNext = true;
  const out = await processOutbox(h.store, h.app.messenger);
  assert.deepEqual(out, { sent: 1, failed: 1 });
  assert.equal(col.get(a.id).status, 'failed');
  assert.equal(col.get(a.id).failureReason, 'providerError');
  assert.equal(col.get(b.id).status, 'sent');
  assert.equal(col.get(b.id).providerId, 't1');
  assert.equal(gym().creditBalance, 11, 'the failed message returned its credit');
  assert.deepEqual(await processOutbox(h.store, h.app.messenger), { sent: 0, failed: 0 }, 'nothing is sent twice');
});

test('MSG91, WhatsApp and Resend calls have the shape the providers expect', async () => {
  const calls = [];
  const fetchImpl = async (url, init) => { calls.push({ url: String(url), init }); return { ok: true, status: 200, json: async () => ({ type: 'success', request_id: 'r1', messages: [{ id: 'wamid.1' }], id: 'e1' }) }; };
  const m = new Messenger({ messaging: {
    sms: { provider: 'msg91', authKey: 'AK', otpTemplateId: 'T1', flowTemplateId: 'F1' },
    whatsapp: { token: 'WT', phoneNumberId: '555', otpTemplate: 'otp_tpl', textTemplate: 'msg_tpl' }, email: { apiKey: 'RK', from: 'Gymmie <no-reply@example.com>' }, fetchImpl,
  } });
  assert.ok(m.canSendOtp('sms') && m.canSendOtp('whatsapp') && m.canSendOtp('email') && m.canSendText('whatsapp'));
  await m.sendOtp({ channel: 'sms', to: '+919876543210', code: '123456' });
  assert.match(calls[0].url, /control\.msg91\.com\/api\/v5\/otp\?.*template_id=T1.*mobile=919876543210.*authkey=AK.*otp=123456/);
  await m.sendOtp({ channel: 'whatsapp', to: '+919876543210', code: '654321' });
  const wa = JSON.parse(calls[1].init.body);
  assert.match(calls[1].url, /graph\.facebook\.com\/v20\.0\/555\/messages/);
  assert.equal(calls[1].init.headers.authorization, 'Bearer WT');
  assert.equal(wa.to, '919876543210');
  assert.equal(wa.template.name, 'otp_tpl');
  assert.equal(wa.template.components[0].parameters[0].text, '654321');
  assert.equal(wa.template.components[1].sub_type, 'url', 'the one-tap copy button carries the code too');
  await m.sendText({ channel: 'sms', to: '+919876543210', body: 'Hi' });
  assert.equal(JSON.parse(calls[2].init.body).recipients[0].var1, 'Hi');
  assert.equal(calls[2].init.headers.authkey, 'AK');
  await m.sendOtp({ channel: 'email', to: 'a@b.co', code: '111222' });
  assert.match(JSON.parse(calls[3].init.body).text, /111222/);
  const none = new Messenger({ messaging: {} });
  assert.equal(none.canSendOtp('sms'), false);
  await assert.rejects(() => none.sendOtp({ channel: 'sms', to: '+91', code: '1' }));
});

test('a provider error is reported, not swallowed', async () => {
  const m = new Messenger({ messaging: { sms: { provider: 'msg91', authKey: 'AK', otpTemplateId: 'T1' }, fetchImpl: async () => ({ ok: false, status: 401, json: async () => ({ message: 'bad key' }) }) } });
  await assert.rejects(() => m.sendOtp({ channel: 'sms', to: '+919876543210', code: '1' }), /401/);
});

test('the integrations list says what really carries WhatsApp messages', async () => {
  const wa = data(await o.as('GET', '/v5/integrations')).find((i) => i.key === 'whatsapp');
  assert.equal(wa.provider, 'whatsapp-cloud');
});
