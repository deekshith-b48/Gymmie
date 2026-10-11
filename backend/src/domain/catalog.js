// What Gymmie sells to gyms: subscription plans and message-credit packs. Prices are GST-inclusive rupees.
// The defaults below are a starting ladder; set PRICING_FILE to a JSON file { plans: [...], creditPacks: [...] } to change
// them without a code change. Plans carry the limits the server enforces (see domain/billing.js for the feature sets).
import { readFileSync } from 'node:fs';

export const DEFAULT_CREDIT_PACKS = [
  { id: 'pack-500', name: 'Starter', credits: 500, bonusCredits: 0, price: 500, currency: 'INR' },
  { id: 'pack-1000', name: 'Growth', credits: 1000, bonusCredits: 100, price: 900, currency: 'INR' },
  { id: 'pack-5000', name: 'Pro', credits: 5000, bonusCredits: 750, price: 4000, currency: 'INR' },
];

export const DEFAULT_PLANS = [
  { id: 'STARTER_30', plan: 'STARTER', name: 'Starter (monthly)', price: 499, currency: 'INR', durationDays: 30, limits: { plans: 10, staff: 3, members: 150 } },
  { id: 'GROWTH_30', plan: 'GROWTH', name: 'Growth (monthly)', price: 999, currency: 'INR', durationDays: 30, limits: { plans: 30, staff: 10, members: 800 } },
  { id: 'GROWTH_365', plan: 'GROWTH', name: 'Growth (yearly)', price: 9990, currency: 'INR', durationDays: 365, limits: { plans: 30, staff: 10, members: 800 } },
  { id: 'PRO_30', plan: 'PRO', name: 'Pro (monthly)', price: 1999, currency: 'INR', durationDays: 30, limits: { plans: 100, staff: 50, members: 5000 } },
  { id: 'PRO_365', plan: 'PRO', name: 'Pro (yearly)', price: 19990, currency: 'INR', durationDays: 365, limits: { plans: 100, staff: 50, members: 5000 } },
];

/** GST on Gymmie's own invoices (SaaS services). Prices above include it. */
export const GST_RATE = 18;

export const CREDIT_PACKS = [...DEFAULT_CREDIT_PACKS];
export const SUBSCRIPTION_PLANS = [...DEFAULT_PLANS];

/** Replaces the catalogue in place from a pricing file (called once at start-up). */
export function loadPricing(file) {
  if (!file) return;
  const j = JSON.parse(readFileSync(file, 'utf8'));
  if (Array.isArray(j.plans) && j.plans.length) SUBSCRIPTION_PLANS.splice(0, SUBSCRIPTION_PLANS.length, ...j.plans);
  if (Array.isArray(j.creditPacks) && j.creditPacks.length) CREDIT_PACKS.splice(0, CREDIT_PACKS.length, ...j.creditPacks);
}

export const planRankOf = (plan) => ({ STARTER: 1, GROWTH: 2, PRO: 3 })[plan] ?? 0;
