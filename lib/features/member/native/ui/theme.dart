import 'package:flutter/material.dart';

import '../domain/accent.dart';
import '../domain/rows.dart' show Json;
import '../domain/settings.dart';

Color _c(String hex) => Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));

/// One look of the member app: openGym's dark one, its light one, each with the member's accent.
class OGPalette {
  const OGPalette({
    required this.dark, required this.bg, required this.card, required this.card2, required this.line,
    required this.text, required this.dim, required this.acc, required this.onAcc,
    required this.blue, required this.orange, required this.red,
    required this.purple, required this.teal, required this.green, required this.yellow, required this.indigo, required this.pink, required this.grey,
  });

  final bool dark;
  final Color bg, card, card2, line, text, dim, acc, onAcc, blue, orange, red;

  /// The rest of the system colours, used to tint Settings icons.
  final Color purple, teal, green, yellow, indigo, pink, grey;

  /// The palette for [log]'s settings (theme, accent). [systemDark] answers 'system'.
  factory OGPalette.of(Json log, {required bool systemDark}) {
    final prefs = Prefs(log);
    final dark = prefs.theme == 'dark' || (prefs.theme == 'system' && systemDark);
    final a = resolveAccent(log, dark ? 'dark' : 'light');
    return dark
        ? OGPalette(
            dark: true, bg: const Color(0xFF0C0E12), card: const Color(0xFF16181D), card2: const Color(0xFF1F2228),
            line: const Color(0xFF2A2D34), text: const Color(0xFFFFFFFF), dim: const Color(0xFF8E939C),
            acc: _c(a.acc), onAcc: _c(a.ink), blue: const Color(0xFF0A84FF), orange: const Color(0xFFFF9F0A), red: const Color(0xFFFF453A),
            purple: const Color(0xFFBF5AF2), teal: const Color(0xFF40C8E0), green: const Color(0xFF30D158), yellow: const Color(0xFFFFD60A),
            indigo: const Color(0xFF5E5CE6), pink: const Color(0xFFFF375F), grey: const Color(0xFF8E8E93),
          )
        : OGPalette(
            dark: false, bg: const Color(0xFFF2F2F7), card: const Color(0xFFFFFFFF), card2: const Color(0xFFECECEF),
            line: const Color(0xFFD6D6DB), text: const Color(0xFF000000), dim: const Color(0xFF6E6E75),
            acc: _c(a.acc), onAcc: _c(a.ink), blue: const Color(0xFF007AFF), orange: const Color(0xFFFF9500), red: const Color(0xFFFF3B30),
            purple: const Color(0xFFAF52DE), teal: const Color(0xFF30B0C7), green: const Color(0xFF34C759), yellow: const Color(0xFFFFCC00),
            indigo: const Color(0xFF5856D6), pink: const Color(0xFFFF2D55), grey: const Color(0xFF8E8E93),
          );
  }

  /// A signature for "did the look change?" (the app repaints itself when it differs).
  String get signature => '${dark ? 'd' : 'l'}${acc.toARGB32()}';
}

/// The colours every member screen draws with. They follow the member's theme and accent setting; the app
/// installs a new palette (and repaints) when either changes, so a screen just reads `OG.acc`.
class OG {
  OG._();
  static OGPalette palette = OGPalette.of(const <String, dynamic>{}, systemDark: true);

  static Color get bg => palette.bg;
  static Color get card => palette.card;
  static Color get card2 => palette.card2;
  static Color get line => palette.line;
  static Color get text => palette.text;
  static Color get dim => palette.dim;
  static Color get acc => palette.acc;
  static Color get onAcc => palette.onAcc;
  static Color get blue => palette.blue;
  static Color get orange => palette.orange;
  static Color get red => palette.red;
  static Color get purple => palette.purple;
  static Color get teal => palette.teal;
  static Color get green => palette.green;
  static Color get yellow => palette.yellow;
  static Color get indigo => palette.indigo;
  static Color get pink => palette.pink;
  static Color get grey => palette.grey;
}

ThemeData ogTheme([OGPalette? p]) {
  final pal = p ?? OG.palette;
  final base = pal.dark ? ThemeData.dark(useMaterial3: true) : ThemeData.light(useMaterial3: true);
  final scheme = pal.dark
      ? ColorScheme.dark(primary: pal.acc, onPrimary: pal.onAcc, surface: pal.card, onSurface: pal.text, error: pal.red, secondary: pal.acc, surfaceContainerHighest: pal.card2)
      : ColorScheme.light(primary: pal.acc, onPrimary: pal.onAcc, surface: pal.card, onSurface: pal.text, error: pal.red, secondary: pal.acc, surfaceContainerHighest: pal.card2);
  return base.copyWith(
    scaffoldBackgroundColor: pal.bg,
    colorScheme: scheme,
    appBarTheme: AppBarTheme(backgroundColor: pal.bg, foregroundColor: pal.text, elevation: 0, scrolledUnderElevation: 0, centerTitle: false),
    cardTheme: CardThemeData(color: pal.card, elevation: 0, margin: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
    dividerTheme: DividerThemeData(color: pal.line, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: pal.card2, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
      backgroundColor: pal.acc, foregroundColor: pal.onAcc, minimumSize: const Size.fromHeight(52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
    )),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
      foregroundColor: pal.text, side: BorderSide(color: pal.line), minimumSize: const Size.fromHeight(52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
    )),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: pal.acc)),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? pal.onAcc : Colors.white),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? pal.acc : pal.line),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(style: ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? pal.acc.withValues(alpha: 0.22) : pal.card2),
      foregroundColor: WidgetStatePropertyAll(pal.text),
      side: const WidgetStatePropertyAll(BorderSide.none),
    )),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: pal.card, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22)))),
    dialogTheme: DialogThemeData(backgroundColor: pal.card, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
    chipTheme: ChipThemeData(
      backgroundColor: pal.card2, selectedColor: pal.acc.withValues(alpha: 0.22), side: BorderSide.none,
      labelStyle: TextStyle(color: pal.text), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: pal.card2, contentTextStyle: TextStyle(color: pal.text)),
  );
}
