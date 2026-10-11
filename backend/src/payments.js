// Takes real money. Razorpay Payment Links (UPI, cards, netbanking) hosted by Razorpay, confirmed by a signed webhook.
// The app only opens the link; nothing is fulfilled until Razorpay's server tells ours the payment was captured.
// The development provider (config.devPayments) stays for local work and is refused in production.
import { createHmac, timingSafeEqual } from 'node:crypto';
import { ApiError } from './errors.js';

const API = 'https://api.razorpay.com/v1';

export class PaymentGateway {
  constructor(config, fetchImpl = globalThis.fetch) {
    this.cfg = config.payments ?? {};
    this.dev = !!config.devPayments;
    this.fetch = this.cfg.fetchImpl ?? fetchImpl;
  }

  /** 'razorpay' when keys are set, else 'dev' (development only), else null. */
  get provider() {
    if (this.cfg.keyId && this.cfg.keySecret) return 'razorpay';
    return this.dev ? 'dev' : null;
  }

  get webhookConfigured() { return !!this.cfg.webhookSecret; }

  /** Creates a hosted checkout for [amount] rupees. Returns { providerRef, url }. */
  async createCheckout({ orderId, amount, description, callbackUrl, notes = {} }) {
    const auth = Buffer.from(`${this.cfg.keyId}:${this.cfg.keySecret}`).toString('base64');
    const res = await this.fetch(`${API}/payment_links`, {
      method: 'POST',
      headers: { authorization: `Basic ${auth}`, 'content-type': 'application/json' },
      body: JSON.stringify({
        amount: Math.round(amount * 100), currency: 'INR', accept_partial: false, description: String(description).slice(0, 250),
        reference_id: orderId, callback_url: callbackUrl, callback_method: 'get', notify: { sms: false, email: false }, reminder_enable: false, notes,
      }),
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok || !body.short_url) {
      throw new ApiError(502, 'PAYMENT_PROVIDER_ERROR', 'The payment provider could not create the checkout. Please try again.', { providerStatus: res.status });
    }
    return { providerRef: body.id, url: body.short_url };
  }

  /** Do these keys work? Razorpay answers 401 to wrong keys; any 2xx means they are good. Returns 'ok' | 'rejected' | 'unreachable'. */
  async verifyKeys() {
    const auth = Buffer.from(`${this.cfg.keyId}:${this.cfg.keySecret}`).toString('base64');
    try {
      const res = await this.fetch(`${API}/payment_links?count=1`, { method: 'GET', headers: { authorization: `Basic ${auth}` } });
      if (res.ok) return 'ok';
      return res.status === 401 || res.status === 403 ? 'rejected' : 'unreachable';
    } catch {
      return 'unreachable';
    }
  }

  /** Is [signature] the HMAC-SHA256 of the exact raw body under the webhook secret? */
  verifyWebhook(rawBody, signature) {
    if (!this.cfg.webhookSecret || !signature) return false;
    const want = createHmac('sha256', this.cfg.webhookSecret).update(rawBody).digest('hex');
    const a = Buffer.from(String(signature));
    const b = Buffer.from(want);
    return a.length === b.length && timingSafeEqual(a, b);
  }
}

/** The facts a fulfilment needs from a Razorpay webhook body, or null if it is not a paid link/order. */
export function paidEvent(body) {
  const ev = body?.event;
  if (ev !== 'payment_link.paid' && ev !== 'order.paid') return null;
  const link = body.payload?.payment_link?.entity;
  const pay = body.payload?.payment?.entity;
  const orderId = link?.reference_id ?? pay?.notes?.orderId ?? null;
  if (!orderId) return null;
  return {
    event: ev, orderId, providerRef: link?.id ?? null, paymentId: pay?.id ?? null,
    amountPaise: Number(pay?.amount ?? link?.amount_paid ?? link?.amount ?? 0), currency: pay?.currency ?? link?.currency ?? 'INR',
    status: pay?.status ?? link?.status ?? '',
  };
}
