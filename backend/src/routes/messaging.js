// Message templates, broadcasts, credits & dev payments, subscription billing, integrations, message history.
import { randomBytes, randomUUID } from 'node:crypto';
import { S, validate } from '../validate.js';
import { ApiError, conflict, forbidden, invalid, notFound } from '../errors.js';
import { created, noContent, raw } from '../http.js';
import { addDays, inRange } from '../domain/dates.js';
import {
  COMMON_VARIABLES, CREDIT_COST, DEFAULT_TEMPLATES, MEMBER_VARIABLES, addCredits, debitCredits, getTemplate, gymVars, renderTemplate,
} from '../domain/notify.js';
import { ensureFeature, loadGym, saveGym, toCsv } from '../helpers.js';
import { listMembers } from './members.js';
import { resolveRange } from './finance.js';
import { round2 } from '../domain/pricing.js';
import { nowIso } from '../db.js';

const MAX_RECIPIENTS = 5000;

// DEV catalogs: the real price list is server-side in the original product and was not recovered.
export const CREDIT_PACKS = [
  { id: 'pack-500', name: 'Starter', credits: 500, bonusCredits: 0, price: 500, currency: 'INR' },
  { id: 'pack-1000', name: 'Growth', credits: 1000, bonusCredits: 100, price: 900, currency: 'INR' },
  { id: 'pack-5000', name: 'Pro', credits: 5000, bonusCredits: 750, price: 4000, currency: 'INR' },
];
export const SUBSCRIPTION_PLANS = [
  { id: 'STARTER_30', plan: 'STARTER', name: 'Starter (monthly)', price: 499, currency: 'INR', durationDays: 30, limits: { plans: 10, staff: 3, members: 150 } },
  { id: 'GROWTH_30', plan: 'GROWTH', name: 'Growth (monthly)', price: 999, currency: 'INR', durationDays: 30, limits: { plans: 30, staff: 10, members: 800 } },
  { id: 'GROWTH_365', plan: 'GROWTH', name: 'Growth (yearly)', price: 9990, currency: 'INR', durationDays: 365, limits: { plans: 30, staff: 10, members: 800 } },
  { id: 'PRO_365', plan: 'PRO', name: 'Pro (yearly)', price: 19990, currency: 'INR', durationDays: 365, limits: { plans: 100, staff: 50, members: 5000 } },
];

const memberVars = (ctx, member) => {
  const cur = ctx.col('memberships').find((m) => m.memberId === member.id).sort((a, b) => b.endDate.localeCompare(a.endDate))[0];
  return { ...gymVars(ctx.gym), memberName: member.name, memberPhone: member.phone, planName: cur?.planName ?? '', endDate: cur?.endDate ?? '' };
};

/** Delivers a (scheduled or immediate) broadcast into the outbox. Credits were reserved when it was created. */
export function deliverBroadcast(ctx, b) {
  const members = new Map(ctx.col('members').all().map((m) => [m.id, m]));
  let sent = 0;
  for (const id of b.recipientIds) {
    const m = members.get(id);
    if (!m) continue;
    ctx.col('outbox').insert({ key: 'BROADCAST', to: m.phone, memberId: m.id, body: renderTemplate(b.body, memberVars(ctx, m)), broadcastId: b.id, channel: 'whatsapp', credits: 0, status: 'recorded' });
    sent++;
  }
  return ctx.col('broadcasts').update(b.id, { status: 'sent', sentAt: nowIso(), deliveredCount: sent });
}

export function processDueBroadcasts(store, now = new Date()) {
  const rows = store.all(
    `SELECT DISTINCT gym_id FROM docs WHERE collection = 'broadcasts' AND deleted_at IS NULL AND json_extract(data, '$.status') = 'scheduled' AND json_extract(data, '$.scheduleAt') <= ?`,
    now.toISOString());
  let n = 0;
  for (const { gym_id } of rows) {
    const gym = loadGym(store, gym_id);
    const ctx = { store, gymId: gym_id, gym, col: (name) => store.col(gym_id, name), user: { id: null } };
    for (const b of ctx.col('broadcasts').find((x) => x.status === 'scheduled' && x.scheduleAt <= now.toISOString())) { deliverBroadcast(ctx, b); n++; }
  }
  return n;
}

export function registerMessagingRoutes({ router, store, config }) {
  const needWhatsapp = (ctx) => { ensureFeature(ctx.gym, 'WHATSAPP_INTEGRATION'); };
  const credits = (ctx) => ({ balance: ctx.gym.creditBalance ?? 0, costPerMessage: CREDIT_COST });

  // ---- notification templates (automation) ---------------------------------------------------------------------
  router.get('/v5/message-templates/notifications', { perm: 'broadcasts.read' }, (ctx) => Object.keys(DEFAULT_TEMPLATES).map((k) => getTemplate(ctx, k)));
  router.get('/v5/message-templates/entity/:entity', { perm: 'broadcasts.read' }, (ctx) => {
    const e = ctx.params.entity;
    if (!['member', 'lead', 'broadcast', 'expense', 'sale'].includes(e)) throw notFound('Unknown template entity');
    return { entity: e, commonVariables: COMMON_VARIABLES, memberVariables: e === 'lead' ? ['memberName', 'memberPhone'] : MEMBER_VARIABLES };
  });
  router.patch('/v5/message-templates/notifications/:key', { perm: 'broadcasts.write' }, (ctx) => {
    const t = getTemplate(ctx, ctx.params.key);
    if (!t) throw notFound('Template not found');
    const b = validate({ body: S.str({ min: 5, max: 1000 }), auto: S.bool() }, ctx.body, { partial: true });
    for (const v of (b.body ?? '').matchAll(/\{\{\s*([A-Za-z0-9_]+)\s*\}\}/g)) {
      if (![...COMMON_VARIABLES, ...MEMBER_VARIABLES].includes(v[1])) throw invalid(`Unknown variable {{${v[1]}}}`);
    }
    const cur = ctx.col('messageTemplates').findOne((x) => x.key === t.key);
    if (cur) ctx.col('messageTemplates').update(cur.id, b);
    else ctx.col('messageTemplates').insert({ key: t.key, ...b });
    return getTemplate(ctx, t.key);
  });
  router.post('/v5/message-templates/notifications/:key/reset', { perm: 'broadcasts.write' }, (ctx) => {
    const t = getTemplate(ctx, ctx.params.key);
    if (!t) throw notFound('Template not found');
    const cur = ctx.col('messageTemplates').findOne((x) => x.key === t.key);
    if (cur) ctx.col('messageTemplates').remove(cur.id);
    return getTemplate(ctx, t.key);
  });
  router.post('/v5/message-templates/preview', { perm: 'broadcasts.read' }, (ctx) => {
    const b = validate({ body: S.str({ required: true, max: 1000 }), memberId: S.str() }, ctx.body);
    const m = b.memberId ? ctx.col('members').get(b.memberId) : null;
    const vars = m ? memberVars(ctx, m) : { ...gymVars(ctx.gym), memberName: 'Alex', memberPhone: '+919000000000', planName: 'Monthly', endDate: addDays(ctx.today(), 20) };
    return { text: renderTemplate(b.body, vars) };
  });

  // Custom broadcast templates ("Create Template", "Manage Your Templates").
  const TPL = { title: S.str({ required: true, min: 1, max: 60 }), body: S.str({ required: true, min: 5, max: 1000 }) };
  router.get('/v5/broadcasts/templates', { perm: 'broadcasts.read' }, (ctx) => ctx.col('broadcastTemplates').all());
  router.post('/v5/broadcasts/templates', { perm: 'broadcasts.write' }, (ctx) => created(ctx.col('broadcastTemplates').insert(validate(TPL, ctx.body))));
  router.patch('/v5/broadcasts/templates/:id', { perm: 'broadcasts.write' }, (ctx) => {
    const t = ctx.col('broadcastTemplates').get(ctx.params.id);
    if (!t) throw notFound('Template not found');
    return ctx.col('broadcastTemplates').update(t.id, validate(TPL, ctx.body, { partial: true }));
  });
  router.delete('/v5/broadcasts/templates/:id', { perm: 'broadcasts.write' }, (ctx) => {
    if (!ctx.col('broadcastTemplates').remove(ctx.params.id)) throw notFound('Template not found');
    return noContent();
  });

  // ---- broadcasts ----------------------------------------------------------------------------------------------------
  const FILTER = S.obj({
    status: S.str({ max: 40 }), labelIds: S.str({ max: 500 }), planId: S.str({ max: 64 }), trainerId: S.str({ max: 64 }), days: S.str({ max: 5 }), gender: S.str({ max: 10 }),
  });
  const BC = {
    name: S.str({ required: true, min: 1, max: 80 }), body: S.str({ required: true, min: 1, max: 1000 }), templateId: S.str({ max: 64 }),
    filter: FILTER, excludeMemberIds: S.list(S.str({ max: 64 }), { max: 5000 }), scheduleAt: S.dt(),
  };

  function resolveRecipients(ctx, filter = {}, exclude = []) {
    const { filtered } = listMembers({ ...ctx, query: { ...filter, sort: 'nameAsc' } });
    const ex = new Set(exclude);
    return filtered.filter((m) => !ex.has(m.id) && !m.blocked);
  }

  router.post('/v5/broadcasts/recipients/preview', { perm: 'broadcasts.read' }, (ctx) => {
    const b = validate({ filter: FILTER, excludeMemberIds: S.list(S.str({ max: 64 }), { max: 5000 }) }, ctx.body);
    const r = resolveRecipients(ctx, b.filter, b.excludeMemberIds);
    return { count: r.length, creditsRequired: r.length * CREDIT_COST, balance: ctx.gym.creditBalance ?? 0, tooMany: r.length > MAX_RECIPIENTS, sample: r.slice(0, 5).map((m) => ({ id: m.id, name: m.name, phone: m.phone })) };
  });

  const bcView = (b) => ({ ...b, recipientIds: undefined });
  router.get('/v5/broadcasts', { perm: 'broadcasts.read' }, (ctx) => ctx.col('broadcasts').all().map(bcView).sort((a, b) => b.createdAt.localeCompare(a.createdAt)));
  router.get('/v5/broadcasts/:id', { perm: 'broadcasts.read' }, (ctx) => {
    const b = ctx.col('broadcasts').get(ctx.params.id);
    if (!b) throw notFound('Broadcast not found');
    const rows = ctx.col('outbox').find((o) => o.broadcastId === b.id);
    const members = new Map(ctx.col('members').all().map((m) => [m.id, m]));
    return {
      ...bcView(b), delivered: rows.filter((r) => r.status !== 'failed').length, failed: rows.filter((r) => r.status === 'failed').length,
      recipients: b.recipientIds.map((id) => ({ id, name: members.get(id)?.name ?? '(removed)', phone: members.get(id)?.phone ?? null })),
    };
  });

  router.post('/v5/broadcasts', { perm: 'broadcasts.write' }, (ctx) => {
    needWhatsapp(ctx);
    const b = validate(BC, ctx.body);
    if (b.scheduleAt && Date.parse(b.scheduleAt) < Date.now() - 60_000) throw invalid('Selected date and time cannot be in the past.');
    const recipients = resolveRecipients(ctx, b.filter, b.excludeMemberIds);
    if (recipients.length === 0) throw invalid('Please select at least one recipient');
    if (recipients.length > MAX_RECIPIENTS) throw invalid('A broadcast can include at most 5,000 recipients. Narrow your filters or exclude fewer members.');
    const cost = recipients.length * CREDIT_COST;
    const doc = store.tx(() => {
      if (!debitCredits(ctx, cost, 'broadcast')) throw new ApiError(402, 'INSUFFICIENT_CREDITS', "You don't have enough credits. Please recharge.", { required: cost, balance: ctx.gym.creditBalance ?? 0 });
      const bc = ctx.col('broadcasts').insert({
        name: b.name, body: b.body, templateId: b.templateId ?? null, filter: b.filter ?? {}, excludeMemberIds: b.excludeMemberIds ?? [], recipientIds: recipients.map((m) => m.id),
        recipientCount: recipients.length, creditsReserved: cost, scheduleAt: b.scheduleAt ?? null, status: 'scheduled', createdById: ctx.user.id,
      });
      return bc;
    });
    const out = !b.scheduleAt || Date.parse(b.scheduleAt) <= Date.now() ? deliverBroadcast(ctx, doc) : doc;
    return created(bcView(out));
  });

  router.patch('/v5/broadcasts/:id', { perm: 'broadcasts.write' }, (ctx) => {
    const cur = ctx.col('broadcasts').get(ctx.params.id);
    if (!cur) throw notFound('Broadcast not found');
    if (cur.status !== 'scheduled') throw conflict('Only a scheduled broadcast can be updated');
    const b = validate(BC, ctx.body, { partial: true });
    const filter = b.filter ?? cur.filter;
    const exclude = b.excludeMemberIds ?? cur.excludeMemberIds;
    const recipients = resolveRecipients(ctx, filter, exclude);
    if (recipients.length === 0) throw invalid('Please select at least one recipient');
    if (recipients.length > MAX_RECIPIENTS) throw invalid('A broadcast can include at most 5,000 recipients. Narrow your filters or exclude fewer members.');
    const newCost = recipients.length * CREDIT_COST;
    const diff = newCost - cur.creditsReserved;
    store.tx(() => {
      if (diff > 0 && !debitCredits(ctx, diff, 'broadcast-update')) throw new ApiError(402, 'INSUFFICIENT_CREDITS', "You don't have enough credits. Please recharge.", { required: diff, balance: ctx.gym.creditBalance ?? 0 });
      if (diff < 0) addCredits(ctx, -diff, 'broadcast-update', 'refund');
      ctx.col('broadcasts').update(cur.id, { ...b, filter, excludeMemberIds: exclude, recipientIds: recipients.map((m) => m.id), recipientCount: recipients.length, creditsReserved: newCost });
    });
    return bcView(ctx.col('broadcasts').get(cur.id));
  });

  router.post('/v5/broadcasts/:id/cancel', { perm: 'broadcasts.write' }, (ctx) => {
    const cur = ctx.col('broadcasts').get(ctx.params.id);
    if (!cur) throw notFound('Broadcast not found');
    if (cur.status !== 'scheduled') throw conflict('Only a scheduled broadcast can be cancelled');
    store.tx(() => { addCredits(ctx, cur.creditsReserved, `broadcast-cancel:${cur.id}`, 'refund'); ctx.col('broadcasts').update(cur.id, { status: 'cancelled', cancelledAt: nowIso() }); });
    return bcView(ctx.col('broadcasts').get(cur.id));
  });

  // ---- credits ---------------------------------------------------------------------------------------------------------
  router.get('/v5/credit-packs', { perm: 'broadcasts.read' }, () => CREDIT_PACKS.map((p) => ({ ...p, catalog: 'dev' })));
  router.get('/v5/credits/stats', { perm: 'broadcasts.read' }, (ctx) => creditStats(ctx));
  function creditStats(ctx) {
    const led = ctx.col('creditLedger').all();
    const monthPrefix = ctx.today().slice(0, 7);
    const m = led.filter((l) => l.createdAt.startsWith(monthPrefix));
    return {
      ...credits(ctx), usedThisMonth: -m.filter((l) => l.type === 'usage').reduce((s, l) => s + l.credits, 0),
      rechargedThisMonth: m.filter((l) => l.type === 'recharge').reduce((s, l) => s + l.credits, 0), lowBalance: (ctx.gym.creditBalance ?? 0) < 50,
    };
  }
  const ledgerList = (ctx) => ctx.col('creditLedger').all().filter((l) => !ctx.query.type || l.type === ctx.query.type).filter((l) => inRange(l.createdAt.slice(0, 10), resolveRange(ctx)))
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  router.get('/v5/credits/transactions', { perm: 'broadcasts.read' }, (ctx) => {
    const all = ledgerList(ctx);
    const page = Math.max(1, parseInt(ctx.query.page ?? '1', 10) || 1);
    const limit = Math.min(200, Math.max(1, parseInt(ctx.query.limit ?? '30', 10) || 30));
    return { __envelope: true, status: 200, body: { data: all.slice((page - 1) * limit, page * limit), meta: { page, limit, total: all.length, totalPages: Math.max(1, Math.ceil(all.length / limit)) } } };
  });
  router.get('/v5/credits/transactions/export', { perm: 'broadcasts.read' }, (ctx) => raw(200, 'text/csv; charset=utf-8', toCsv(ledgerList(ctx), [
    { header: 'Date', value: (l) => l.createdAt }, { header: 'Type', value: (l) => l.type }, { header: 'Credits', value: (l) => l.credits },
    { header: 'Balance After', value: (l) => l.balanceAfter }, { header: 'Reference', value: (l) => l.reference },
  ]), { 'content-disposition': `attachment; filename="credits-${ctx.today()}.csv"` }));

  // ---- payment orders (DEV provider) ------------------------------------------------------------------------------------
  const baseUrl = (ctx) => config.publicBaseUrl || `http://${ctx.req.headers.host}`;
  function createOrder(ctx, { type, amount, ref, description }) {
    if (!config.devPayments) throw new ApiError(501, 'PAYMENT_PROVIDER_NOT_CONFIGURED', 'No payment provider is configured on this server');
    const token = randomBytes(24).toString('base64url');
    const order = ctx.col('orders').insert({ type, amount, currency: 'INR', ref, description, token, status: 'created', createdById: ctx.user.id, provider: 'dev' });
    return { ...order, token: undefined, paymentUrl: `${baseUrl(ctx)}/dev/pay/${token}` };
  }
  router.post('/v5/payments/orders/credit-packs', { perm: 'broadcasts.write' }, (ctx) => {
    const b = validate({ packId: S.str({ required: true }) }, ctx.body);
    const pack = CREDIT_PACKS.find((p) => p.id === b.packId);
    if (!pack) throw invalid('Unknown credit pack');
    return created(createOrder(ctx, { type: 'credits', amount: pack.price, ref: pack.id, description: `${pack.credits + pack.bonusCredits} WhatsApp credits` }));
  });
  router.post('/v5/payments/orders/renewal-link', { perm: 'settings.write' }, (ctx) => {
    const b = validate({ planId: S.str({ required: true }) }, ctx.body);
    const plan = SUBSCRIPTION_PLANS.find((p) => p.id === b.planId);
    if (!plan) throw invalid('Unknown subscription plan');
    return created(createOrder(ctx, { type: 'subscription', amount: plan.price, ref: plan.id, description: `${plan.name} subscription` }));
  });
  router.get('/v5/payments/orders/:id', { perm: 'broadcasts.read' }, (ctx) => {
    const o = ctx.col('orders').get(ctx.params.id);
    if (!o) throw notFound('Order not found');
    return { ...o, token: undefined };
  });

  const orderByToken = (token) => {
    const row = store.get(`SELECT id, gym_id FROM docs WHERE collection = 'orders' AND deleted_at IS NULL AND json_extract(data, '$.token') = ?`, String(token));
    if (!row) throw notFound('Payment link not found');
    const gym = loadGym(store, row.gym_id);
    const col = (n) => store.col(row.gym_id, n);
    return { ctx: { store, gymId: row.gym_id, gym, col, user: { id: null } }, order: col('orders').get(row.id) };
  };
  const html = (body, status = 200) => raw(status, 'text/html; charset=utf-8', `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>DGymBook dev payment</title><style>body{font-family:system-ui;margin:0;padding:24px;background:#f8f9fc;color:#061750}.c{max-width:420px;margin:0 auto;background:#fff;border:1px solid #e5e9f2;border-radius:12px;padding:24px}button{width:100%;padding:14px;border-radius:10px;border:0;font-size:16px;margin-top:12px}.p{background:#061750;color:#fff}.s{background:#f1f4f9}small{color:#667}</style><div class="c">${body}</div>`, { 'content-security-policy': "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'" });
  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);

  router.get('/dev/pay/:token', { auth: 'none' }, (ctx) => {
    if (!config.devPayments) throw notFound('Not found');
    const { order } = orderByToken(ctx.params.token);
    if (order.status !== 'created') return html(`<h2>Order ${esc(order.status)}</h2><p>This payment link has already been used.</p>`);
    return html(`<small>DEVELOPMENT PAYMENT PROVIDER — no real money moves</small><h2>${esc(order.description)}</h2><p style="font-size:28px;margin:8px 0">₹${esc(order.amount)}</p>
      <form method="post" action="/dev/pay/${esc(ctx.params.token)}/complete"><input type="hidden" name="result" value="success"><button class="p">Pay (simulate success)</button></form>
      <form method="post" action="/dev/pay/${esc(ctx.params.token)}/complete"><input type="hidden" name="result" value="failed"><button class="s">Simulate failure</button></form>`);
  });
  router.post('/dev/pay/:token/complete', { auth: 'none' }, (ctx) => {
    if (!config.devPayments) throw notFound('Not found');
    const { ctx: g, order } = orderByToken(ctx.params.token);
    const result = ctx.body.result === 'success' ? 'success' : 'failed';
    if (order.status === 'created') {
      store.tx(() => {
        if (result === 'success') {
          if (order.type === 'credits') { const p = CREDIT_PACKS.find((x) => x.id === order.ref); addCredits(g, p.credits + p.bonusCredits, `order:${order.id}`); }
          else {
            const plan = SUBSCRIPTION_PLANS.find((x) => x.id === order.ref);
            const sub = g.gym.subscription ?? {};
            const base = sub.endsAt && sub.endsAt >= new Date().toISOString().slice(0, 10) ? sub.endsAt : new Date().toISOString().slice(0, 10);
            saveGym(store, g.gymId, { subscription: { ...sub, plan: plan.plan, startsAt: sub.startsAt ?? base, endsAt: addDays(base, plan.durationDays), limits: plan.limits } });
          }
        }
        g.col('orders').update(order.id, { status: result === 'success' ? 'paid' : 'failed', completedAt: nowIso() });
      });
    }
    const status = order.status === 'created' ? result : order.status === 'paid' ? 'success' : 'failed';
    const link = `dgymbook://payments?status=${status}&orderId=${encodeURIComponent(order.id)}&type=${order.type}`;
    return html(`<h2>${status === 'success' ? 'Payment successful' : 'Payment failed'}</h2><p>Return to the DGymBook Partner app.</p><p><a href="${esc(link)}">Open the app</a></p><meta http-equiv="refresh" content="1;url=${esc(link)}">`);
  });

  // ---- subscription billing ----------------------------------------------------------------------------------------------
  router.get('/v5/billings/subscriptions', { perm: 'settings.read' }, (ctx) => ({ current: ctx.gym.subscription, plans: SUBSCRIPTION_PLANS.map((p) => ({ ...p, catalog: 'dev' })) }));
  router.get('/v5/billings/subscriptions/usage', { perm: 'settings.read' }, (ctx) => {
    const lim = ctx.gym.subscription?.limits ?? {};
    const staff = ctx.store.get('SELECT COUNT(*) c FROM gym_users WHERE gym_id = ?', ctx.gymId).c;
    return {
      plans: { used: ctx.col('plans').count((p) => p.active !== false), limit: lim.plans ?? null },
      staff: { used: staff, limit: lim.staff ?? null }, members: { used: ctx.col('members').count(), limit: lim.members ?? null },
    };
  });
  router.get('/v5/billings/subscriptions/history', { perm: 'settings.read' }, (ctx) =>
    ctx.col('orders').find((o) => o.type === 'subscription').map((o) => ({ ...o, token: undefined })).sort((a, b) => b.createdAt.localeCompare(a.createdAt)));

  // ---- integrations ----------------------------------------------------------------------------------------------------------
  router.get('/v5/integrations', { perm: 'settings.read' }, (ctx) => ([
    { key: 'whatsapp', name: 'WhatsApp Integration', enabled: !!ctx.gym.whatsapp?.enabled, status: ctx.gym.whatsapp?.status ?? 'disconnected', provider: 'dev-outbox', available: !!ctx.gym.features?.WHATSAPP_INTEGRATION },
    { key: 'biometrics', name: 'Biometric devices', enabled: ctx.col('devices').count() > 0, status: ctx.col('devices').count((d) => d.status === 'connected') > 0 ? 'connected' : 'disconnected', provider: 'device-callback', available: true },
  ]));
  router.post('/v5/integrations/whatsapp/enable', { perm: 'settings.write' }, (ctx) => {
    needWhatsapp(ctx);
    return saveGym(store, ctx.gymId, { whatsapp: { enabled: true, status: 'connected', provider: 'dev-outbox', enabledAt: nowIso() } }).whatsapp;
  });
  router.post('/v5/integrations/whatsapp/disable', { perm: 'settings.write' }, (ctx) => saveGym(store, ctx.gymId, { whatsapp: { ...ctx.gym.whatsapp, enabled: false, status: 'disconnected' } }).whatsapp);

  // ---- message history ------------------------------------------------------------------------------------------------------------
  const outboxList = (ctx) => {
    const range = resolveRange(ctx);
    const members = new Map(ctx.col('members').all().map((m) => [m.id, m]));
    return ctx.col('outbox').all().filter((o) => inRange(o.createdAt.slice(0, 10), range)).filter((o) => !ctx.query.memberId || o.memberId === ctx.query.memberId)
      .filter((o) => !ctx.query.status || o.status === ctx.query.status).map((o) => ({ ...o, memberName: members.get(o.memberId)?.name ?? null }))
      .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  };
  router.get('/v5/messages', { perm: 'broadcasts.read' }, (ctx) => {
    const all = outboxList(ctx);
    const page = Math.max(1, parseInt(ctx.query.page ?? '1', 10) || 1);
    const limit = Math.min(200, Math.max(1, parseInt(ctx.query.limit ?? '30', 10) || 30));
    return { __envelope: true, status: 200, body: { data: all.slice((page - 1) * limit, page * limit), meta: { page, limit, total: all.length, totalPages: Math.max(1, Math.ceil(all.length / limit)), delivery: 'dev-outbox' } } };
  });
  router.get('/v5/messages/export', { perm: 'broadcasts.read' }, (ctx) => raw(200, 'text/csv; charset=utf-8', toCsv(outboxList(ctx), [
    { header: 'Date', value: (o) => o.createdAt }, { header: 'To', value: (o) => o.to }, { header: 'Member', value: (o) => o.memberName }, { header: 'Type', value: (o) => o.key },
    { header: 'Status', value: (o) => o.status }, { header: 'Credits', value: (o) => o.credits }, { header: 'Message', value: (o) => o.body },
  ]), { 'content-disposition': `attachment; filename="messages-${ctx.today()}.csv"` }));

  // Manual one-off message ("Send Hello Message", "Send Balance Reminder"): rendered text + optional credit-metered recording.
  router.post('/v5/messages/send', { perm: 'members.write' }, (ctx) => {
    needWhatsapp(ctx);
    if (!ctx.gym.whatsapp?.enabled) throw invalid('You have not set up WhatsApp integration yet.');
    const b = validate({ memberId: S.str({ required: true }), body: S.str({ required: true, min: 1, max: 1000 }), templateKey: S.str({ max: 60 }) }, ctx.body);
    const m = ctx.col('members').get(b.memberId);
    if (!m) throw notFound('Member not found');
    if (!debitCredits(ctx, CREDIT_COST, 'manual-message')) throw new ApiError(402, 'INSUFFICIENT_CREDITS', "You don't have enough credits. Please recharge.");
    return created(ctx.col('outbox').insert({ key: b.templateKey ?? 'MANUAL', to: m.phone, memberId: m.id, body: renderTemplate(b.body, memberVars(ctx, m)), channel: 'whatsapp', credits: CREDIT_COST, status: 'recorded' }));
  });
}
