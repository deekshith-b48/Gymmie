import 'package:flutter/material.dart';

/// Design tokens sampled from the original app's recovered screenshots
/// (`assets/leads1.png`, `assets/leads2.png`) and `res/values/colors.xml`
/// (`splash_background = #061750`). Typeface: Poppins (bundled, as in the original).
class AppColors {
  AppColors._();

  static const navy = Color(0xFF061750);
  static const navyLight = Color(0xFF1B2A6B);
  static const background = Color(0xFFF8F9FC);
  static const surface = Colors.white;
  static const border = Color(0xFFE5E9F2);
  static const chip = Color(0xFFF1F4F9);
  static const textPrimary = Color(0xFF0B1026);
  static const textSecondary = Color(0xFF5B6478);
  static const textMuted = Color(0xFF8A93A6);
  static const info = Color(0xFF4A5BAE);
  static const success = Color(0xFF1E9E5A);
  static const successTint = Color(0xFFE5F5EC);
  static const warning = Color(0xFFE08A1E);
  static const warningTint = Color(0xFFFFF1E3);
  static const danger = Color(0xFFD93C41);
  static const dangerTint = Color(0xFFFDECEC);
  static const neutralTint = Color(0xFFEEF0F4);

  // Dark scheme
  static const darkBackground = Color(0xFF0A1022);
  static const darkSurface = Color(0xFF121A33);
  static const darkBorder = Color(0xFF263052);
  static const darkChip = Color(0xFF1B2547);
}

class AppTheme {
  AppTheme._();

  static const fontFamily = 'Poppins';

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final dark = b == Brightness.dark;
    final bg = dark ? AppColors.darkBackground : AppColors.background;
    final surface = dark ? AppColors.darkSurface : AppColors.surface;
    final border = dark ? AppColors.darkBorder : AppColors.border;
    final onSurface = dark ? const Color(0xFFEAEFFF) : AppColors.textPrimary;
    final primary = dark ? const Color(0xFF8FA2FF) : AppColors.navy;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.navy,
      brightness: b,
      primary: primary,
      onPrimary: dark ? AppColors.darkBackground : Colors.white,
      surface: surface,
      onSurface: onSurface,
      error: AppColors.danger,
    );
    final radius = BorderRadius.circular(12);
    OutlineInputBorder outline(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: c, width: w),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      fontFamily: fontFamily,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      dividerColor: border,
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: onSurface,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintStyle: TextStyle(
          color: dark ? AppColors.textMuted : AppColors.textMuted,
          fontWeight: FontWeight.w400,
        ),
        border: outline(border),
        enabledBorder: outline(border),
        focusedBorder: outline(primary, 1.5),
        errorBorder: outline(AppColors.danger),
        focusedErrorBorder: outline(AppColors.danger, 1.5),
        disabledBorder: outline(border),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          backgroundColor: primary,
          foregroundColor: dark ? AppColors.darkBackground : Colors.white,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: radius),
          side: BorderSide(color: primary),
          foregroundColor: primary,
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: dark ? AppColors.darkChip : AppColors.chip,
        selectedColor: primary,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 13,
          color: onSurface,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primary.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontFamily: fontFamily,
            fontSize: 11,
            fontWeight: s.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w400,
            color: s.contains(WidgetState.selected)
                ? primary
                : AppColors.textSecondary,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected)
                ? primary
                : AppColors.textSecondary,
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: onSurface,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: AppColors.navy,
        contentTextStyle: const TextStyle(
          fontFamily: fontFamily,
          color: Colors.white,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Colors.white
              : AppColors.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? primary
              : AppColors.neutralTint,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: AppColors.textSecondary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: dark ? AppColors.darkBackground : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),
    );
  }
}
