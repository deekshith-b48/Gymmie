import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChrome, SystemUiOverlayStyle;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/di.dart';
import '../../member_repository.dart';
import '../../member_session_cubit.dart';
import '../domain/catalogue.dart';
import '../domain/settings.dart';
import '../log_store.dart';
import 'exercises_tab.dart';
import 'home_screen.dart';
import 'plan_screen.dart';
import 'member_welcome.dart';
import 'reminders.dart';
import 'scope.dart';
import 'start_screen.dart';
import 'stats_screen.dart';
import 'theme.dart';
import 'widgets.dart' show setWeightDecimals;

/// The member's whole app: its own MaterialApp in openGym's dark look.
///
/// Loads the catalogue and this member's log first, then shows the app. Works offline once the
/// member has signed in on this phone (the identity is cached; the log is local-first). The scope
/// sits ABOVE the MaterialApp so every pushed screen (workout, library, settings…) can reach it.
class NativeMemberApp extends StatefulWidget {
  const NativeMemberApp({super.key});

  @override
  State<NativeMemberApp> createState() => _NativeMemberAppState();
}

class _NativeMemberAppState extends State<NativeMemberApp> with WidgetsBindingObserver {
  MemberLogStore? _store;
  Catalogue? _catalogue;
  Object? _error;
  String? _key;
  late final MemberSessionCubit _session = getIt<MemberSessionCubit>();
  StreamSubscription<MemberSessionState>? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sub = _session.stream.listen((_) {
      _maybeStart();
      if (mounted) setState(() {});
    });
    _maybeStart();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _store?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      _store?.sync();
      _session.refresh(); // membership may have been renewed or ended at the desk
    }
  }

  Future<void> _maybeStart() async {
    final o = _session.state.overview;
    if (o == null) return;
    final key = 'memberlog:${o.gym.id}:${o.id}';
    if (key == _key) return;
    _key = key;
    try {
      final cat = await Catalogue.load();
      final store = MemberLogStore(key: key, prefs: getIt<SharedPreferences>(), api: getIt<MemberRepository>())
        ..onAuthProblem = () => _session.refresh();
      await store.load();
      _store?.dispose();
      if (!mounted) return;
      setState(() { _catalogue = cat; _store = store; _error = null; });
      unawaited(store.sync());
    } catch (e) {
      _key = null;
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _signOut() async {
    await WorkoutReminders.cancel();
    final store = _store;
    if (store != null) {
      // Send what is waiting (best effort). If something could not be sent, keep this phone's copy
      // for the next sign-in instead of losing it; otherwise forget it (the account keeps its copy).
      await store.sync().timeout(const Duration(seconds: 6), onTimeout: () {});
      if (!store.dirty) await store.wipeLocal();
    }
    await _session.signOut();
  }

  /// Sign out on every phone. The server must answer (it holds the sessions); if it cannot be reached nothing
  /// changes and the caller says so.
  Future<void> _signOutEverywhere() async {
    await WorkoutReminders.cancel();
    final store = _store;
    if (store != null) await store.sync().timeout(const Duration(seconds: 6), onTimeout: () {});
    await _session.revokeEverywhere();
    if (store != null && !store.dirty) await store.wipeLocal();
    await _session.signOut(); // leave the app (the sessions are already gone)
  }

  Widget _plain(Widget body) => MaterialApp(
    title: 'Gymmie', debugShowCheckedModeBanner: false, theme: ogTheme(), darkTheme: ogTheme(), themeMode: OG.palette.dark ? ThemeMode.dark : ThemeMode.light,
    home: Scaffold(body: Center(child: body)),
  );

  @override
  Widget build(BuildContext context) {
    final o = _session.state.overview;
    final store = _store;
    final cat = _catalogue;
    if (_error != null) {
      return _plain(Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.error_outline, color: OG.red, size: 40),
        const SizedBox(height: 12),
        Text('Could not open your training log.\n$_error', textAlign: TextAlign.center, style: TextStyle(color: OG.dim)),
        const SizedBox(height: 16),
        FilledButton(onPressed: () { setState(() => _error = null); _maybeStart(); }, child: const Text('Try again')),
      ])));
    }
    // right after a sign-in: "Welcome to <gym>!" for about three seconds, while the training log loads behind it
    if (_session.state.welcome && o != null) {
      return MaterialApp(
        title: 'Gymmie', debugShowCheckedModeBanner: false, theme: ogTheme(), darkTheme: ogTheme(), themeMode: OG.palette.dark ? ThemeMode.dark : ThemeMode.light,
        home: MemberWelcome(gymName: o.gym.name, memberName: o.name, onDone: _session.dismissWelcome),
      );
    }
    if (store == null || cat == null || o == null) {
      final failed = _session.state.error != null && o == null;
      return _plain(failed
          ? Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.cloud_off, color: OG.orange, size: 40), const SizedBox(height: 12),
              Text("Can't reach your gym right now.", style: TextStyle(color: OG.dim)),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => _session.refresh(), child: const Text('Try again')),
              TextButton(onPressed: _signOut, child: const Text('Sign out')),
            ]))
          : const CircularProgressIndicator());
    }
    return NativeScope(
      store: store,
      catalogue: cat,
      memberName: o.name,
      mediaBase: o.mediaBase,
      overview: o,
      gymApi: getIt<MemberRepository>(),
      signOut: _signOut,
      signOutEverywhere: _signOutEverywhere,
      child: ThemedMemberApp(store: store),
    );
  }
}

/// The member app's MaterialApp, dressed in the member's own theme and accent (Settings → Look & Home).
///
/// The palette lives in [OG]; when the member changes the theme, the accent, or the system switches between
/// light and dark, a new palette is installed and every screen repaints at once (the navigation stack, an open
/// workout and the Settings page the change was made on stay exactly where they are).
class ThemedMemberApp extends StatefulWidget {
  const ThemedMemberApp({super.key, required this.store, this.home = const NativeShell()});
  final MemberLogStore store;

  /// The first screen; the whole app in production, a screen under test otherwise.
  final Widget home;

  @override
  State<ThemedMemberApp> createState() => _ThemedMemberAppState();
}

class _ThemedMemberAppState extends State<ThemedMemberApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // a new day may have started: today's reminder is skipped only if a workout is logged today
    if (state == AppLifecycleState.resumed) WorkoutReminders.sync(widget.store.state, force: true);
  }

  void _repaintEverything() {
    void visit(Element e) {
      e.markNeedsBuild();
      e.visitChildren(visit);
    }
    if (mounted) (context as Element).visitChildren(visit);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: widget.store, builder: (context, _) {
    final log = widget.store.state;
    WorkoutReminders.sync(log);
    setWeightDecimals(Prefs(log).decimals);
    final systemDark = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    final pal = OGPalette.of(log, systemDark: systemDark);
    final style = (pal.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(statusBarColor: Colors.transparent, systemNavigationBarColor: Colors.transparent);
    if (pal.signature != OG.palette.signature) {
      OG.palette = pal;
      WidgetsBinding.instance.addPostFrameCallback((_) => _repaintEverything());
    }
    // A screen without an app bar (Home) sets no icon colour of its own, so say it for the whole app.
    SystemChrome.setSystemUIOverlayStyle(style);
    final theme = ogTheme(pal);
    return MaterialApp(
      title: 'Gymmie',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
      themeMode: pal.dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: style,
        child: child ?? const SizedBox.shrink(),
      ),
      home: widget.home,
    );
  });
}

/// Home · Plan · Start · Stats · Exercises, as in openGym.
class NativeShell extends StatefulWidget {
  const NativeShell({super.key});

  @override
  State<NativeShell> createState() => _NativeShellState();
}

class _NativeShellState extends State<NativeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final sc = NativeScope.of(context);
    return Scaffold(
      body: IndexedStack(index: _tab, children: [
        HomeScreen(onTab: (i) => setState(() => _tab = i)),
        const PlanScreen(),
        const SizedBox.shrink(),
        const StatsScreen(),
        const LibraryTab(),
      ]),
      bottomNavigationBar: ListenableBuilder(listenable: sc.store, builder: (context, _) {
        final running = sc.store.active != null;
        Widget item(int i, IconData icon, String label) => Expanded(child: InkWell(
          onTap: () => setState(() => _tab = i),
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: _tab == i ? OG.acc : OG.dim), const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: _tab == i ? OG.acc : OG.dim, fontWeight: FontWeight.w600)),
          ])),
        ));
        return Container(
          decoration: BoxDecoration(color: OG.card, border: Border(top: BorderSide(color: OG.line))),
          child: SafeArea(top: false, child: SizedBox(height: 74, child: Row(children: [
            item(0, Icons.home_filled, 'Home'),
            item(1, Icons.calendar_month, 'Plan'),
            Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
              GestureDetector(
                onTap: () => running ? openWorkout(context) : Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const StartScreen())),
                child: Container(
                  width: 50, height: 50, decoration: BoxDecoration(shape: BoxShape.circle, color: running ? OG.orange : OG.acc, boxShadow: [BoxShadow(color: (running ? OG.orange : OG.acc).withValues(alpha: 0.4), blurRadius: 12)]),
                  child: Icon(running ? Icons.play_arrow : Icons.fitness_center, color: OG.onAcc, size: 26),
                ),
              ),
              Text(running ? 'Resume' : 'Start', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: running ? OG.orange : OG.acc)),
            ])),
            item(3, Icons.bar_chart, 'Stats'),
            item(4, Icons.list, 'Exercises'),
          ]))),
        );
      }),
    );
  }
}

