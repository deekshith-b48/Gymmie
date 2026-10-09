// Message templates, rendering and the credit-metered outbox.
//
// DELIVERY: this development backend has no WhatsApp/SMS provider. Messages are written to the
// outbox with status 'recorded' (credits are still debited so the credit flow is testable). A real
// provider would replace `deliver()` and set status to 'sent' / 'failed'.
import { saveGym } from '../helpers.js';

export const CREDIT_COST = 1; // credits per message

/** Template keys mirror the constants found in the app binary. */
export const DEFAULT_TEMPLATES = {
  MEMBER_WELCOME_SMS: { title: 'Member Welcome', auto: true, body: 'Hi {{memberName}}, welcome to {{gymName}}! Your membership {{planName}} is valid till {{endDate}}.' },
  MEMBER_ONBOARD_SMS: { title: 'Member Onboard', auto: false, body: 'Hi {{memberName}}, you have been added to {{gymName}}. Gym code: {{gymCode}}.' },
  MEMBERSHIP_RENEWAL_SUCCESS_SMS: { title: 'Membership Renewal Success', auto: true, body: 'Hi {{memberName}}, your {{planName}} membership at {{gymName}} is renewed till {{endDate}}. Thank you!' },
  MEMBERSHIP_EXPIRING_REMINDER_SMS: { title: 'Membership Expiring Reminder', auto: true, body: 'Hi {{memberName}}, your membership at {{gymName}} expires on {{endDate}}. Renew now to keep training.' },
  MEMBERSHIP_EXPIRED_SMS: { title: 'Membership Expired', auto: false, body: 'Hi {{memberName}}, your membership at {{gymName}} expired on {{endDate}}. Visit us to renew.' },
  MEMBERSHIP_REMINDER_SMS: { title: 'Membership Reminder', auto: false, body: 'Hi {{memberName}}, a gentle reminder to renew your {{planName}} membership at {{gymName}}.' },
  MEMBER_BALANCE_REMINDER_SMS: { title: 'Member Balance Reminder', auto: true, body: 'Hi {{memberName}}, a balance of {{balance}} is pending at {{gymName}}. Please clear it at your earliest.' },
  MEMBER_SETTLEMENT_SUCCESS_SMS: { title: 'Member Settlement Success', auto: true, body: 'Hi {{memberName}}, we received {{amount}} at {{gymName}}. Remaining balance: {{balance}}.' },
  MEMBER_BIRTHDAY_SMS: { title: 'Member Birthday', auto: false, body: 'Happy Birthday {{memberName}}! Team {{gymName}} wishes you a fit and healthy year.' },
  MEMBERSHIP_PAUSE_SMS: { title: 'Membership Pause', auto: true, body: 'Hi {{memberName}}, your membership at {{gymName}} is paused from {{date}}.' },
  MEMBERSHIP_RESUME_SMS: { title: 'Membership Resume', auto: true, body: 'Hi {{memberName}}, your membership at {{gymName}} resumed. New end date: {{endDate}}.' },
  MEMBERSHIP_STATUS_EXTEND_SMS: { title: 'Membership Status Extend', auto: true, body: 'Hi {{memberName}}, your membership at {{gymName}} was extended. New end date: {{endDate}}.' },
  MEMBERSHIP_STATUS_UPDATE_SMS: { title: 'Membership Status Update', auto: false, body: 'Hi {{memberName}}, your membership status at {{gymName}} was updated.' },
  MEMBERSHIP_SESSION_MARKED_SMS: { title: 'Membership Session Marked', auto: false, body: 'Hi {{memberName}}, a session was marked on your plan. Sessions left: {{sessionsLeft}}.' },
  PRODUCT_SALE_SUCCESS_SMS: { title: 'Product Sale Success', auto: false, body: 'Hi {{memberName}}, thanks for your purchase at {{gymName}}. Invoice {{invoiceNo}}: {{amount}}.' },
  PARQ_FORM_SHARE_SMS: { title: 'PARQ Form Share', auto: false, body: 'Hi {{memberName}}, please complete your health questionnaire (PAR-Q) for {{gymName}}.' },
  PROSPECT_GYM_MEMBER_WELCOME_SMS: { title: 'Prospect Gym Member Welcome', auto: true, body: 'Hi {{memberName}}, thanks for your interest in {{gymName}}! We will get in touch shortly.' },
  PROSPECT_GYM_MEMBER_REMINDER_SMS: { title: 'Prospect Gym Member Reminder', auto: false, body: 'Hi {{memberName}}, following up on your enquiry with {{gymName}}. Shall we schedule a visit?' },
};

export const COMMON_VARIABLES = ['gymName', 'gymCode', 'gymPhone'];
export const MEMBER_VARIABLES = ['memberName', 'memberPhone', 'planName', 'endDate', 'balance', 'amount', 'invoiceNo', 'date', 'sessionsLeft'];

export function renderTemplate(body, vars) {
  return body.replace(/\{\{\s*([A-Za-z0-9_]+)\s*\}\}/g, (_, k) => (vars[k] !== undefined && vars[k] !== null ? String(vars[k]) : ''));
}

export function getTemplate(ctx, key) {
  const def = DEFAULT_TEMPLATES[key];
  if (!def) return null;
  const custom = ctx.col('messageTemplates').findOne((t) => t.key === key);
  return { key, title: def.title, body: custom?.body ?? def.body, isCustom: !!custom, auto: custom?.auto ?? def.auto, defaultBody: def.body, id: custom?.id ?? null };
}

export function gymVars(gym) {
  return { gymName: gym.name, gymCode: gym.code, gymPhone: gym.phone ?? '' };
}

export function debitCredits(ctx, amount, reference) {
  const bal = ctx.gym.creditBalance ?? 0;
  if (bal < amount) return false;
  const next = bal - amount;
  const gym = saveGym(ctx.store, ctx.gymId, { creditBalance: next });
  ctx.gym.creditBalance = gym.creditBalance;
  ctx.col('creditLedger').insert({ type: 'usage', credits: -amount, balanceAfter: next, reference });
  return true;
}

export function addCredits(ctx, amount, reference, type = 'recharge') {
  const next = (ctx.gym.creditBalance ?? 0) + amount;
  const gym = saveGym(ctx.store, ctx.gymId, { creditBalance: next });
  ctx.gym.creditBalance = gym.creditBalance;
  return ctx.col('creditLedger').insert({ type, credits: amount, balanceAfter: next, reference });
}

/** Records one outbound message. Returns the outbox row (status 'recorded' | 'failed'). */
export function enqueue(ctx, { key, to, memberId = null, body, broadcastId = null, channel = 'whatsapp' }) {
  const ok = debitCredits(ctx, CREDIT_COST, `message:${key}`);
  return ctx.col('outbox').insert({
    key, to, memberId, body, broadcastId, channel, credits: ok ? CREDIT_COST : 0,
    status: ok ? 'recorded' : 'failed', failureReason: ok ? null : 'insufficientWhatsappCredits',
  });
}

/** Automated, event-driven message (only when WhatsApp integration is on and the template is automated). */
export function sendAutomated(ctx, key, member, vars = {}) {
  if (!ctx.gym.whatsapp?.enabled || !member?.phone) return null;
  const t = getTemplate(ctx, key);
  if (!t || !t.auto) return null;
  const body = renderTemplate(t.body, { ...gymVars(ctx.gym), memberName: member.name, memberPhone: member.phone, ...vars });
  return enqueue(ctx, { key, to: member.phone, memberId: member.id, body });
}
