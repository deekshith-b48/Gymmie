import '../../core/util/json.dart';

/// A gym a member belongs to (what the member app needs, nothing staff-side).
class MemberGym {
  const MemberGym({
    required this.id,
    required this.code,
    required this.name,
    this.city,
  });

  final String id;
  final String code;
  final String name;
  final String? city;

  factory MemberGym.fromJson(Json j) => MemberGym(
    id: j.s('id'),
    code: j.s('code'),
    name: j.s('name'),
    city: j.str('city'),
  );
}

/// Result of verifying a member's one-time code: either signed in, or the number belongs to several
/// gyms and one has to be picked ([needsGym], finished with `MemberRepository.selectGym`).
class MemberAuthResult {
  const MemberAuthResult({
    this.memberName,
    this.gym,
    this.gyms = const [],
    this.selectionToken,
  });

  final String? memberName;
  final MemberGym? gym;
  final List<MemberGym> gyms;
  final String? selectionToken;

  bool get needsGym => selectionToken != null;
}

class MembershipSummary {
  const MembershipSummary({
    required this.planName,
    required this.startDate,
    required this.endDate,
    required this.status,
    this.daysLeft,
    this.sessionsLeft,
    this.sessionsTotal,
    this.balance = 0,
  });

  final String planName;
  final String startDate;
  final String endDate;

  /// active | upcoming | paused | expired | ended
  final String status;
  final int? daysLeft;
  final int? sessionsLeft;
  final int? sessionsTotal;
  final double balance;

  factory MembershipSummary.fromJson(Json j) => MembershipSummary(
    planName: j.s('planName'),
    startDate: j.s('startDate'),
    endDate: j.s('endDate'),
    status: j.s('status'),
    daysLeft: j.intOrNull('daysLeft'),
    sessionsLeft: j.intOrNull('sessionsLeft'),
    sessionsTotal: j.intOrNull('sessionsTotal'),
    balance: j.d('balance'),
  );
}

/// `GET /v5/member/me`.
class MemberOverview {
  const MemberOverview({
    required this.id,
    required this.name,
    required this.gym,
    required this.currencySymbol,
    required this.qrPayload,
    this.mediaBase,
    this.admissionNo,
    this.membership,
    this.trainerName,
    this.visitsLast30 = 0,
    this.lastAttendedAt,
  });

  final String id;
  final String name;
  final MemberGym gym;
  final String currencySymbol;
  final String qrPayload;

  /// Where exercise pictures are served (`<base>/exercise-media/still/<file>`).
  final String? mediaBase;
  final int? admissionNo;
  final MembershipSummary? membership;
  final String? trainerName;
  final int visitsLast30;
  final String? lastAttendedAt;

  factory MemberOverview.fromJson(Json j) {
    final m = j.obj('member') ?? const <String, dynamic>{};
    final g = j.obj('gym') ?? const <String, dynamic>{};
    final ms = j.obj('membership');
    return MemberOverview(
      id: m.s('id'),
      name: m.s('name'),
      admissionNo: m.intOrNull('admissionNo'),
      gym: MemberGym.fromJson(g),
      currencySymbol: g.s('currencySymbol', '₹'),
      qrPayload: j.s('qrPayload'),
      mediaBase: j.str('mediaBase'),
      membership: ms == null ? null : MembershipSummary.fromJson(ms),
      trainerName: j.obj('trainer')?.str('name'),
      visitsLast30: j.i('visitsLast30'),
      lastAttendedAt: j.str('lastAttendedAt'),
    );
  }
}

class MembershipRecord {
  const MembershipRecord({
    this.planId,
    required this.planName,
    required this.startDate,
    required this.endDate,
    required this.status,
    this.daysLeft,
    this.sessionsLeft,
    this.sessionsTotal,
    this.total = 0,
    this.amountReceived = 0,
    this.balance = 0,
    this.invoiceNo,
    this.benefits = const [],
    this.paymentStatus = 'paid',
  });

  final String? planId;
  final String planName;
  final String startDate;
  final String endDate;
  final String status;
  final int? daysLeft;
  final int? sessionsLeft;
  final int? sessionsTotal;
  final double total;
  final double amountReceived;
  final double balance;
  final String? invoiceNo;
  final List<String> benefits;

  /// paid | partial | unpaid | free, from what the gym has recorded.
  final String paymentStatus;

  bool get isCurrent => status == 'active' || status == 'paused';

  factory MembershipRecord.fromJson(Json j) => MembershipRecord(
    planId: j.str('planId'),
    planName: j.s('planName'),
    startDate: j.s('startDate'),
    endDate: j.s('endDate'),
    status: j.s('status'),
    daysLeft: j.intOrNull('daysLeft'),
    sessionsLeft: j.intOrNull('sessionsLeft'),
    sessionsTotal: j.intOrNull('sessionsTotal'),
    total: j.d('total'),
    amountReceived: j.d('amountReceived'),
    balance: j.d('balance'),
    invoiceNo: j.str('invoiceNo'),
    benefits: [for (final b in (j['benefits'] as List? ?? const [])) '$b'],
    paymentStatus: j.s('paymentStatus', 'paid'),
  );
}

/// A plan the gym sells (what the member could renew or upgrade to).
class GymPlanInfo {
  const GymPlanInfo({this.id = '', required this.name, required this.price, required this.durationDays, this.description, this.benefits = const [], this.sessionsTotal});
  final String id;
  final String name;
  final double price;
  final int durationDays;
  final String? description;
  final List<String> benefits;
  final int? sessionsTotal;

  factory GymPlanInfo.fromJson(Json j) => GymPlanInfo(
    id: j.s('id'),
    name: j.s('name'),
    price: j.d('price'),
    durationDays: j.i('durationDays'),
    description: j.str('description'),
    benefits: [for (final b in (j['benefits'] as List? ?? const [])) '$b'],
    sessionsTotal: j.intOrNull('sessionsTotal'),
  );
}

/// `GET /v5/member/me/preferences`: what the member lets the gym send them (their own choice; the owner sees it).
class MemberPrefs {
  const MemberPrefs({this.broadcasts = true, this.updatedAt});
  final bool broadcasts;
  final String? updatedAt;
  factory MemberPrefs.fromJson(Json j) => MemberPrefs(broadcasts: j.b('broadcasts', true), updatedAt: j.str('updatedAt'));
}

/// `GET /v5/member/me/profile`: the member's own record at the gym.
class MemberProfile {
  const MemberProfile({
    required this.name,
    required this.phone,
    required this.gymName,
    required this.gymCode,
    required this.currencySymbol,
    this.email,
    this.gender,
    this.birthDate,
    this.bloodGroup,
    this.address,
    this.joinedAt,
    this.admissionNo,
    this.heightCm,
    this.weightKg,
    this.emergencyName,
    this.emergencyPhone,
    this.gymAddress,
    this.gymCity,
    this.gymPhone,
    this.gymEmail,
    this.trainerName,
    this.memberships = const [],
    this.gymPlans = const [],
    this.payments = const [],
    this.workoutPlansOn = false,
    this.dietPlansOn = false,
  });

  final String name;
  final String phone;
  final String? email;
  final String? gender;
  final String? birthDate;
  final String? bloodGroup;
  final String? address;
  final String? joinedAt;
  final int? admissionNo;
  final double? heightCm;
  final double? weightKg;
  final String? emergencyName;
  final String? emergencyPhone;
  final String gymName;
  final String gymCode;
  final String currencySymbol;
  final String? gymAddress;
  final String? gymCity;
  final String? gymPhone;
  final String? gymEmail;
  final String? trainerName;
  final List<MembershipRecord> memberships;
  final List<GymPlanInfo> gymPlans;

  /// The member's own payments and invoices, newest first.
  final List<PaymentRow> payments;

  /// What this gym has switched on for its members (read-only here).
  final bool workoutPlansOn;
  final bool dietPlansOn;

  /// The running membership, else the next one, else the most recent.
  MembershipRecord? get current {
    for (final m in memberships) {
      if (m.isCurrent) return m;
    }
    for (final m in memberships.reversed) {
      if (m.status == 'upcoming') return m;
    }
    return memberships.isEmpty ? null : memberships.first;
  }

  factory MemberProfile.fromJson(Json j) {
    final m = j.obj('member') ?? const <String, dynamic>{};
    final g = j.obj('gym') ?? const <String, dynamic>{};
    final e = m.obj('emergencyContact');
    return MemberProfile(
      name: m.s('name'),
      phone: m.s('phone'),
      email: m.str('email'),
      gender: m.str('gender'),
      birthDate: m.str('birthDate'),
      bloodGroup: m.str('bloodGroup'),
      address: m.str('address'),
      joinedAt: m.str('joinedAt'),
      admissionNo: m.intOrNull('admissionNo'),
      heightCm: m.dblOrNull('heightCm'),
      weightKg: m.dblOrNull('weightKg'),
      emergencyName: e?.str('name'),
      emergencyPhone: e?.str('phone'),
      gymName: g.s('name'),
      gymCode: g.s('code'),
      currencySymbol: g.s('currencySymbol', '₹'),
      gymAddress: g.str('address'),
      gymCity: g.str('city'),
      gymPhone: g.str('phone'),
      gymEmail: g.str('email'),
      trainerName: j.obj('trainer')?.str('name'),
      memberships: [for (final x in j.list('memberships')) MembershipRecord.fromJson(x)],
      gymPlans: [for (final x in j.list('gymPlans')) GymPlanInfo.fromJson(x)],
      payments: [for (final x in j.list('payments')) PaymentRow.fromJson(x)],
      workoutPlansOn: (g.obj('features') ?? const <String, dynamic>{}).b('workoutPlans'),
      dietPlansOn: (g.obj('features') ?? const <String, dynamic>{}).b('dietPlans'),
    );
  }
}

class Visit {
  const Visit(this.date, this.checkIn, this.checkOut, this.source);
  final String date;
  final String checkIn;
  final String? checkOut;
  final String source;
}

/// `GET /v5/member/me/attendance`.
class AttendanceSummary {
  const AttendanceSummary({this.visits = const [], this.total = 0, this.last30 = 0, this.lastAttendedAt, this.streakDays = 0});
  final List<Visit> visits;
  final int total;
  final int last30;
  final String? lastAttendedAt;
  final int streakDays;

  factory AttendanceSummary.fromJson(Json j) => AttendanceSummary(
    visits: [for (final v in j.list('visits')) Visit(v.s('date'), v.s('checkIn'), v.str('checkOut'), v.s('source', 'manual'))],
    total: j.i('total'),
    last30: j.i('last30'),
    lastAttendedAt: j.str('lastAttendedAt'),
    streakDays: j.i('streakDays'),
  );
}

/// What the trainer assigned (`GET /v5/member/me/plans`); either may be absent.
class AssignedPlans {
  const AssignedPlans({this.workout, this.diet});
  final Json? workout;
  final Json? diet;
  bool get isEmpty => workout == null && diet == null;

  factory AssignedPlans.fromJson(Json j) => AssignedPlans(workout: j.obj('workout'), diet: j.obj('diet'));
}

/// One payment or invoice line of the member's own (never staff notes).
class PaymentRow {
  const PaymentRow({required this.amount, this.date, this.paymentType, this.invoiceNo, this.planName, this.kind = 'payment'});
  final double amount;
  final String? date;
  final String? paymentType;
  final String? invoiceNo;
  final String? planName;
  final String kind;
  factory PaymentRow.fromJson(Json j) => PaymentRow(
    amount: j.d('amount'), date: j.str('date'), paymentType: j.str('paymentType'), invoiceNo: j.str('invoiceNo'), planName: j.str('planName'), kind: j.s('kind', 'payment'),
  );
}

/// `GET /v5/member/me/account`: the member's own editable profile.
class MemberAccount {
  const MemberAccount({
    required this.name,
    required this.phone,
    this.email,
    this.gender,
    this.birthDate,
    this.age,
    this.bloodGroup,
    this.address,
    this.emergencyName,
    this.emergencyPhone,
    this.heightCm,
    this.weightKg,
    this.goal,
    this.level,
    this.daysPerWeek,
    this.fitnessNotes,
    this.hasPhoto = false,
  });
  final String name;
  final String phone;
  final String? email;
  final String? gender;
  final String? birthDate;
  final int? age;
  final String? bloodGroup;
  final String? address;
  final String? emergencyName;
  final String? emergencyPhone;
  final double? heightCm;
  final double? weightKg;
  final String? goal;
  final String? level;
  final int? daysPerWeek;
  final String? fitnessNotes;
  final bool hasPhoto;

  factory MemberAccount.fromJson(Json j) {
    final e = j.obj('emergencyContact');
    final f = j.obj('fitness') ?? const <String, dynamic>{};
    return MemberAccount(
      name: j.s('name'), phone: j.s('phone'), email: j.str('email'), gender: j.str('gender'), birthDate: j.str('birthDate'), age: j.intOrNull('age'),
      bloodGroup: j.str('bloodGroup'), address: j.str('address'), emergencyName: e?.str('name'), emergencyPhone: e?.str('phone'),
      heightCm: j.dblOrNull('heightCm'), weightKg: j.dblOrNull('weightKg'), goal: f.str('goal'), level: f.str('level'),
      daysPerWeek: f.intOrNull('daysPerWeek'), fitnessNotes: f.str('notes'), hasPhoto: j.str('photoUrl') != null,
    );
  }
}

/// A signed-in phone of this member.
class DeviceSession {
  const DeviceSession({required this.id, required this.device, required this.signedInAt, required this.lastActiveAt, required this.current});
  final String id;
  final String device;
  final String signedInAt;
  final String lastActiveAt;
  final bool current;
  factory DeviceSession.fromJson(Json j) => DeviceSession(
    id: j.s('id'), device: j.s('device', 'Unknown device'), signedInAt: j.s('signedInAt'), lastActiveAt: j.s('lastActiveAt'), current: j.b('current'),
  );
}

/// A renewal, plan change or cancellation the member asked for; the gym decides.
class MembershipRequest {
  const MembershipRequest({required this.id, required this.type, required this.status, required this.createdAt, this.planName, this.note, this.decisionNote, this.decidedAt});
  final String id;
  final String type;
  final String status;
  final String createdAt;
  final String? planName;
  final String? note;
  final String? decisionNote;
  final String? decidedAt;
  bool get pending => status == 'pending';
  factory MembershipRequest.fromJson(Json j) => MembershipRequest(
    id: j.s('id'), type: j.s('type'), status: j.s('status'), createdAt: j.s('createdAt'), planName: j.str('planName'), note: j.str('note'),
    decisionNote: j.str('decisionNote'), decidedAt: j.str('decidedAt'),
  );
}

/// What a trainer may see, and whether the member shares a training summary.
class PrivacySettings {
  const PrivacySettings({this.trainerCanSee = const {'email': true, 'birthDate': true, 'address': true, 'emergencyContact': true, 'health': true}, this.shareTraining = 'off'});
  final Map<String, bool> trainerCanSee;
  final String shareTraining;
  factory PrivacySettings.fromJson(Json j) {
    final t = j.obj('trainerCanSee') ?? const <String, dynamic>{};
    return PrivacySettings(
      trainerCanSee: {for (final k in const ['email', 'birthDate', 'address', 'emergencyContact', 'health']) k: t.b(k, true)},
      shareTraining: j.s('shareTraining', 'off'),
    );
  }
}

/// The optional notices the member can switch, and the ones they cannot.
class NotificationSettings {
  const NotificationSettings({this.announcements = true, this.expiryOn = true, this.expiryDaysBefore = 7, this.mandatory = const []});
  final bool announcements;
  final bool expiryOn;
  final int expiryDaysBefore;
  final List<String> mandatory;
  factory NotificationSettings.fromJson(Json j) {
    final e = j.obj('membershipExpiry') ?? const <String, dynamic>{};
    return NotificationSettings(
      announcements: (j.obj('announcements') ?? const <String, dynamic>{}).b('on', true), expiryOn: e.b('on', true),
      expiryDaysBefore: e.i('daysBefore', 7), mandatory: j.strings('mandatory'),
    );
  }
}
