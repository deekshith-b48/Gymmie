import 'dart:convert';

import '../../core/network/api_client.dart';
import '../../core/util/json.dart';
import '../models/settings.dart';

/// Gym-level settings: profile, features, preferences, payment methods, QR, subscription, timezones.
class GymRepository {
  GymRepository(this._api);
  final ApiClient _api;

  Future<void> updateGym(String id, Json patch) async =>
      _api.patch('/v5/gyms/$id', body: patch);

  Future<void> setLogo(String id, List<int> bytes, String contentType) async =>
      _api.patch(
        '/v5/gyms/$id',
        body: {
          'logo': {'data': base64Encode(bytes), 'contentType': contentType},
        },
      );

  Future<List<FeatureItem>> features() async =>
      (await _api.get('/v5/gyms/features')).list
          .map(FeatureItem.fromJson)
          .toList();
  Future<List<FeatureItem>> setFeature(String key, bool enabled) async =>
      (await _api.put(
        '/v5/gyms/features/$key',
        body: {'enabled': enabled},
      )).list.map(FeatureItem.fromJson).toList();

  Future<void> setPreferences({
    bool? simpleMemberCard,
    bool? renewalSound,
  }) async => _api.patch(
    '/v5/gyms/preferences',
    body: compact({
      'simpleMemberCard': simpleMemberCard,
      'renewalSound': renewalSound,
    }),
  );

  Future<void> setPaymentMethods(
    List<String> active,
    String defaultType,
  ) async => _api.put(
    '/v5/gyms/payment-methods',
    body: {'active': active, 'default': defaultType},
  );

  Future<({String payload, int version, String gymCode})> portalQr() async {
    final m = (await _api.get('/v5/gyms/portal/qr')).map;
    return (
      payload: m.s('payload'),
      version: m.i('version'),
      gymCode: m.s('gymCode'),
    );
  }

  Future<({String payload, int version, String gymCode})> regenerateQr() async {
    final m = (await _api.post('/v5/gyms/portal/qr/regenerate')).map;
    return (
      payload: m.s('payload'),
      version: m.i('version'),
      gymCode: m.s('gymCode'),
    );
  }

  Future<List<String>> timezones() async => (await _api.get(
    '/v5/masters/timezones',
    auth: false,
    gym: false,
  )).stringList;

  // ---- subscription ----
  Future<({Json? current, List<SubscriptionPlanOption> plans})>
  subscriptions() async {
    final m = (await _api.get('/v5/billings/subscriptions')).map;
    return (
      current: m.obj('current'),
      plans: m.list('plans').map(SubscriptionPlanOption.fromJson).toList(),
    );
  }

  Future<SubscriptionUsage> usage() async => SubscriptionUsage.fromJson(
    (await _api.get('/v5/billings/subscriptions/usage')).map,
  );
  Future<List<PaymentOrder>> subscriptionHistory() async =>
      (await _api.get('/v5/billings/subscriptions/history')).list
          .map(PaymentOrder.fromJson)
          .toList();
  Future<PaymentOrder> subscriptionOrder(String planId) async =>
      PaymentOrder.fromJson(
        (await _api.post(
          '/v5/payments/orders/renewal-link',
          body: {'planId': planId},
        )).map,
      );
  Future<PaymentOrder> order(String id) async =>
      PaymentOrder.fromJson((await _api.get('/v5/payments/orders/$id')).map);

  // ---- push token ----
  Future<void> registerPushToken(String token, {String? deviceId}) async =>
      _api.post(
        '/v5/notifiers',
        body: compact({
          'fcmToken': token,
          'platform': 'android',
          'deviceId': deviceId,
        }),
        gym: false,
      );

  // ---- announcements ----
  Future<List<Json>> announcements() async =>
      (await _api.get('/v5/me/feature-announcements', gym: false)).list;
  Future<void> markAnnouncementSeen(String id) async =>
      _api.post('/v5/me/feature-announcements/$id/seen', gym: false);
}
