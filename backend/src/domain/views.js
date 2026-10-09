// Read-model helpers: one pass over the gym's collections builds lookups reused by list/detail/dashboard.
import { balanceOf, currentMembership, daysLeft, membershipStatus, sessionsLeft } from './membership.js';
import { diffDays, addDays } from './dates.js';
import { round2 } from './pricing.js';

export function buildIndex(ctx) {
  const today = ctx.today();
  const memberships = ctx.col('memberships').all();
  const byMember = new Map();
  for (const m of memberships) {
    if (!byMember.has(m.memberId)) byMember.set(m.memberId, []);
    byMember.get(m.memberId).push(m);
  }
  const balances = new Map();
  const addBal = (id, v) => balances.set(id, round2((balances.get(id) ?? 0) + v));
  for (const m of memberships) { const b = balanceOf(m); if (b > 0) addBal(m.memberId, b); }
  for (const s of ctx.col('productSales').all()) { if (s.memberId) { const b = balanceOf(s); if (b > 0) addBal(s.memberId, b); } }
  const lastAttended = new Map();
  const visits = new Map(); // memberId -> [dates]
  for (const a of ctx.col('attendance').all()) {
    if (a.kind && a.kind !== 'member') continue;
    if (!visits.has(a.memberId)) visits.set(a.memberId, []);
    visits.get(a.memberId).push(a.date);
    if (!lastAttended.has(a.memberId) || lastAttended.get(a.memberId) < a.date) lastAttended.set(a.memberId, a.date);
  }
  const tags = new Map(ctx.col('tags').all().map((t) => [t.id, t]));
  const staff = new Map(ctx.store.all(
    "SELECT u.id, u.name, gu.role FROM gym_users gu JOIN users u ON u.id = gu.user_id WHERE gu.gym_id = ?", ctx.gymId).map((r) => [r.id, r]));
  const reminders = new Map(ctx.col('balanceReminders').find((r) => !r.done).map((r) => [r.memberId, r]));
  return { today, memberships, byMember, balances, lastAttended, visits, tags, staff, reminders };
}

export function currentSummary(idx, memberId) {
  const list = idx.byMember.get(memberId) ?? [];
  const cur = currentMembership(list, idx.today);
  if (!cur) return null;
  const { m, s } = cur;
  return {
    id: m.id, planId: m.planId, planName: m.planName, startDate: m.startDate, endDate: m.endDate, status: s,
    daysLeft: daysLeft(m, idx.today), sessionsLeft: sessionsLeft(m), sessionsTotal: m.sessions?.total ?? null, balance: balanceOf(m),
    upcomingCount: list.filter((x) => membershipStatus(x, idx.today) === 'upcoming').length,
  };
}

export function memberSummary(member, idx) {
  const cur = currentSummary(idx, member.id);
  const trainer = member.trainerId ? idx.staff.get(member.trainerId) : null;
  return {
    id: member.id, admissionNo: member.admissionNo, name: member.name, phone: member.phone, email: member.email ?? null,
    gender: member.gender ?? null, birthDate: member.birthDate ?? null, bloodGroup: member.bloodGroup ?? null,
    joinedAt: member.joinedAt, blocked: !!member.blocked, blockedReason: member.blockedReason ?? null,
    photoUrl: member.photoFileId ? `/v5/files/${member.photoFileId}` : null,
    labels: (member.labelIds ?? []).map((id) => idx.tags.get(id)).filter(Boolean).map((t) => ({ id: t.id, name: t.name, color: t.color })),
    trainer: trainer ? { id: trainer.id, name: trainer.name } : null,
    membership: cur,
    balance: idx.balances.get(member.id) ?? 0,
    balanceReminder: idx.reminders.get(member.id)?.reminderDate ?? null,
    lastAttendedAt: idx.lastAttended.get(member.id) ?? null,
    parqSigned: !!member.parqSignedAt,
    createdAt: member.createdAt,
  };
}

/** Rule-based churn insights (reconstruction of the "At-risk Members" / "AI Insights" cards). */
export function atRiskReasons(member, idx) {
  const cur = currentSummary(idx, member.id);
  if (!cur || cur.status !== 'active') return [];
  const reasons = [];
  const dates = idx.visits.get(member.id) ?? [];
  const recent = dates.filter((d) => diffDays(d, idx.today) <= 13).length;
  const prior = dates.filter((d) => { const x = diffDays(d, idx.today); return x >= 14 && x <= 27; }).length;
  const age = diffDays(member.joinedAt ?? idx.today, idx.today);
  if (prior >= 3 && recent <= prior / 2) reasons.push({ code: 'attendanceDeclining', label: 'Attendance declining', detail: `${recent} visits in the last 14 days vs ${prior} before` });
  else if (age >= 14 && recent === 0) reasons.push({ code: 'lowAttendance', label: 'Low gym attendance', detail: 'No visits in the last 14 days' });
  if ((cur.balance ?? 0) > 0 && cur.daysLeft !== null && cur.daysLeft <= 7) reasons.push({ code: 'balanceDue', label: 'Balance due before expiry', detail: `${cur.balance} pending, expires in ${cur.daysLeft} days` });
  return reasons;
}

export { addDays };
