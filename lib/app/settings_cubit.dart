import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/l10n/l10n.dart';

class AppPrefs extends Equatable {
  const AppPrefs({this.themeMode = ThemeMode.system, this.language = 'en'});
  final ThemeMode themeMode;
  final String language;

  @override
  List<Object?> get props => [themeMode, language];
}

/// Device-local preferences: theme ("settings_theme_*") and app language ("settings_lang").
class SettingsCubit extends Cubit<AppPrefs> {
  SettingsCubit(this._prefs) : super(const AppPrefs()) {
    final theme = switch (_prefs.getString(_kTheme)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    final lang = _prefs.getString(_kLang) ?? 'en';
    L10n.code = L10n.supported.containsKey(lang) ? lang : 'en';
    emit(AppPrefs(themeMode: theme, language: L10n.code));
  }

  final SharedPreferences _prefs;
  static const _kTheme = 'theme_mode';
  static const _kLang = 'app_language';

  Future<void> setTheme(ThemeMode m) async {
    await _prefs.setString(_kTheme, m.name);
    emit(AppPrefs(themeMode: m, language: state.language));
  }

  Future<void> setLanguage(String code) async {
    if (!L10n.supported.containsKey(code)) return;
    L10n.code = code;
    await _prefs.setString(_kLang, code);
    emit(AppPrefs(themeMode: state.themeMode, language: code));
  }
}
