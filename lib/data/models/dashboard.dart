import '../../core/util/json.dart';

class OccupancySnapshot {
  const OccupancySnapshot({
    this.liveCount = 0,
    this.todayCount = 0,
    this.peakHour,
    this.peakCheckIns = 0,
    this.hours = const [],
    this.devicesTotal = 0,
    this.devicesConnected = 0,
    this.hasDevice = false,
  });

  final int liveCount;
  final int todayCount;
  final int? peakHour;
  final int peakCheckIns;
  final List<int> hours;
  final int devicesTotal;
  final int devicesConnected;
  final bool hasDevice;

  factory OccupancySnapshot.fromJson(Json j) {
    final peak = j.obj('peakToday');
    final dev = j.obj('devices') ?? const {};
    return OccupancySnapshot(
      liveCount: j.i('liveCount'),
      todayCount: j.i('todayCount'),
      peakHour: peak?.intOrNull('hour'),
      peakCheckIns: peak?.i('checkIns') ?? 0,
      hours: [for (final h in j.list('hours')) h.i('checkIns')],
      devicesTotal: dev.i('total'),
      devicesConnected: dev.i('connected'),
      hasDevice: j.b('hasBiometricDevice'),
    );
  }
}

class BirthdayItem {
  const BirthdayItem({
    required this.id,
    required this.name,
    required this.phone,
    this.age,
    this.photoUrl,
  });
  final String id;
  final String name;
  final String phone;
  final int? age;
  final String? photoUrl;
  factory BirthdayItem.fromJson(Json j) => BirthdayItem(
    id: j.s('id'),
    name: j.s('name'),
    phone: j.s('phone'),
    age: j.intOrNull('age'),
    photoUrl: j.str('photoUrl'),
  );
}

class ReminderItem {
  const ReminderItem({
    required this.id,
    required this.memberId,
    required this.name,
    required this.phone,
    required this.reminderDate,
    required this.balance,
    this.notes,
  });
  final String id;
  final String memberId;
  final String name;
  final String phone;
  final String reminderDate;
  final double balance;
  final String? notes;
  factory ReminderItem.fromJson(Json j) {
    final m = j.obj('member') ?? const {};
    return ReminderItem(
      id: j.s('id'),
      memberId: j.s('memberId'),
      name: m.s('name'),
      phone: m.s('phone'),
      reminderDate: j.s('reminderDate'),
      balance: j.d('balance'),
      notes: j.str('notes'),
    );
  }
}

class DashboardSummary {
  const DashboardSummary({
    required this.today,
    this.activeMembers = 0,
    this.allMembers = 0,
    this.atRisk,
    this.expiring10 = 0,
    this.expiring30 = 0,
    this.leadsToday = 0,
    this.leadsTotal = 0,
    this.attendanceToday = 0,
    this.attendanceWeek = 0,
    this.attendanceMonth = 0,
    this.balanceTotal = 0,
    this.balanceMembers = 0,
    this.reminders = const [],
    this.birthdays = const [],
    this.newMembersThisMonth = 0,
    this.subscriptionDaysLeft,
    this.subscriptionExpired = false,
    this.credits = 0,
    this.whatsappEnabled = false,
    this.occupancy = const OccupancySnapshot(),
  });

  final String today;
  final int activeMembers;
  final int allMembers;
  final int? atRisk;
  final int expiring10;
  final int expiring30;
  final int leadsToday;
  final int leadsTotal;
  final int attendanceToday;
  final int attendanceWeek;
  final int attendanceMonth;
  final double balanceTotal;
  final int balanceMembers;
  final List<ReminderItem> reminders;
  final List<BirthdayItem> birthdays;
  final int newMembersThisMonth;
  final int? subscriptionDaysLeft;
  final bool subscriptionExpired;
  final int credits;
  final bool whatsappEnabled;
  final OccupancySnapshot occupancy;

  factory DashboardSummary.fromJson(Json j) {
    final t = j.obj('tiles') ?? const {};
    final a = j.obj('attendance') ?? const {};
    final b = j.obj('balance') ?? const {};
    final sub = j.obj('subscription');
    return DashboardSummary(
      today: j.s('today'),
      activeMembers: t.i('activeMembers'),
      allMembers: t.i('allMembers'),
      atRisk: t.intOrNull('atRisk'),
      expiring10: t.i('expiring10'),
      expiring30: t.i('expiring30'),
      leadsToday: t.i('leadsToday'),
      leadsTotal: t.i('leadsTotal'),
      attendanceToday: a.i('today'),
      attendanceWeek: a.i('week'),
      attendanceMonth: a.i('month'),
      balanceTotal: b.d('total'),
      balanceMembers: b.i('members'),
      reminders: j.list('balanceReminders').map(ReminderItem.fromJson).toList(),
      birthdays: j.list('birthdays').map(BirthdayItem.fromJson).toList(),
      newMembersThisMonth: j.i('newMembersThisMonth'),
      subscriptionDaysLeft: sub?.intOrNull('daysLeft'),
      subscriptionExpired: sub?.b('expired') ?? false,
      credits: j.i('credits'),
      whatsappEnabled: (j.obj('whatsapp') ?? const {}).b('enabled'),
      occupancy: OccupancySnapshot.fromJson(j.obj('occupancy') ?? const {}),
    );
  }
}

class Insight {
  const Insight({
    required this.code,
    required this.severity,
    required this.title,
    required this.detail,
    this.count = 0,
    this.memberIds = const [],
  });
  final String code;
  final String severity;
  final String title;
  final String detail;
  final int count;
  final List<String> memberIds;
  factory Insight.fromJson(Json j) => Insight(
    code: j.s('code'),
    severity: j.s('severity', 'info'),
    title: j.s('title'),
    detail: j.s('detail'),
    count: j.i('count'),
    memberIds: j.strings('memberIds'),
  );
}

class QuickReport {
  const QuickReport({
    required this.from,
    required this.to,
    required this.revenue,
    required this.membershipRevenue,
    required this.salesRevenue,
    required this.expenses,
    required this.net,
    required this.newMembers,
    required this.outstanding,
    this.byPlan = const [],
    this.byProduct = const [],
    this.byCategory = const [],
    this.byPayment = const [],
    this.prevRevenue = 0,
    this.prevExpenses = 0,
    this.prevNet = 0,
    this.prevNewMembers = 0,
  });

  final String from;
  final String to;
  final double revenue;
  final double membershipRevenue;
  final double salesRevenue;
  final double expenses;
  final double net;
  final int newMembers;
  final double outstanding;
  final List<Json> byPlan;
  final List<Json> byProduct;
  final List<Json> byCategory;
  final List<Json> byPayment;
  final double prevRevenue;
  final double prevExpenses;
  final double prevNet;
  final int prevNewMembers;

  factory QuickReport.fromJson(Json j) {
    final r = j.obj('range') ?? const {};
    final p = j.obj('previous') ?? const {};
    return QuickReport(
      from: r.s('from'),
      to: r.s('to'),
      revenue: j.d('revenue'),
      membershipRevenue: j.d('membershipRevenue'),
      salesRevenue: j.d('salesRevenue'),
      expenses: j.d('expenses'),
      net: j.d('net'),
      newMembers: j.i('newMembers'),
      outstanding: j.d('outstandingBalance'),
      byPlan: j.list('membershipsByPlan'),
      byProduct: j.list('salesByProduct'),
      byCategory: j.list('expensesByCategory'),
      byPayment: j.list('revenueByPaymentType'),
      prevRevenue: p.d('revenue'),
      prevExpenses: p.d('expenses'),
      prevNet: p.d('net'),
      prevNewMembers: p.i('newMembers'),
    );
  }
}
