// Hands recorded messages to the real provider. A row leaves the outbox as 'sent' (with the provider's id) or 'failed',
// and a failed message gives its credit back, so a gym is only ever charged for messages that went out.
//
// Recovery: a row is claimed ('sending') before the provider is called. If the server dies in between we cannot know whether the message
// left, so `recoverStuckMessages` marks it failed ('interrupted') and refunds the credit ONCE; it is never re-sent automatically, because a
// retry could text a member twice. Every refund is guarded by a flag on the row, so no path can refund (or charge) twice.
import { addCredits } from './notify.js';
import { loadGym } from '../helpers.js';
import { nowIso } from '../db.js';

const STUCK_AFTER_MS = 15 * 60 * 1000; // the provider calls time out after 15 s, so 15 minutes of 'sending' means the process died

/** Gives the credit of a failed message back, once. Returns true if it did. */
function refundOnce(store, gymId, msg, col, reason) {
  if (!(msg.credits > 0) || msg.refunded) return false;
  const gym = loadGym(store, gymId);
  addCredits({ store, gymId, gym, col: (n) => store.col(gymId, n) }, msg.credits, `refund:${msg.id}`, 'refund');
  col.update(msg.id, { refunded: true, refundReason: reason });
  return true;
}

/** Sends up to [limit] recorded messages. Returns how many were sent and failed. */
export async function processOutbox(store, messenger, { limit = 40, ops = null } = {}) {
  if (!messenger.anyText) return { sent: 0, failed: 0 };
  const rows = store.all(
    `SELECT id, gym_id FROM docs WHERE collection = 'outbox' AND deleted_at IS NULL AND json_extract(data, '$.status') = 'recorded' ORDER BY created_at LIMIT ?`, limit,
  );
  let sent = 0; let failed = 0;
  for (const r of rows) {
    const col = store.col(r.gym_id, 'outbox');
    const msg = col.get(r.id);
    if (!msg || msg.status !== 'recorded') continue;
    const channel = msg.channel ?? 'whatsapp';
    if (!messenger.canSendText(channel)) continue; // another channel's provider is not set up: leave it recorded
    col.update(msg.id, { status: 'sending', sendingAt: Date.now() }); // claimed, so a slow provider call is never repeated
    try {
      const out = await messenger.sendText({ channel, to: msg.to, body: msg.body });
      const now = col.get(msg.id);
      if (now.status !== 'sending') { // recovery gave up on this message while the provider call was in flight: it did go out, so say so and keep the refund
        col.update(msg.id, { sentAfterRecovery: true, providerId: out?.providerId ?? null });
        ops?.event('message_sent_after_recovery', { subject: msg.id });
        continue;
      }
      col.update(msg.id, { status: 'sent', sentAt: nowIso(), providerId: out?.providerId ?? null });
      sent++;
    } catch (e) {
      store.tx(() => {
        const now = col.get(msg.id);
        if (now.status !== 'sending') return; // already settled by recovery
        col.update(msg.id, { status: 'failed', failureReason: 'providerError', failureDetail: String(e.message ?? e).slice(0, 200) });
        refundOnce(store, r.gym_id, col.get(msg.id), col, 'providerError');
      });
      failed++;
    }
  }
  return { sent, failed };
}

/**
 * Messages stuck in 'sending' (the process died mid-call): marked failed and refunded once, never re-sent. Safe to run any time and as
 * often as you like: a message already settled is left alone. Returns the number recovered.
 */
export function recoverStuckMessages(store, { olderThanMs = STUCK_AFTER_MS, ops = null, now = Date.now() } = {}) {
  const rows = store.all(
    `SELECT id, gym_id FROM docs WHERE collection = 'outbox' AND deleted_at IS NULL AND json_extract(data, '$.status') = 'sending'`,
  );
  let recovered = 0; let refunded = 0;
  for (const r of rows) {
    store.tx(() => {
      const col = store.col(r.gym_id, 'outbox');
      const msg = col.get(r.id);
      if (!msg || msg.status !== 'sending') return;
      if (now - (msg.sendingAt ?? 0) < olderThanMs) return;
      col.update(msg.id, { status: 'failed', failureReason: 'interrupted', failureDetail: 'the server stopped while sending; not retried automatically to avoid texting the member twice' });
      if (refundOnce(store, r.gym_id, col.get(msg.id), col, 'interrupted')) refunded++;
      recovered++;
    });
  }
  if (recovered) ops?.event('outbox_stuck_recovered', { detail: { recovered, refunded }, alert: true });
  return recovered;
}
