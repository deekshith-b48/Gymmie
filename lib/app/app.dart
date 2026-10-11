import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import '../core/l10n/l10n.dart';
import '../core/theme/app_theme.dart';
import 'di.dart';
import 'router.dart';
import 'session_cubit.dart';
import 'settings_cubit.dart';

class GymmieApp extends StatefulWidget {
  const GymmieApp({super.key});

  @override
  State<GymmieApp> createState() => _GymmieAppState();
}

class _GymmieAppState extends State<GymmieApp> {
  late final GoRouter _router = buildRouter();
  bool? _dark;

  /// The palette follows the theme in force (the setting, or the phone's). When it flips, colours that screens read
  /// at build time must be read again, so everything is marked for rebuild.
  void _syncPalette(bool dark) {
    if (_dark == dark) return;
    final first = _dark == null;
    _dark = dark;
    AppColors.apply(dark);
    if (first) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      void visit(Element e) {
        e.markNeedsBuild();
        e.visitChildren(visit);
      }
      if (mounted) (context as Element).visitChildren(visit);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<SessionCubit>.value(value: getIt<SessionCubit>()),
        BlocProvider<SettingsCubit>.value(value: getIt<SettingsCubit>()),
      ],
      child: BlocBuilder<SettingsCubit, AppPrefs>(
        builder: (context, prefs) => MaterialApp.router(
          title: 'Gymmie',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: prefs.themeMode,
          locale: Locale(prefs.language),
          supportedLocales: L10n.locales,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: _router,
          // Rebuilding the whole tree on language change re-evaluates every `.tr` string.
          builder: (context, child) {
            final dark = Theme.of(context).brightness == Brightness.dark;
            _syncPalette(dark);
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: Colors.transparent,
              ),
              child: KeyedSubtree(
                key: ValueKey(prefs.language),
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
        ),
      ),
    );
  }
}
