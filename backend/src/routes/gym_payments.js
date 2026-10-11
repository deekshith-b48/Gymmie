// A gym collecting its members' fees with the gym's OWN payment-gateway account (Razorpay). This is separate from what the gym pays
// Gymmie (routes/messaging.js, Gymmie's own keys): the money goes to the gym's account, Gymmie only creates the checkout link with the
// gym's sealed keys and records the payment when the gym's own webhook confirms it. Optional: a gym that skips it loses nothing else.
import { randomBytes } from 'node:crypto';
import { S, validate } from '../validate.js';
import { ApiError, conflict, forbidden, invalid, notFound } from '../errors.js';
import { created, noContent } from '../http.js';
import { nowIso } from '../db.js';
import { PaymentGateway, paidEvent } from '../payments.js';
import { seal, unseal } from '../secrets.js';
import { balanceOf } from '../domain/membership.js';
import { round2 } from '../domain/pricing.js';
import { allocateSettlement, openDues } from './finance.js';
import { loadGym, saveGym } from '../helpers.js';
import { todayIn } from '../domain/dates.js';

const PROVIDERS = ['razorpay'];
const METHOD = { upi: 'upi', card: 'creditCard', netbanking: 'netBanking', wallet: 'wallet' };

export function registerGymPaymentRoutes({ router, store, config, limiter }) {
  const account = (gymId) => store.get('SELECT * FROM gym_payment_accounts WHERE gym_id = ?', gymId);
  const baseUrl = (ctx) => config.publicBaseUrl || `http://${ctx.req.headers.host}`;
  const gatewayFor = (row) => new PaymentGateway({
    payments: { keyId: row.key_id, keySecret: unseal(config.jwtSecret, row.secret_sealed), webhookSecret: unseal(config.jwtSecret, row.webhook_secret_sealed), fetchImpl: config.payments?.fetchImpl },
    devPayments: false,
  });
  const view = (ctx) => {
    const row = account(ctx.gymId);
    const status = row ? 'active' : (ctx.gym.paymentSetup?.status ?? 'none');
    return {
      status, provider: row?.provider ?? null, supportedProviders: PROVIDERS,
      keyId: row ? `${row.key_id.slice(0, 9)}…${row.key_id.slice(-3)}` : null, mode: row ? (row.key_id.startsWith('rzp_live') ? 'live' : 'test') : null,
      verifiedAt: row?.verified_at ?? null, decidedAt: ctx.gym.paymentSetup?.at ?? null,
      webhookUrl: `${baseUrl(ctx)}/v5/payments/webhooks/gym/${ctx.gymId}/razorpay`, webhookEvent: 'payment_link.paid',
      canEdit: ctx.role === 'owner',
    };
  };

  router.get('/v5/gyms/payment-setup', { perm: 'settings.read' }, (ctx) => view(ctx));

  router.put('/v5/gyms/payment-setup', { perm: 'settings.write' }, async (ctx) => {
    if (ctx.role !== 'owner') throw forbidden('Only the gym owner can connect a payment account');
    limiter.check(`gpay-setup:${ctx.gymId}`, 10, 600);
    const b = validate({
      provider: S.oneOf(PROVIDERS, { required: true }),
      keyId: S.str({ required: true, pattern: /^rzp_(test|live)_[A-Za-z0-9]{6,40}$/, patternMessage: 'This does not look like a Razorpay Key ID (rzp_test_… or rzp_live_…)' }),
      keySecret: S.str({ required: true, min: 8, max: 120 }),
      webhookSecret: S.str({ required: true, min: 8, max: 120 }),
    }, ctx.body);
    if (ctx.gym.currencyCode && ctx.gym.currencyCode !== 'INR') throw invalid('Online payments support rupee (INR) gyms only for now.');
    if (config.production && b.keyId.startsWith('rzp_test_')) throw invalid('Use your live keys: test keys cannot collect real money.');
    const gw = new PaymentGateway({ payments: { keyId: b.keyId, keySecret: b.keySecret, webhookSecret: b.webhookSecret, fetchImpl: config.payments?.fetchImpl }, devPayments: false });
    const check = await gw.verifyKeys();
    if (check === 'rejected') throw invalid('Razorpay did not accept these keys. Check the Key ID and Key Secret.');
    if (check === 'unreachable') throw new ApiError(502, 'PAYMENT_PROVIDER_ERROR', 'Could not reach Razorpay to check the keys. Try again in a moment.');
    store.tx(() => {
      store.run(
        `INSERT INTO gym_payment_accounts(gym_id, provider, key_id, secret_sealed, webhook_secret_sealed, status, verified_at, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?)
         ON CONFLICT(gym_id) DO UPDATE SET provider = excluded.provider, key_id = excluded.key_id, secret_sealed = excluded.secret_sealed,
           webhook_secret_sealed = excluded.webhook_secret_sealed, status = 'active', verified_at = excluded.verified_at, updated_at = excluded.updated_at`,
        ctx.gymId, b.provider, b.keyId, seal(config.jwtSecret, b.keySecret), seal(config.jwtSecret, b.webhookSecret), 'active', nowIso(), nowIso(), nowIso(),
      );
      saveGym(store, ctx.gymId, { paymentSetup: { status: 'active', provider: b.provider, at: nowIso() } });
    });
    return view({ ...ctx, gym: loadGym(store, ctx.gymId) });
  });

  // "Skip for now": remembered so the prompt is not shown again; every other feature works the same.
  router.post('/v5/gyms/payment-setup/skip', { perm: 'settings.write' }, (ctx) => {
    if (account(ctx.gymId)) return view(ctx);
    saveGym(store, ctx.gymId, { paymentSetup: { status: 'skipped', at: nowIso() } });
    return view({ ...ctx, gym: loadGym(store, ctx.gymId) });
  });

  router.delete('/v5/gyms/payment-setup', { perm: 'settings.write' }, (ctx) => {
    if (ctx.role !== 'owner') throw forbidden('Only the gym owner can disconnect the payment account');
    store.tx(() => {
      store.run('DELETE FROM gym_payment_accounts WHERE gym_id = ?', ctx.gymId);
      saveGym(store, ctx.gymId, { paymentSetup: { status: 'none', at: nowIso() } });
    });
    return noContent();
  });

  // ---- a link a member pays their dues with --------------------------------------------------------------------------------
  async function createDuesLink(ctx, member, amount) {
    const row = account(ctx.gymId);
    if (!row) throw conflict('Online payments are not set up for this gym.');
    if ((ctx.gym.currencyCode ?? 'INR') !== 'INR') throw invalid('Online payments support rupee (INR) gyms only for now.');
    const dues = openDues(ctx, member.id);
    const totalDue = round2(dues.reduce((s, d) => s + balanceOf(d), 0));
    if (totalDue <= 0) throw invalid('This member has nothing to pay.');
    const pay = amount == null ? totalDue : round2(amount);
    if (pay < 1) throw invalid('The amount must be at least 1.');
    if (pay > totalDue) throw invalid(`The amount cannot be more than the balance (${totalDue}).`);
    const token = randomBytes(24).toString('base64url');
    const order = ctx.col('orders').insert({
      type: 'member_fee', memberId: member.id, amount: pay, currency: 'INR', description: `${ctx.gym.name}: membership dues`, token, status: 'created', provider: 'razorpay', createdById: ctx.user?.id ?? null,
    });
    try {
      const checkout = await gatewayFor(row).createCheckout({
        orderId: order.id, amount: pay, description: `${ctx.gym.name}: membership dues for ${member.name}`, callbackUrl: `${baseUrl(ctx)}/pay/return/${token}`,
        notes: { orderId: order.id, gymId: ctx.gymId, memberId: member.id, type: 'member_fee' },
      });
      ctx.col('orders').update(order.id, { providerRef: checkout.providerRef });
      return { orderId: order.id, amount: pay, balance: totalDue, url: checkout.url };
    } catch (e) {
      ctx.col('orders').update(order.id, { status: 'failed', failureReason: 'checkout_not_created' });
      throw e;
    }
  }

  router.post('/v5/members/:id/payment-link', { perm: 'finance.write' }, async (ctx) => {
    limiter.check(`gpay-link:${ctx.gymId}`, 120, 600);
    const b = validate({ amount: S.num({ min: 1, max: 10_000_000 }) }, ctx.body);
    const member = ctx.col('members').get(ctx.params.id);
    if (!member) throw notFound('Member not found');
    return created(await createDuesLink(ctx, member, b.amount));
  });

  // The member pays their own dues from the app (only their own: the member comes from the token).
  router.post('/v5/member/me/payment-link', { auth: 'member' }, async (ctx) => {
    limiter.check(`gpay-mylink:${ctx.gymId}:${ctx.member.id}`, 20, 600);
    const b = validate({ amount: S.num({ min: 1, max: 10_000_000 }) }, ctx.body);
    return created(await createDuesLink({ ...ctx, user: null }, ctx.member, b.amount));
  });

  // Tells the app whether to offer "Pay online": true only when this gym has connected its account.
  router.get('/v5/member/me/payment-options', { auth: 'member' }, (ctx) => ({ online: !!account(ctx.gymId) && (ctx.gym.currencyCode ?? 'INR') === 'INR' }));

  // ---- the gym's own Razorpay webhook ---------------------------------------------------------------------------------------
  router.post('/v5/payments/webhooks/gym/:gymId/razorpay', { auth: 'none', maxBody: 256 * 1024 }, (ctx) => {
    const row = account(ctx.params.gymId);
    if (!row) throw new ApiError(401, 'BAD_SIGNATURE', 'Invalid signature');
    const gw = gatewayFor(row);
    if (!gw.verifyWebhook(ctx.req.rawBody ?? Buffer.alloc(0), ctx.req.headers['x-razorpay-signature'])) throw new ApiError(401, 'BAD_SIGNATURE', 'Invalid signature');
    const ev = paidEvent(ctx.body);
    if (!ev) return { received: true };
    const gym = loadGym(store, ctx.params.gymId);
    const col = (n) => store.col(gym.id, n);
    const order = col('orders').get(ev.orderId); // only this gym's own orders can be found here
    if (!order || order.type !== 'member_fee') return { received: true };
    if (ev.currency !== 'INR' || ev.amountPaise !== Math.round(order.amount * 100)) {
      col('orders').update(order.id, { status: 'mismatch', failureReason: `paid ${ev.amountPaise} ${ev.currency}` });
      return { received: true };
    }
    store.tx(() => {
      const fresh = col('orders').get(order.id);
      if (fresh.status !== 'created') return; // already delivered (Razorpay retries)
      const member = col('members').get(order.memberId);
      if (!member) { col('orders').update(order.id, { status: 'failed', failureReason: 'member_removed' }); return; }
      const fctx = { store, gymId: gym.id, gym, col, user: { id: null }, today: () => todayIn(gym.timezone) };
      const dues = openDues(fctx, member.id);
      const due = round2(dues.reduce((s, d) => s + balanceOf(d), 0));
      const apply = Math.min(due, order.amount);
      if (apply > 0) allocateSettlement(fctx, member, dues, [{ paymentType: 'upi', amount: apply }], fctx.today(), `Online payment ${ev.paymentId ?? ''}`.trim());
      col('orders').update(order.id, { status: 'paid', completedAt: nowIso(), paymentId: ev.paymentId, applied: apply, unapplied: round2(order.amount - apply) });
    });
    return { received: true };
  });
}
