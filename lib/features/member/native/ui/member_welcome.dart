// "Welcome to [Gym Name]!": shown for about three seconds after a member signs in, then the dashboard.
import 'dart:async';

import 'package:flutter/material.dart';

import 'theme.dart';

class MemberWelcome extends StatefulWidget {
  const MemberWelcome({super.key, required this.gymName, required this.memberName, required this.onDone, this.duration = const Duration(seconds: 3)});
  final String gymName;
  final String memberName;
  final VoidCallback onDone;
  final Duration duration;

  @override
  State<MemberWelcome> createState() => _MemberWelcomeState();
}

class _MemberWelcomeState extends State<MemberWelcome> with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, widget.onDone);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(parent: _in, curve: Curves.easeOut);
    return Scaffold(
      backgroundColor: OG.bg,
      body: Center(
        child: FadeTransition(
          opacity: fade,
          child: ScaleTransition(
            scale: Tween(begin: 0.94, end: 1.0).animate(fade),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/brand/logo_mark.png', height: 84),
                  const SizedBox(height: 28),
                  Text('Welcome to', style: TextStyle(color: OG.dim, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text('${widget.gymName}!', textAlign: TextAlign.center, style: TextStyle(color: OG.text, fontSize: 30, fontWeight: FontWeight.w800, height: 1.15)),
                  const SizedBox(height: 14),
                  Text(widget.memberName, textAlign: TextAlign.center, style: TextStyle(color: OG.acc, fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 36),
                  SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: OG.acc)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
