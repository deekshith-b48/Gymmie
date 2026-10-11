import { startServer } from '../src/server.js';

export async function boot(overrides = {}) {
  const s = await startServer({ port: 0, host: '127.0.0.1', dbFile: ':memory:', jwtSecret: 'test-secret-test-secret-test-secret', fixedOtp: '123456', devOtp: true, devPayments: true, logRequests: false, otpResendSec: 0, rateLimitScale: 1000, ...overrides });
  const base = `http://127.0.0.1:${s.port}`;
  async function call(method, path, { body, token, gym, headers = {}, raw = false } = {}) {
    const res = await fetch(base + path, {
      method, headers: { ...(body !== undefined ? { 'content-type': 'application/json' } : {}), ...(token ? { authorization: `Bearer ${token}` } : {}), ...(gym ? { 'x-gym-id': gym } : {}), ...headers },
      body: body !== undefined ? JSON.stringify(body) : undefined,
    });
    if (raw) return res;
    const text = await res.text();
    return { status: res.status, body: text ? JSON.parse(text) : null, headers: res.headers };
  }
  /** Registers a new gym owner and returns { token, refresh, gymId, call helpers }. */
  async function owner({ phone = '+919876500001', name = 'Olivia Owner', gymName = 'Iron Temple', features = true } = {}) {
    const r = await call('POST', '/v5/register/partner', { body: { name, phone } });
    if (r.status !== 200) throw new Error(`register failed ${JSON.stringify(r.body)}`);
    const v = await call('POST', '/v5/register/partner/verify', { body: { requestId: r.body.data.requestId, otp: '123456' } });
    const token = v.body.data.accessToken;
    const g = await call('POST', '/v5/register/partner/gym', { token, body: { name: gymName, address: '12 MG Road, Bengaluru', pincode: '560001', city: 'Bengaluru', state: 'Karnataka' } });
    const gym = g.body.data.gym.id;
    if (features) {
      const gs = s.store.get('SELECT data FROM gyms WHERE id = ?', gym);
      const d = JSON.parse(gs.data);
      d.features = { ...d.features, WHATSAPP_INTEGRATION: true, SALES: true, BIOMETRICS: true, AI_INSIGHTS: true, AI_WORKOUTS: true, DIET_PLANS: true, WORKOUT_PLANS: true, RISK_MEMBERS: true, QUICK_REPORTS: true, MEMBER_HEALTH: true };
      s.store.run('UPDATE gyms SET data = ? WHERE id = ?', JSON.stringify(d), gym);
    }
    const as = (method, path, body, extra = {}) => call(method, path, { body, token, gym, ...extra });
    return { token, refresh: v.body.data.refreshToken, gym, phone, as, user: v.body.data.user };
  }
  async function loginAs(phone, gym) {
    const r = await call('POST', '/v5/auth/login/otp', { body: { phone } });
    if (r.status !== 200) throw new Error(`login otp failed ${JSON.stringify(r.body)}`);
    const v = await call('POST', '/v5/auth/login/otp/verify', { body: { requestId: r.body.data.requestId, otp: '123456' } });
    const token = v.body.data.accessToken;
    return { token, gym, as: (method, path, body, extra = {}) => call(method, path, { body, token, gym, ...extra }) };
  }
  return { ...s, call, owner, loginAs, base };
}

export const data = (r) => r.body?.data;
