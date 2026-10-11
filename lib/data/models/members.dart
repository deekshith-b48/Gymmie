import '../../core/util/json.dart';

class LabelRef {
  const LabelRef({
    required this.id,
    required this.name,
    this.color = '#061750',
  });
  final String id;
  final String name;
  final String color;
  factory LabelRef.fromJson(Json j) => LabelRef(
    id: j.s('id'),
    name: j.s('name'),
    color: j.s('color', '#061750'),
  );
}

class MembershipInfo {
  const MembershipInfo({
    required this.id,
    required this.planId,
    required this.planName,
    required this.startDate,
    required this.endDate,
    required this.status,
    this.daysLeft,
    this.sessionsLeft,
    this.sessionsTotal,
    this.balance = 0,
    this.upcomingCount = 0,
  });

  final String id;
  final String planId;
  final String planName;
  final String startDate;
  final String endDate;
  final String status; // active | upcoming | paused | expired | ended
  final int? daysLeft;
  final int? sessionsLeft;
  final int? sessionsTotal;
  final double balance;
  final int upcomingCount;

  bool get isActive => status == 'active';
  bool get isRunning => status == 'active' || status == 'paused';

  factory MembershipInfo.fromJson(Json j) => MembershipInfo(
    id: j.s('id'),
    planId: j.s('planId'),
    planName: j.s('planName'),
    startDate: j.s('startDate'),
    endDate: j.s('endDate'),
    status: j.s('status'),
    daysLeft: j.intOrNull('daysLeft'),
    sessionsLeft: j.intOrNull('sessionsLeft'),
    sessionsTotal: j.intOrNull('sessionsTotal'),
    balance: j.d('balance'),
    upcomingCount: j.i('upcomingCount'),
  );
}

class MemberSummary {
  const MemberSummary({
    required this.id,
    required this.admissionNo,
    required this.name,
    required this.phone,
    this.email,
    this.gender,
    this.birthDate,
    this.bloodGroup,
    required this.joinedAt,
    this.blocked = false,
    this.blockedReason,
    this.photoUrl,
    this.labels = const [],
    this.trainerId,
    this.trainerName,
    this.membership,
    this.balance = 0,
    this.balanceReminder,
    this.lastAttendedAt,
    this.parqSigned = false,
    this.hasAccessCode = false,
    this.accessCodeIssuedAt,
    this.accessCode,
  });

  final String id;
  final int admissionNo;
  final String name;
  final String phone;
  final String? email;
  final String? gender;
  final String? birthDate;
  final String? bloodGroup;
  final String joinedAt;
  final bool blocked;
  final String? blockedReason;
  final String? photoUrl;
  final List<LabelRef> labels;
  final String? trainerId;
  final String? trainerName;
  final MembershipInfo? membership;
  final double balance;
  final String? balanceReminder;
  final String? lastAttendedAt;
  final bool parqSigned;

  /// Whether the member has a working access code, and when it was issued. The code itself is only in the answer to creating a member.
  final bool hasAccessCode;
  final String? accessCodeIssuedAt;
  final String? accessCode;

  factory MemberSummary.fromJson(Json j) {
    final tr = j.obj('trainer');
    final ms = j.obj('membership');
    return MemberSummary(
      id: j.s('id'),
      admissionNo: j.i('admissionNo'),
      name: j.s('name'),
      phone: j.s('phone'),
      email: j.str('email'),
      gender: j.str('gender'),
      birthDate: j.str('birthDate'),
      bloodGroup: j.str('bloodGroup'),
      joinedAt: j.s('joinedAt'),
      blocked: j.b('blocked'),
      blockedReason: j.str('blockedReason'),
      photoUrl: j.str('photoUrl'),
      labels: j.list('labels').map(LabelRef.fromJson).toList(),
      trainerId: tr?.str('id'),
      trainerName: tr?.str('name'),
      membership: ms == null ? null : MembershipInfo.fromJson(ms),
      balance: j.d('balance'),
      balanceReminder: j.str('balanceReminder'),
      lastAttendedAt: j.str('lastAttendedAt'),
      parqSigned: j.b('parqSigned'),
      hasAccessCode: j.b('hasAccessCode'),
      accessCodeIssuedAt: j.str('accessCodeIssuedAt'),
      accessCode: j.str('accessCode'),
    );
  }
}

class Membership {
  const Membership({
    required this.id,
    required this.memberId,
    required this.planId,
    required this.planName,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.kind,
    required this.total,
    required this.subtotal,
    required this.amountReceived,
    required this.balance,
    this.discountAmount = 0,
    this.taxAmount = 0,
    this.taxName,
    this.taxRate = 0,
    this.taxIncluded = false,
    this.sessionsTotal,
    this.sessionsLeft,
    this.sessionLogs = const [],
    this.pausedAt,
    this.pausedDays = 0,
    this.extensions = const [],
    this.invoiceNo,
    this.notes,
    this.daysLeft,
    this.previousPlanName,
    this.writtenOff = 0,
  });

  final String id;
  final String memberId;
  final String planId;
  final String planName;
  final String startDate;
  final String endDate;
  final String status;
  final String kind;
  final double total;
  final double subtotal;
  final double amountReceived;
  final double balance;
  final double discountAmount;
  final double taxAmount;
  final String? taxName;
  final double taxRate;
  final bool taxIncluded;
  final int? sessionsTotal;
  final int? sessionsLeft;
  final List<Json> sessionLogs;
  final String? pausedAt;
  final int pausedDays;
  final List<Json> extensions;
  final String? invoiceNo;
  final String? notes;
  final int? daysLeft;
  final String? previousPlanName;
  final double writtenOff;

  bool get isActive => status == 'active';
  bool get hasSessions => sessionsTotal != null;

  factory Membership.fromJson(Json j) {
    final tax = j.obj('tax') ?? const {};
    final disc = j.obj('discount') ?? const {};
    final sess = j.obj('sessions');
    return Membership(
      id: j.s('id'),
      memberId: j.s('memberId'),
      planId: j.s('planId'),
      planName: j.s('planName'),
      startDate: j.s('startDate'),
      endDate: j.s('endDate'),
      status: j.s('status'),
      kind: j.s('kind', 'new'),
      total: j.d('total'),
      subtotal: j.d('subtotal'),
      amountReceived: j.d('amountReceived'),
      balance: j.d('balance'),
      discountAmount: disc.d('amount'),
      taxAmount: tax.d('amount'),
      taxName: tax.str('name'),
      taxRate: tax.d('rate'),
      taxIncluded: tax.b('included'),
      sessionsTotal: sess?.intOrNull('total'),
      sessionsLeft: j.intOrNull('sessionsLeft'),
      sessionLogs: j.list('sessionLogs'),
      pausedAt: j.str('pausedAt'),
      pausedDays: j.i('pausedDays'),
      extensions: j.list('extensions'),
      invoiceNo: j.str('invoiceNo'),
      notes: j.str('notes'),
      daysLeft: j.intOrNull('daysLeft'),
      previousPlanName: j.str('previousPlanName'),
      writtenOff: j.d('writtenOff'),
    );
  }
}

class HealthSummary {
  const HealthSummary({
    this.weightKg,
    this.heightCm,
    this.bmi,
    this.bmiCategory,
    this.weightTrend = const [],
    this.conditions = const [],
  });

  final double? weightKg;
  final double? heightCm;
  final double? bmi;
  final String? bmiCategory;
  final List<({String date, double value})> weightTrend;
  final List<HealthCondition> conditions;

  factory HealthSummary.fromJson(Json j) => HealthSummary(
    weightKg: j.dblOrNull('weightKg'),
    heightCm: j.dblOrNull('heightCm'),
    bmi: j.dblOrNull('bmi'),
    bmiCategory: j.str('bmiCategory'),
    weightTrend: [
      for (final t in j.list('weightTrend'))
        (date: t.s('date'), value: t.d('value')),
    ],
    conditions: j.list('conditions').map(HealthCondition.fromJson).toList(),
  );
}

class HealthCondition {
  const HealthCondition({required this.id, required this.name, this.notes});
  final String id;
  final String name;
  final String? notes;
  factory HealthCondition.fromJson(Json j) =>
      HealthCondition(id: j.s('id'), name: j.s('name'), notes: j.str('notes'));
}

class RiskReason {
  const RiskReason({required this.code, required this.label, this.detail});
  final String code;
  final String label;
  final String? detail;
  factory RiskReason.fromJson(Json j) => RiskReason(
    code: j.s('code'),
    label: j.s('label'),
    detail: j.str('detail'),
  );
}

class MemberDetail {
  const MemberDetail({
    required this.summary,
    this.address,
    this.notes,
    this.emergencyName,
    this.emergencyPhone,
    this.idCardUrl,
    this.memberships = const [],
    this.recentTransactions = const [],
    this.health = const HealthSummary(),
    this.visitsLast30 = 0,
    this.visitsTotal = 0,
    this.atRisk = const [],
    this.heightCm,
    this.weightKg,
    this.appEnabled = false,
    this.appLastSeenAt,
    this.appSignIns = 0,
    this.appBroadcasts = true,
    this.appClosedAt,
    this.appInvitedAt,
    this.pendingRequests = 0,
  });

  final MemberSummary summary;
  final String? address;
  final String? notes;
  final String? emergencyName;
  final String? emergencyPhone;
  final String? idCardUrl;
  final List<Membership> memberships;
  final List<Json> recentTransactions;
  final HealthSummary health;
  final int visitsLast30;
  final int visitsTotal;
  final List<RiskReason> atRisk;
  final double? heightCm;
  final double? weightKg;

  /// Whether the member app is switched on for this gym, when this member last opened it, and how often.
  final bool appEnabled;
  final String? appLastSeenAt;
  final int appSignIns;

  /// The member's own choice in the app: whether the gym's promotional broadcasts may reach them.
  final bool appBroadcasts;

  /// Set when the member closed their own app account (the gym can reopen it); when they were last invited; and how
  /// many renewal / plan-change / cancellation requests wait for a decision.
  final String? appClosedAt;
  final String? appInvitedAt;
  final int pendingRequests;

  factory MemberDetail.fromJson(Json j) {
    final em = j.obj('emergencyContact');
    final att = j.obj('attendance') ?? const {};
    return MemberDetail(
      summary: MemberSummary.fromJson(j),
      address: j.str('address'),
      notes: j.str('notes'),
      emergencyName: em?.str('name'),
      emergencyPhone: em?.str('phone'),
      idCardUrl: j.str('idCardUrl'),
      memberships: j.list('memberships').map(Membership.fromJson).toList(),
      recentTransactions: j.list('recentTransactions'),
      health: HealthSummary.fromJson(j.obj('health') ?? const {}),
      visitsLast30: att.i('last30Days'),
      visitsTotal: att.i('total'),
      atRisk: j.list('atRisk').map(RiskReason.fromJson).toList(),
      appEnabled: (j.obj('memberApp') ?? const {}).b('enabled'),
      appLastSeenAt: (j.obj('memberApp') ?? const {}).str('lastSeenAt'),
      appSignIns: (j.obj('memberApp') ?? const {}).i('signIns'),
      appBroadcasts: (j.obj('memberApp') ?? const {}).b('broadcasts', true),
      appClosedAt: (j.obj('memberApp') ?? const {}).str('closedAt'),
      appInvitedAt: (j.obj('memberApp') ?? const {}).str('invitedAt'),
      pendingRequests: (j.obj('memberApp') ?? const {}).i('pendingRequests'),
    );
  }
}

/// A member's request to renew, change plan or cancel, as the gym sees it.
class MembershipRequestRow {
  const MembershipRequestRow({
    required this.id,
    required this.type,
    required this.status,
    required this.createdAt,
    required this.memberId,
    required this.memberName,
    this.memberPhone,
    this.planName,
    this.note,
    this.decisionNote,
    this.currentPlan,
    this.currentEnd,
  });
  final String id;
  final String type;
  final String status;
  final String createdAt;
  final String memberId;
  final String memberName;
  final String? memberPhone;
  final String? planName;
  final String? note;
  final String? decisionNote;
  final String? currentPlan;
  final String? currentEnd;
  bool get pending => status == 'pending';
  String get typeLabel => switch (type) {
    'renew' => 'Renewal',
    'change_plan' => 'Plan change',
    'cancel' => 'Cancellation',
    _ => type,
  };

  factory MembershipRequestRow.fromJson(Json j) {
    final m = j.obj('member') ?? const <String, dynamic>{};
    final c = j.obj('currentMembership');
    return MembershipRequestRow(
      id: j.s('id'),
      type: j.s('type'),
      status: j.s('status'),
      createdAt: j.s('createdAt'),
      memberId: m.s('id'),
      memberName: m.s('name', 'Member'),
      memberPhone: m.str('phone'),
      planName: j.str('planName'),
      note: j.str('note'),
      decisionNote: j.str('decisionNote'),
      currentPlan: c?.str('planName'),
      currentEnd: c?.str('endDate'),
    );
  }
}
