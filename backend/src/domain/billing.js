// What a gym's subscription allows. One place decides: which plan includes which paid feature, whether the
// subscription is running, in its read-only grace period, or locked. The routes and the app both read from it.
import { diffDays, todayIn } from './dates.js';

/** Plans, lowest to highest. A trial gets every feature so an owner can try everything they would buy first. */
export const PLAN_RANK = { NONE: 0, STARTER: 1, GROWTH: 2, PRO: 3, TRIAL: 3 };

/** Paid features and the lowest plan that includes them. Anything not listed is free on every plan. */
export const PREMIUM_FEATURES = {
  MEMBER_APP: 'GROWTH',
  WHATSAPP_INTEGRATION: 'GROWTH',
  SALES: 'GROWTH',
  DIET_PLANS: 'GROWTH',
  WORKOUT_PLANS: 'GROWTH',
  AI_INSIGHTS: 'PRO',
  AI_WORKOUTS: 'PRO',
  BIOMETRICS: 'PRO',
};

export const requiredPlanFor = (key) => PREMIUM_FEATURES[key] ?? null;

/** Does this gym's plan include [key]? A gym with no subscription record (old data) is not restricted. */
export function planAllows(gym, key) {
  const need = PREMIUM_FEATURES[key];
  if (!need) return true;
  const sub = gym?.subscription;
  if (!sub) return true;
  return (PLAN_RANK[sub.plan] ?? 0) >= PLAN_RANK[need];
}

/**
 * `active` (running), `grace` (ended, read-only for [graceDays]) or `locked` (only billing works). `none` = no record.
 * `daysOver` is how many days past the end date.
 */
export function subscriptionState(gym, { graceDays = 7, now = new Date() } = {}) {
  const sub = gym?.subscription;
  if (!sub) return { status: 'none', daysOver: 0 };
  const today = todayIn(gym.timezone, now);
  if (sub.endsAt >= today) return { status: 'active', daysOver: 0 };
  const over = diffDays(sub.endsAt, today);
  return { status: over <= graceDays ? 'grace' : 'locked', daysOver: over };
}

// What still works when the subscription has ended: paying, signing out, reading your own profile.
const ALWAYS = [/^\/v5\/billings(\/|$)/, /^\/v5\/payments(\/|$)/, /^\/v5\/users\/self(\/|$)/, /^\/v3\/auth(\/|$)/, /^\/v5\/auth(\/|$)/];
const READ_ONLY_OK = [/^\/v5\/gyms(\/|$)/, /^\/v5\/files(\/|$)/, /^\/v5\/apps(\/|$)/];

/** May this request run for a gym in [state]? Reading is allowed in grace; after that only paying and signing out. */
export function allowedWhileLapsed(state, method, path) {
  if (state.status === 'active' || state.status === 'none') return true;
  if (ALWAYS.some((r) => r.test(path))) return true;
  const read = method === 'GET' || method === 'HEAD';
  if (READ_ONLY_OK.some((r) => r.test(path))) return read;
  return state.status === 'grace' && read;
}

/** Paths that need a paid feature switched on (checked for staff routes). */
export const FEATURE_ROUTES = [
  [/^\/v5\/(products|product-sales)(\/|$)/, 'SALES'],
  [/^\/v[35]\/biohub(\/|$)/, 'BIOMETRICS'],
];
