import 'package:flutter/widgets.dart';

import 'strings_hi.dart';
import 'strings_other.dart';

/// Lightweight localisation: the English text IS the key, so untranslated strings fall back to
/// English automatically. Locale choice mirrors the original app's `LOCALIZATION` feature
/// (English + Hindi, Bengali, Gujarati, Kannada, Marathi, Tamil, Telugu).
class L10n {
  L10n._();

  static const supported = <String, String>{
    'en': 'English',
    'hi': 'हिन्दी',
    'bn': 'বাংলা',
    'gu': 'ગુજરાતી',
    'kn': 'ಕನ್ನಡ',
    'mr': 'मराठी',
    'ta': 'தமிழ்',
    'te': 'తెలుగు',
  };

  static String code = 'en';

  static const _tables = <String, Map<String, String>>{
    'hi': stringsHi,
    'bn': stringsBn,
    'gu': stringsGu,
    'kn': stringsKn,
    'mr': stringsMr,
    'ta': stringsTa,
    'te': stringsTe,
  };

  static String tr(String s) => _tables[code]?[s] ?? s;

  static Locale get locale => Locale(code);
  static List<Locale> get locales => [
    for (final c in supported.keys) Locale(c),
  ];
}

extension TrString on String {
  String get tr => L10n.tr(this);
}
