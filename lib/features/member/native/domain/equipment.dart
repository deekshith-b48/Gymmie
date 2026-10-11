// Equipment profiles ("Home", "Gym", ...), ported from openGym's lib/equipment.js. Each profile is
// {id, name, equipment: [...]}; the active one filters the library and the exercise picker.
//
// Purely additive: with filtering off, or no profile chosen, everything is available. Body weight is never
// gated by a profile; only the accessory an exercise needs (a bar, a bench) can still gate it.
import 'catalogue.dart';
import 'rows.dart';

/// Pieces of kit the catalogue never names as an exercise's equipment: "dumbbell bench press" is tagged
/// `dumbbell`, yet it needs a bench. They are read off the exercise name.
const accessories = ['bench', 'pull-up bar'];
const _selfContained = {'leverage machine', 'sled machine', 'assisted'};
const _alwaysAvailable = 'body weight';
const accV = 1;

final _benchWords = RegExp(r'\bbench\b|\bincline\b|\bdecline\b');
final _barWords = RegExp(r'pull-up|pull up|chin-up|\bchin\b|hanging|muscle-up|muscle up');

/// Which accessories an exercise needs, e.g. ['bench'] for "dumbbell incline bench press".
List<String> accessoriesOf(Exercise ex) {
  if (ex.name.isEmpty || _selfContained.contains(ex.equipment)) return const [];
  final n = ex.name.toLowerCase();
  return [if (_benchWords.hasMatch(n)) 'bench', if (_barWords.hasMatch(n)) 'pull-up bar'];
}

/// Every equipment value in the catalogue, most common first, then the accessories: the checklist shown
/// when a profile is built.
List<String> allEquipment(Iterable<Exercise> catalogue) {
  final counts = <String, int>{};
  for (final e in catalogue) {
    if (e.equipment.isNotEmpty && !e.custom) counts[e.equipment] = (counts[e.equipment] ?? 0) + 1;
  }
  final ranked = counts.keys.toList()
    ..sort((a, b) => counts[b]! != counts[a]! ? counts[b]!.compareTo(counts[a]!) : a.compareTo(b));
  for (final extra in const ['clubbell', 'macebell']) {
    if (!ranked.contains(extra)) ranked.add(extra);
  }
  return [...ranked, ...accessories];
}

/// A profile saved before the bench and the bar were on the checklist counts as having both.
List<String> profileEquipment(Json? p) {
  if (p == null) return const [];
  final have = [for (final x in (p['equipment'] as List? ?? const [])) '$x'];
  return p['accV'] != accV ? {...have, ...accessories}.toList() : have;
}

/// The profile in force: null while filtering is off or the chosen profile is gone.
Json? activeProfile(Json s) {
  if (s['equipFilterOn'] != true) return null;
  for (final p in asRows(s['equipProfiles'])) {
    if (p['id'] == s['activeEquipId']) return p;
  }
  return null;
}

bool eqAvailable(List<String> have, Exercise ex, List<String> all) {
  if (ex.equipment.isNotEmpty && ex.equipment != _alwaysAvailable) {
    // Equipment no profile can tick (a custom exercise's own) stays, like body weight.
    if (!all.contains(ex.equipment)) return true;
    if (!have.contains(ex.equipment)) return false;
  }
  return accessoriesOf(ex).every(have.contains);
}

/// Whether [ex] is usable under the active profile.
bool exAvailable(Json s, Exercise ex, List<String> all) {
  final p = activeProfile(s);
  return p == null || eqAvailable(profileEquipment(p), ex, all);
}

Json newProfile(String name, {int? at}) {
  final stamp = (at ?? DateTime.now().millisecondsSinceEpoch).toRadixString(36);
  return {'id': 'eq$stamp', 'name': name.trim(), 'equipment': <String>[], 'accV': accV};
}
