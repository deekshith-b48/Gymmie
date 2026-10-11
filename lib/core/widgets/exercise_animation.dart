// An exercise's picture the way openGym shows it: the still frame at once, then the short clip plays muted on a loop over it.
// Tap to pause (back to the still) and again to play. If the clip cannot load the still stays; if that fails too a neutral tile
// stands in, and a tap tries again. Used by the member app (workout, library, plans) and the owner's exercise library.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Builds a controller for [url]. Tests replace it so no platform video is needed.
typedef ClipControllerFactory = VideoPlayerController Function(Uri url);
VideoPlayerController _defaultController(Uri url) =>
    VideoPlayerController.networkUrl(url, videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
ClipControllerFactory clipControllerFactory = _defaultController;

class ExerciseAnimation extends StatefulWidget {
  const ExerciseAnimation({
    super.key,
    required this.stillUrl,
    required this.clipUrl,
    this.height = 320,
    this.label,
    this.onToggleSize,
    this.mini = false,
    this.showHint = true,
    this.background = Colors.white,
    this.radius = 16,
  });

  /// The first frame (webp). Shown while the clip loads, while paused and if the clip fails.
  final String? stillUrl;

  /// The looping clip (mp4).
  final String? clipUrl;
  final double height;
  final String? label;

  /// Adds the "Minimize / Expand" control (the workout view); the caller saves the choice.
  final VoidCallback? onToggleSize;
  final bool mini;
  final bool showHint;

  /// The clips are drawn on white, so the frame is white in every theme.
  final Color background;
  final double radius;

  @override
  State<ExerciseAnimation> createState() => _ExerciseAnimationState();
}

enum _Fail { none, clip }

class _ExerciseAnimationState extends State<ExerciseAnimation> {
  VideoPlayerController? _video;
  bool _playing = true;
  bool _ready = false;
  _Fail _fail = _Fail.none;
  bool _stillFailed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(ExerciseAnimation old) {
    super.didUpdateWidget(old);
    if (old.clipUrl != widget.clipUrl) {
      _stop();
      _fail = _Fail.none;
      _playing = true;
      _start();
    }
    if (old.stillUrl != widget.stillUrl) _stillFailed = false;
  }

  Future<void> _start() async {
    final url = widget.clipUrl;
    if (url == null || url.isEmpty || !_playing) return;
    final c = clipControllerFactory(Uri.parse(url));
    _video = c;
    try {
      await c.initialize();
      if (!mounted || _video != c) return;
      await c.setVolume(0);
      await c.setLooping(true);
      await c.play();
      if (mounted && _video == c) setState(() => _ready = true);
    } catch (_) {
      // an unreachable host, an expired session, a dropped connection: the still stands in for the clip
      if (mounted && _video == c) setState(() => _fail = _Fail.clip);
    }
  }

  void _stop() {
    final c = _video;
    _video = null;
    _ready = false;
    if (c != null) unawaited(c.dispose().catchError((Object _) {}));
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _tap() {
    if (_fail != _Fail.none) {
      // try again
      _stop();
      setState(() { _fail = _Fail.none; _stillFailed = false; _playing = true; });
      _start();
      return;
    }
    setState(() => _playing = !_playing);
    final c = _video;
    if (_playing) {
      if (c != null && _ready) {
        unawaited(c.play());
      } else {
        _start();
      }
    } else if (c != null) {
      unawaited(c.pause());
    }
  }

  Widget _tile(BuildContext context) => Center(child: Icon(Icons.fitness_center, size: widget.height * 0.18, color: Colors.black26));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final showVideo = _playing && _ready && _fail == _Fail.none && _video != null;
    final still = widget.stillUrl;
    Widget body;
    if ((still == null || _stillFailed) && !showVideo) {
      body = _tile(context);
    } else {
      body = Stack(fit: StackFit.expand, children: [
        if (still != null && !_stillFailed)
          Image.network(
            still,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            semanticLabel: widget.label,
            errorBuilder: (_, _, _) {
              WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted && !_stillFailed) setState(() => _stillFailed = true); });
              return _tile(context);
            },
          ),
        if (showVideo)
          FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(width: _video!.value.size.width, height: _video!.value.size.height, child: VideoPlayer(_video!)),
          ),
      ]);
    }
    Widget chip(IconData icon, String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: Colors.white), const SizedBox(width: 4),
        Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
    return Semantics(
      label: widget.label,
      button: true,
      child: GestureDetector(
        onTap: _tap,
        child: Container(
          height: widget.height,
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: widget.background, borderRadius: BorderRadius.circular(widget.radius), border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4))),
          child: Stack(fit: StackFit.expand, children: [
            body,
            if (widget.onToggleSize != null)
              Positioned(left: 8, bottom: 8, child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onToggleSize,
                child: chip(widget.mini ? Icons.open_in_full_rounded : Icons.close_fullscreen_rounded, widget.mini ? 'Expand' : 'Minimize'),
              )),
            if (widget.showHint && !widget.mini && _fail == _Fail.none && (widget.clipUrl ?? '').isNotEmpty)
              Positioned(right: 8, bottom: 8, child: IgnorePointer(child: chip(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, _playing ? 'tap to pause' : 'tap to play'))),
          ]),
        ),
      ),
    );
  }
}

/// The URLs of an exercise's still and clip under a media host (`<base>/exercise-media/still|clip/<file>`).
class ExerciseMediaUrls {
  const ExerciseMediaUrls(this.still, this.clip);
  final String? still;
  final String? clip;

  static ExerciseMediaUrls of({required String? base, required String img, required String gif}) {
    if (base == null || base.isEmpty) return const ExerciseMediaUrls(null, null);
    final b = base.replaceAll(RegExp(r'/+$'), '');
    return ExerciseMediaUrls(img.isEmpty ? null : '$b/exercise-media/still/$img', gif.isEmpty ? null : '$b/exercise-media/clip/$gif');
  }
}

/// A sheet with the exercise's animation, opened from a thumbnail anywhere (plans, lists). Does nothing without media.
Future<void> showExerciseAnimation(BuildContext context, String name, ExerciseMediaUrls u, {String? subtitle}) {
  if (u.still == null && u.clip == null) return Future.value();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(name, style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        if (subtitle != null && subtitle.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle, style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.6)))),
        const SizedBox(height: 14),
        ExerciseAnimation(stillUrl: u.still, clipUrl: u.clip, height: 320, label: name),
      ]),
    ),
  );
}
