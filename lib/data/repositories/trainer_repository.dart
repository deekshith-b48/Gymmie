import '../../core/network/api_client.dart';
import '../../core/util/json.dart';

class WorkDay {
  WorkDay({
    required this.day,
    required this.enabled,
    required this.start,
    required this.end,
  });
  final int day; // 0 = Sunday
  bool enabled;
  String start;
  String end;
  factory WorkDay.fromJson(Json j) => WorkDay(
    day: j.i('day'),
    enabled: j.b('enabled'),
    start: j.s('start', '06:00'),
    end: j.s('end', '21:00'),
  );
  Json toJson() => {'day': day, 'enabled': enabled, 'start': start, 'end': end};
}

class Booking {
  const Booking({
    required this.id,
    required this.trainerId,
    required this.memberId,
    required this.memberName,
    this.memberPhone,
    required this.date,
    required this.start,
    required this.end,
    required this.status,
  });
  final String id;
  final String trainerId;
  final String memberId;
  final String memberName;
  final String? memberPhone;
  final String date;
  final String start;
  final String end;
  final String status;
  factory Booking.fromJson(Json j) {
    final m = j.obj('member');
    return Booking(
      id: j.s('id'),
      trainerId: j.s('trainerId'),
      memberId: j.s('memberId'),
      memberName: m?.s('name') ?? 'Member',
      memberPhone: m?.str('phone'),
      date: j.s('date'),
      start: j.s('start'),
      end: j.s('end'),
      status: j.s('status', 'booked'),
    );
  }
}

class SlotCheck {
  const SlotCheck({
    required this.date,
    required this.start,
    required this.end,
    required this.ok,
    this.reason,
  });
  final String date;
  final String start;
  final String end;
  final bool ok;
  final String? reason;
}

class BookingPreview {
  const BookingPreview({
    required this.valid,
    required this.slots,
    required this.budget,
    this.message,
  });
  final bool valid;
  final List<SlotCheck> slots;
  final int budget;
  final String? message;
}

class TrainerRepository {
  TrainerRepository(this._api);
  final ApiClient _api;

  Future<List<WorkDay>> workHours({String? trainerId}) async {
    final r = (await _api.get(
      trainerId == null
          ? '/v5/trainers/me/work-hours'
          : '/v5/trainers/$trainerId/work-hours',
    )).map;
    return r.list('days').map(WorkDay.fromJson).toList();
  }

  Future<void> saveWorkHours(List<WorkDay> days) async => _api.put(
    '/v5/trainers/me/work-hours',
    body: {'days': days.map((d) => d.toJson()).toList()},
  );

  Future<List<Booking>> bookings({
    String? trainerId,
    String? date,
    String? from,
    String? to,
    String? memberId,
  }) async {
    final path = trainerId == null
        ? '/v5/trainers/me/bookings'
        : '/v5/trainers/$trainerId/bookings';
    return (await _api.get(
      path,
      query: {'date': date, 'from': from, 'to': to, 'memberId': memberId},
    )).list.map(Booking.fromJson).toList();
  }

  Future<BookingPreview> preview({
    required String memberId,
    String? trainerId,
    required List<Json> slots,
  }) async {
    final r = (await _api.post(
      '/v5/trainers/me/bookings/preview',
      body: compact({
        'memberId': memberId,
        'trainerId': trainerId,
        'slots': slots,
      }),
    )).map;
    return BookingPreview(
      valid: r.b('valid'),
      budget: r.i('budget'),
      message: r.str('message'),
      slots: [
        for (final s in r.list('results'))
          SlotCheck(
            date: s.s('date'),
            start: s.s('start'),
            end: s.s('end'),
            ok: s.b('ok'),
            reason: s.str('reason'),
          ),
      ],
    );
  }

  Future<void> create({
    required String memberId,
    String? trainerId,
    required List<Json> slots,
  }) async => _api.post(
    '/v5/trainers/me/bookings',
    body: compact({
      'memberId': memberId,
      'trainerId': trainerId,
      'slots': slots,
    }),
  );

  Future<void> cancel(String id) async =>
      _api.delete('/v5/trainers/me/bookings/$id');
  Future<int> clear(String memberId) async => (await _api.post(
    '/v5/trainers/me/bookings/clear',
    body: {'memberId': memberId},
  )).map.i('cancelled');
}
