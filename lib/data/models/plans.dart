import '../../core/util/json.dart';

class Plan {
  const Plan({
    required this.id,
    required this.name,
    required this.price,
    required this.durationDays,
    this.description,
    this.benefits = const [],
    this.groupId,
    this.groupName,
    this.sessionCount,
    this.active = true,
    this.activeMembers = 0,
  });

  final String id;
  final String name;
  final double price;
  final int durationDays;
  final String? description;
  final List<String> benefits;
  final String? groupId;
  final String? groupName;
  final int? sessionCount;
  final bool active;
  final int activeMembers;

  bool get hasSessions => sessionCount != null;

  factory Plan.fromJson(Json j) => Plan(
    id: j.s('id'),
    name: j.s('name'),
    price: j.d('price'),
    durationDays: j.i('durationDays'),
    description: j.str('description'),
    benefits: [for (final b in (j['benefits'] as List? ?? const [])) '$b'],
    groupId: j.str('groupId'),
    groupName: j.str('groupName'),
    sessionCount: j.obj('sessions')?.intOrNull('count'),
    active: j.b('active', true),
    activeMembers: j.i('activeMembers'),
  );

  String get durationLabel {
    if (durationDays % 365 == 0) {
      return '${durationDays ~/ 365} year${durationDays ~/ 365 == 1 ? '' : 's'}';
    }
    if (durationDays % 30 == 0) {
      return '${durationDays ~/ 30} month${durationDays ~/ 30 == 1 ? '' : 's'}';
    }
    return '$durationDays days';
  }
}

class PlanGroup {
  const PlanGroup({required this.id, required this.name, this.planCount = 0});
  final String id;
  final String name;
  final int planCount;
  factory PlanGroup.fromJson(Json j) =>
      PlanGroup(id: j.s('id'), name: j.s('name'), planCount: j.i('planCount'));
}

class Quote {
  const Quote({
    required this.price,
    required this.discountAmount,
    required this.taxableValue,
    required this.taxAmount,
    required this.taxRate,
    this.taxName,
    required this.taxIncluded,
    required this.total,
    required this.startDate,
    required this.endDate,
  });

  final double price;
  final double discountAmount;
  final double taxableValue;
  final double taxAmount;
  final double taxRate;
  final String? taxName;
  final bool taxIncluded;
  final double total;
  final String startDate;
  final String endDate;

  factory Quote.fromJson(Json j) => Quote(
    price: j.d('price'),
    discountAmount: j.d('discountAmount'),
    taxableValue: j.d('taxableValue'),
    taxAmount: j.d('taxAmount'),
    taxRate: j.d('taxRate'),
    taxName: j.str('taxName'),
    taxIncluded: j.b('taxIncluded'),
    total: j.d('total'),
    startDate: j.s('startDate'),
    endDate: j.s('endDate'),
  );
}

class TaxConfig {
  const TaxConfig({
    required this.id,
    required this.name,
    required this.rate,
    required this.isIncluded,
    this.taxNumber,
    this.isDefault = false,
  });
  final String id;
  final String name;
  final double rate;
  final bool isIncluded;
  final String? taxNumber;
  final bool isDefault;
  factory TaxConfig.fromJson(Json j) => TaxConfig(
    id: j.s('id'),
    name: j.s('name'),
    rate: j.d('rate'),
    isIncluded: j.b('isIncluded'),
    taxNumber: j.str('taxNumber'),
    isDefault: j.b('isDefault'),
  );
}
