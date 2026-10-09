import '../../core/util/json.dart';
import 'members.dart';

class Lead {
  const Lead({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    this.gender,
    required this.source,
    required this.chanceOfJoining,
    this.followUpDate,
    this.notes,
    this.disabled = false,
    this.interestedPlanId,
    this.photoUrl,
    this.labels = const [],
    required this.createdAt,
    this.lastContactedAt,
  });

  final String id;
  final String name;
  final String phone;
  final String? email;
  final String? gender;
  final String source;
  final String chanceOfJoining; // Low | Medium | High
  final String? followUpDate;
  final String? notes;
  final bool disabled;
  final String? interestedPlanId;
  final String? photoUrl;
  final List<LabelRef> labels;
  final String createdAt;
  final String? lastContactedAt;

  factory Lead.fromJson(Json j) => Lead(
    id: j.s('id'),
    name: j.s('name'),
    phone: j.s('phone'),
    email: j.str('email'),
    gender: j.str('gender'),
    source: j.s('source', 'Walk-in'),
    chanceOfJoining: j.s('chanceOfJoining', 'Medium'),
    followUpDate: j.str('followUpDate'),
    notes: j.str('notes'),
    disabled: j.b('disabled'),
    interestedPlanId: j.str('interestedPlanId'),
    photoUrl: j.str('photoUrl'),
    labels: j.list('labels').map(LabelRef.fromJson).toList(),
    createdAt: j.s('createdAt'),
    lastContactedAt: j.str('lastContactedAt'),
  );
}

const leadSources = [
  'Walk-in',
  'Social Media',
  'Friend',
  'Existing Member',
  'Google',
  'Campaign',
  'Other',
];
const leadChances = ['Low', 'Medium', 'High'];
