// Dashboard tiles, live occupancy, quick reports and rule-based insights.
import { S, validate } from '../validate.js';
import { invalid } from '../errors.js';
import { addDays, diffDays, inRange, monthStart, periodRange } from '../domain/dates.js';
import { atRiskReasons, buildIndex, currentSummary, memberSummary } from '../domain/views.js';
import { round2 } from '../domain/pricing.js';
import { ensureFeature } from '../helpers.js';
import { saveGym } from '../helpers.js';
import { balanceOf } from '../domain/membership.js';

const LIVE_WINDOW_MS = 3 * 3600 * 1000;

function ageOn(birthDate, today) {
  if (!birthDate) return null;
  let a = +today.slice(0, 4) - +birthDate.slice(0, 4);
  if (today.slice(5) < birthDate.slice(5)) a--;
  return a;
}

export function occupancy(ctx) {
  const today = ctx.today();
  const rows = ctx.col('attendance').all().filter((a) => a.date === today);
  const now = Date.now();
  const live = rows.filter((a) => !a.checkOut && now - Date.parse(a.checkIn) <= LIVE_WINDOW_MS);
  const hourOf = (iso) => Number(new Intl.DateTimeFormat('en-GB', { timeZone: ctx.gym.timezone, hour: '2-digit', hour12: false }).format(new Date(iso))) % 24;
  const hours = Array.from({ length: 24 }, (_, h) => ({ hour: h, checkIns: 0 }));
  for (const a of rows) hours[hourOf(a.checkIn)].checkIns++;
  const peak = hours.reduce((b, h) => (h.checkIns > b.checkIns ? h : b), { hour: null, checkIns: 0 });
  const devices = ctx.col('devices').all();
  return {
    liveCount: live.length, todayCount: rows.length, peakToday: peak.checkIns > 0 ? { hour: peak.hour, checkIns: peak.checkIns } : null, hours,
    devices: { total: devices.length, connected: devices.filter((d) => d.status === 'connected').length },
    hasBiometricDevice: devices.length > 0,
  };
}

export function registerDashboardRoutes({ router }) {
  router.get('/v5/dashboards/gyms/occupancy', { perm: 'attendance.read' }, (ctx) => occupancy(ctx));

  router.get('/v5/dashboards/gyms/summary', { perm: 'members.read' }, (ctx) => {
    const idx = buildIndex(ctx);
    const members = ctx.col('members').all();
    const summaries = members.map((m) => memberSummary(m, idx));
    const t = idx.today;
    const left = (s) => (s.membership && ['active', 'paused'].includes(s.membership.status) ? s.membership.daysLeft : null);
    const atRisk = ctx.gym.features?.RISK_MEMBERS ? members.filter((m) => atRiskReasons(m, idx).length).length : null;
    const visits = ctx.col('attendance').all();
    const att = (r) => visits.filter((a) => inRange(a.date, r)).length;
    const week = periodRange('thisWeek', t);
    const month = periodRange('thisMonth', t);
    const leads = ctx.col('leads').all().filter((l) => !l.convertedMemberId && !l.disabled);
    const reminders = ctx.col('balanceReminders').find((r) => !r.done);
    const balanceTotal = round2([...idx.balances.values()].reduce((s, v) => s + v, 0));
    const birthdays = summaries.filter((s) => s.birthDate && s.birthDate.slice(5) === t.slice(5)).map((s) => ({ id: s.id, name: s.name, phone: s.phone, age: ageOn(s.birthDate, t), photoUrl: s.photoUrl }));
    const sub = ctx.gym.subscription;
    return {
      today: t,
      tiles: {
        activeMembers: summaries.filter((s) => s.membership?.status === 'active').length,
        allMembers: summaries.length,
        atRisk,
        expiring10: summaries.filter((s) => left(s) !== null && left(s) <= 10).length,
        expiring30: summaries.filter((s) => left(s) !== null && left(s) <= 30).length,
        leadsToday: leads.filter((l) => l.followUpDate === t).length,
        leadsTotal: leads.length,
      },
      attendance: { today: att({ from: t, to: t }), week: att(week), month: att(month) },
      balance: { total: balanceTotal, members: [...idx.balances.values()].filter((v) => v > 0).length },
      balanceReminders: reminders.filter((r) => r.reminderDate <= t).map((r) => ({ ...r, member: idx.byMember.has(r.memberId) || members.find((m) => m.id === r.memberId) ? { id: r.memberId, name: members.find((m) => m.id === r.memberId)?.name, phone: members.find((m) => m.id === r.memberId)?.phone } : null, balance: idx.balances.get(r.memberId) ?? 0 })).filter((r) => r.member?.name),
      birthdays,
      newMembersThisMonth: summaries.filter((s) => s.joinedAt >= monthStart(t)).length,
      subscription: sub ? { plan: sub.plan, endsAt: sub.endsAt, daysLeft: diffDays(t, sub.endsAt), expired: sub.endsAt < t } : null,
      credits: ctx.gym.creditBalance ?? 0,
      whatsapp: ctx.gym.whatsapp,
      occupancy: occupancy(ctx),
    };
  });

  // ---- quick reports ---------------------------------------------------------------------------------------------
  function report(ctx, range) {
    const memberships = ctx.col('memberships').all();
    const txns = ctx.col('transactions').all().filter((t) => inRange(t.date, range));
    const expenses = ctx.col('expenses').all().filter((e) => inRange(e.date, range));
    const sales = ctx.col('productSales').all().filter((s) => inRange(s.date, range));
    const received = (kinds) => round2(txns.filter((t) => kinds.includes(t.kind)).reduce((s, t) => s + t.amount, 0));
    const membershipRevenue = received(['membership', 'settlement']);
    const salesRevenue = received(['sale']);
    const expenseTotal = round2(expenses.reduce((s, e) => s + e.amount, 0));
    const byPlan = new Map();
    for (const m of memberships.filter((x) => inRange(x.createdAt.slice(0, 10), range))) {
      const cur = byPlan.get(m.planName) ?? { plan: m.planName, count: 0, revenue: 0 };
      cur.count++; cur.revenue = round2(cur.revenue + m.total);
      byPlan.set(m.planName, cur);
    }
    const byProduct = new Map();
    for (const s of sales) for (const i of s.items) {
      const cur = byProduct.get(i.name) ?? { product: i.name, units: 0, revenue: 0 };
      cur.units += i.quantity; cur.revenue = round2(cur.revenue + i.price * i.quantity);
      byProduct.set(i.name, cur);
    }
    const byCat = new Map();
    for (const e of expenses) byCat.set(e.category, round2((byCat.get(e.category) ?? 0) + e.amount));
    const byPay = new Map();
    for (const t of txns.filter((x) => x.kind !== 'writeoff')) byPay.set(t.paymentType, round2((byPay.get(t.paymentType) ?? 0) + t.amount));
    const newMembers = ctx.col('members').all().filter((m) => inRange(m.joinedAt, range)).length;
    return {
      range, revenue: round2(membershipRevenue + salesRevenue), membershipRevenue, salesRevenue, expenses: expenseTotal,
      net: round2(membershipRevenue + salesRevenue - expenseTotal), newMembers,
      membershipsByPlan: [...byPlan.values()].sort((a, b) => b.revenue - a.revenue), salesByProduct: [...byProduct.values()].sort((a, b) => b.revenue - a.revenue),
      expensesByCategory: [...byCat.entries()].map(([category, amount]) => ({ category, amount })).sort((a, b) => b.amount - a.amount),
      revenueByPaymentType: [...byPay.entries()].map(([paymentType, amount]) => ({ paymentType, amount })),
    };
  }

  router.get('/v5/dashboards/gyms/reports/transactions', { perm: 'reports.read' }, (ctx) => {
    ensureFeature(ctx.gym, 'QUICK_REPORTS');
    const today = ctx.today();
    const range = periodRange(ctx.query.period ?? 'thisMonth', today, { from: ctx.query.from, to: ctx.query.to });
    if (!range) throw invalid('Please select a date range');
    if (range.from > range.to) throw invalid('Please select start and end date');
    const len = diffDays(range.from, range.to) + 1;
    const prev = { from: addDays(range.from, -len), to: addDays(range.from, -1) };
    const cur = report(ctx, range);
    const before = report(ctx, prev);
    const idx = buildIndex(ctx);
    return { ...cur, outstandingBalance: round2([...idx.balances.values()].reduce((s, v) => s + v, 0)), previous: { range: prev, revenue: before.revenue, expenses: before.expenses, net: before.net, newMembers: before.newMembers } };
  });

  // Periodic e-mailed reports: only the preference is stored here; no mail provider is configured.
  router.get('/v5/dashboards/gyms/reports/schedule', { perm: 'reports.read' }, (ctx) => ({ frequency: 'off', email: ctx.gym.email, ...(ctx.gym.reportSchedule ?? {}), delivery: 'not-configured' }));
  router.put('/v5/dashboards/gyms/reports/schedule', { perm: 'settings.write' }, (ctx) => {
    const b = validate({ frequency: S.oneOf(['off', 'monthly', 'quarterly', 'yearly'], { required: true }), email: S.email() }, ctx.body);
    if (b.frequency !== 'off' && !b.email && !ctx.gym.email) throw invalid('email is required to receive reports');
    saveGym(ctx.store, ctx.gymId, { reportSchedule: b });
    return { ...b, delivery: 'not-configured' };
  });

  // ---- insights ---------------------------------------------------------------------------------------------------
  router.get('/v5/dashboards/gyms/insights', { perm: 'reports.read' }, (ctx) => {
    ensureFeature(ctx.gym, 'AI_INSIGHTS');
    const idx = buildIndex(ctx);
    const t = idx.today;
    const out = [];
    const members = ctx.col('members').all();
    const risky = members.map((m) => ({ m, r: atRiskReasons(m, idx) })).filter((x) => x.r.length);
    for (const code of ['attendanceDeclining', 'lowAttendance']) {
      const hit = risky.filter((x) => x.r.some((r) => r.code === code));
      if (hit.length) out.push({ code, severity: 'warning', title: code === 'attendanceDeclining' ? 'Attendance declining' : 'Low gym attendance', count: hit.length, detail: `${hit.length} active members are visiting less`, memberIds: hit.map((x) => x.m.id).slice(0, 20) });
    }
    const last30 = { from: addDays(t, -29), to: t };
    const recent = idx.memberships.filter((m) => inRange(m.createdAt.slice(0, 10), last30));
    const listed = recent.reduce((s, m) => s + m.subtotal, 0);
    const disc = recent.reduce((s, m) => s + (m.discount?.amount ?? 0), 0);
    if (listed > 0 && disc / listed > 0.2) out.push({ code: 'highOverallDiscounts', severity: 'warning', title: 'High overall discounts', count: recent.length, detail: `${Math.round((disc / listed) * 100)}% of list price was discounted in the last 30 days` });
    const heavy = recent.filter((m) => m.subtotal > 0 && (m.discount?.amount ?? 0) / m.subtotal > 0.3);
    if (heavy.length) out.push({ code: 'highDiscounts', severity: 'info', title: 'High discounts', count: heavy.length, detail: `${heavy.length} memberships were sold with more than 30% off` });
    const last90 = idx.memberships.filter((m) => inRange(m.createdAt.slice(0, 10), { from: addDays(t, -89), to: t }));
    const rev = new Map();
    for (const m of last90) rev.set(m.planName, (rev.get(m.planName) ?? 0) + m.total);
    const totalRev = [...rev.values()].reduce((s, v) => s + v, 0);
    const top = [...rev.entries()].sort((a, b) => b[1] - a[1])[0];
    if (top && totalRev > 0 && top[1] / totalRev > 0.6 && rev.size > 1) out.push({ code: 'revenueConcentrationRisk', severity: 'info', title: 'Revenue concentration risk', count: 1, detail: `${top[0]} brings ${Math.round((top[1] / totalRev) * 100)}% of membership revenue` });
    const sold = new Set(last90.map((m) => m.planId));
    const unused = ctx.col('plans').find((p) => p.active !== false && !sold.has(p.id));
    if (unused.length) out.push({ code: 'unusedPlans', severity: 'info', title: 'Plans with no sign-ups', count: unused.length, detail: `These plans had no sign-ups in the last 3 months: ${unused.map((p) => p.name).join(', ')}` });
    const churn = members.map((m) => ({ m, c: currentSummary(idx, m.id) })).filter((x) => x.c?.status === 'expired' && diffDays(x.c.endDate, t) <= 10);
    if (churn.length) out.push({ code: 'memberChurnAlert', severity: 'warning', title: 'Member churn alert', count: churn.length, detail: `${churn.length} memberships expired in the last 10 days without renewal`, memberIds: churn.map((x) => x.m.id).slice(0, 20) });
    const low = ctx.col('products').find((p) => p.trackStock && p.active !== false && p.quantity <= (p.lowStockThreshold ?? 0));
    if (low.length) out.push({ code: 'lowStock', severity: 'info', title: 'Low stock', count: low.length, detail: low.map((p) => p.name).join(', ') });
    return { generatedAt: new Date().toISOString(), engine: 'rule-based', insights: out };
  });
}
