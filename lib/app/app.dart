import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import '../core/l10n/l10n.dart';
import '../core/theme/app_theme.dart';
import 'di.dart';
import 'router.dart';
import 'session_cubit.dart';
import 'settings_cubit.dart';

class GymBookApp extends StatefulWidget {
  const GymBookApp({super.key});

  @override
  State<GymBookApp> createState() => _GymBookAppState();
}

class _GymBookAppState extends State<GymBookApp> {
  late final GoRouter _router = buildRouter();

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<SessionCubit>.value(value: getIt<SessionCubit>()),
        BlocProvider<SettingsCubit>.value(value: getIt<SettingsCubit>()),
      ],
      child: BlocBuilder<SettingsCubit, AppPrefs>(
        builder: (context, prefs) => MaterialApp.router(
          title: 'DGymBook Partner',
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
          builder: (context, child) => KeyedSubtree(
            key: ValueKey(prefs.language),
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
