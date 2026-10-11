// The workout-day reminder: openGym's "Workout day reminder" setting. The log holds `reminder: {on, time}`; the
// phone's alarm clock (Reminders.kt, over the `gymmie/reminders` channel) fires it on the weekdays that have a
// planned routine. If a workout is already logged today, today's reminder is skipped.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/activity.dart' show workoutDay;
import '../domain/plan.dart' show isoOf;
import '../domain/rows.dart';

class ReminderPlan {
  const ReminderPlan({required this.on, required this.hour, required this.minute, required this.days, required this.skipThrough});
  final bool on;
  final int hour;
  final int minute;

  /// Weekdays with a planned routine, Sunday = 0 (JS getDay()).
  final List<int> days;

  /// 'yyyy-MM-dd' of the last day whose reminder is skipped ('' for none).
  final String skipThrough;

  String get signature => '$on/$hour:$minute/${days.join(',')}/$skipThrough';

  /// What the phone should be told, from the member's log.
  static ReminderPlan of(Json log, {DateTime? now}) {
    final r = asMap(log['reminder']);
    final t = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch('${r['time'] ?? '07:30'}');
    final h = int.tryParse(t?.group(1) ?? '') ?? 7, m = int.tryParse(t?.group(2) ?? '') ?? 30;
    final week = asMap(log['week']);
    final days = <int>[for (var d = 0; d < 7; d++) if (asRows(week['$d']).isNotEmpty || (week['$d'] is List && (week['$d'] as List).isNotEmpty)) d];
    final today = isoOf(now ?? DateTime.now());
    final done = asRows(log['workouts']).any((w) => workoutDay(w) == today);
    return ReminderPlan(on: r['on'] == true && days.isNotEmpty, hour: h.clamp(0, 23), minute: m.clamp(0, 59), days: days, skipThrough: done ? today : '');
  }
}

class WorkoutReminders {
  static const _ch = MethodChannel('gymmie/reminders');
  static String? _last;

  /// Tells the phone about the reminder, only when something changed. Silent where there is no native side (tests, iOS).
  static Future<void> sync(Json log, {bool force = false}) async {
    final p = ReminderPlan.of(log);
    if (!force && p.signature == _last) return;
    _last = p.signature;
    try {
      await _ch.invokeMethod<Object?>('schedule', {
        'on': p.on, 'hour': p.hour, 'minute': p.minute, 'days': p.days,
        'title': 'Time to train', 'body': 'Your workout is planned for today.', 'skipThrough': p.skipThrough,
      });
    } on MissingPluginException {
      // no native side
    } catch (e) {
      debugPrint('Workout reminder not scheduled: $e');
    }
  }

  /// Asks for the notification permission (Android 13+); true when notices can be shown.
  static Future<bool> allowed() async {
    try {
      return await _ch.invokeMethod<bool>('requestPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Forget the schedule (sign-out): a signed-out phone must not remind someone else's routine.
  static Future<void> cancel() async {
    _last = null;
    try {
      await _ch.invokeMethod<Object?>('cancel');
    } catch (_) {}
  }
}
