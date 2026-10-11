import 'dart:convert';
import 'dart:typed_data';

import '../../core/network/api_client.dart';
import '../../core/util/json.dart';
import '../models/members.dart';
import '../models/settings.dart';
import '../models/plans.dart';

class MembersRepository {
  MembersRepository(this._api);
  final ApiClient _api;

  Future<ApiResponse> list(int page, int limit, Json query) =>
      _api.get('/v5/members', query: {...query, 'page': page, 'limit': limit});

  /// Members' renewal / plan-change / cancellation requests (pending first).
  Future<List<MembershipRequestRow>> membershipRequests({String? status}) async =>
      (await _api.get('/v5/membership-requests', query: {'status': ?status, 'limit': 100}))
          .list
          .map(MembershipRequestRow.fromJson)
          .toList();

  /// Records the gym's answer. It does not change the membership or any money: staff do that as usual.
  Future<void> decideRequest(String id, {required bool approve, String? note}) async {
    await _api.post(
      '/v5/membership-requests/$id/decision',
      body: {'decision': approve ? 'approve' : 'reject', if (note != null && note.isNotEmpty) 'note': note},
    );
  }

  /// A link the member can pay their dues with, through the gym's own payment account.
  Future<DuesLink> duesPaymentLink(String memberId, {double? amount}) async =>
      DuesLink.fromJson((await _api.post('/v5/members/$memberId/payment-link', body: {'amount': ?amount})).map);

  /// A new access code for the member (the old one stops working at once). The code is in this answer only.
  Future<({String code, String issuedAt})> issueAccessCode(String memberId) async {
    final r = (await _api.post('/v5/members/$memberId/access-code')).map;
    return (code: r.s('accessCode'), issuedAt: r.s('issuedAt'));
  }

  Future<void> revokeAccessCode(String memberId) async {
    await _api.delete('/v5/members/$memberId/access-code');
  }

  Future<void> inviteToApp(String memberId) async {
    await _api.post('/v5/members/$memberId/app-invite');
  }

  Future<void> reopenApp(String memberId) async {
    await _api.post('/v5/members/$memberId/member-app/reopen');
  }

  Future<MemberDetail> detail(String id) async =>
      MemberDetail.fromJson((await _api.get('/v5/members/$id')).map);

  Future<MemberSummary> create(Json body) async =>
      MemberSummary.fromJson((await _api.post('/v5/members', body: body)).map);

  Future<MemberSummary> update(String id, Json body) async =>
      MemberSummary.fromJson(
        (await _api.patch('/v5/members/$id', body: body)).map,
      );

  Future<void> delete(String id) async => _api.delete('/v5/members/$id');

  Future<MemberSummary> block(String id, {String? reason}) async =>
      MemberSummary.fromJson(
        (await _api.post(
          '/v5/members/$id/block',
          body: compact({'reason': reason}),
        )).map,
      );

  Future<MemberSummary> unblock(String id) async =>
      MemberSummary.fromJson((await _api.post('/v5/members/$id/unblock')).map);

  Future<MemberSummary> setLabels(String id, List<String> labelIds) async =>
      MemberSummary.fromJson(
        (await _api.put(
          '/v5/members/$id/labels',
          body: {'labelIds': labelIds},
        )).map,
      );

  Future<MemberSummary> setTrainer(String id, String? trainerId) async =>
      MemberSummary.fromJson(
        (await _api.put(
          '/v5/members/$id/trainer',
          body: {'trainerId': trainerId},
        )).map,
      );

  Future<Uint8List> exportCsv(Json query) =>
      _api.bytes('/v5/members/export', query: query);

  Future<List<({MemberSummary member, List<RiskReason> reasons})>>
  atRisk() async {
    final r = await _api.get('/v5/members/insights/at-risk');
    return [
      for (final j in r.list)
        (
          member: MemberSummary.fromJson(j),
          reasons: j.list('reasons').map(RiskReason.fromJson).toList(),
        ),
    ];
  }

  // ---- health ----
  Future<HealthSummary> health(String id) async =>
      HealthSummary.fromJson((await _api.get('/v5/members/$id/health')).map);

  Future<HealthSummary> addHealth(
    String id, {
    required String type,
    required double value,
    String? date,
  }) async => HealthSummary.fromJson(
    (await _api.post(
      '/v5/members/$id/health',
      body: compact({'type': type, 'value': value, 'date': date}),
    )).map,
  );

  Future<void> addCondition(String id, String name, {String? notes}) async =>
      _api.post(
        '/v5/members/$id/conditions',
        body: compact({'name': name, 'notes': notes}),
      );

  Future<void> deleteCondition(String id, String conditionId) async =>
      _api.delete('/v5/members/$id/conditions/$conditionId');

  Future<List<String>> healthConditionNames() async => (await _api.get(
    '/v5/masters/health-conditions',
    auth: false,
    gym: false,
  )).stringList;

  // ---- labels ----
  Future<List<LabelRef>> labels({String scope = 'member'}) async =>
      (await _api.get(
        '/v5/gyms/tags',
        query: {'scope': scope},
      )).list.map(LabelRef.fromJson).toList();

  Future<LabelRef> createLabel(
    String name, {
    String color = '#061750',
    String scope = 'member',
  }) async => LabelRef.fromJson(
    (await _api.post(
      '/v5/gyms/tags',
      body: {'name': name, 'color': color, 'scope': scope},
    )).map,
  );

  Future<void> updateLabel(String id, {String? name, String? color}) async =>
      _api.patch(
        '/v5/gyms/tags/$id',
        body: compact({'name': name, 'color': color}),
      );

  Future<void> deleteLabel(String id) async => _api.delete('/v5/gyms/tags/$id');

  // ---- documents ----
  Future<List<Json>> documents(String id) async =>
      (await _api.get('/v5/members/$id/documents')).list;

  Future<void> addUrlDocument(String id, String title, String url) async =>
      _api.post(
        '/v5/members/$id/documents',
        body: {'title': title, 'type': 'url', 'url': url},
      );

  Future<void> addFileDocument(
    String id,
    String title,
    List<int> bytes,
    String contentType,
  ) async => _api.post(
    '/v5/members/$id/documents',
    body: {
      'title': title,
      'type': 'file',
      'file': {'data': base64Encode(bytes), 'contentType': contentType},
    },
  );

  Future<void> deleteDocument(String id, String docId) async =>
      _api.delete('/v5/members/$id/documents/$docId');
}

class MembershipsRepository {
  MembershipsRepository(this._api);
  final ApiClient _api;

  Future<Quote> quote({
    required String planId,
    Json? discount,
    String? memberId,
    String? startDate,
  }) async => Quote.fromJson(
    (await _api.post(
      '/v5/memberships/quote',
      body: compact({
        'planId': planId,
        'discount': discount,
        'memberId': memberId,
        'startDate': startDate,
      }),
    )).map,
  );

  Future<Membership> create(Json body) async =>
      Membership.fromJson((await _api.post('/v5/memberships', body: body)).map);

  Future<Membership> get(String id) async =>
      Membership.fromJson((await _api.get('/v5/memberships/$id')).map);

  Future<Membership> extend(String id, int days, {String? reason}) async =>
      Membership.fromJson(
        (await _api.post(
          '/v5/memberships/$id/extend',
          body: compact({'days': days, 'reason': reason}),
        )).map,
      );

  Future<Membership> freeze(String id, {String? date}) async =>
      Membership.fromJson(
        (await _api.post(
          '/v5/memberships/$id/freeze',
          body: compact({'date': date}),
        )).map,
      );

  Future<Membership> resume(String id) async =>
      Membership.fromJson((await _api.post('/v5/memberships/$id/resume')).map);

  Future<Membership> end(String id, {String? reason}) async =>
      Membership.fromJson(
        (await _api.post(
          '/v5/memberships/$id/end',
          body: compact({'reason': reason}),
        )).map,
      );

  Future<Membership> startNow(String id) async =>
      Membership.fromJson((await _api.post('/v5/memberships/$id/start')).map);

  Future<Membership> upgrade(String id, Json body) async => Membership.fromJson(
    (await _api.post('/v5/memberships/$id/upgrade', body: body)).map,
  );

  Future<Membership> markSession(
    String id, {
    String? date,
    String? note,
  }) async => Membership.fromJson(
    (await _api.post(
      '/v5/memberships/$id/sessions',
      body: compact({'date': date, 'note': note}),
    )).map,
  );

  Future<Membership> unmarkSession(String id, String logId) async =>
      Membership.fromJson(
        (await _api.delete('/v5/memberships/$id/sessions/$logId')).map,
      );
}

class PlansRepository {
  PlansRepository(this._api);
  final ApiClient _api;

  Future<List<Plan>> plans({
    bool includeDisabled = false,
    String? groupId,
  }) async => (await _api.get(
    '/v5/memberships/plans',
    query: {
      'includeDisabled': includeDisabled ? 'true' : null,
      'groupId': groupId,
    },
  )).list.map(Plan.fromJson).toList();

  Future<Plan> create(Json body) async =>
      Plan.fromJson((await _api.post('/v5/memberships/plans', body: body)).map);
  Future<Plan> update(String id, Json body) async => Plan.fromJson(
    (await _api.patch('/v5/memberships/plans/$id', body: body)).map,
  );
  Future<Plan> duplicate(String id) async => Plan.fromJson(
    (await _api.post('/v5/memberships/plans/$id/duplicate')).map,
  );
  Future<Plan> setActive(String id, bool active) async => Plan.fromJson(
    (await _api.post(
      '/v5/memberships/plans/$id/${active ? 'enable' : 'disable'}',
    )).map,
  );
  Future<void> delete(String id) async =>
      _api.delete('/v5/memberships/plans/$id');

  Future<List<PlanGroup>> groups() async =>
      (await _api.get('/v5/memberships/plan-groups')).list
          .map(PlanGroup.fromJson)
          .toList();
  Future<PlanGroup> createGroup(String name) async => PlanGroup.fromJson(
    (await _api.post('/v5/memberships/plan-groups', body: {'name': name})).map,
  );
  Future<void> renameGroup(String id, String name) async =>
      _api.patch('/v5/memberships/plan-groups/$id', body: {'name': name});
  Future<void> deleteGroup(String id, {String? moveTo}) async =>
      _api.delete('/v5/memberships/plan-groups/$id', query: {'moveTo': moveTo});

  // ---- tax ----
  Future<List<TaxConfig>> taxes() async =>
      (await _api.get('/v5/gyms/tax')).list.map(TaxConfig.fromJson).toList();
  Future<TaxConfig> createTax(Json body) async =>
      TaxConfig.fromJson((await _api.post('/v5/gyms/tax', body: body)).map);
  Future<TaxConfig> updateTax(String id, Json body) async => TaxConfig.fromJson(
    (await _api.patch('/v5/gyms/tax/$id', body: body)).map,
  );
  Future<void> deleteTax(String id) async => _api.delete('/v5/gyms/tax/$id');
}
