import '../../core/network/api_client.dart';
import '../../core/util/json.dart';
import '../models/dashboard.dart';

class DashboardRepository {
  DashboardRepository(this._api);
  final ApiClient _api;

  Future<DashboardSummary> summary() async => DashboardSummary.fromJson(
    (await _api.get('/v5/dashboards/gyms/summary')).map,
  );

  Future<OccupancySnapshot> occupancy() async => OccupancySnapshot.fromJson(
    (await _api.get('/v5/dashboards/gyms/occupancy')).map,
  );

  Future<List<Insight>> insights() async =>
      (await _api.get('/v5/dashboards/gyms/insights')).map
          .list('insights')
          .map(Insight.fromJson)
          .toList();

  Future<QuickReport> report({
    String period = 'thisMonth',
    String? from,
    String? to,
  }) async => QuickReport.fromJson(
    (await _api.get(
      '/v5/dashboards/gyms/reports/transactions',
      query: {'period': period, 'from': from, 'to': to},
    )).map,
  );

  Future<({String frequency, String? email})> reportSchedule() async {
    final m = (await _api.get('/v5/dashboards/gyms/reports/schedule')).map;
    return (frequency: m.s('frequency', 'off'), email: m.str('email'));
  }

  Future<void> saveReportSchedule(String frequency, String? email) async =>
      _api.put(
        '/v5/dashboards/gyms/reports/schedule',
        body: compact({'frequency': frequency, 'email': email}),
      );

  Future<({int total, List<({String date, int count})> days})>
  attendanceSummary(String period) async {
    final m = (await _api.get(
      '/v5/attendance/summary',
      query: {'period': period},
    )).map;
    return (
      total: m.i('total'),
      days: [
        for (final d in m.list('days'))
          (date: d.s('date'), count: d.i('count')),
      ],
    );
  }
}
