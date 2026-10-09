// Payments ledger: every rupee received is a `transactions` doc linked to a membership or sale.
import { randomUUID } from 'node:crypto';
import { invalid } from '../errors.js';
import { round2 } from './pricing.js';
import { PAYMENT_TYPES } from '../helpers.js';

export const nextInvoiceNo = (ctx) => `INV-${String(ctx.store.nextCounter(ctx.gymId, 'invoice')).padStart(5, '0')}`;

export function defaultTax(ctx) {
  const t = ctx.col('taxes').findOne((x) => x.isDefault) ?? null;
  return t ? { isIncluded: t.isIncluded, rate: t.rate, name: t.name, taxNumber: t.taxNumber ?? null } : null;
}

/** Normalises the payment part of a request into [{paymentType, amount}] (split payments allowed). */
export function normalisePayments(ctx, { payments, amountReceived, paymentType }) {
  let list = [];
  if (Array.isArray(payments) && payments.length) list = payments.map((p) => ({ paymentType: p.paymentType, amount: round2(p.amount) }));
  else if (amountReceived) list = [{ paymentType: paymentType ?? ctx.gym.paymentMethods?.default ?? 'cash', amount: round2(amountReceived) }];
  for (const p of list) {
    if (!PAYMENT_TYPES.includes(p.paymentType)) throw invalid('Payment method is not valid');
    if (!ctx.gym.paymentMethods.active.includes(p.paymentType)) throw invalid('Payment method is not valid');
    if (!(p.amount > 0)) throw invalid('Amount not valid');
  }
  return list.filter((p) => p.amount > 0);
}

/**
 * Records payments against a parent doc ({collection:'memberships'|'productSales', id}).
 * Returns the created transaction docs. The parent's `amountReceived` is incremented atomically.
 */
export function recordPayments(ctx, { kind, parentCollection, parent, memberId = null, payments, date, invoiceNo, notes = null }) {
  if (!payments.length) return [];
  const splitGroupId = payments.length > 1 ? randomUUID() : null;
  const out = payments.map((p) => ctx.col('transactions').insert({
    kind, memberId, parentCollection, parentId: parent.id, amount: p.amount, paymentType: p.paymentType, date,
    invoiceNo: invoiceNo ?? parent.invoiceNo ?? null, notes, createdById: ctx.user.id, splitGroupId,
  }));
  const total = round2(payments.reduce((s, p) => s + p.amount, 0));
  ctx.col(parentCollection).update(parent.id, { amountReceived: round2((parent.amountReceived ?? 0) + total) });
  return out;
}
