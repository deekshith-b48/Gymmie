import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app/app_root.dart';
import 'features/member/member_session_cubit.dart';
import 'app/di.dart';
import 'app/session_cubit.dart';
import 'core/config/app_config.dart';
import 'core/legal/notices.dart';
import 'core/widgets/brand_splash.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerNotices();
  await configureDependencies();

  Future<void> start() async {
    await _initFirebase();
    SplashClock.start();
    runApp(const AppRoot());
    unawaited(getIt<SessionCubit>().boot());
    unawaited(getIt<MemberSessionCubit>().boot());
  }

  // Crash reporting is opt-in: only when a DSN is provided at build time.
  if (AppConfig.sentryDsn.isNotEmpty && !kDebugMode) {
    await SentryFlutter.init((o) {
      o.dsn = AppConfig.sentryDsn;
      o.tracesSampleRate = 0.0;
      o.sendDefaultPii = false;
    }, appRunner: start);
  } else {
    await start();
  }
}

/// Firebase (push notifications, analytics) is initialised only when its options were supplied via
/// --dart-define; nothing is bundled. See docs/BUILD.md.
Future<void> _initFirebase() async {
  if (!AppConfig.firebaseConfigured) return;
  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: AppConfig.firebaseApiKey,
        appId: AppConfig.firebaseAppId,
        messagingSenderId: AppConfig.firebaseSenderId,
        projectId: AppConfig.firebaseProjectId,
        storageBucket: AppConfig.firebaseStorageBucket,
      ),
    );
  } catch (e) {
    debugPrint('Firebase init failed: $e');
  }
}
