// What the operator needs to know. Security events are written to the database (so `scripts/admin.js events` can show them after the
// fact) and to the log as one JSON line; the ones that need a human are also pushed to ALERT_WEBHOOK_URL (Slack, Discord, ntfy ...).
// Alerts are best effort and rate limited per kind, so a storm of one problem is one message, never a flood, and a down webhook
// never breaks a request.
import { nowIso } from './db.js';

const ALERT_EVERY_MS = 10 * 60 * 1000;

export class Ops {
  constructor(store, config) {
    this.store = store;
    this.url = config.alerts?.webhookUrl ?? '';
    this.fetch = config.alerts?.fetchImpl ?? globalThis.fetch;
    this.last = new Map();
    this.sent = []; // recent alerts, for tests and for the admin console
  }

  /** Records a security or operations event. `subject` must already be safe to store (a masked phone, an order id): never a secret. */
  event(kind, { subject = null, ip = null, detail = null, alert = false } = {}) {
    try {
      this.store.run('INSERT INTO security_events(at, kind, subject, ip, detail) VALUES (?,?,?,?,?)', Date.now(), kind, subject, ip, detail ? JSON.stringify(detail) : null);
    } catch { /* an event must never break the request that raised it */ }
    console.warn(JSON.stringify({ level: alert ? 'alert' : 'warn', event: kind, subject, ip, detail, at: nowIso() }));
    if (alert) this.alert(kind, { subject, detail });
  }

  /** Pushes a message to the operator's webhook (at most one per kind every ten minutes). */
  alert(kind, info = {}) {
    const now = Date.now();
    if (now - (this.last.get(kind) ?? 0) < ALERT_EVERY_MS) return false;
    this.last.set(kind, now);
    const text = `Gymmie alert: ${kind}${info.subject ? ` (${info.subject})` : ''}${info.detail ? ` ${JSON.stringify(info.detail).slice(0, 300)}` : ''}`;
    this.sent.push({ kind, text, at: nowIso() });
    if (this.sent.length > 50) this.sent.shift();
    if (!this.url) return true;
    Promise.resolve(this.fetch(this.url, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ text, content: text }), signal: AbortSignal.timeout(5000) }))
      .catch((e) => console.error(JSON.stringify({ level: 'error', msg: 'alert webhook failed', error: String(e.message ?? e) })));
    return true;
  }
}

export const maskPhone = (t) => (t && t.length > 6 ? `${t.slice(0, 3)}${'*'.repeat(t.length - 6)}${t.slice(-3)}` : '***');
