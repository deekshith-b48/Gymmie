import '../../core/util/json.dart';

class StaffMember {
  const StaffMember({
    required this.userId,
    required this.name,
    this.phone,
    this.email,
    required this.role,
    required this.status,
    this.photoUrl,
    this.memberCount,
  });
  final String userId;
  final String name;
  final String? phone;
  final String? email;
  final String role;
  final String status; // active | invited
  final String? photoUrl;
  final int? memberCount;

  bool get invited => status == 'invited';
  factory StaffMember.fromJson(Json j) => StaffMember(
    userId: j.s('userId'),
    name: j.s('name'),
    phone: j.str('phone'),
    email: j.str('email'),
    role: j.s('role'),
    status: j.s('status', 'active'),
    photoUrl: j.str('photoUrl'),
    memberCount: j.intOrNull('memberCount'),
  );
}

class Txn {
  const Txn({
    required this.id,
    required this.kind,
    required this.kindLabel,
    this.memberId,
    this.memberName,
    this.memberPhone,
    required this.amount,
    required this.paymentType,
    required this.date,
    this.invoiceNo,
    this.description,
    this.createdByName,
    this.notes,
    this.parentId,
    this.parentCollection,
  });

  final String id;
  final String kind; // membership | sale | settlement | writeoff
  final String kindLabel;
  final String? memberId;
  final String? memberName;
  final String? memberPhone;
  final double amount;
  final String paymentType;
  final String date;
  final String? invoiceNo;
  final String? description;
  final String? createdByName;
  final String? notes;
  final String? parentId;
  final String? parentCollection;

  bool get isWriteOff => kind == 'writeoff';

  factory Txn.fromJson(Json j) {
    final m = j.obj('member');
    return Txn(
      id: j.s('id'),
      kind: j.s('kind'),
      kindLabel: j.s('kindLabel', j.s('kind')),
      memberId: j.str('memberId'),
      memberName: m?.str('name'),
      memberPhone: m?.str('phone'),
      amount: j.d('amount'),
      paymentType: j.s('paymentType', 'cash'),
      date: j.s('date'),
      invoiceNo: j.str('invoiceNo'),
      description: j.str('description'),
      createdByName: j.obj('createdBy')?.str('name'),
      notes: j.str('notes'),
      parentId: j.str('parentId'),
      parentCollection: j.str('parentCollection'),
    );
  }
}

class BalanceItem {
  const BalanceItem({
    required this.memberId,
    required this.name,
    required this.phone,
    required this.balance,
    this.oldestDueDate,
    this.reminderDate,
  });
  final String memberId;
  final String name;
  final String phone;
  final double balance;
  final String? oldestDueDate;
  final String? reminderDate;
  factory BalanceItem.fromJson(Json j) => BalanceItem(
    memberId: j.s('memberId'),
    name: j.s('name'),
    phone: j.s('phone'),
    balance: j.d('balance'),
    oldestDueDate: j.str('oldestDueDate'),
    reminderDate: j.str('reminderDate'),
  );
}

class BalanceSummary {
  const BalanceSummary({
    required this.total,
    required this.members,
    required this.items,
  });
  final double total;
  final int members;
  final List<BalanceItem> items;
  factory BalanceSummary.fromJson(Json j) => BalanceSummary(
    total: j.d('totalBalance'),
    members: j.i('membersWithBalance'),
    items: j.list('items').map(BalanceItem.fromJson).toList(),
  );
}

class BalanceReminder {
  const BalanceReminder({
    required this.id,
    required this.memberId,
    required this.name,
    required this.phone,
    required this.reminderDate,
    this.notes,
    this.done = false,
    this.overdue = false,
    this.balance = 0,
  });
  final String id;
  final String memberId;
  final String name;
  final String phone;
  final String reminderDate;
  final String? notes;
  final bool done;
  final bool overdue;
  final double balance;
  factory BalanceReminder.fromJson(Json j) {
    final m = j.obj('member') ?? const {};
    return BalanceReminder(
      id: j.s('id'),
      memberId: j.s('memberId'),
      name: m.s('name'),
      phone: m.s('phone'),
      reminderDate: j.s('reminderDate'),
      notes: j.str('notes'),
      done: j.b('done'),
      overdue: j.b('overdue'),
      balance: j.d('balance'),
    );
  }
}

class InvoiceData {
  InvoiceData(this.j);
  final Json j;
  String get invoiceNo => j.s('invoiceNo');
  String get type => j.s('type');
  String get date => j.s('date');
  Json get gym => j.obj('gym') ?? const {};
  Json? get member => j.obj('member');
  List<Json> get items => j.list('items');
  double get subtotal => j.d('subtotal');
  double get discount => j.d('discount');
  Json? get tax => j.obj('tax');
  double get total => j.d('total');
  double get received => j.d('amountReceived');
  double get writtenOff => j.d('writtenOff');
  double get balance => j.d('balance');
  List<Json> get payments => j.list('payments');
}

class Expense {
  const Expense({
    required this.id,
    required this.category,
    this.title,
    required this.amount,
    required this.date,
    required this.paymentType,
    this.notes,
    this.vendor,
    this.labelIds = const [],
  });
  final String id;
  final String category;
  final String? title;
  final double amount;
  final String date;
  final String paymentType;
  final String? notes;
  final String? vendor;
  final List<String> labelIds;
  factory Expense.fromJson(Json j) => Expense(
    id: j.s('id'),
    category: j.s('category'),
    title: j.str('title'),
    amount: j.d('amount'),
    date: j.s('date'),
    paymentType: j.s('paymentType', 'cash'),
    notes: j.str('notes'),
    vendor: j.str('vendor'),
    labelIds: j.strings('labelIds'),
  );
}

class AttendanceLog {
  const AttendanceLog({
    required this.id,
    required this.kind,
    this.memberId,
    this.name,
    this.phone,
    this.photoUrl,
    required this.date,
    required this.checkIn,
    this.checkOut,
    required this.source,
  });
  final String id;
  final String kind;
  final String? memberId;
  final String? name;
  final String? phone;
  final String? photoUrl;
  final String date;
  final String checkIn;
  final String? checkOut;
  final String source;
  factory AttendanceLog.fromJson(Json j) {
    final m = j.obj('member');
    return AttendanceLog(
      id: j.s('id'),
      kind: j.s('kind', 'member'),
      memberId: j.str('memberId'),
      name: m?.str('name') ?? j.str('guestName'),
      phone: m?.str('phone') ?? j.str('guestPhone'),
      photoUrl: m?.str('photoUrl'),
      date: j.s('date'),
      checkIn: j.s('checkIn'),
      checkOut: j.str('checkOut'),
      source: j.s('source', 'manual'),
    );
  }
}

String paymentTypeLabel(String t) => switch (t) {
  'cash' => 'Cash',
  'upi' => 'UPI',
  'creditCard' => 'Credit card',
  'debitCard' => 'Debit card',
  'netBanking' => 'Net banking',
  'cheque' => 'Cheque',
  'wallet' => 'Wallet',
  _ => 'Other',
};

const allPaymentTypes = [
  'cash',
  'upi',
  'debitCard',
  'creditCard',
  'netBanking',
  'cheque',
  'wallet',
  'other',
];
