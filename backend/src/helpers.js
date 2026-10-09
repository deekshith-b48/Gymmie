import { randomInt } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { forbidden, notFound, invalid } from './errors.js';
import { nowIso } from './db.js';
import { todayIn } from './domain/dates.js';

const here = dirname(fileURLToPath(import.meta.url));
/** Recovered from the original APK (assets/feature_flags_data.json). */
export const FEATURE_CATALOG = JSON.parse(readFileSync(resolve(here, 'feature_flags.json'), 'utf8'));

export const PAYMENT_TYPES = ['cash', 'upi', 'creditCard', 'debitCard', 'netBanking', 'cheque', 'wallet', 'other'];

export const parseGym = (row) => (row ? { ...JSON.parse(row.data), id: row.id, code: row.code, createdAt: row.created_at } : null);

export function loadGym(store, gymId) {
  return parseGym(store.get('SELECT * FROM gyms WHERE id = ?', gymId));
}

export function saveGym(store, gymId, patch) {
  const row = store.get('SELECT * FROM gyms WHERE id = ?', gymId);
  if (!row) throw notFound('Gym not found');
  const { id: _i, code: _c, createdAt: _ca, ...cur } = parseGym(row);
  const next = { ...cur, ...patch };
  store.run('UPDATE gyms SET data = ?, updated_at = ? WHERE id = ?', JSON.stringify(next), nowIso(), gymId);
  return loadGym(store, gymId);
}

export function newGymCode(store) {
  for (let i = 0; i < 50; i++) {
    const code = String(randomInt(100000, 1000000));
    if (!store.get('SELECT 1 FROM gyms WHERE code = ?', code)) return code;
  }
  throw new Error('could not allocate gym code');
}

export function defaultFeatures() {
  const out = {};
  for (const f of FEATURE_CATALOG) out[f.key] = !!f.defaultEnabled;
  return out;
}

export function publicUser(u) {
  return {
    id: u.id, name: u.name, phone: u.phone, email: u.email, language: u.language, timezone: u.timezone,
    phoneVerified: !!u.phone_verified, emailVerified: !!u.email_verified,
    photoUrl: u.photo_file_id ? `/v5/files/${u.photo_file_id}` : null,
  };
}

export function gymBrief(store, g, role, status = 'active') {
  return {
    id: g.id, code: g.code, name: g.name, city: g.city ?? null, logoUrl: g.logoFileId ? `/v5/files/${g.logoFileId}` : null,
    timezone: g.timezone, currencySymbol: g.currencySymbol, role, status,
    subscription: g.subscription ? { plan: g.subscription.plan, status: subscriptionStatus(g, g.timezone), endsAt: g.subscription.endsAt } : null,
  };
}

export function userGyms(store, userId) {
  return store.all(
    `SELECT g.*, gu.role, gu.status FROM gym_users gu JOIN gyms g ON g.id = gu.gym_id
     WHERE gu.user_id = ? AND gu.status IN ('active') ORDER BY gu.created_at`, userId,
  ).map((r) => gymBrief(store, parseGym(r), r.role, r.status));
}

export function subscriptionStatus(gym, tz) {
  const s = gym.subscription;
  if (!s) return 'none';
  return s.endsAt >= todayIn(tz ?? gym.timezone) ? 'active' : 'expired';
}

export function ensureFeature(gym, key) {
  const def = FEATURE_CATALOG.find((f) => f.key === key);
  const on = gym.features?.[key] ?? def?.defaultEnabled ?? false;
  if (!on) throw forbidden('This feature is not included in your current subscription');
}

export const requireFields = (obj, fields) => {
  for (const f of fields) if (obj[f] === undefined || obj[f] === '') throw invalid(`${f} is required`);
};

export const csvEscape = (v) => {
  const s = v === null || v === undefined ? '' : String(v);
  return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};
export const toCsv = (rows, columns) =>
  [columns.map((c) => csvEscape(c.header)).join(','), ...rows.map((r) => columns.map((c) => csvEscape(c.value(r))).join(','))].join('\n');
