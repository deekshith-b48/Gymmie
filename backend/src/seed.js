// Seeds a demo gym through the real API (in-process server) so every rule/validation applies.
// Usage: node src/seed.js [--reset]
//   Demo logins (DEV ONLY, fixed OTP 123456): owner +919000000001, manager +919000000002,
//   trainer +919000000003, staff +919000000004.
import { existsSync, rmSync } from 'node:fs';
import { loadConfig } from './config.js';
import { startServer } from './server.js';
import { addDays, todayIn } from './domain/dates.js';
import { addCredits } from './domain/notify.js';
import { loadGym, saveGym } from './helpers.js';

const OWNER = '+919000000001';

let s = 1234567;
const rnd = () => { s = (s * 1664525 + 1013904223) % 4294967296; return s / 4294967296; };
const pick = (a) => a[Math.floor(rnd() * a.length)];
const int = (lo, hi) => lo + Math.floor(rnd() * (hi - lo + 1));

const FIRST = ['Aarav', 'Vivaan', 'Aditya', 'Vihaan', 'Arjun', 'Sai', 'Reyansh', 'Krishna', 'Ishaan', 'Rohan', 'Ananya', 'Diya', 'Saanvi', 'Aadhya', 'Kavya', 'Meera', 'Priya', 'Neha', 'Pooja', 'Riya', 'Karan', 'Rahul', 'Amit', 'Sneha', 'Tanvi', 'Varun', 'Nikhil', 'Isha', 'Manish', 'Deepak'];
const LAST = ['Sharma', 'Verma', 'Gupta', 'Reddy', 'Nair', 'Iyer', 'Patel', 'Mehta', 'Singh', 'Kapoor', 'Rao', 'Joshi', 'Bose', 'Das', 'Kulkarni'];

export async function seed({ reset = false } = {}) {
  const cfg = loadConfig();
  if (reset && cfg.dbFile !== ':memory:') for (const f of [cfg.dbFile, `${cfg.dbFile}-wal`, `${cfg.dbFile}-shm`]) if (existsSync(f)) rmSync(f);
  const srv = await startServer({ port: 0, host: '127.0.0.1', rateLimitScale: 1000, logRequests: false, otpResendSec: 0 });
  const base = `http://127.0.0.1:${srv.port}`;
  const call = async (method, path, body, token, gym) => {
    const r = await fetch(base + path, { method, headers: { ...(body ? { 'content-type': 'application/json' } : {}), ...(token ? { authorization: `Bearer ${token}` } : {}), ...(gym ? { 'x-gym-id': gym } : {}) }, body: body ? JSON.stringify(body) : undefined });
    const t = await r.text();
    const j = t ? JSON.parse(t) : null;
    if (r.status >= 400) throw new Error(`${method} ${path} -> ${r.status} ${t}`);
    return j?.data;
  };
  try {
    if (srv.store.get('SELECT 1 FROM users WHERE phone = ?', OWNER)) { console.log('Demo data already present (use --reset to rebuild).'); return; }
    const login = async (phone) => {
      const r = await call('POST', '/v5/auth/login/otp', { phone });
      return (await call('POST', '/v5/auth/login/otp/verify', { requestId: r.requestId, otp: srv.config.fixedOtp })).accessToken;
    };
    // ---- owner + gym ----
    const reg = await call('POST', '/v5/register/partner', { name: 'Demo Owner', phone: OWNER, email: 'owner@example.com' });
    const ver = await call('POST', '/v5/register/partner/verify', { requestId: reg.requestId, otp: srv.config.fixedOtp });
    const token = ver.accessToken;
    const gymRes = await call('POST', '/v5/register/partner/gym', { name: 'Iron Temple Fitness', address: '12 MG Road, Indiranagar', pincode: '560038', city: 'Bengaluru', state: 'Karnataka', country: 'IN' }, token);
    const gym = gymRes.gym.id;
    const T = (m, p, b) => call(m, p, b, token, gym);
    const today = todayIn('Asia/Kolkata');
    // demo gym is on a paid-up subscription with all visible features on (an admin would do this in the original product)
    const g = loadGym(srv.store, gym);
    saveGym(srv.store, gym, {
      features: { ...g.features, WHATSAPP_INTEGRATION: true, SALES: true, GYM_UPI_QR: true, AI_INSIGHTS: true, AI_WORKOUTS: true, DIET_PLANS: true, WORKOUT_PLANS: true, RISK_MEMBERS: true, QUICK_REPORTS: true, MEMBER_HEALTH: true, TAX_INFORMATION: true, POSTER_TEMPLATE: true, RENEWAL_SOUND: true, SIMPLE_MEMBER_CARD: true, LOCALIZATION: true, MEMBER_APP: true },
      subscription: { plan: 'GROWTH', startsAt: addDays(today, -60), endsAt: addDays(today, 300), limits: { plans: 30, staff: 10, members: 800 } }, upiId: 'irontemple@okbank', onboardingCompleted: true,
    });
    // ---- staff ----
    for (const [name, phone, role] of [['Maya Manager', '+919000000002', 'manager'], ['Tarun Trainer', '+919000000003', 'trainer'], ['Tina Trainer', '+919000000005', 'trainer'], ['Sam Staff', '+919000000004', 'staff']]) await T('POST', '/v5/gyms/staffs', { name, phone, role });
    const staff = await T('GET', '/v5/gyms/staffs');
    const trainers = staff.filter((x) => x.role === 'trainer').map((x) => x.userId);
    // ---- settings ----
    await T('POST', '/v5/gyms/tax', { name: 'GST', rate: 18, isIncluded: true, taxNumber: '29ABCDE1234F1Z5' });
    await T('PUT', '/v5/gyms/payment-methods', { active: ['cash', 'upi', 'debitCard', 'creditCard', 'netBanking'], default: 'upi' });
    const labels = {};
    for (const [n, c] of [['VIP', '#B8860B'], ['Student', '#1E88E5'], ['Morning Batch', '#43A047'], ['Evening Batch', '#8E24AA']]) labels[n] = (await T('POST', '/v5/gyms/tags', { name: n, color: c })).id;
    const groupStrength = (await T('POST', '/v5/memberships/plan-groups', { name: 'Gym Access' })).id;
    const groupPT = (await T('POST', '/v5/memberships/plan-groups', { name: 'Personal Training' })).id;
    const plans = {};
    for (const [key, name, price, days, grp, sessions] of [
      ['m1', 'Monthly', 1500, 30, groupStrength], ['m3', 'Quarterly', 4000, 90, groupStrength], ['m6', 'Half-yearly', 7000, 180, groupStrength], ['m12', 'Annual', 12000, 365, groupStrength],
      ['pt', 'PT 12 Sessions', 9000, 60, groupPT, 12],
    ]) plans[key] = (await T('POST', '/v5/memberships/plans', { name, price, durationDays: days, groupId: grp, ...(sessions ? { sessions: { enabled: true, count: sessions } } : {}) })).id;
    // ---- members: varied membership states ----
    const members = [];
    const profile = [
      // [startOffsetDays, plan, paid fraction]
      ...Array.from({ length: 14 }, () => [-int(0, 20), 'm1', 1]), ...Array.from({ length: 6 }, () => [-int(0, 60), 'm3', 1]), ...Array.from({ length: 4 }, () => [-int(0, 150), 'm6', 1]),
      ...Array.from({ length: 3 }, () => [-int(0, 300), 'm12', 1]), ...Array.from({ length: 5 }, () => [-int(31, 70), 'm1', 1]), ...Array.from({ length: 4 }, () => [-int(100, 200), 'm3', 1]),
      ...Array.from({ length: 4 }, () => [-int(0, 15), 'm1', 0.4]), ...Array.from({ length: 3 }, () => [-int(0, 20), 'pt', 0.7]),
    ];
    const used = new Set();
    for (let i = 0; i < profile.length + 3; i++) {
      let name; do { name = `${pick(FIRST)} ${pick(LAST)}`; } while (used.has(name)); used.add(name);
      const phone = `+9199${String(10000000 + i * 7919).slice(0, 8)}`;
      const gender = ['Ananya', 'Diya', 'Saanvi', 'Aadhya', 'Kavya', 'Meera', 'Priya', 'Neha', 'Pooja', 'Riya', 'Sneha', 'Tanvi', 'Isha'].includes(name.split(' ')[0]) ? 'female' : 'male';
      const body = {
        name, phone, gender, birthDate: `${int(1980, 2004)}-${String(int(1, 12)).padStart(2, '0')}-${String(int(1, 28)).padStart(2, '0')}`,
        joinedAt: addDays(today, -int(0, 200)), labelIds: rnd() < 0.5 ? [labels[pick(Object.keys(labels))]] : [], bloodGroup: pick(['A+', 'B+', 'O+', 'AB+', 'O-']),
        heightCm: int(155, 190), weightKg: int(52, 95), address: `${int(1, 99)}, ${pick(['Indiranagar', 'Koramangala', 'HSR Layout', 'Whitefield', 'Jayanagar'])}, Bengaluru`,
      };
      const pr = profile[i];
      if (pr) {
        const [off, pk, frac] = pr;
        const plan = pk === 'm1' ? 1500 : pk === 'm3' ? 4000 : pk === 'm6' ? 7000 : pk === 'm12' ? 12000 : 9000;
        body.membership = { planId: plans[pk], startDate: addDays(today, off), amountReceived: Math.round(plan * 1.0 * frac), paymentType: pick(['cash', 'upi', 'debitCard']) };
        if (pk === 'pt') body.trainerId = pick(trainers);
        if (rnd() < 0.15) body.membership.discount = { type: 'percent', value: pick([5, 10, 15]) };
        if (frac < 1 || body.membership.discount) body.membership.amountReceived = Math.min(body.membership.amountReceived, Math.round(plan * (body.membership.discount ? 0.85 : frac)));
      }
      body.joinedAt = pr ? addDays(today, pr[0]) : body.joinedAt;
      if (rnd() < 0.3) body.trainerId ??= pick(trainers);
      try { const m = await T('POST', '/v5/members', body); members.push({ ...m, pk: pr?.[1], off: pr?.[0] }); } catch (e) { console.warn('member skipped:', e.message.slice(0, 120)); }
    }
    // ---- attendance history (only dates where the member held an active plan) ----
    let marks = 0;
    for (const m of members.filter((x) => x.pk)) {
      const days = Math.min(30, -m.off + 1);
      const freq = m.pk === 'm1' && rnd() < 0.25 ? 0.15 : 0.55;
      for (let d = days - 1; d >= 0; d--) {
        if (rnd() > freq) continue;
        const date = addDays(today, -d);
        const hour = pick([6, 7, 8, 18, 19, 20]);
        const at = new Date(`${date}T${String(hour).padStart(2, '0')}:${String(int(0, 59)).padStart(2, '0')}:00+05:30`);
        if (at.getTime() > Date.now()) continue;
        try { await T('POST', '/v5/attendance/mark', { memberId: m.id, at: at.toISOString(), source: 'manual' }); marks++; } catch { /* expired / duplicate on that day */ }
      }
    }
    // ---- balance reminders, health, leads ----
    const owing = (await T('GET', '/v5/members/transactions/balance')).items;
    for (const [i, it] of owing.slice(0, 3).entries()) await T('POST', '/v5/balance-reminder', { memberId: it.memberId, reminderDate: addDays(today, i === 0 ? 0 : i + 1) });
    for (const m of members.slice(0, 6)) { await T('POST', `/v5/members/${m.id}/health`, { type: 'weight', value: int(60, 90), date: addDays(today, -30) }); await T('POST', `/v5/members/${m.id}/health`, { type: 'weight', value: int(58, 88) }); }
    await T('POST', `/v5/members/${members[2].id}/conditions`, { name: 'Back Pain', notes: 'Lower back, avoid heavy deadlifts' });
    const SOURCES = ['Walk-in', 'Social Media', 'Friend', 'Google', 'Campaign', 'Existing Member', 'Other'];
    const leadNames = ['John Doe', 'James Highland', 'Jacob Thomas', 'Anna Hathaway', 'Jane Doe', 'Rhea Kapoor', 'Sahil Arora', 'Kiran Pillai', 'Zoya Khan', 'Dev Malhotra'];
    for (const [i, n] of leadNames.entries()) await T('POST', '/v5/prospects/members', { name: n, phone: `+9198${String(70000000 + i * 1237)}`, source: SOURCES[i % SOURCES.length], chanceOfJoining: ['Low', 'Medium', 'High'][i % 3], followUpDate: addDays(today, i % 4 === 0 ? 0 : i - 3), interestedPlanId: plans.m3, notes: i % 2 ? 'Asked about weekend batches' : undefined });
    // ---- products, sales, expenses ----
    const prods = {};
    for (const [n, cat, price, cost, qty, th] of [['Whey Protein 1kg', 'Supplements', 2800, 2100, 14, 4], ['Creatine 250g', 'Supplements', 1500, 1000, 3, 4], ['Shaker Bottle', 'Accessories', 350, 180, 25, 5], ['Gym Towel', 'Merchandise', 250, 120, 40, 10], ['Energy Drink', 'Beverages', 120, 70, 60, 12], ['Lifting Gloves', 'Accessories', 600, 350, 0, 3]])
      prods[n] = await T('POST', '/v5/products', { name: n, category: cat, price, costPrice: cost, trackStock: qty > 0 || n === 'Lifting Gloves', openingStock: qty, lowStockThreshold: th });
    for (let i = 0; i < 8; i++) {
      const m = pick(members);
      const p = pick([prods['Energy Drink'], prods['Shaker Bottle'], prods['Gym Towel'], prods['Whey Protein 1kg']]);
      try { await T('POST', '/v5/product-sales', { memberId: m.id, items: [{ productId: p.id, quantity: int(1, 2) }], payments: [{ paymentType: pick(['cash', 'upi']), amount: p.price * 2 * 1.0 }] }); } catch { try { await T('POST', '/v5/product-sales', { memberId: m.id, items: [{ productId: p.id, quantity: 1 }], payments: [{ paymentType: 'cash', amount: p.price }] }); } catch { /* skip */ } }
    }
    for (const [cat, amt, off] of [['Rent', 85000, 3], ['Salaries', 120000, 2], ['Electricity & Water', 18500, 5], ['Equipment', 42000, 9], ['Maintenance', 6500, 7], ['Marketing', 12000, 4], ['Software', 2500, 1]])
      await T('POST', '/v5/expenses', { category: cat, amount: amt, date: addDays(today, -off), paymentType: pick(['upi', 'cash', 'netBanking']), notes: `${cat} for the month` });
    // ---- plans / diet / workout templates ----
    const w = await T('POST', '/v5/workout/generate', { goal: 'Build Muscle', level: 'Intermediate', daysPerWeek: 4, equipment: ['Full Gym'] });
    await T('POST', '/v5/workout/plans', { name: 'Hypertrophy 4-day', goal: w.goal, level: w.level, description: w.description, days: w.days });
    const w2 = await T('POST', '/v5/workout/generate', { goal: 'Lose Fat', level: 'Beginner', daysPerWeek: 3, equipment: ['Full Gym'] });
    await T('POST', '/v5/workout/plans', { name: 'Fat-loss starter', goal: w2.goal, level: w2.level, description: w2.description, days: w2.days });
    const d = await T('POST', '/v5/diet/generate', { goal: 'Lose Fat', dietaryPreference: 'Vegetarian', mealsPerDay: 5, calorieTarget: 1800 });
    await T('POST', '/v5/diet/plans', { name: 'Vegetarian 1800 kcal', goal: d.goal, dietaryPreference: d.dietaryPreference, calorieTarget: d.calorieTarget, macros: d.macros, meals: d.meals });
    // ---- messaging ----
    await T('POST', '/v5/integrations/whatsapp/enable');
    const ctx = { store: srv.store, gymId: gym, gym: loadGym(srv.store, gym), col: (n) => srv.store.col(gym, n) };
    addCredits(ctx, 1500, 'seed:welcome-credits');
    await T('POST', '/v5/broadcasts/templates', { title: 'Festival greeting', body: 'Wishing you a happy festival, {{memberName}}! Team {{gymName}}' });
    await T('POST', '/v5/video-links', { title: 'Perfect squat form', url: 'https://www.youtube.com/watch?v=ultWZbUMPL8' });
    await T('POST', '/v3/biohub/devices', { name: 'Main entrance', serialNumber: 'DEMO-SN-0001', ip: '192.168.1.40', type: 'both' });
    // feedback through the public portal (OTP-verified)
    const code = loadGym(srv.store, gym).code;
    for (const [i, [rating, comment, cat]] of [[5, 'Great trainers and spotless floors', 'Trainers'], [4, 'More dumbbells on weekends please', 'Equipment'], [3, 'AC was not working on Sunday', 'Facilities']].entries()) {
      const ph = `+9197000000${10 + i}`;
      const o = await call('POST', `/v5/portal/${code}/otp`, { phone: ph });
      const v = await call('POST', `/v5/portal/${code}/verify`, { requestId: o.requestId, otp: srv.config.fixedOtp });
      await call('POST', `/v5/portal/${code}/feedback`, { portalToken: v.portalToken, rating, comment, category: cat });
    }
    // sanity: a trainer login works
    await login('+919000000003');
    console.log(`Seeded gym "Iron Temple Fitness" (code ${code}): ${members.length} members, ${marks} attendance marks, ${leadNames.length} leads, ${Object.keys(prods).length} products.`);
    console.log('Demo logins (DEV, OTP 123456): owner +919000000001 · manager +919000000002 · trainer +919000000003 · staff +919000000004');
    console.log(`Demo MEMBER login (DEV, OTP 123456, "For gym members" on the login screen): ${members[0].phone}  (gym code ${code})`);
  } finally {
    await srv.close();
  }
}

if (import.meta.url === `file://${process.argv[1]}`) await seed({ reset: process.argv.includes('--reset') });
