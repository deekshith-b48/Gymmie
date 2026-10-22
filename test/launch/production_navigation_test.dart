import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:gym_book_app/app/router.dart';
import 'package:gym_book_app/app/session_cubit.dart';
import 'package:gym_book_app/core/config/app_config.dart';
import 'package:gym_book_app/core/network/api_exception.dart';
import 'package:gym_book_app/data/repositories/auth_repository.dart';
import 'package:gym_book_app/features/system/system_screens.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Session extends Mock implements SessionCubit {}

class _Auth extends Mock implements AuthRepository {}

void main() {
  late _Session session;
  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues({
      'backend_url': 'http://old-server:8787',
      'dev_tools_enabled': true,
    });
    PackageInfo.setMockInitialValues(
      appName: 'Gymmie',
      packageName: 'app.gymmie.android',
      version: '2.0.2',
      buildNumber: '2002',
      buildSignature: '',
    );
    final prefs = await SharedPreferences.getInstance();
    session = _Session();
    when(() => session.state)
        .thenReturn(const SessionState(status: SessionStatus.signedOut));
    when(() => session.stream)
        .thenAnswer((_) => const Stream<SessionState>.empty());
    GetIt.instance
      ..registerSingleton<AppConfig>(
        AppConfig.forTesting(
          prefs,
          debugMode: false,
          apiBaseUrl: 'https://api.gymmie.test',
        ),
      )
      ..registerSingleton<SessionCubit>(session)
      ..registerSingleton<AuthRepository>(_Auth());
  });
  tearDown(() async => GetIt.instance.reset());

  testWidgets('managed login has no endpoint control or hidden unlock', (
    tester,
  ) async {
    final router = buildRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Set backend URL'), findsNothing);
    expect(find.byIcon(Icons.dns_outlined), findsNothing);
    await tester.ensureVisible(find.text('v2.0.2 (2002)'));
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.text('v2.0.2 (2002)'));
    }
    await tester.pump();
    expect(find.text('Developer tools enabled'), findsNothing);
    expect(GetIt.instance<AppConfig>().devToolsEnabled, isFalse);
    for (final path in ['/backend-setup', '/settings/dev']) {
      router.go(path);
      await tester.pumpAndSettle();
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('Backend URL'), findsNothing);
      expect(find.text('Developer tools'), findsNothing);
    }
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  });

  testWidgets('connection errors offer retry without server configuration', (
    tester,
  ) async {
    when(() => session.state)
        .thenReturn(SessionState(bootError: ApiException.network()));
    when(() => session.retryBoot()).thenAnswer((_) async {});
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
    await tester.pump();
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Change backend URL'), findsNothing);
    await tester.tap(find.text('Try again'));
    verify(() => session.retryBoot()).called(1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'a misconfigured build shows an update message, never a server form or endless spinner',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await GetIt.instance.unregister<AppConfig>();
      GetIt.instance.registerSingleton<AppConfig>(
        AppConfig.forTesting(prefs, debugMode: false),
      );
      await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
      expect(find.text('Please update Gymmie'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'update fallback fits small screens, landscape and large text in both themes',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await GetIt.instance.unregister<AppConfig>();
      GetIt.instance.registerSingleton<AppConfig>(
        AppConfig.forTesting(prefs, debugMode: false),
      );
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final size in [
        const Size(375, 667),
        const Size(812, 375),
        const Size(768, 1024),
      ]) {
        tester.view.physicalSize = size;
        for (final brightness in Brightness.values) {
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: const SplashScreen(),
            ),
          );
          await tester.pump();
          expect(find.text('Please update Gymmie'), findsOneWidget);
          expect(tester.takeException(), isNull, reason: '$size $brightness');
        }
      }
    },
  );
}
