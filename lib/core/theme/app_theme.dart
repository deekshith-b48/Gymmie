import 'package:flutter/material.dart';

import '../../features/member/native/ui/theme.dart' show OGPalette, ogTheme;

/// The owner/staff app wears the member app's look: the same dark and light palettes, the same accent, the same
/// component shapes. Both read one palette (`OGPalette`), so changing it changes both apps.
///
/// Colours here are read at build time from the palette of the current brightness; [apply] is called by the app root
/// whenever the theme flips, and the tree repaints.
class AppColors {
  AppColors._();

  static OGPalette _p = _make(false);

  static OGPalette _make(bool dark) => OGPalette.of({'theme': dark ? 'dark' : 'light'}, systemDark: dark);

  /// The palette for [dark]; the app root calls this when the theme (or the system theme) changes.
  static void apply(bool dark) {
    if (_p.dark != dark) _p = _make(dark);
  }

  static OGPalette get palette => _p;
  static bool get isDark => _p.dark;

  static Color get accent => _p.acc;
  static Color get onAccent => _p.onAcc;

  static Color get background => _p.bg;
  static Color get surface => _p.card;
  static Color get chip => _p.card2;
  static Color get border => _p.line;
  static Color get textPrimary => _p.text;
  static Color get textSecondary => _p.dim;
  static Color get textMuted => Color.lerp(_p.dim, _p.bg, 0.28)!;

  static Color get info => _p.blue;
  static Color get success => _p.green;
  static Color get warning => _p.orange;
  static Color get danger => _p.red;
  static Color get successTint => _p.green.withValues(alpha: 0.16);
  static Color get warningTint => _p.orange.withValues(alpha: 0.16);
  static Color get dangerTint => _p.red.withValues(alpha: 0.16);
  static Color get neutralTint => _p.card2;

  /// The brand colour: the accent. `navy` is the old name, kept so existing screens follow the new look.
  static Color get navy => _p.acc;
  static Color get navyLight => Color.lerp(_p.acc, _p.bg, 0.3)!;
  static Color get onNavy => _p.onAcc;

  static Color get darkBackground => _p.bg;
  static Color get darkSurface => _p.card;
  static Color get darkBorder => _p.line;
  static Color get darkChip => _p.card2;
}

class AppTheme {
  AppTheme._();

  /// The system font, as in the member app.
  static const String? fontFamily = null;

  static ThemeData light() => _build(false);
  static ThemeData dark() => _build(true);

  static ThemeData _build(bool dark) {
    final p = AppColors._make(dark);
    final base = ogBase(p);
    const radius = 14.0;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
    return base.copyWith(
      canvasColor: p.bg,
      dividerColor: p.line,
      appBarTheme: base.appBarTheme.copyWith(
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: p.text),
      ),
      cardTheme: base.cardTheme.copyWith(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        fillColor: p.card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: TextStyle(color: Color.lerp(p.dim, p.bg, 0.28), fontWeight: FontWeight.w400),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.line)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.acc, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.red)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.red, width: 1.5)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52), shape: shape, side: BorderSide(color: p.line), foregroundColor: p.text,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52), shape: shape, backgroundColor: p.acc, foregroundColor: p.onAcc,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        selectedColor: p.acc.withValues(alpha: 0.22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: TextStyle(fontSize: 13, color: p.text),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
        indicatorColor: p.acc.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
          fontSize: 11,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
          color: s.contains(WidgetState.selected) ? p.acc : p.dim,
        )),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? p.acc : p.dim)),
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(surfaceTintColor: Colors.transparent, showDragHandle: true),
      dialogTheme: base.dialogTheme.copyWith(
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: p.text),
      ),
      listTileTheme: ListTileThemeData(iconColor: p.dim, contentPadding: const EdgeInsets.symmetric(horizontal: 16)),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.acc, foregroundColor: p.onAcc, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.acc),
      tabBarTheme: TabBarThemeData(labelColor: p.acc, unselectedLabelColor: p.dim, indicatorColor: p.acc, dividerColor: p.line),
      textSelectionTheme: TextSelectionThemeData(cursorColor: p.acc, selectionHandleColor: p.acc),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.acc : null),
        checkColor: WidgetStatePropertyAll(p.onAcc),
      ),
      radioTheme: RadioThemeData(fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.acc : p.dim)),
    );
  }

  /// The member app's own theme for a palette (shared so both apps are built from the same pieces).
  static ThemeData ogBase(OGPalette p) => ogTheme(p);
}
