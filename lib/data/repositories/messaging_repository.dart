import 'dart:typed_data';

import '../../core/network/api_client.dart';
import '../../core/util/json.dart';
import '../models/messaging.dart';
import '../models/settings.dart';

class MessagingRepository {
  MessagingRepository(this._api);
  final ApiClient _api;

  // broadcasts
  Future<List<Broadcast>> broadcasts() async =>
      (await _api.get('/v5/broadcasts')).list.map(Broadcast.fromJson).toList();
  Future<Broadcast> broadcast(String id) async =>
      Broadcast.fromJson((await _api.get('/v5/broadcasts/$id')).map);
  Future<Broadcast> createBroadcast(Json body) async =>
      Broadcast.fromJson((await _api.post('/v5/broadcasts', body: body)).map);
  Future<Broadcast> updateBroadcast(String id, Json body) async =>
      Broadcast.fromJson(
        (await _api.patch('/v5/broadcasts/$id', body: body)).map,
      );
  Future<Broadcast> cancelBroadcast(String id) async =>
      Broadcast.fromJson((await _api.post('/v5/broadcasts/$id/cancel')).map);
  Future<RecipientPreview> previewRecipients(
    Json filter,
    List<String> exclude,
  ) async => RecipientPreview.fromJson(
    (await _api.post(
      '/v5/broadcasts/recipients/preview',
      body: {'filter': filter, 'excludeMemberIds': exclude},
    )).map,
  );

  // templates
  Future<List<NotificationTemplate>> notificationTemplates() async =>
      (await _api.get('/v5/message-templates/notifications')).list
          .map(NotificationTemplate.fromJson)
          .toList();
  Future<NotificationTemplate> updateNotificationTemplate(
    String key, {
    String? body,
    bool? auto,
  }) async => NotificationTemplate.fromJson(
    (await _api.patch(
      '/v5/message-templates/notifications/$key',
      body: compact({'body': body, 'auto': auto}),
    )).map,
  );
  Future<NotificationTemplate> resetNotificationTemplate(String key) async =>
      NotificationTemplate.fromJson(
        (await _api.post('/v5/message-templates/notifications/$key/reset')).map,
      );
  Future<({List<String> common, List<String> member})> variables(
    String entity,
  ) async {
    final m = (await _api.get('/v5/message-templates/entity/$entity')).map;
    return (
      common: m.strings('commonVariables'),
      member: m.strings('memberVariables'),
    );
  }

  Future<String> preview(String body, {String? memberId}) async =>
      (await _api.post(
        '/v5/message-templates/preview',
        body: compact({'body': body, 'memberId': memberId}),
      )).map.s('text');
  Future<List<BroadcastTemplate>> broadcastTemplates() async =>
      (await _api.get('/v5/broadcasts/templates')).list
          .map(BroadcastTemplate.fromJson)
          .toList();
  Future<void> createBroadcastTemplate(String title, String body) async => _api
      .post('/v5/broadcasts/templates', body: {'title': title, 'body': body});
  Future<void> updateBroadcastTemplate(
    String id,
    String title,
    String body,
  ) async => _api.patch(
    '/v5/broadcasts/templates/$id',
    body: {'title': title, 'body': body},
  );
  Future<void> deleteBroadcastTemplate(String id) async =>
      _api.delete('/v5/broadcasts/templates/$id');

  // credits
  Future<CreditStats> creditStats() async =>
      CreditStats.fromJson((await _api.get('/v5/credits/stats')).map);
  Future<List<CreditPack>> creditPacks() async =>
      (await _api.get('/v5/credit-packs')).list
          .map(CreditPack.fromJson)
          .toList();
  Future<ApiResponse> ledger(int page, int limit, Json q) => _api.get(
    '/v5/credits/transactions',
    query: {...q, 'page': page, 'limit': limit},
  );
  Future<Uint8List> exportLedger(Json q) =>
      _api.bytes('/v5/credits/transactions/export', query: q);
  Future<PaymentOrder> orderCredits(String packId) async =>
      PaymentOrder.fromJson(
        (await _api.post(
          '/v5/payments/orders/credit-packs',
          body: {'packId': packId},
        )).map,
      );
  Future<PaymentOrder> order(String id) async =>
      PaymentOrder.fromJson((await _api.get('/v5/payments/orders/$id')).map);

  // history & integrations
  Future<ApiResponse> messages(int page, int limit, Json q) =>
      _api.get('/v5/messages', query: {...q, 'page': page, 'limit': limit});
  Future<Uint8List> exportMessages(Json q) =>
      _api.bytes('/v5/messages/export', query: q);
  Future<List<Integration>> integrations() async =>
      (await _api.get('/v5/integrations')).list
          .map(Integration.fromJson)
          .toList();
  Future<void> setWhatsapp(bool enabled) async =>
      _api.post('/v5/integrations/whatsapp/${enabled ? 'enable' : 'disable'}');
}
