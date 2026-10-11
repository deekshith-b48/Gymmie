// The exercise animation behaves as openGym's: the still first, the clip over it, tap to pause, and a still (or a plain tile)
// when the network lets it down. The video platform is replaced by a fake controller.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_book_app/core/widgets/exercise_animation.dart';
import 'package:video_player/video_player.dart';

class _FakeController extends VideoPlayerController {
  _FakeController(this.failInit) : super.networkUrl(Uri.parse('https://x/clip.mp4'));
  final bool failInit;
  int plays = 0, pauses = 0;
  bool looping = false;
  double volume = 1;
  bool disposedFlag = false;
  VideoPlayerValue _v = const VideoPlayerValue(duration: Duration(seconds: 2));
  @override
  VideoPlayerValue get value => _v;
  @override
  Future<void> initialize() async {
    if (failInit) throw Exception('no network');
    _v = const VideoPlayerValue(duration: Duration(seconds: 2), size: Size(180, 180), isInitialized: true);
  }
  @override
  Future<void> play() async { plays++; }
  @override
  Future<void> pause() async { pauses++; }
  @override
  Future<void> setLooping(bool l) async { looping = l; }
  @override
  Future<void> setVolume(double v) async { volume = v; }
  @override
  // ignore: must_call_super
  Future<void> dispose() async { disposedFlag = true; }
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

void main() {
  late _FakeController last;
  bool failInit = false;
  setUp(() {
    failInit = false;
    clipControllerFactory = (_) => last = _FakeController(failInit);
  });
  tearDown(() => clipControllerFactory = (u) => VideoPlayerController.networkUrl(u));

  Widget host(Widget w) => MaterialApp(home: Scaffold(body: Center(child: w)));

  testWidgets('the clip starts muted and looping by itself, and the hint says it can be paused', (t) async {
    await t.pumpWidget(host(const ExerciseAnimation(stillUrl: 'https://x/still.webp', clipUrl: 'https://x/clip.mp4')));
    await t.pump();
    await t.pump();
    expect(last.plays, 1);
    expect(last.looping, isTrue);
    expect(last.volume, 0, reason: 'silent, as in a gym');
    expect(find.text('tap to pause'), findsOneWidget);
  });

  testWidgets('a tap pauses it (back to the still) and another plays it again', (t) async {
    await t.pumpWidget(host(const ExerciseAnimation(stillUrl: 'https://x/still.webp', clipUrl: 'https://x/clip.mp4')));
    await t.pump();
    await t.pump();
    await t.tap(find.byType(ExerciseAnimation));
    await t.pump();
    expect(last.pauses, 1);
    expect(find.text('tap to play'), findsOneWidget);
    await t.tap(find.byType(ExerciseAnimation));
    await t.pump();
    expect(last.plays, 2);
    expect(find.text('tap to pause'), findsOneWidget);
  });

  testWidgets('if the clip cannot load the still stays, with no error and no hint; a tap tries again', (t) async {
    failInit = true;
    await t.pumpWidget(host(const ExerciseAnimation(stillUrl: 'https://x/still.webp', clipUrl: 'https://x/clip.mp4')));
    await t.pump();
    await t.pump();
    expect(find.byType(VideoPlayer), findsNothing, reason: 'no video surface when the clip failed');
    expect(find.text('tap to pause'), findsNothing);
    expect(t.takeException(), isNull);
    failInit = false;
    await t.tap(find.byType(ExerciseAnimation));
    await t.pump();
    await t.pump();
    expect(last.plays, 1, reason: 'the retry started a fresh clip');
    expect(find.text('tap to pause'), findsOneWidget);
  });

  testWidgets('the Minimize / Expand control reports the tap without pausing the clip', (t) async {
    var taps = 0;
    await t.pumpWidget(host(ExerciseAnimation(stillUrl: 'https://x/s.webp', clipUrl: 'https://x/c.mp4', onToggleSize: () => taps++)));
    await t.pump();
    await t.pump();
    expect(find.text('Minimize'), findsOneWidget);
    await t.tap(find.text('Minimize'));
    expect(taps, 1);
    expect(last.pauses, 0);
  });

  testWidgets('a mini animation says Expand and has no hint', (t) async {
    await t.pumpWidget(host(ExerciseAnimation(stillUrl: 'https://x/s.webp', clipUrl: 'https://x/c.mp4', mini: true, height: 84, onToggleSize: () {})));
    await t.pump();
    expect(find.text('Expand'), findsOneWidget);
    expect(find.text('tap to pause'), findsNothing);
  });

  testWidgets('without any media there is a plain tile, never a broken image', (t) async {
    await t.pumpWidget(host(const ExerciseAnimation(stillUrl: null, clipUrl: null)));
    await t.pump();
    expect(find.byIcon(Icons.fitness_center), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(find.byType(VideoPlayer), findsNothing);
  });

  testWidgets('leaving the screen disposes the video', (t) async {
    await t.pumpWidget(host(const ExerciseAnimation(stillUrl: 'https://x/s.webp', clipUrl: 'https://x/c.mp4')));
    await t.pump();
    await t.pump();
    await t.pumpWidget(host(const SizedBox()));
    expect(last.disposedFlag, isTrue);
  });

  test('media URLs are built under the host, and a missing host means no media', () {
    final u = ExerciseMediaUrls.of(base: 'https://m.example.com/', img: '5965.webp', gif: '5965.mp4');
    expect(u.still, 'https://m.example.com/exercise-media/still/5965.webp');
    expect(u.clip, 'https://m.example.com/exercise-media/clip/5965.mp4');
    final none = ExerciseMediaUrls.of(base: null, img: 'a.webp', gif: 'a.mp4');
    expect([none.still, none.clip], [null, null]);
    expect(ExerciseMediaUrls.of(base: 'https://m', img: '', gif: '').clip, isNull);
  });
}
