// Pricing, discount and tax rules for memberships and product sales.
import { invalid } from '../errors.js';

export const round2 = (n) => Math.round((n + Number.EPSILON) * 100) / 100;

/**
 * @param price       list price (before discount)
 * @param discount    { type: 'amount' | 'percent', value }
 * @param tax         { isIncluded, rate, name } | null
 * @param what        'plan' | 'total' (only changes the validation message, matching the app's copy)
 */
export function quote({ price, discount, tax, what = 'plan' }) {
  if (!(price >= 0)) throw invalid('Price must be zero or more');
  let discountAmount = 0;
  if (discount && discount.value) {
    if (discount.type === 'percent') {
      if (discount.value < 0 || discount.value > 100) throw invalid('Enter percentage between 1-100');
      discountAmount = round2((price * discount.value) / 100);
    } else {
      if (discount.value < 0) throw invalid('Discount cannot be negative');
      discountAmount = round2(discount.value);
    }
    if (discountAmount > price) {
      throw invalid(what === 'plan' ? 'Discount cannot be greater than plan price' : 'Discount cannot be greater than total price');
    }
  }
  const net = round2(price - discountAmount);
  let taxAmount = 0;
  let total = net;
  let taxableValue = net;
  if (tax && tax.rate > 0) {
    if (tax.isIncluded) {
      taxableValue = round2(net / (1 + tax.rate / 100));
      taxAmount = round2(net - taxableValue);
      total = net;
    } else {
      taxAmount = round2((net * tax.rate) / 100);
      total = round2(net + taxAmount);
    }
  }
  return {
    price: round2(price),
    discountType: discount?.type ?? 'amount',
    discountValue: discount?.value ?? 0,
    discountAmount,
    taxableValue,
    taxAmount,
    taxRate: tax?.rate ?? 0,
    taxName: tax?.name ?? null,
    taxIncluded: !!tax?.isIncluded,
    total,
  };
}

/** Validate the amount received against the total ("Payment received cannot exceed total"). */
export function checkReceived(amountReceived, total) {
  if (!(amountReceived >= 0)) throw invalid('Payment received is not valid.');
  if (round2(amountReceived) > round2(total)) throw invalid(`Payment received cannot exceed total (${total})`);
}
