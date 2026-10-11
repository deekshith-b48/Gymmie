// The Gymmie logo, animated in: it fades and settles up from slightly smaller while a soft glow of the accent colour opens behind it.
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AnimatedLogo extends StatefulWidget {
  const AnimatedLogo({super.key, this.size = 210, this.child});
  final double size;

  /// Shown under the logo (a spinner, an error).
  final Widget? child;

  @override
  State<AnimatedLogo> createState() => _AnimatedLogoState();
}

class _AnimatedLogoState extends State<AnimatedLogo> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(parent: _c, curve: const Interval(0, 0.7, curve: Curves.easeOut));
    final settle = CurvedAnimation(parent: _c, curve: Curves.easeOutBack);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: widget.size * 1.5,
                height: widget.size * 1.5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [AppColors.accent.withValues(alpha: 0.22 * fade.value), Colors.transparent]),
                ),
              ),
              Opacity(
                opacity: fade.value,
                child: Transform.scale(
                  scale: 0.82 + 0.18 * settle.value,
                  child: Image.asset('assets/brand/logo_title.png', width: widget.size, height: widget.size, semanticLabel: 'Gymmie'),
                ),
              ),
            ],
          ),
          if (widget.child != null) ...[const SizedBox(height: 8), Opacity(opacity: fade.value, child: widget.child)],
        ],
      ),
    );
  }
}

/// Keeps the logo on screen for a short moment at launch, so the animation is seen, then lets the app show the right screen.
class SplashClock {
  SplashClock._();
  static final ValueNotifier<bool> done = ValueNotifier(false);
  static bool _started = false;

  static void start([Duration d = const Duration(milliseconds: 1900)]) {
    if (_started) return;
    _started = true;
    Future<void>.delayed(d, () => done.value = true);
  }
}

class BrandSplash extends StatelessWidget {
  const BrandSplash({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark(),
    home: Scaffold(backgroundColor: AppColors.background, body: const Center(child: AnimatedLogo())),
  );
}
