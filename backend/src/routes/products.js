// Products, stock tracking and product sales.
import { S, validate } from '../validate.js';
import { conflict, invalid, notFound } from '../errors.js';
import { created, noContent } from '../http.js';
import { inRange, monthStart, monthEnd } from '../domain/dates.js';
import { quote, checkReceived, round2 } from '../domain/pricing.js';
import { balanceOf } from '../domain/membership.js';
import { defaultTax, nextInvoiceNo, normalisePayments, recordPayments } from '../domain/ledger.js';
import { PAYMENT_TYPES } from '../helpers.js';
import { storeFile } from './auth.js';
import { sendAutomated } from '../domain/notify.js';
import { resolveRange } from './finance.js';

export const PRODUCT_CATEGORIES = ['Supplements', 'Beverages', 'Merchandise', 'Accessories', 'Other'];
export const DAMAGE_REASONS = ['Damaged in transit', 'Broken / Dropped', 'Defective / Faulty', 'Packaging damaged', 'Water / Moisture damage', 'Expired', 'Other'];

const PRODUCT = {
  name: S.str({ required: true, min: 1, max: 100 }), category: S.str({ max: 40, default: 'Other' }), price: S.num({ required: true, min: 0, max: 10_000_000 }),
  costPrice: S.num({ min: 0, max: 10_000_000 }), barcode: S.str({ max: 64 }), description: S.str({ max: 300 }), lowStockThreshold: S.int({ min: 0, max: 100000 }),
  photo: S.obj({ data: S.str({ required: true, max: 8_000_000 }), contentType: S.str({ max: 60 }) }),
};

export function registerProductRoutes({ router, store }) {
  const unitsSold = (ctx) => {
    const m = new Map();
    for (const s of ctx.col('productSales').all()) for (const i of s.items) m.set(i.productId, (m.get(i.productId) ?? 0) + i.quantity);
    return m;
  };
  const view = (p, sold) => ({
    ...p, photoUrl: p.photoFileId ? `/v5/files/${p.photoFileId}` : null, unitsSold: sold.get(p.id) ?? 0,
    lowStock: !!p.trackStock && p.quantity <= (p.lowStockThreshold ?? 0), outOfStock: !!p.trackStock && p.quantity <= 0,
  });
  const find = (ctx, id) => {
    const p = ctx.col('products').get(id);
    if (!p) throw notFound('Product not found');
    return p;
  };
  const ledger = (ctx, p, type, qty, extra = {}) => ctx.col('stockLedger').insert({ productId: p.id, type, quantity: qty, balanceAfter: p.quantity, createdById: ctx.user.id, ...extra });

  router.get('/v5/products/categories', { perm: 'products.read' }, () => PRODUCT_CATEGORIES);
  router.get('/v5/products/damage-reasons', { perm: 'products.read' }, () => DAMAGE_REASONS);

  router.get('/v5/products', { perm: 'products.read' }, (ctx) => {
    const sold = unitsSold(ctx);
    const q = (ctx.query.q ?? '').toLowerCase();
    const sorts = { mostSold: (a, b) => b.unitsSold - a.unitsSold, nameAsc: (a, b) => a.name.localeCompare(b.name), priceAsc: (a, b) => a.price - b.price, priceDesc: (a, b) => b.price - a.price };
    return ctx.col('products').all().map((p) => view(p, sold))
      .filter((p) => (ctx.query.includeInactive === 'true' || p.active !== false) && (!ctx.query.category || p.category === ctx.query.category)
        && (!ctx.query.barcode || p.barcode === ctx.query.barcode) && (!q || p.name.toLowerCase().includes(q) || (p.barcode ?? '').includes(q)) && (ctx.query.lowStock !== 'true' || p.lowStock))
      .sort(sorts[ctx.query.sort] ?? sorts.nameAsc);
  });
  router.get('/v5/products/low-stock', { perm: 'products.read' }, (ctx) => ctx.col('products').all().map((p) => view(p, new Map())).filter((p) => p.lowStock && p.active !== false));
  router.get('/v5/products/:id', { perm: 'products.read' }, (ctx) => view(find(ctx, ctx.params.id), unitsSold(ctx)));

  const barcodeFree = (ctx, code, ignoreId) => {
    if (code && ctx.col('products').findOne((p) => p.barcode === code && p.id !== ignoreId)) throw conflict('A product with this barcode already exists');
  };
  const savePhoto = (ctx, photo) => storeFile(store, { gymId: ctx.gymId, ownerId: ctx.user.id, data: photo.data, declared: photo.contentType }).id;

  router.post('/v5/products', { perm: 'products.write' }, (ctx) => {
    const b = validate({ ...PRODUCT, openingStock: S.int({ min: 0, max: 1_000_000 }), trackStock: S.bool({ default: false }) }, ctx.body);
    barcodeFree(ctx, b.barcode);
    const { photo, openingStock, ...rest } = b;
    const doc = store.tx(() => {
      const p = ctx.col('products').insert({ ...rest, active: true, quantity: rest.trackStock ? (openingStock ?? 0) : 0, lowStockThreshold: rest.lowStockThreshold ?? 0, ...(photo ? { photoFileId: savePhoto(ctx, photo) } : {}) });
      if (p.trackStock && (openingStock ?? 0) > 0) ledger(ctx, p, 'opening', openingStock);
      return p;
    });
    return created(view(doc, new Map()));
  });

  router.patch('/v5/products/:id', { perm: 'products.write' }, (ctx) => {
    const p = find(ctx, ctx.params.id);
    const b = validate(PRODUCT, ctx.body, { partial: true });
    barcodeFree(ctx, b.barcode, p.id);
    if (b.lowStockThreshold !== undefined && p.trackStock && b.lowStockThreshold > p.quantity && p.quantity > 0) throw invalid('Low stock threshold cannot be greater than stock');
    const { photo, ...rest } = b;
    return view(ctx.col('products').update(p.id, { ...rest, ...(photo ? { photoFileId: savePhoto(ctx, photo) } : {}) }), unitsSold(ctx));
  });

  router.delete('/v5/products/:id', { perm: 'products.write' }, (ctx) => {
    find(ctx, ctx.params.id);
    ctx.col('products').remove(ctx.params.id);
    return noContent();
  });

  // ---- stock ------------------------------------------------------------------------------------------------------
  router.post('/v5/products/:id/stock/track', { perm: 'products.write' }, (ctx) => {
    const p = find(ctx, ctx.params.id);
    const b = validate({ openingCount: S.int({ required: true, min: 0, max: 1_000_000 }), lowStockThreshold: S.int({ min: 0 }) }, ctx.body);
    if (p.trackStock) throw conflict('Product already has a count. Use stock correction to change it.');
    if (b.lowStockThreshold !== undefined && b.lowStockThreshold > b.openingCount) throw invalid('Low stock threshold cannot be greater than stock');
    const doc = ctx.col('products').update(p.id, { trackStock: true, quantity: b.openingCount, lowStockThreshold: b.lowStockThreshold ?? p.lowStockThreshold ?? 0 });
    ledger(ctx, doc, 'opening', b.openingCount, { reason: 'Stock tracking started' });
    return view(doc, unitsSold(ctx));
  });
  router.post('/v5/products/:id/stock/untrack', { perm: 'products.write' }, (ctx) => {
    const p = find(ctx, ctx.params.id);
    if (!p.trackStock) throw conflict('Product already has no quantity.');
    const doc = ctx.col('products').update(p.id, { trackStock: false });
    ctx.col('stockLedger').insert({ productId: p.id, type: 'untracked', quantity: 0, balanceAfter: p.quantity, createdById: ctx.user.id, reason: 'Stock tracking stopped' });
    return view(doc, unitsSold(ctx));
  });
  const needTracked = (p) => { if (!p.trackStock) throw conflict('Stock is not being tracked for this product'); };

  router.post('/v5/products/:id/stock/receive', { perm: 'products.write' }, (ctx) => {
    const p = find(ctx, ctx.params.id);
    needTracked(p);
    const b = validate({ quantity: S.int({ required: true, min: 1, max: 1_000_000 }), totalCost: S.num({ min: 0, max: 100_000_000 }), logAsExpense: S.bool({ default: false }), notes: S.str({ max: 300 }) }, ctx.body);
    if (b.logAsExpense && !(b.totalCost > 0)) throw invalid('Stock cannot be 0 when logging as expense');
    const doc = store.tx(() => {
      const next = ctx.col('products').update(p.id, { quantity: p.quantity + b.quantity });
      ledger(ctx, next, 'receive', b.quantity, { cost: b.totalCost ?? null, reason: b.notes ?? null });
      if (b.logAsExpense) ctx.col('expenses').insert({ category: 'Stock Purchase', title: `Stock added: ${p.name} x${b.quantity}`, amount: b.totalCost, date: ctx.today(), paymentType: 'cash', createdById: ctx.user.id });
      return next;
    });
    return view(doc, unitsSold(ctx));
  });
  router.post('/v5/products/:id/stock/damage', { perm: 'products.write' }, (ctx) => {
    const p = find(ctx, ctx.params.id);
    needTracked(p);
    const b = validate({ quantity: S.int({ required: true, min: 1, max: 1_000_000 }), reason: S.str({ required: true, max: 100 }), notes: S.str({ max: 300 }) }, ctx.body);
    if (b.quantity > p.quantity) throw invalid('Please enter a valid quantity, Stock is less than the entered quantity');
    const doc = store.tx(() => { const next = ctx.col('products').update(p.id, { quantity: p.quantity - b.quantity }); ledger(ctx, next, 'damage', -b.quantity, { reason: b.reason, notes: b.notes ?? null }); return next; });
    return view(doc, unitsSold(ctx));
  });
  router.post('/v5/products/:id/stock/correct', { perm: 'products.write' }, (ctx) => {
    const p = find(ctx, ctx.params.id);
    needTracked(p);
    const b = validate({ newCount: S.int({ required: true, min: 0, max: 1_000_000 }), reason: S.str({ required: true, min: 1, max: 200 }) }, ctx.body);
    const doc = store.tx(() => { const next = ctx.col('products').update(p.id, { quantity: b.newCount }); ledger(ctx, next, 'correction', b.newCount - p.quantity, { reason: b.reason }); return next; });
    return view(doc, unitsSold(ctx));
  });
  router.get('/v5/products/:id/stock/history', { perm: 'products.read' }, (ctx) => {
    find(ctx, ctx.params.id);
    return ctx.col('stockLedger').find((l) => l.productId === ctx.params.id).sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  });

  // ---- sales --------------------------------------------------------------------------------------------------------------
  const SALE = {
    memberId: S.str({ max: 64 }), guestName: S.str({ max: 80 }), notes: S.str({ max: 300 }),
    items: S.list(S.obj({ productId: S.str({ required: true }), quantity: S.int({ required: true, min: 1, max: 10000 }), price: S.num({ min: 0, max: 10_000_000 }) }), { required: true, min: 1, max: 50 }),
    discount: S.obj({ type: S.oneOf(['amount', 'percent'], { default: 'amount' }), value: S.num({ required: true, min: 0 }) }),
    payments: S.list(S.obj({ paymentType: S.oneOf(PAYMENT_TYPES, { required: true }), amount: S.num({ required: true, min: 0.01 }) }), { max: 5 }),
    amountReceived: S.num({ min: 0 }), paymentType: S.oneOf(PAYMENT_TYPES),
  };
  const saleView = (s) => ({ ...s, balance: balanceOf(s) });

  router.post('/v5/product-sales', { perm: 'products.write' }, (ctx) => {
    const b = validate(SALE, ctx.body);
    const member = b.memberId ? ctx.col('members').get(b.memberId) : null;
    if (b.memberId && !member) throw notFound('Member not found');
    const merged = new Map();
    for (const i of b.items) merged.set(i.productId, { ...i, quantity: (merged.get(i.productId)?.quantity ?? 0) + i.quantity });
    const sale = store.tx(() => {
      const lines = [];
      for (const i of merged.values()) {
        const p = ctx.col('products').get(i.productId);
        if (!p || p.active === false) throw invalid('Please select a product');
        if (p.trackStock) {
          if (p.quantity <= 0) throw invalid('Product is out of stock');
          if (i.quantity > p.quantity) throw invalid(`Stock limit exceeded for ${p.name}`);
        }
        lines.push({ productId: p.id, name: p.name, quantity: i.quantity, price: i.price ?? p.price, costPrice: p.costPrice ?? null });
      }
      const subtotal = round2(lines.reduce((s, l) => s + l.price * l.quantity, 0));
      const q = quote({ price: subtotal, discount: b.discount ? { type: b.discount.type ?? 'amount', value: b.discount.value } : null, tax: defaultTax(ctx), what: 'total' });
      const payments = normalisePayments(ctx, b);
      const paid = round2(payments.reduce((s, p) => s + p.amount, 0));
      checkReceived(paid, q.total);
      if (!member && paid < q.total) throw invalid('A walk-in sale must be paid in full. Select a member to leave a balance.');
      const invoiceNo = nextInvoiceNo(ctx);
      const doc = ctx.col('productSales').insert({
        memberId: member?.id ?? null, guestName: member ? null : (b.guestName ?? null), items: lines, subtotal: q.price, discountAmount: q.discountAmount,
        tax: { name: q.taxName, rate: q.taxRate, included: q.taxIncluded, amount: q.taxAmount, taxableValue: q.taxableValue }, total: q.total, amountReceived: 0, writtenOff: 0,
        invoiceNo, notes: b.notes ?? null, createdById: ctx.user.id, date: ctx.today(),
      });
      recordPayments(ctx, { kind: 'sale', parentCollection: 'productSales', parent: doc, memberId: member?.id ?? null, payments, date: ctx.today(), invoiceNo });
      for (const l of lines) {
        const p = ctx.col('products').get(l.productId);
        if (p.trackStock) { const next = ctx.col('products').update(p.id, { quantity: p.quantity - l.quantity }); ledger(ctx, next, 'sale', -l.quantity, { reference: doc.id }); }
      }
      return ctx.col('productSales').get(doc.id);
    });
    if (member) sendAutomated(ctx, 'PRODUCT_SALE_SUCCESS_SMS', member, { invoiceNo: sale.invoiceNo, amount: sale.total });
    return created(saleView(sale));
  });

  router.get('/v5/product-sales', { perm: 'products.read' }, (ctx) => {
    const range = resolveRange(ctx);
    const members = new Map(ctx.col('members').all().map((m) => [m.id, m]));
    const all = ctx.col('productSales').all().filter((s) => inRange(s.date, range)).filter((s) => !ctx.query.productId || s.items.some((i) => i.productId === ctx.query.productId))
      .filter((s) => !ctx.query.memberId || s.memberId === ctx.query.memberId)
      .map((s) => ({ ...saleView(s), member: s.memberId && members.get(s.memberId) ? { id: s.memberId, name: members.get(s.memberId).name } : null }))
      .sort((a, b) => b.date.localeCompare(a.date) || b.createdAt.localeCompare(a.createdAt));
    const page = Math.max(1, parseInt(ctx.query.page ?? '1', 10) || 1);
    const limit = Math.min(200, Math.max(1, parseInt(ctx.query.limit ?? '20', 10) || 20));
    return { __envelope: true, status: 200, body: { data: all.slice((page - 1) * limit, page * limit), meta: { page, limit, total: all.length, totalPages: Math.max(1, Math.ceil(all.length / limit)), totalAmount: round2(all.reduce((s, x) => s + x.total, 0)) } } };
  });
  router.get('/v5/product-sales/:id', { perm: 'products.read' }, (ctx) => {
    const s = ctx.col('productSales').get(ctx.params.id);
    if (!s) throw notFound('Sale not found');
    return saleView(s);
  });
  router.delete('/v5/product-sales/:id', { perm: 'products.write' }, (ctx) => {
    const s = ctx.col('productSales').get(ctx.params.id);
    if (!s) throw notFound('Sale not found');
    store.tx(() => {
      for (const l of s.items) {
        const p = ctx.col('products').get(l.productId);
        if (p?.trackStock) { const next = ctx.col('products').update(p.id, { quantity: p.quantity + l.quantity }); ledger(ctx, next, 'sale-reversal', l.quantity, { reference: s.id }); }
      }
      for (const t of ctx.col('transactions').find((x) => x.parentId === s.id)) ctx.col('transactions').remove(t.id);
      ctx.col('productSales').remove(s.id);
    });
    return noContent();
  });
}
