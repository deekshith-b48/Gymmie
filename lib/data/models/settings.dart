import '../../core/util/json.dart';

class SubscriptionPlanOption {
  const SubscriptionPlanOption({
    required this.id,
    required this.plan,
    required this.name,
    required this.price,
    required this.durationDays,
    this.limits = const {},
  });
  final String id;
  final String plan;
  final String name;
  final double price;
  final int durationDays;
  final Map<String, int> limits;
  factory SubscriptionPlanOption.fromJson(Json j) => SubscriptionPlanOption(
    id: j.s('id'),
    plan: j.s('plan'),
    name: j.s('name'),
    price: j.d('price'),
    durationDays: j.i('durationDays'),
    limits: {
      for (final e in (j.obj('limits') ?? {}).entries)
        e.key: (e.value as num).toInt(),
    },
  );
}

class UsageItem {
  const UsageItem({required this.used, this.limit});
  final int used;
  final int? limit;
  factory UsageItem.fromJson(Json j) =>
      UsageItem(used: j.i('used'), limit: j.intOrNull('limit'));
  double get ratio =>
      limit == null || limit == 0 ? 0 : (used / limit!).clamp(0, 1).toDouble();
}

class SubscriptionUsage {
  const SubscriptionUsage({
    required this.plans,
    required this.staff,
    required this.members,
  });
  final UsageItem plans;
  final UsageItem staff;
  final UsageItem members;
  factory SubscriptionUsage.fromJson(Json j) => SubscriptionUsage(
    plans: UsageItem.fromJson(j.obj('plans') ?? {}),
    staff: UsageItem.fromJson(j.obj('staff') ?? {}),
    members: UsageItem.fromJson(j.obj('members') ?? {}),
  );
}

class PaymentOrder {
  const PaymentOrder({
    required this.id,
    required this.status,
    required this.amount,
    this.paymentUrl,
    this.description,
    this.type,
    this.createdAt,
  });
  final String id;
  final String status; // created | paid | failed
  final double amount;
  final String? paymentUrl;
  final String? description;
  final String? type;
  final String? createdAt;
  factory PaymentOrder.fromJson(Json j) => PaymentOrder(
    id: j.s('id'),
    status: j.s('status'),
    amount: j.d('amount'),
    paymentUrl: j.str('paymentUrl'),
    description: j.str('description'),
    type: j.str('type'),
    createdAt: j.str('createdAt'),
  );
}

class FeatureItem {
  const FeatureItem({
    required this.key,
    required this.name,
    required this.description,
    required this.category,
    required this.enabled,
    required this.adminEnabled,
  });
  final String key;
  final String name;
  final String description;
  final String category;
  final bool enabled;
  final bool adminEnabled;
  factory FeatureItem.fromJson(Json j) => FeatureItem(
    key: j.s('key'),
    name: j.s('name'),
    description: j.s('description'),
    category: j.s('category'),
    enabled: j.b('enabled'),
    adminEnabled: j.b('adminEnabled'),
  );
}
