// What happens when a rest ends: a sound, a buzz, a flash of the screen, each on its own switch
// (Settings → Timer alerts). Uses the phone's own system sound and haptics, so it works with the app open
// on any screen and needs no permission.
import 'package:flutter/services.dart';

import '../domain/settings.dart';

class RestAlerts {
  RestAlerts._();

  /// The rest is over: ring what the member switched on. The flash is drawn by the workout screen.
  static void ring(Prefs p) {
    if (p.vibrate) previewVibration();
    if (p.sound) previewSound();
  }

  // A phone without the hardware, or a platform that refuses, must never break a workout: errors are dropped.
  static void _safe(Future<void> Function() f) {
    try {
      f().catchError((Object _) {});
    } catch (_) {}
  }

  /// Heard once when the member switches the sound on, so they know what they chose.
  static void previewSound() => _safe(() => SystemSound.play(SystemSoundType.alert));
  static void previewVibration() => _safe(HapticFeedback.heavyImpact);
}
