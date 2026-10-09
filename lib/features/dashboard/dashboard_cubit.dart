import '../../core/state/async_cubit.dart';
import '../../data/models/dashboard.dart';
import '../../data/repositories/dashboard_repository.dart';

class HomeData {
  const HomeData({
    required this.summary,
    this.insights = const [],
    this.week = const [],
    this.month = const [],
  });
  final DashboardSummary summary;
  final List<Insight> insights;
  final List<({String date, int count})> week;
  final List<({String date, int count})> month;
}

/// Loads the dashboard. The summary is required; insights and the attendance series are
/// best-effort (a gym without the AI_INSIGHTS flag simply gets none).
class DashboardCubit extends AsyncCubit<HomeData> {
  DashboardCubit(
    DashboardRepository repo, {
    required bool wantsInsights,
    required bool wantsAttendance,
  }) : super(() async {
         final summary = await repo.summary();
         final results = await Future.wait<Object?>([
           wantsInsights
               ? repo.insights().catchError((Object _) => <Insight>[])
               : Future.value(<Insight>[]),
           wantsAttendance
               ? repo
                     .attendanceSummary('thisWeek')
                     .then<Object?>((v) => v)
                     .catchError((Object _) => null)
               : Future<Object?>.value(null),
           wantsAttendance
               ? repo
                     .attendanceSummary('thisMonth')
                     .then<Object?>((v) => v)
                     .catchError((Object _) => null)
               : Future<Object?>.value(null),
         ]);
         final w =
             results[1]
                 as ({int total, List<({String date, int count})> days})?;
         final m =
             results[2]
                 as ({int total, List<({String date, int count})> days})?;
         return HomeData(
           summary: summary,
           insights: results[0] as List<Insight>,
           week: w?.days ?? const [],
           month: m?.days ?? const [],
         );
       });
}
