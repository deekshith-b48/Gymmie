// Gym profile, labels (tags), tax, payment methods, feature switches, preferences, portal QR.
import { S, validate } from '../validate.js';
import { conflict, forbidden, invalid, notFound } from '../errors.js';
import { created, noContent } from '../http.js';
import { paymentRequired } from '../errors.js';
import { planAllows, requiredPlanFor } from '../domain/billing.js';
import { FEATURE_CATALOG, PAYMENT_TYPES, gymBrief, loadGym, saveGym, userGyms, subscriptionStatus } from '../helpers.js';
import { createGym, storeFile } from './auth.js';
import { COUNTRIES } from './config.js';

const UPI_RE = /^[A-Za-z0-9._-]{2,256}@[A-Za-z]{2,64}$/;

export function gymProfile(store, g, role) {
  return {
    id: g.id, code: g.code, name: g.name, address: g.address, city: g.city, state: g.state, pincode: g.pincode, country: g.country,
    phone: g.phone, email: g.email, timezone: g.timezone, currencyCode: g.currencyCode, currencySymbol: g.currencySymbol,
    upiId: g.upiId ?? null, logoUrl: g.logoFileId ? `/v5/files/${g.logoFileId}` : null,
    preferences: g.preferences, paymentMethods: g.paymentMethods, features: g.features, role,
    onboardingCompleted: !!g.onboardingCompleted,
    subscription: g.subscription ? { ...g.subscription, status: subscriptionStatus(g) } : null,
    trial: g.trial ? { status: g.trial.status, startedAt: g.trial.startedAt ?? null, endsAt: g.trial.endsAt ?? null } : null,
    paymentSetup: g.paymentSetup?.status ?? 'none',
    whatsapp: g.whatsapp, creditBalance: g.creditBalance ?? 0,
  };
}

export function registerGymRoutes({ router, store }) {
  // ---- list / create / read ---------------------------------------------------------------
  router.get('/v5/gyms', { auth: 'user' }, (ctx) => userGyms(store, ctx.user.id));

  router.post('/v5/gyms', { auth: 'user' }, (ctx) => {
    const owns = store.get("SELECT 1 FROM gym_users WHERE user_id = ? AND role = 'owner' LIMIT 1", ctx.user.id);
    if (!owns) throw forbidden('Only gym owners can add another gym');
    const b = validate({
      name: S.str({ required: true, min: 2, max: 80 }), address: S.str({ required: true, min: 5, max: 250 }), pincode: S.str({ max: 10 }),
      city: S.str({ max: 80 }), state: S.str({ max: 80 }), country: S.str({ default: 'IN', max: 2 }), phone: S.phone(), email: S.email(), timezone: S.str({ max: 64 }),
    }, ctx.body);
    const country = COUNTRIES.find((c) => c.code === b.country.toUpperCase()) ?? COUNTRIES[0];
    return created(gymBrief(store, createGym(store, ctx.user, { ...b, country: country.code }, country), 'owner'));
  });

  const readGym = (ctx) => {
    if (ctx.params.id !== ctx.gymId) throw forbidden('You do not have access to this gym');
    return gymProfile(store, ctx.gym, ctx.role);
  };
  router.get('/v5/gyms/:id', { auth: 'gym', perm: 'settings.read' }, readGym);
  router.get('/v4/gyms/:id', { auth: 'gym', perm: 'settings.read' }, readGym);
  // The current gym (convenience for clients that already send x-gym-id).
  router.get('/v5/gyms/current', { auth: 'gym' }, (ctx) => gymProfile(store, ctx.gym, ctx.role));

  router.patch('/v5/gyms/:id', { auth: 'gym', perm: 'settings.write' }, (ctx) => {
    if (ctx.params.id !== ctx.gymId) throw forbidden('You do not have access to this gym');
    const b = validate({
      name: S.str({ min: 2, max: 80 }), address: S.str({ min: 5, max: 250 }), pincode: S.str({ max: 10 }), city: S.str({ max: 80 }),
      state: S.str({ max: 80 }), phone: S.phone(), email: S.email(), timezone: S.str({ max: 64 }),
      upiId: S.str({ max: 100 }, ), logo: S.obj({ data: S.str({ required: true, max: 8_000_000 }), contentType: S.str({ max: 60 }) }),
    }, ctx.body, { partial: true });
    if (b.name !== undefined && b.name !== ctx.gym.name) throw forbidden('Please contact support to change your gym name');
    if (b.upiId !== undefined && b.upiId !== '' && !UPI_RE.test(b.upiId)) throw invalid('UPI ID or VPA (e.g. merchant@bank)');
    if (b.timezone) { try { new Intl.DateTimeFormat('en', { timeZone: b.timezone }); } catch { throw invalid('Unknown time zone'); } }
    const patch = { ...b };
    delete patch.name; delete patch.logo;
    if (b.upiId === '') patch.upiId = null;
    if (b.logo) {
      const f = storeFile(store, { gymId: ctx.gymId, ownerId: ctx.user.id, data: b.logo.data, declared: b.logo.contentType });
      if (!f.mime.startsWith('image/')) throw invalid('Gym logo must be an image');
      patch.logoFileId = f.id;
    }
    return gymProfile(store, saveGym(store, ctx.gymId, patch), ctx.role);
  });

  // ---- labels (tags) ----------------------------------------------------------------------
  const TAG = { name: S.str({ required: true, min: 1, max: 40 }), color: S.str({ pattern: /^#[0-9A-Fa-f]{6}$/, default: '#061750' }), scope: S.oneOf(['member', 'lead', 'expense'], { default: 'member' }) };
  router.get('/v5/gyms/tags', { perm: 'members.read' }, (ctx) => {
    const scope = ctx.query.scope;
    return ctx.col('tags').find((t) => !scope || t.scope === scope).map((t) => ({ ...t, memberCount: ctx.col('members').count((m) => m.labelIds?.includes(t.id)) }));
  });
  router.post('/v5/gyms/tags', { perm: 'members.write' }, (ctx) => {
    const b = validate(TAG, ctx.body);
    if (!b.name) throw invalid('Label name is empty');
    if (ctx.col('tags').findOne((t) => t.scope === b.scope && t.name.toLowerCase() === b.name.toLowerCase())) throw conflict('A label with this name already exists');
    return created(ctx.col('tags').insert(b));
  });
  router.patch('/v5/gyms/tags/:id', { perm: 'members.write' }, (ctx) => {
    const t = ctx.col('tags').get(ctx.params.id);
    if (!t) throw notFound('Label not found');
    const b = validate(TAG, ctx.body, { partial: true });
    delete b.scope;
    if (b.name && ctx.col('tags').findOne((x) => x.id !== t.id && x.scope === t.scope && x.name.toLowerCase() === b.name.toLowerCase())) throw conflict('A label with this name already exists');
    return ctx.col('tags').update(t.id, b);
  });
  router.delete('/v5/gyms/tags/:id', { perm: 'members.write' }, (ctx) => {
    if (!ctx.col('tags').remove(ctx.params.id)) throw notFound('Label not found');
    return noContent();
  });

  // ---- tax -------------------------------------------------------------------------------------
  const TAXSCHEMA = {
    name: S.str({ required: true, min: 1, max: 40 }), rate: S.num({ required: true, min: 0, max: 100 }),
    isIncluded: S.bool({ default: false }), taxNumber: S.str({ max: 30 }), isDefault: S.bool({ default: false }),
  };
  const normaliseDefault = (ctx, id) => {
    for (const t of ctx.col('taxes').find((x) => x.id !== id && x.isDefault)) ctx.col('taxes').update(t.id, { isDefault: false });
  };
  router.get('/v5/gyms/tax', { perm: 'settings.read' }, (ctx) => ctx.col('taxes').all());
  router.post('/v5/gyms/tax', { perm: 'settings.write' }, (ctx) => {
    const b = validate(TAXSCHEMA, ctx.body);
    const existing = ctx.col('taxes').all();
    if (existing.length === 0) b.isDefault = true;
    const doc = ctx.col('taxes').insert(b);
    if (doc.isDefault) normaliseDefault(ctx, doc.id);
    return created(doc);
  });
  router.patch('/v5/gyms/tax/:id', { perm: 'settings.write' }, (ctx) => {
    const t = ctx.col('taxes').get(ctx.params.id);
    if (!t) throw notFound('Tax configuration not found');
    const b = validate(TAXSCHEMA, ctx.body, { partial: true });
    const doc = ctx.col('taxes').update(t.id, b);
    if (b.isDefault) normaliseDefault(ctx, t.id);
    return doc;
  });
  router.delete('/v5/gyms/tax/:id', { perm: 'settings.write' }, (ctx) => {
    const t = ctx.col('taxes').get(ctx.params.id);
    if (!t) throw notFound('Tax configuration not found');
    ctx.col('taxes').remove(t.id);
    const rest = ctx.col('taxes').all();
    if (t.isDefault && rest.length) ctx.col('taxes').update(rest[0].id, { isDefault: true });
    return noContent();
  });

  // ---- payment methods ---------------------------------------------------------------------------
  router.get('/v5/gyms/payment-methods', { perm: 'finance.read' }, (ctx) => ({ available: PAYMENT_TYPES, ...ctx.gym.paymentMethods }));
  router.put('/v5/gyms/payment-methods', { perm: 'settings.write' }, (ctx) => {
    const b = validate({ active: S.list(S.oneOf(PAYMENT_TYPES), { required: true }), default: S.oneOf(PAYMENT_TYPES, { required: true }) }, ctx.body);
    const active = [...new Set(b.active)];
    if (active.length === 0) throw invalid('Please select at least one payment method');
    if (!active.includes(b.default)) throw invalid('Please select a default payment method from selected methods');
    saveGym(store, ctx.gymId, { paymentMethods: { active, default: b.default } });
    return { available: PAYMENT_TYPES, active, default: b.default };
  });

  // ---- feature switches (catalog recovered from the app) --------------------------------------------
  const featureView = (g) => FEATURE_CATALOG.filter((f) => f.visible).map((f) => ({
    key: f.key, name: f.name, description: f.description, category: f.category,
    enabled: g.features?.[f.key] ?? f.defaultEnabled, adminEnabled: f.adminEnabled,
    requiredPlan: requiredPlanFor(f.key), locked: !planAllows(g, f.key),
  }));
  router.get('/v5/gyms/features', { perm: 'settings.read' }, (ctx) => featureView(ctx.gym));
  router.put('/v5/gyms/features/:key', { perm: 'settings.write' }, (ctx) => {
    const def = FEATURE_CATALOG.find((f) => f.key === ctx.params.key && f.visible);
    if (!def) throw notFound('Unknown feature');
    if (!def.adminEnabled) throw forbidden('This feature is not available for your gym yet');
    const b = validate({ enabled: S.bool({ required: true }) }, ctx.body);
    if (b.enabled && !planAllows(ctx.gym, def.key)) {
      throw paymentRequired('PLAN_UPGRADE_REQUIRED', `${def.name} is part of the ${requiredPlanFor(def.key)} plan. Upgrade in Settings > Subscription.`, { feature: def.key, requiredPlan: requiredPlanFor(def.key) });
    }
    const g = saveGym(store, ctx.gymId, { features: { ...ctx.gym.features, [def.key]: b.enabled } });
    return featureView(g);
  });

  // ---- preferences -------------------------------------------------------------------------------------
  router.get('/v5/gyms/preferences', { perm: 'settings.read' }, (ctx) => ctx.gym.preferences);
  router.patch('/v5/gyms/preferences', { perm: 'settings.write' }, (ctx) => {
    const b = validate({ simpleMemberCard: S.bool(), renewalSound: S.bool() }, ctx.body, { partial: true });
    return saveGym(store, ctx.gymId, { preferences: { ...ctx.gym.preferences, ...b } }).preferences;
  });

  // ---- portal QR (self registration / feedback) ------------------------------------------------------
  const qrView = (g) => ({ gymCode: g.code, version: g.portalQrVersion, payload: `gymmie://portal/${g.code}?v=${g.portalQrVersion}` });
  router.get('/v5/gyms/portal/qr', { perm: 'settings.read' }, (ctx) => qrView(ctx.gym));
  router.post('/v5/gyms/portal/qr/regenerate', { perm: 'settings.write' }, (ctx) => qrView(saveGym(store, ctx.gymId, { portalQrVersion: (ctx.gym.portalQrVersion ?? 1) + 1 })));
}
