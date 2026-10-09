// Membership lifecycle rules shared by routes (status, current membership, balances, expiry maths).
import { addDays, diffDays } from './dates.js';
import { round2 } from './pricing.js';

export function membershipStatus(m, today) {
  if (m.endedAt) return 'ended';
  if (m.pausedAt) return 'paused';
  if (m.startDate > today) return 'upcoming';
  if (m.endDate < today) return 'expired';
  return 'active';
}

export const balanceOf = (m) => round2(Math.max(0, m.total - (m.amountReceived ?? 0) - (m.writtenOff ?? 0)));

/** Priority: active > paused > earliest upcoming > most recent expired/ended. */
export function currentMembership(list, today) {
  const withStatus = list.map((m) => ({ m, s: membershipStatus(m, today) }));
  const pick = (s) => withStatus.filter((x) => x.s === s);
  const active = pick('active').sort((a, b) => b.m.endDate.localeCompare(a.m.endDate));
  if (active.length) return active[0];
  const paused = pick('paused');
  if (paused.length) return paused[0];
  const upcoming = pick('upcoming').sort((a, b) => a.m.startDate.localeCompare(b.m.startDate));
  if (upcoming.length) return upcoming[0];
  const past = withStatus.filter((x) => x.s === 'expired' || x.s === 'ended').sort((a, b) => b.m.endDate.localeCompare(a.m.endDate));
  return past[0] ?? null;
}

/** End date for a plan of `durationDays` starting on `startDate` (inclusive of the first day). */
export const endDateFor = (startDate, durationDays) => addDays(startDate, Math.max(1, durationDays) - 1);

export function daysLeft(m, today) {
  const s = membershipStatus(m, today);
  if (s === 'upcoming' || s === 'ended') return null;
  return diffDays(today, m.endDate);
}

/** Overlap check between the proposed [start, end] window and existing live memberships. */
export function overlaps(existing, start, end, ignoreId) {
  return existing.find((m) => m.id !== ignoreId && !m.endedAt && m.startDate <= end && m.endDate >= start) ?? null;
}

export function sessionsLeft(m) {
  if (!m.sessions) return null;
  return Math.max(0, m.sessions.total - (m.sessionLogs?.length ?? 0));
}
