import '../../core/util/json.dart';

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    this.costPrice,
    this.barcode,
    this.description,
    this.trackStock = false,
    this.quantity = 0,
    this.lowStockThreshold = 0,
    this.active = true,
    this.photoUrl,
    this.unitsSold = 0,
    this.lowStock = false,
    this.outOfStock = false,
  });

  final String id;
  final String name;
  final String category;
  final double price;
  final double? costPrice;
  final String? barcode;
  final String? description;
  final bool trackStock;
  final int quantity;
  final int lowStockThreshold;
  final bool active;
  final String? photoUrl;
  final int unitsSold;
  final bool lowStock;
  final bool outOfStock;

  factory Product.fromJson(Json j) => Product(
    id: j.s('id'),
    name: j.s('name'),
    category: j.s('category', 'Other'),
    price: j.d('price'),
    costPrice: j.dblOrNull('costPrice'),
    barcode: j.str('barcode'),
    description: j.str('description'),
    trackStock: j.b('trackStock'),
    quantity: j.i('quantity'),
    lowStockThreshold: j.i('lowStockThreshold'),
    active: j.b('active', true),
    photoUrl: j.str('photoUrl'),
    unitsSold: j.i('unitsSold'),
    lowStock: j.b('lowStock'),
    outOfStock: j.b('outOfStock'),
  );
}

class SaleItem {
  const SaleItem({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.price,
  });
  final String productId;
  final String name;
  final int quantity;
  final double price;
  factory SaleItem.fromJson(Json j) => SaleItem(
    productId: j.s('productId'),
    name: j.s('name'),
    quantity: j.i('quantity'),
    price: j.d('price'),
  );
}

class Sale {
  const Sale({
    required this.id,
    required this.invoiceNo,
    this.memberId,
    this.memberName,
    this.guestName,
    required this.items,
    required this.subtotal,
    required this.discountAmount,
    required this.total,
    required this.amountReceived,
    required this.balance,
    required this.date,
  });
  final String id;
  final String invoiceNo;
  final String? memberId;
  final String? memberName;
  final String? guestName;
  final List<SaleItem> items;
  final double subtotal;
  final double discountAmount;
  final double total;
  final double amountReceived;
  final double balance;
  final String date;
  factory Sale.fromJson(Json j) => Sale(
    id: j.s('id'),
    invoiceNo: j.s('invoiceNo'),
    memberId: j.str('memberId'),
    memberName: j.obj('member')?.str('name'),
    guestName: j.str('guestName'),
    items: j.list('items').map(SaleItem.fromJson).toList(),
    subtotal: j.d('subtotal'),
    discountAmount: j.d('discountAmount'),
    total: j.d('total'),
    amountReceived: j.d('amountReceived'),
    balance: j.d('balance'),
    date: j.s('date'),
  );
}

class StockEntry {
  const StockEntry({
    required this.type,
    required this.quantity,
    required this.balanceAfter,
    this.reason,
    required this.createdAt,
  });
  final String type;
  final int quantity;
  final int balanceAfter;
  final String? reason;
  final String createdAt;
  factory StockEntry.fromJson(Json j) => StockEntry(
    type: j.s('type'),
    quantity: j.i('quantity'),
    balanceAfter: j.i('balanceAfter'),
    reason: j.str('reason'),
    createdAt: j.s('createdAt'),
  );
}
