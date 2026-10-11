// The 14-day free trial. It starts when the owner has registered AND finished setting up the gym (not when the account is made),
// and each owner identity (phone number, or email when there is none) gets one: it is kept in the database, so logging out,
// reinstalling the app or registering again cannot start another. A gym that is not eligible starts locked, on the plans page.
import { addDays, todayIn } from './dates.js';
import { nowIso } from '../db.js';
import { loadGym, saveGym } from '../helpers.js';

export const TRIAL_DAYS = 14;
export const TRIAL_LIMITS = { plans: 10, staff: 5, members: 300 };

export const identityOf = (user) => (user.phone ? `phone:${user.phone}` : `email:${String(user.email ?? '').toLowerCase()}`);

/** The state to put on a gym that has just been created: it works while the owner finishes setup, and the clock has not started. */
export function pendingTrial(today) {
  return {
    subscription: { plan: 'TRIAL', startsAt: today, endsAt: addDays(today, TRIAL_DAYS), limits: TRIAL_LIMITS },
    trial: { status: 'pending' },
  };
}

/**
 * Called when registration and gym setup are complete. Starts the trial once, or marks the gym as not eligible. Calling it again changes nothing.
 * Returns the gym.
 */
export function startTrialIfDue(store, gymId) {
  const gym = loadGym(store, gymId);
  if (gym.trial?.status !== 'pending') return gym; // already started, used up, or an older gym without a trial record
  const owner = store.get('SELECT * FROM users WHERE id = ?', gym.ownerId);
  const identity = owner ? identityOf(owner) : `gym:${gymId}`;
  const today = todayIn(gym.timezone);
  return store.tx(() => {
    const prior = store.get('SELECT * FROM trial_grants WHERE identity = ?', identity);
    if (prior && prior.gym_id !== gymId) {
      // this person already had their trial on another gym: no second one, the gym waits for a plan
      return saveGym(store, gymId, {
        trial: { status: 'unavailable', reason: 'already_used', checkedAt: nowIso() },
        subscription: { plan: 'NONE', startsAt: today, endsAt: addDays(today, -30), limits: TRIAL_LIMITS },
      });
    }
    const endsAt = addDays(today, TRIAL_DAYS);
    if (!prior) store.run('INSERT INTO trial_grants(identity, gym_id, started_at, ends_at) VALUES (?,?,?,?)', identity, gymId, nowIso(), endsAt);
    return saveGym(store, gymId, {
      trial: { status: 'active', startedAt: nowIso(), endsAt },
      subscription: { plan: 'TRIAL', startsAt: today, endsAt, limits: TRIAL_LIMITS },
    });
  });
}
