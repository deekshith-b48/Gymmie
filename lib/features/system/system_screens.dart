import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/di.dart';
import '../../app/routes.dart';
import '../../app/session_cubit.dart';
import '../../core/config/app_config.dart';
import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_splash.dart';
import '../../core/widgets/states.dart';

/// Shown while the session boots.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = getIt<SessionCubit>();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AnimatedLogo(),
            const SizedBox(height: 24),
            StreamBuilder<SessionState>(
              stream: session.stream,
              initialData: session.state,
              builder: (context, snap) {
                final e = snap.data?.bootError;
                if (e == null) {
                  return SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                  );
                }
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        e.message,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size(160, 46)),
                      onPressed: session.retryBoot,
                      child: const Text('Try again'),
                    ),
                    TextButton(
                      onPressed: () => context.go(R.backendSetup),
                      child: const Text('Change backend URL'),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: EmptyState(
        icon: Icons.construction_rounded,
        title: 'Under Maintenance',
        message: 'Gymmie is currently under maintenance. Please check back after a few hours.',
        actionLabel: 'Try again',
        onAction: () => getIt<SessionCubit>().boot(),
      ),
    ),
  );
}

/// Shown when the gym's subscription has lapsed ("Subscription Expired!").
class ExpiredGymScreen extends StatelessWidget {
  const ExpiredGymScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = getIt<SessionCubit>().state;
    final isOwner = s.can('settings.write');
    final sub = s.profile?.subscription;
    final trialEnded = sub?.plan == 'TRIAL' || sub?.plan == 'NONE';
    final unavailable = s.profile?.trial?.unavailable ?? false;
    return Scaffold(
      appBar: AppBar(
        actions: [
          TextButton(
            onPressed: () => context.go(R.gymSelection),
            child: Text('Switch Gym'.tr),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: EmptyState(
                icon: Icons.lock_clock_outlined,
                title: trialEnded ? (unavailable ? 'Choose a plan to start' : 'Your free trial has ended') : 'Subscription Expired!'.tr,
                message: isOwner
                    ? (trialEnded
                        ? (unavailable
                            ? 'The 14-day free trial is available once per owner and has already been used. Pick a plan to start using this gym.'
                            : 'Your 14 days are up. Pick a plan to keep managing your gym: your members and data are all still here.')
                        : 'Please renew the subscription plan.')
                    : 'Please contact admin to renew the subscription plan.',
                actionLabel: isOwner ? (trialEnded ? 'See plans' : 'Renew Now'.tr) : null,
                onAction: isOwner
                    ? () => context.push('/settings/subscription')
                    : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextButton(
                onPressed: () => getIt<SessionCubit>().signOut(),
                child: Text('Log out'.tr),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class UnauthorizedScreen extends StatelessWidget {
  const UnauthorizedScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded, size: 84, color: AppColors.textMuted),
              const SizedBox(height: 24),
              Text(
                'Access Denied',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'You do not have sufficient permissions to access this. If you believe this is an error, please contact customer service for assistance.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go(R.home),
                child: const Text('Go back home'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: EmptyState(
        icon: Icons.system_update,
        title: 'Update Required',
        message: 'Your app version is outdated. Please update your app to continue using our services.',
        actionLabel: 'Update now',
        onAction: () => launchUrl(
          Uri.parse(
            'https://play.google.com/store/apps/details?id=app.gymmie.android',
          ),
          mode: LaunchMode.externalApplication,
        ),
      ),
    ),
  );
}

/// Version label that reveals developer tools after 5 taps (debug builds show them always).
class VersionFooter extends StatefulWidget {
  const VersionFooter({super.key, this.dark = false});
  final bool dark;
  @override
  State<VersionFooter> createState() => _VersionFooterState();
}

class _VersionFooterState extends State<VersionFooter> {
  String _v = '';
  int _taps = 0;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then(
      (p) => mounted
          ? setState(() => _v = 'v${p.version} (${p.buildNumber})')
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cfg = getIt<AppConfig>();
    final color = widget.dark ? Colors.white54 : AppColors.textMuted;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () async {
            if (++_taps >= 5) {
              _taps = 0;
              await cfg.setDevToolsEnabled(true);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Developer tools enabled')),
                );
                setState(() {});
              }
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text(_v, style: TextStyle(fontSize: 12, color: color)),
          ),
        ),
        if (cfg.devToolsEnabled)
          TextButton.icon(
            onPressed: () => context.push(R.backendSetup),
            icon: const Icon(Icons.dns_outlined, size: 16),
            label: Text(
              cfg.isConfigured
                  ? Uri.parse(cfg.baseUrl).authority
                  : 'Set backend URL',
              style: const TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }
}

/// Small helper used by screens that need a delayed callback tied to a widget lifetime.
class Debouncer {
  Debouncer([this.delay = const Duration(milliseconds: 350)]);
  final Duration delay;
  Timer? _t;
  void run(void Function() f) {
    _t?.cancel();
    _t = Timer(delay, f);
  }

  void dispose() => _t?.cancel();
}

/// The Gymmie mark (the "G" and barbell), for headers.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.height = 36});
  final double height;
  @override
  Widget build(BuildContext context) =>
      Image.asset('assets/brand/logo_mark.png', height: height, fit: BoxFit.contain, semanticLabel: 'Gymmie');
}
