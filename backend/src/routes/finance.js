// Finance: transaction ledger, balance settlement / write-off, balance reminders, expenses, invoices.
import { S, validate } from '../validate.js';
import { conflict, forbidden, invalid, notFound } from '../errors.js';
import { created, noContent, raw } from '../http.js';
import { addDays, inRange, periodRange } from '../domain/dates.js';
import { balanceOf } from '../domain/membership.js';
import { round2 } from '../domain/pricing.js';
import { normalisePayments, recordPayments } from '../domain/ledger.js';
import { PAYMENT_TYPES, toCsv } from '../helpers.js';
import { sendAutomated } from '../domain/notify.js';
import { buildIndex } from '../domain/views.js';

export const EXPENSE_CATEGORIES = ['Rent', 'Salaries', 'Electricity & Water', 'Equipment', 'Maintenance', 'Marketing', 'Supplies', 'Software', 'Taxes', 'Stock Purchase', 'Other'];
const KIND_LABEL = { membership: 'Membership', sale: 'Product Sale', settlement: 'Balance Settlement', writeoff: 'Write-off' };

export function resolveRange(ctx) {
  const today = ctx.today();
  const q = ctx.query;
  if (q.period) return periodRange(q.period, today, { from: q.from, to: q.to });
  if (q.from && q.to) return { from: q.from, to: q.to };
  return null;
}

/** Open (unpaid) receivables for a member, oldest first. */
export function openDues(ctx, memberId) {
  const parents = [
    ...ctx.col('memberships').find((m) => m.memberId === memberId).map((d) => ({ ...d, collection: 'memberships' })),
    ...ctx.col('productSales').find((s) => s.memberId === memberId).map((d) => ({ ...d, collection: 'productSales' })),
  ].filter((d) => balanceOf(d) > 0);
  return parents.sort((a, b) => a.createdAt.localeCompare(b.createdAt));
}

/**
 * Spreads [payments] over the member's open dues, oldest first, recording each part against the membership or sale it settles.
 * Shared by the front desk (settle) and by online payments confirmed by the gym's own payment gateway.
 */
export function allocateSettlement(ctx, member, dues, payments, today, notes = null) {
  // Allocate oldest-first; split payments are consumed in order.
  const queue = payments.map((p) => ({ ...p }));
  for (const due of dues) {
    let need = balanceOf(due);
    const slice = [];
    while (need > 0 && queue.length) {
      const take = round2(Math.min(need, queue[0].amount));
      slice.push({ paymentType: queue[0].paymentType, amount: take });
      queue[0].amount = round2(queue[0].amount - take);
      need = round2(need - take);
      if (queue[0].amount <= 0) queue.shift();
    }
    if (slice.length) {
      const parent = ctx.col(due.collection).get(due.id);
      recordPayments(ctx, { kind: 'settlement', parentCollection: due.collection, parent, memberId: member.id, payments: slice, date: today, invoiceNo: parent.invoiceNo, notes });
    }
    if (!queue.length) break;
  }
  const left = openDues(ctx, member.id).reduce((s, d) => s + balanceOf(d), 0);
  if (left <= 0) for (const r of ctx.col('balanceReminders').find((x) => x.memberId === member.id && !x.done)) ctx.col('balanceReminders').update(r.id, { done: true, doneAt: new Date().toISOString() });
}

export function enrichTransaction(ctx, t, caches) {
  const member = t.memberId ? (caches.members.get(t.memberId) ?? null) : null;
  const staff = caches.staff.get(t.createdById);
  return {
    ...t, kindLabel: KIND_LABEL[t.kind] ?? t.kind,
    member: member ? { id: member.id, name: member.name, phone: member.phone } : null,
    createdBy: staff ? { id: staff.id, name: staff.name } : null,
    description: t.description ?? caches.parentName(t),
  };
}

export function txnCaches(ctx) {
  const members = new Map(ctx.col('members').all().map((m) => [m.id, m]));
  const staff = new Map(ctx.store.all('SELECT u.id, u.name FROM gym_users gu JOIN users u ON u.id = gu.user_id WHERE gu.gym_id = ?', ctx.gymId).map((r) => [r.id, r]));
  const mems = new Map(ctx.col('memberships').all().map((m) => [m.id, m]));
  const sales = new Map(ctx.col('productSales').all().map((m) => [m.id, m]));
  const parentName = (t) => {
    if (t.parentCollection === 'memberships') return mems.get(t.parentId)?.planName ?? 'Membership';
    if (t.parentCollection === 'productSales') return sales.get(t.parentId)?.items?.map((i) => `${i.name} x${i.quantity}`).join(', ') ?? 'Product sale';
    return KIND_LABEL[t.kind] ?? t.kind;
  };
  return { members, staff, parentName };
}

export function listTransactions(ctx) {
  const range = resolveRange(ctx);
  const caches = txnCaches(ctx);
  const q = (ctx.query.q ?? '').trim().toLowerCase();
  return ctx.col('transactions').all()
    .filter((t) => inRange(t.date, range))
    .filter((t) => !ctx.query.memberId || t.memberId === ctx.query.memberId)
    .filter((t) => !ctx.query.kind || t.kind === ctx.query.kind)
    .filter((t) => !ctx.query.paymentType || t.paymentType === ctx.query.paymentType)
    .filter((t) => !ctx.query.createdById || t.createdById === ctx.query.createdById)
    .map((t) => enrichTransaction(ctx, t, caches))
    .filter((t) => !q || t.member?.name.toLowerCase().includes(q) || (t.invoiceNo ?? '').toLowerCase().includes(q))
    .sort((a, b) => b.date.localeCompare(a.date) || b.createdAt.localeCompare(a.createdAt));
}

export function registerFinanceRoutes({ router, store }) {
  const page = (items, query) => {
    const p = Math.max(1, parseInt(query.page ?? '1', 10) || 1);
    const l = Math.min(200, Math.max(1, parseInt(query.limit ?? '20', 10) || 20));
    return { __envelope: true, status: 200, body: { data: items.slice((p - 1) * l, p * l), meta: { page: p, limit: l, total: items.length, totalPages: Math.max(1, Math.ceil(items.length / l)) } } };
  };

  // ---- transactions ----------------------------------------------------------------------------------------
  router.get('/v5/members/transactions', { perm: 'finance.read' }, (ctx) => {
    const all = listTransactions(ctx);
    const res = page(all, ctx.query);
    res.body.meta.totalAmount = round2(all.filter((t) => t.kind !== 'writeoff').reduce((s, t) => s + t.amount, 0));
    return res;
  });

  router.get('/v5/members/transactions/export', { perm: 'finance.read' }, (ctx) => {
    const csv = toCsv(listTransactions(ctx), [
      { header: 'Date', value: (t) => t.date }, { header: 'Invoice', value: (t) => t.invoiceNo }, { header: 'Member', value: (t) => t.member?.name },
      { header: 'Phone', value: (t) => t.member?.phone }, { header: 'Type', value: (t) => t.kindLabel }, { header: 'Description', value: (t) => t.description },
      { header: 'Payment Type', value: (t) => t.paymentType }, { header: 'Amount', value: (t) => t.amount }, { header: 'Received By', value: (t) => t.createdBy?.name },
    ]);
    return raw(200, 'text/csv; charset=utf-8', csv, { 'content-disposition': `attachment; filename="transactions-${ctx.today()}.csv"` });
  });

  router.get('/v5/members/transactions/balance', { perm: 'finance.read' }, (ctx) => {
    const idx = buildIndex(ctx);
    const members = new Map(ctx.col('members').all().map((m) => [m.id, m]));
    const items = [...idx.balances.entries()].filter(([id, b]) => b > 0 && members.has(id)).map(([id, balance]) => {
      const m = members.get(id);
      const dues = openDues(ctx, id);
      return { memberId: id, name: m.name, phone: m.phone, balance, oldestDueDate: dues[0]?.createdAt.slice(0, 10) ?? null, reminderDate: idx.reminders.get(id)?.reminderDate ?? null };
    }).sort((a, b) => b.balance - a.balance);
    return { totalBalance: round2(items.reduce((s, i) => s + i.balance, 0)), membersWithBalance: items.length, items };
  });

  router.get('/v5/members/transactions/:id', { perm: 'finance.read' }, (ctx) => {
    const t = ctx.col('transactions').get(ctx.params.id);
    if (!t) throw notFound('Transaction not found');
    return enrichTransaction(ctx, t, txnCaches(ctx));
  });

  router.delete('/v5/members/transactions/:id', { perm: 'finance.write' }, (ctx) => {
    if (!['owner', 'manager'].includes(ctx.role)) throw forbidden('Only a manager or owner can delete a transaction');
    const t = ctx.col('transactions').get(ctx.params.id);
    if (!t) throw notFound('Transaction not found');
    store.tx(() => {
      const parent = t.parentCollection ? ctx.col(t.parentCollection).get(t.parentId) : null;
      if (parent) {
        if (t.kind === 'writeoff') ctx.col(t.parentCollection).update(parent.id, { writtenOff: round2(Math.max(0, (parent.writtenOff ?? 0) - t.amount)) });
        else ctx.col(t.parentCollection).update(parent.id, { amountReceived: round2(Math.max(0, (parent.amountReceived ?? 0) - t.amount)) });
      }
      ctx.col('transactions').remove(t.id);
    });
    return noContent();
  });

  // ---- settle / write off ----------------------------------------------------------------------------------------
  router.post('/v5/members/transactions/settle', { perm: 'finance.write' }, (ctx) => {
    const b = validate({
      memberId: S.str({ required: true }), amount: S.num({ min: 0.01, max: 10_000_000 }), paymentType: S.oneOf(PAYMENT_TYPES),
      payments: S.list(S.obj({ paymentType: S.oneOf(PAYMENT_TYPES, { required: true }), amount: S.num({ required: true, min: 0.01 }) }), { max: 5 }), notes: S.str({ max: 300 }),
    }, ctx.body);
    if (!b.amount && !b.payments?.length) throw invalid('Enter Amount');
    const member = ctx.col('members').get(b.memberId);
    if (!member) throw notFound('Member not found');
    const dues = openDues(ctx, member.id);
    const totalDue = round2(dues.reduce((s, d) => s + balanceOf(d), 0));
    if (totalDue <= 0) throw invalid('This member has no outstanding balance');
    const payments = normalisePayments(ctx, b.payments ? { payments: b.payments } : { amountReceived: b.amount, paymentType: b.paymentType });
    const paid = round2(payments.reduce((s, p) => s + p.amount, 0));
    if (paid > totalDue) throw invalid(`Payment received cannot exceed total (${totalDue})`);
    const today = ctx.today();
    store.tx(() => allocateSettlement(ctx, member, dues, payments, ctx.today(), b.notes));
    const remaining = round2(totalDue - paid);
    sendAutomated(ctx, 'MEMBER_SETTLEMENT_SUCCESS_SMS', member, { amount: paid, balance: remaining });
    return { settled: paid, remainingBalance: remaining };
  });

  router.post('/v5/members/transactions/write-off', { perm: 'finance.write' }, (ctx) => {
    if (!['owner', 'manager'].includes(ctx.role)) throw forbidden('Only a manager or owner can write off a balance');
    const b = validate({ memberId: S.str({ required: true }), reason: S.str({ max: 300 }) }, ctx.body);
    const member = ctx.col('members').get(b.memberId);
    if (!member) throw notFound('Member not found');
    const dues = openDues(ctx, member.id);
    if (!dues.length) throw invalid('This member has no outstanding balance');
    const today = ctx.today();
    let total = 0;
    store.tx(() => {
      for (const d of dues) {
        const amt = balanceOf(d);
        total = round2(total + amt);
        ctx.col(d.collection).update(d.id, { writtenOff: round2((d.writtenOff ?? 0) + amt) });
        ctx.col('transactions').insert({ kind: 'writeoff', memberId: member.id, parentCollection: d.collection, parentId: d.id, amount: amt, paymentType: 'other', date: today, invoiceNo: d.invoiceNo ?? null, notes: b.reason ?? null, createdById: ctx.user.id });
      }
      for (const r of ctx.col('balanceReminders').find((x) => x.memberId === member.id && !x.done)) ctx.col('balanceReminders').update(r.id, { done: true, doneAt: new Date().toISOString() });
    });
    return { writtenOff: total };
  });

  // ---- balance reminders ----------------------------------------------------------------------------------------
  const REM = { memberId: S.str({ required: true, max: 64 }), reminderDate: S.date({ required: true }), notes: S.str({ max: 300 }) };
  const remView = (ctx, r, caches) => ({ ...r, member: caches.get(r.memberId) ? { id: r.memberId, name: caches.get(r.memberId).name, phone: caches.get(r.memberId).phone } : null, overdue: !r.done && r.reminderDate < ctx.today() });
  router.get('/v5/balance-reminder', { perm: 'finance.read' }, (ctx) => {
    const members = new Map(ctx.col('members').all().map((m) => [m.id, m]));
    const idx = buildIndex(ctx);
    return ctx.col('balanceReminders').find((r) => (ctx.query.done === 'true' ? r.done : !r.done)).map((r) => ({ ...remView(ctx, r, members), balance: idx.balances.get(r.memberId) ?? 0 }))
      .sort((a, b) => a.reminderDate.localeCompare(b.reminderDate));
  });
  router.get('/v5/balance-reminder/member/:memberId', { perm: 'finance.read' }, (ctx) => {
    const r = ctx.col('balanceReminders').findOne((x) => x.memberId === ctx.params.memberId && !x.done);
    return r ? remView(ctx, r, new Map(ctx.col('members').all().map((m) => [m.id, m]))) : null;
  });
  router.post('/v5/balance-reminder', { perm: 'finance.write' }, (ctx) => {
    const b = validate(REM, ctx.body);
    const member = ctx.col('members').get(b.memberId);
    if (!member) throw notFound('Member not found');
    if (b.reminderDate < ctx.today()) throw invalid('Select a date from today onwards');
    const idx = buildIndex(ctx);
    if (!(idx.balances.get(member.id) > 0)) throw invalid('This member has no outstanding balance');
    if (ctx.col('balanceReminders').findOne((x) => x.memberId === member.id && !x.done)) throw conflict('A balance reminder is already set for this member');
    return created(ctx.col('balanceReminders').insert({ ...b, done: false }));
  });
  router.patch('/v5/balance-reminder/:id', { perm: 'finance.write' }, (ctx) => {
    const r = ctx.col('balanceReminders').get(ctx.params.id);
    if (!r) throw notFound('Reminder not found');
    const b = validate({ reminderDate: S.date(), notes: S.str({ max: 300 }) }, ctx.body, { partial: true });
    if (!Object.keys(b).length) throw invalid('At least one field should be passed to update reminder');
    return ctx.col('balanceReminders').update(r.id, b);
  });
  router.post('/v5/balance-reminder/:id/done', { perm: 'finance.write' }, (ctx) => {
    const r = ctx.col('balanceReminders').get(ctx.params.id);
    if (!r) throw notFound('Reminder not found');
    return ctx.col('balanceReminders').update(r.id, { done: true, doneAt: new Date().toISOString() });
  });
  router.delete('/v5/balance-reminder/:id', { perm: 'finance.write' }, (ctx) => {
    if (!ctx.col('balanceReminders').remove(ctx.params.id)) throw notFound('Reminder not found');
    return noContent();
  });

  // ---- expenses --------------------------------------------------------------------------------------------------
  const EXP = {
    category: S.str({ required: true, min: 1, max: 60 }), title: S.str({ max: 100 }), amount: S.num({ required: true, min: 0.01, max: 100_000_000 }),
    date: S.date(), paymentType: S.oneOf(PAYMENT_TYPES, { default: 'cash' }), notes: S.str({ max: 500 }), labelIds: S.list(S.str({ max: 64 }), { max: 10 }), vendor: S.str({ max: 100 }),
  };
  router.get('/v5/expenses/categories', { perm: 'expenses.read' }, (ctx) => [...new Set([...EXPENSE_CATEGORIES, ...ctx.col('expenses').all().map((e) => e.category)])]);
  router.get('/v5/expenses', { perm: 'expenses.read' }, (ctx) => {
    const range = resolveRange(ctx);
    const labelIds = (ctx.query.labelIds ?? '').split(',').filter(Boolean);
    const q = (ctx.query.q ?? '').toLowerCase();
    const all = ctx.col('expenses').all()
      .filter((e) => inRange(e.date, range)).filter((e) => !ctx.query.category || e.category === ctx.query.category)
      .filter((e) => !labelIds.length || labelIds.some((l) => e.labelIds?.includes(l)))
      .filter((e) => !q || (e.title ?? '').toLowerCase().includes(q) || e.category.toLowerCase().includes(q) || (e.vendor ?? '').toLowerCase().includes(q))
      .sort((a, b) => b.date.localeCompare(a.date) || b.createdAt.localeCompare(a.createdAt));
    const res = page(all, ctx.query);
    res.body.meta.totalAmount = round2(all.reduce((s, e) => s + e.amount, 0));
    return res;
  });
  router.get('/v5/expenses/:id', { perm: 'expenses.read' }, (ctx) => {
    const e = ctx.col('expenses').get(ctx.params.id);
    if (!e) throw notFound('Expense not found');
    return e;
  });
  const checkExpense = (ctx, b) => {
    if (b.date && b.date > ctx.today()) throw invalid('Selected date and time cannot be in the future.');
    for (const id of b.labelIds ?? []) if (!ctx.col('tags').get(id)) throw invalid('Unknown label');
  };
  router.post('/v5/expenses', { perm: 'expenses.write' }, (ctx) => {
    const b = validate(EXP, ctx.body);
    checkExpense(ctx, b);
    return created(ctx.col('expenses').insert({ ...b, date: b.date ?? ctx.today(), createdById: ctx.user.id }));
  });
  router.patch('/v5/expenses/:id', { perm: 'expenses.write' }, (ctx) => {
    const e = ctx.col('expenses').get(ctx.params.id);
    if (!e) throw notFound('Expense not found');
    const b = validate(EXP, ctx.body, { partial: true });
    checkExpense(ctx, b);
    return ctx.col('expenses').update(e.id, b);
  });
  router.delete('/v5/expenses/:id', { perm: 'expenses.write' }, (ctx) => {
    if (!ctx.col('expenses').remove(ctx.params.id)) throw notFound('Expense not found');
    return noContent();
  });

  // ---- invoices -----------------------------------------------------------------------------------------------------
  router.get('/v5/invoices/:invoiceNo', { perm: 'finance.read' }, (ctx) => {
    const no = ctx.params.invoiceNo;
    const mem = ctx.col('memberships').findOne((m) => m.invoiceNo === no);
    const sale = mem ? null : ctx.col('productSales').findOne((s) => s.invoiceNo === no);
    const doc = mem ?? sale;
    if (!doc) throw notFound('Invoice not found');
    const member = doc.memberId ? ctx.col('members').get(doc.memberId) : null;
    const payments = ctx.col('transactions').find((t) => t.parentId === doc.id && t.kind !== 'writeoff').map((t) => ({ id: t.id, date: t.date, amount: t.amount, paymentType: t.paymentType, kind: t.kind }));
    const items = mem
      ? [{ name: mem.planName, detail: `${mem.startDate} to ${mem.endDate}`, quantity: 1, unitPrice: mem.subtotal, amount: mem.subtotal }]
      : sale.items.map((i) => ({ name: i.name, detail: null, quantity: i.quantity, unitPrice: i.price, amount: round2(i.price * i.quantity) }));
    const defaultTaxNo = ctx.col('taxes').findOne((t) => t.isDefault)?.taxNumber ?? null;
    return {
      invoiceNo: no, type: mem ? 'membership' : 'sale', date: doc.createdAt.slice(0, 10),
      gym: { name: ctx.gym.name, address: ctx.gym.address, phone: ctx.gym.phone, email: ctx.gym.email, taxNumber: defaultTaxNo, currencySymbol: ctx.gym.currencySymbol },
      member: member ? { id: member.id, name: member.name, phone: member.phone, admissionNo: member.admissionNo } : null,
      items, subtotal: doc.subtotal ?? round2(items.reduce((s, i) => s + i.amount, 0)), discount: doc.discount?.amount ?? doc.discountAmount ?? 0,
      tax: doc.tax ?? null, total: doc.total, amountReceived: doc.amountReceived ?? 0, writtenOff: doc.writtenOff ?? 0, balance: balanceOf(doc), payments,
    };
  });
}
