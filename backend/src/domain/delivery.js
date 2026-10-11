// Hands recorded messages to the real provider. A row leaves the outbox as 'sent' (with the provider's id) or 'failed',
// and a failed message gives its credit back, so a gym is only ever charged for messages that went out.
import { addCredits } from './notify.js';
import { loadGym } from '../helpers.js';
import { nowIso } from '../db.js';

/** Sends up to [limit] recorded messages. Returns how many were sent and failed. */
export async function processOutbox(store, messenger, { limit = 40 } = {}) {
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
    col.update(msg.id, { status: 'sending' }); // claimed, so a slow provider call is never repeated
    try {
      const out = await messenger.sendText({ channel, to: msg.to, body: msg.body });
      col.update(msg.id, { status: 'sent', sentAt: nowIso(), providerId: out?.providerId ?? null });
      sent++;
    } catch (e) {
      col.update(msg.id, { status: 'failed', failureReason: 'providerError', failureDetail: String(e.message ?? e).slice(0, 200) });
      if (msg.credits > 0) {
        const gym = loadGym(store, r.gym_id);
        addCredits({ store, gymId: r.gym_id, gym, col: (n) => store.col(r.gym_id, n) }, msg.credits, `refund:${msg.id}`, 'refund');
      }
      failed++;
    }
  }
  return { sent, failed };
}
