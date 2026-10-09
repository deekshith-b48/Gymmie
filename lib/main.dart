import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app/app.dart';
import 'app/di.dart';
import 'app/session_cubit.dart';
import 'core/config/app_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDependencies();

  Future<void> start() async {
    await _initFirebase();
    runApp(const GymmieApp());
    unawaited(getIt<SessionCubit>().boot());
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
