import 'dart:typed_data';

import '../../core/network/api_client.dart';
import '../../core/util/json.dart';
import '../models/leads.dart';

class LeadsRepository {
  LeadsRepository(this._api);
  final ApiClient _api;

  Future<ApiResponse> list(int page, int limit, Json q) => _api.get(
    '/v5/prospects/members',
    query: {...q, 'page': page, 'limit': limit},
  );
  Future<Lead> get(String id) async =>
      Lead.fromJson((await _api.get('/v5/prospects/members/$id')).map);
  Future<Lead> create(Json body) async =>
      Lead.fromJson((await _api.post('/v5/prospects/members', body: body)).map);
  Future<Lead> update(String id, Json body) async => Lead.fromJson(
    (await _api.patch('/v5/prospects/members/$id', body: body)).map,
  );
  Future<void> delete(String id) async =>
      _api.delete('/v5/prospects/members/$id');
  Future<Lead> setDisabled(String id, bool disabled) async => Lead.fromJson(
    (await _api.post(
      '/v5/prospects/members/$id/${disabled ? 'disable' : 'enable'}',
    )).map,
  );
  Future<Lead> snooze(String id, String preset, {String? date}) async =>
      Lead.fromJson(
        (await _api.post(
          '/v5/prospects/members/$id/snooze',
          body: compact({'preset': preset, 'date': date}),
        )).map,
      );
  Future<String> convert(String id, {Json? membership}) async =>
      (await _api.post(
        '/v5/prospects/members/$id/convert',
        body: compact({'membership': membership}),
      )).map.s('memberId');
  Future<Uint8List> export(Json q) =>
      _api.bytes('/v5/prospects/members/export', query: q);
}
