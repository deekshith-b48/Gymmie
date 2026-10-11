// What happens when an order is paid: credits are added or the subscription is extended, the platform's GST invoice
// number is assigned, and the referrer is rewarded on a gym's first paid subscription. Safe to call twice for the same
// order (the dev page, the return link and the webhook may all arrive): only the first call changes anything.
import { addDays, todayIn } from './dates.js';
import { addCredits } from './notify.js';
import { CREDIT_PACKS, GST_RATE, SUBSCRIPTION_PLANS } from './catalog.js';
import { loadGym, saveGym } from '../helpers.js';
import { nowIso } from '../db.js';
import { round2 } from './pricing.js';

const PLATFORM = '_platform';

export const REFERRAL_REWARD = { days: 30, credits: 100 };

/** The tax split of a GST-inclusive amount. */
export function gstSplit(amount, rate = GST_RATE) {
  const taxable = round2(amount / (1 + rate / 100));
  return { taxable, gst: round2(amount - taxable), rate };
}

/** Marks [order] paid and delivers it. Returns the order as stored (unchanged if it was already settled). */
export function fulfilOrder(store, gymId, orderId, { paymentId = null, provider = null } = {}) {
  return store.tx(() => {
    const col = store.col(gymId, 'orders');
    const order = col.get(orderId);
    if (!order) return null;
    if (order.status !== 'created') return order; // already paid, failed or cancelled: nothing more to do
    const gym = loadGym(store, gymId);
    const ctx = { store, gymId, gym, col: (n) => store.col(gymId, n) };
    if (order.type === 'credits') {
      const p = CREDIT_PACKS.find((x) => x.id === order.ref);
      if (p) addCredits(ctx, p.credits + p.bonusCredits, `order:${order.id}`);
    } else {
      const plan = SUBSCRIPTION_PLANS.find((x) => x.id === order.ref);
      if (plan) {
        const sub = gym.subscription ?? {};
        const today = todayIn(gym.timezone);
        const base = sub.endsAt && sub.endsAt >= today ? sub.endsAt : today;
        saveGym(store, gymId, { subscription: { ...sub, plan: plan.plan, startsAt: sub.startsAt ?? base, endsAt: addDays(base, plan.durationDays), limits: plan.limits } });
        rewardReferrer(store, gym, order);
      }
    }
    const invoiceNo = `GYM-${new Date().getUTCFullYear()}-${String(store.nextCounter(PLATFORM, 'invoice')).padStart(5, '0')}`;
    return col.update(order.id, {
      status: 'paid', completedAt: nowIso(), invoiceNo, tax: gstSplit(order.amount), paymentId, provider: provider ?? order.provider,
    });
  });
}

/** First paid subscription of a gym that signed up with another gym's code: free days and credits for the referrer, once. */
function rewardReferrer(store, gym, order) {
  if (!gym.referralCode || gym.referralRewarded) return;
  const row = store.get('SELECT id FROM gyms WHERE code = ?', String(gym.referralCode));
  if (!row || row.id === gym.id) return;
  const referrer = loadGym(store, row.id);
  const today = todayIn(referrer.timezone);
  const sub = referrer.subscription ?? null;
  if (sub) {
    const base = sub.endsAt >= today ? sub.endsAt : today;
    saveGym(store, referrer.id, { subscription: { ...sub, endsAt: addDays(base, REFERRAL_REWARD.days) } });
  }
  const rctx = { store, gymId: referrer.id, gym: loadGym(store, referrer.id), col: (n) => store.col(referrer.id, n) };
  addCredits(rctx, REFERRAL_REWARD.credits, `referral:${gym.id}`, 'referral');
  saveGym(store, gym.id, { referralRewarded: true });
}
