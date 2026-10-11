// Backups of the member's log: the same JSON document openGym exports (its state), so a backup moves
// between the two apps. An import is always an ADD: the backup's workouts, routines, weigh-ins and
// settings are merged into the log (domain/merge.dart) and nothing the member already logged is deleted.
// To start over from a backup, "Delete all my training data" first, then import.
import 'dart:convert';

import 'rows.dart';

/// What the backup file may weigh (the account's own limit is 2 MB).
const backupMaxBytes = 2 * 1024 * 1024;

class BackupError implements Exception {
  const BackupError(this.message);
  final String message;
  @override
  String toString() => message;
}

String backupFileName(DateTime day) =>
    'gymmie-backup-${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}.json';

/// The log as a backup file. An unfinished workout stays on the phone and is not part of it.
String exportBackup(Json state) {
  final out = Map<String, dynamic>.from(state)..remove('active');
  return const JsonEncoder.withIndent('  ').convert(out);
}

/// Reads and checks a backup. Throws [BackupError] (with a sentence a member can act on) when the file is
/// not one of ours or is too large; otherwise the document, without the device-local keys.
Json parseBackup(String text) {
  if (text.length > backupMaxBytes) throw const BackupError('This file is too large to be a backup.');
  Object? raw;
  try {
    raw = jsonDecode(text);
  } catch (_) {
    throw const BackupError('This file is not a backup. Choose a .json file exported from Gymmie or openGym.');
  }
  if (raw is! Map) throw const BackupError('This file is not a backup. Choose a .json file exported from Gymmie or openGym.');
  final doc = asMap(raw);
  const known = ['workouts', 'routines', 'bodyweight', 'week', 'exWeights', 'customEx'];
  if (!known.any(doc.containsKey)) throw const BackupError('This file does not contain a training log.');
  for (final k in ['workouts', 'routines', 'bodyweight', 'customEx', 'favEx', 'measurements']) {
    if (doc[k] != null && doc[k] is! List) throw BackupError('The backup is damaged ("$k" is not a list).');
  }
  for (final k in ['week', 'dayPlan', 'exWeights']) {
    if (doc[k] != null && doc[k] is! Map) throw BackupError('The backup is damaged ("$k" is not a map).');
  }
  doc
    ..remove('active')
    ..remove('_rev')
    ..remove('_wid')
    ..remove('_ts');
  return doc;
}

/// A short description of what an import will add, for the confirmation sheet.
({int workouts, int routines, int weighIns}) backupSummary(Json doc) => (
  workouts: asRows(doc['workouts']).length,
  routines: asRows(doc['routines']).length,
  weighIns: asRows(doc['bodyweight']).length,
);
