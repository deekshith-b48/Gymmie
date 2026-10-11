// The member's training log on this phone, and its sync with the Gymmie backend.
//
// Local first: every change is saved to the phone immediately and the app works offline. When the
// network is there the whole document is pushed (revision-checked); if another device changed it
// meanwhile the two copies are merged (domain/merge.dart) and pushed again. An unfinished workout
// (`active`) stays on this phone.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_exception.dart';
import 'domain/merge.dart';
import 'domain/rows.dart';
import 'domain/settings.dart';
import 'domain/units.dart';

class LogDoc {
  const LogDoc(this.rev, this.wid, this.state);
  final int rev;
  final String? wid;
  final Json? state;
}

class LogConflict implements Exception {
  const LogConflict(this.doc);
  final LogDoc doc;
}

class LogOffline implements Exception {
  const LogOffline([this.message = 'offline']);
  final String message;
  @override
  String toString() => 'LogOffline($message)';
}

/// The two calls the store needs from the backend (implemented by `MemberRepository`).
abstract class LogApi {
  Future<LogDoc> fetchLog();

  /// Throws [LogConflict] when [baseRev] is stale and [LogOffline] when the network is down.
  Future<LogDoc> pushLog(Json state, int baseRev);
  Future<void> eraseLog();
}

enum SyncStatus { idle, syncing, offline, error }

/// A new member's log. Settings (unit, rest, week start, theme...) are not in it on purpose: a setting is
/// written only when the member changes it, so a phone that never touched one cannot overwrite the account's
/// choice when two copies merge. Readers fall back to openGym's defaults (domain/settings.dart).
Json defaultLog() => {
  'bodyweight': <Object?>[],
  'routines': <Object?>[],
  'week': <String, dynamic>{},
  'dayPlan': <String, dynamic>{},
  'exWeights': <String, dynamic>{},
  'workouts': <Object?>[],
  'customEx': <Object?>[],
  'favEx': <Object?>[],
  'active': null,
};

class MemberLogStore extends ChangeNotifier {
  MemberLogStore({required this.key, required this._prefs, this.api, this.syncDelay = const Duration(seconds: 4)});

  final String key;
  final SharedPreferences _prefs;
  final LogApi? api;
  final Duration syncDelay;

  Json state = defaultLog();
  int baseRev = 0;
  bool dirty = false;
  SyncStatus status = SyncStatus.idle;
  Object? lastError;
  Timer? _timer;

  /// Called when the server refuses the session (401/403) so the app can re-check who is signed in.
  VoidCallback? onAuthProblem;
  bool _syncing = false;
  bool _disposed = false;

  String get _kState => '$key:state';
  String get _kMeta => '$key:meta';

  Json? get active => state['active'] is Map ? asMap(state['active']) : null;

  /// Reads the saved copy from the phone (and fills in any setting the saved copy lacks).
  Future<void> load() async {
    final raw = _prefs.getString(_kState);
    if (raw != null) {
      try {
        final j = jsonDecode(raw);
        if (j is Map) state = {...defaultLog(), ...j.cast<String, dynamic>()};
      } catch (_) {
        // A damaged copy must never stop the app: start empty, the server copy comes back on sync.
      }
    }
    final meta = _prefs.getString(_kMeta);
    if (meta != null) {
      try {
        final m = asMap(jsonDecode(meta));
        baseRev = (m['rev'] as num?)?.toInt() ?? 0;
        dirty = m['dirty'] == true;
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    await _prefs.setString(_kState, jsonEncode(state));
    await _prefs.setString(_kMeta, jsonEncode({'rev': baseRev, 'dirty': dirty}));
  }

  /// Changes the log. [fn] edits [state] in place; it is saved at once and synced soon after.
  void update(void Function(Json s) fn, {bool syncSoon = true}) {
    fn(state);
    dirty = true;
    _persist();
    notifyListeners();
    if (syncSoon && api != null) {
      _timer?.cancel();
      _timer = Timer(syncDelay, () => sync());
    }
  }

  /// kg ⇄ lb. With [convert] every stored weight is converted (domain/units.dart); without, the numbers stay
  /// and only the label changes. The switch is stamped so another phone still in the old unit follows it on its
  /// next sync instead of reading its numbers in the wrong unit (domain/merge.dart).
  void setUnit(String to, {bool convert = true, String? Function(String id)? equipmentOf}) {
    if (Prefs(state).unit == to) return;
    update((s) {
      final next = convert ? convertStateUnit(s, to, equipmentOf: equipmentOf) : {...s, 'unit': to};
      final prev = numOrNull(asMap(s['unitSet'])['at']) ?? 0;
      next['unitSet'] = {'at': DateTime.now().millisecondsSinceEpoch > prev ? DateTime.now().millisecondsSinceEpoch : prev + 1, 'convert': convert};
      s
        ..clear()
        ..addAll(next);
    }, syncSoon: true);
  }

  /// Adds a backup (domain/backup.dart parseBackup) to the log: its workouts, routines and weigh-ins are merged
  /// in, nothing the member already logged is removed, and this phone's choices win a clash.
  void importBackup(Json doc) => update((s) {
    final merged = mergeLogs(Map<String, dynamic>.from(s), doc);
    s
      ..clear()
      ..addAll(merged);
  });

  /// Saves without scheduling a sync or marking the log changed (an unfinished workout lives
  /// only on this phone; the next finished workout carries its data to the server).
  void updateLocalOnly(void Function(Json s) fn) {
    fn(state);
    _prefs.setString(_kState, jsonEncode(state));
    notifyListeners();
  }

  Json _forServer() => Map<String, dynamic>.from(state)..remove('active');

  /// Brings this phone and the server together. Safe to call any time; concurrent calls collapse.
  Future<void> sync() async {
    final a = api;
    if (a == null || _syncing || _disposed) return;
    _syncing = true;
    _timer?.cancel();
    status = SyncStatus.syncing;
    notifyListeners();
    try {
      for (var attempt = 0; attempt < 4; attempt++) {
        final remote = await a.fetchLog();
        final theirs = remote.state;
        if (!dirty) {
          if (theirs != null && remote.rev != baseRev) {
            final active = state['active'];
            state = {...defaultLog(), ...theirs, 'active': active};
            baseRev = remote.rev;
          } else if (theirs == null && baseRev != 0) {
            baseRev = 0; // the server copy was erased; keep ours and push it next time we change
          }
          break;
        }
        final merged = theirs == null ? _forServer() : mergeLogs(_forServer(), theirs);
        try {
          final put = await a.pushLog(merged, remote.rev);
          final active = state['active'];
          state = {...defaultLog(), ...merged, 'active': active};
          baseRev = put.rev;
          dirty = false;
          break;
        } on LogConflict {
          continue; // someone wrote between our read and write: read again and merge again
        }
      }
      status = SyncStatus.idle;
      lastError = null;
      await _persist();
    } on LogOffline catch (e) {
      status = SyncStatus.offline;
      lastError = e;
    } catch (e) {
      status = SyncStatus.error;
      lastError = e;
      if (e is ApiException && (e.status == 401 || e.status == 403)) onAuthProblem?.call();
    } finally {
      _syncing = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// "Delete everything": the server copy and this phone's copy.
  Future<void> eraseAll() async {
    await api?.eraseLog();
    state = defaultLog();
    baseRev = 0;
    dirty = false;
    await _persist();
    notifyListeners();
  }

  /// Forget this phone's copy (sign-out on a shared phone). The server copy is untouched.
  Future<void> wipeLocal() async {
    _timer?.cancel();
    await _prefs.remove(_kState);
    await _prefs.remove(_kMeta);
    state = defaultLog();
    baseRev = 0;
    dirty = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
