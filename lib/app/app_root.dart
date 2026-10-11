import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/widgets/brand_splash.dart';
import '../features/member/native/ui/native_app.dart';
import '../features/member/member_session_cubit.dart';
import 'app.dart';
import 'di.dart';

/// Decides which app is on screen: the member app while a gym member is signed in, otherwise the
/// staff app (whose login page also carries the "For gym members" section).
///
/// The two are separate `MaterialApp`s and never alive together, so they do not share a navigator,
/// router, theme scope or back-button handling.
class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<MemberSessionCubit>.value(
      value: getIt<MemberSessionCubit>(),
      child: BlocBuilder<MemberSessionCubit, MemberSessionState>(
        buildWhen: (a, b) => a.signedIn != b.signedIn,
        // the logo animation plays first, then the app that matches the saved session: the member app, or the staff app (its router
        // sends a signed-out person to the login page and a signed-in one to the dashboard)
        builder: (context, s) => ValueListenableBuilder<bool>(
          valueListenable: SplashClock.done,
          builder: (context, done, _) => !done ? const BrandSplash() : (s.signedIn ? const NativeMemberApp() : const GymmieApp()),
        ),
      ),
    );
  }
}
