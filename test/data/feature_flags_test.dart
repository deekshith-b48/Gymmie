import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_book_app/data/models/user_gym.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('attendance, members-in-gym and biometrics default to off', () async {
    final cat = await FeatureCatalog.load();
    for (final k in [Feat.attendance, Feat.membersInGym, Feat.biometrics]) {
      final def = cat.byKey(k);
      expect(def, isNotNull, reason: '$k is in the catalog');
      expect(def!.defaultEnabled, isFalse, reason: '$k defaults to off');
      expect(def.adminEnabled, isTrue, reason: 'admin can enable $k');
      expect(def.visible, isTrue);
    }
  });

  test('app catalog and backend catalog list the same flags', () {
    List<String> keys(String p) => [
      for (final e in jsonDecode(File(p).readAsStringSync()) as List)
        (e as Map)['key'] as String,
    ]..sort();
    expect(
      keys('assets/feature_flags_data.json'),
      keys('backend/src/feature_flags.json'),
    );
  });
}
