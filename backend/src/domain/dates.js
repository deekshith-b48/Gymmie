// Calendar-date helpers. Dates are 'YYYY-MM-DD' strings interpreted in the gym's timezone.
export function todayIn(tz = 'Asia/Kolkata', now = new Date()) {
  try {
    return new Intl.DateTimeFormat('en-CA', { timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit' }).format(now);
  } catch {
    return now.toISOString().slice(0, 10);
  }
}

const toUtc = (s) => new Date(`${s}T00:00:00Z`);
const fmt = (d) => d.toISOString().slice(0, 10);

export function addDays(s, n) {
  const d = toUtc(s);
  d.setUTCDate(d.getUTCDate() + n);
  return fmt(d);
}

export function addMonths(s, n) {
  const d = toUtc(s);
  const day = d.getUTCDate();
  d.setUTCDate(1);
  d.setUTCMonth(d.getUTCMonth() + n);
  const last = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 0)).getUTCDate();
  d.setUTCDate(Math.min(day, last));
  return fmt(d);
}

/** Whole days from a to b (b - a). */
export const diffDays = (a, b) => Math.round((toUtc(b) - toUtc(a)) / 86400000);
export const dayOfWeek = (s) => toUtc(s).getUTCDay(); // 0 = Sunday
export const monthStart = (s) => `${s.slice(0, 7)}-01`;
export const monthEnd = (s) => fmt(new Date(Date.UTC(+s.slice(0, 4), +s.slice(5, 7), 0)));

export function nextMonday(s) {
  const dow = dayOfWeek(s);
  return addDays(s, dow === 0 ? 1 : 8 - dow);
}

/** Resolve a named reporting period (labels used by the app's date filters) into an inclusive range. */
export function periodRange(period, today, custom = {}) {
  const y = today.slice(0, 4);
  switch (period) {
    case 'today': return { from: today, to: today };
    case 'thisWeek': {
      const dow = dayOfWeek(today);
      const from = addDays(today, -(dow === 0 ? 6 : dow - 1));
      return { from, to: addDays(from, 6) };
    }
    case 'last7Days': return { from: addDays(today, -6), to: today };
    case 'last30Days': return { from: addDays(today, -29), to: today };
    case 'thisMonth': return { from: monthStart(today), to: monthEnd(today) };
    case 'lastMonth': {
      const prev = addMonths(monthStart(today), -1);
      return { from: prev, to: monthEnd(prev) };
    }
    case 'last6Months': return { from: monthStart(addMonths(today, -5)), to: today };
    case 'thisYear': return { from: `${y}-01-01`, to: `${y}-12-31` };
    case 'lastYear': return { from: `${+y - 1}-01-01`, to: `${+y - 1}-12-31` };
    case 'firstHalfThisYear': return { from: `${y}-01-01`, to: `${y}-06-30` };
    case 'secondHalfThisYear': return { from: `${y}-07-01`, to: `${y}-12-31` };
    case 'custom':
      if (custom.from && custom.to) return { from: custom.from, to: custom.to };
      return null;
    default: return null;
  }
}

export const inRange = (d, r) => !r || (d >= r.from && d <= r.to);
export const dateOf = (iso, tz) => todayIn(tz, new Date(iso));
