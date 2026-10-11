import 'package:flutter/material.dart';

import '../domain/catalogue.dart';
import '../../member_models.dart';
import '../domain/rows.dart';
import '../domain/settings.dart';
import '../gym_api.dart';
import '../log_store.dart';

/// What every member screen needs: the log, the catalogue and who is signed in.
class NativeScope extends InheritedWidget {
  const NativeScope({
    super.key,
    required this.store,
    required this.catalogue,
    required this.memberName,
    required this.mediaBase,
    required this.overview,
    required this.gymApi,
    required this.signOut,
    required this.signOutEverywhere,
    required super.child,
  });

  final MemberLogStore store;
  final Catalogue catalogue;
  final String memberName;
  final String? mediaBase;

  /// The member's gym summary as last read from the server (cached, so it exists offline).
  final MemberOverview overview;
  final MemberGymApi gymApi;
  final Future<void> Function() signOut;

  /// Ends every session of this member (all phones). Throws when the server cannot be reached.
  final Future<void> Function() signOutEverywhere;

  static NativeScope of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<NativeScope>();
    assert(s != null, 'NativeScope missing');
    return s!;
  }

  Json get state => store.state;
  List<Exercise> get allExercises => catalogue.withCustom(store.state['customEx']);
  Exercise? exercise(String id) => catalogue.find(id, store.state['customEx']);
  String unit() => Prefs(store.state).unit;

  /// The member's settings (domain/settings.dart), read fresh each time.
  Prefs get prefs => Prefs(store.state);

  @override
  bool updateShouldNotify(NativeScope old) => old.store != store || old.catalogue != catalogue || old.memberName != memberName || old.overview != overview;
}
