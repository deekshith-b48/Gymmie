// What a gym's staff may see of a member, given the member's own privacy choices (member app → Settings → Privacy).
//
// Owners, managers and the front desk keep the access their role has always had: the gym needs these details to run. A
// TRAINER is different: they can only see members assigned to them, and the member may also hide some details from them.
// The member's training log is private unless they chose to share a summary.
import { forbidden } from '../errors.js';
import { diffDays } from './dates.js';

export const TRAINER_FIELDS = ['email', 'birthDate', 'address', 'emergencyContact', 'health'];
export const SHARE_LEVELS = ['off', 'trainer', 'gym'];

/** The details this member hides from trainers. */
export const hiddenFromTrainers = (m) => TRAINER_FIELDS.filter((k) => m?.privacy?.trainerCanSee?.[k] === false);

export const shareLevelOf = (m) => (SHARE_LEVELS.includes(m?.privacy?.shareTraining) ? m.privacy.shareTraining : 'off');

/** A trainer sees only the members assigned to them. */
export function assertTrainerScope(ctx, member) {
  if (ctx.role === 'trainer' && member?.trainerId !== ctx.user.id) throw forbidden('Member is not assigned to this trainer.');
}

/** Whether this caller may read the member's health details (conditions, PAR-Q, blood group). */
export function mayReadHealth(ctx, member) {
  if (ctx.role !== 'trainer') return true;
  return member?.trainerId === ctx.user.id && !hiddenFromTrainers(member).includes('health');
}

/** The member view with whatever the member hid from trainers taken out (a no-op for every other role). */
export function redactForTrainer(ctx, view, member) {
  if (ctx.role !== 'trainer') return view;
  const hide = hiddenFromTrainers(member);
  if (!hide.length) return view;
  const out = { ...view };
  for (const k of ['email', 'birthDate', 'address', 'emergencyContact']) if (hide.includes(k) && k in out) out[k] = null;
  if (hide.includes('health')) {
    out.bloodGroup = null;
    if ('health' in out) out.health = null;
  }
  out.hiddenByMember = hide;
  return out;
}

const isoOf = (d) => `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`;
const addDaysIso = (iso, n) => { const d = new Date(`${iso}T12:00:00Z`); d.setUTCDate(d.getUTCDate() + n); return isoOf(d); };
const workoutDay = (w) => (/^\d{4}-\d{2}-\d{2}$/.test(String(w?.d)) ? w.d : null);

/**
 * A short summary of a member's training log for the people they chose to share it with. Never the sets themselves:
 * how often they train, how long, and the last few sessions by name.
 */
export function trainingSummary(state, today) {
  const workouts = (Array.isArray(state?.workouts) ? state.workouts : []).filter((w) => w && workoutDay(w));
  const weekStart = state?.weekStart === 0 ? 0 : 1;
  const days = [...new Set(workouts.map(workoutDay))].sort();
  const startOfWeek = (iso) => {
    const d = new Date(`${iso}T12:00:00Z`);
    const offset = (d.getUTCDay() - weekStart + 7) % 7;
    return addDaysIso(iso, -offset);
  };
  const week = (iso) => startOfWeek(iso);
  const thisWeek = week(today);
  const weeks = [];
  for (let k = 7; k >= 0; k--) {
    const from = addDaysIso(thisWeek, -7 * k);
    const to = addDaysIso(from, 6);
    weeks.push({ from, count: workouts.filter((w) => workoutDay(w) >= from && workoutDay(w) <= to).length });
  }
  let streak = 0;
  const has = (from) => workouts.some((w) => workoutDay(w) >= from && workoutDay(w) <= addDaysIso(from, 6));
  let cursor = thisWeek;
  if (!has(cursor)) cursor = addDaysIso(cursor, -7);
  while (has(cursor)) { streak++; cursor = addDaysIso(cursor, -7); }
  const mins = workouts.map((w) => (Number.isFinite(w.start) && Number.isFinite(w.end) && w.end > w.start ? Math.round((w.end - w.start) / 60000) : null)).filter((x) => x !== null);
  return {
    totalWorkouts: workouts.length,
    last30Days: workouts.filter((w) => diffDays(workoutDay(w), today) >= 0 && diffDays(workoutDay(w), today) <= 29).length,
    lastWorkoutAt: days.at(-1) ?? null,
    weekStreak: streak,
    averageMinutes: mins.length ? Math.round(mins.reduce((a, b) => a + b, 0) / mins.length) : null,
    weeks,
    recent: [...workouts].sort((a, b) => workoutDay(b).localeCompare(workoutDay(a)) || (b.start ?? 0) - (a.start ?? 0)).slice(0, 5)
      .map((w) => ({ date: workoutDay(w), name: String(w.name ?? 'Workout').slice(0, 60), minutes: Number.isFinite(w.start) && Number.isFinite(w.end) && w.end > w.start ? Math.round((w.end - w.start) / 60000) : null })),
  };
}
