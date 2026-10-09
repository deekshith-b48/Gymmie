import '../../core/network/api_client.dart';
import '../../core/util/json.dart';

/// Feedback, video links, biometric devices, PAR-Q and push-token registration.
class ExtrasRepository {
  ExtrasRepository(this._api);
  final ApiClient _api;

  // Feedback
  Future<List<Json>> feedbacks({bool favoriteOnly = false}) async =>
      (await _api.get(
        '/v5/feedbacks',
        query: {if (favoriteOnly) 'favorite': 'true'},
      )).list;
  Future<Json> feedbackStats() async =>
      (await _api.get('/v5/feedbacks/stats')).map;
  Future<void> markSeen(String id) async => _api.post('/v5/feedbacks/$id/seen');
  Future<void> setFavorite(String id, bool v) async =>
      _api.post('/v5/feedbacks/$id/favorite', body: {'isFavorite': v});

  // Video links
  Future<List<Json>> videos() async => (await _api.get('/v5/video-links')).list;
  Future<void> createVideo(Json b) async =>
      _api.post('/v5/video-links', body: b);
  Future<void> updateVideo(String id, Json b) async =>
      _api.patch('/v5/video-links/$id', body: b);
  Future<void> deleteVideo(String id) async =>
      _api.delete('/v5/video-links/$id');

  // Biometric devices
  Future<List<Json>> devices() async =>
      (await _api.get('/v3/biohub/devices')).list;
  Future<Json> createDevice(Json b) async =>
      (await _api.post('/v3/biohub/devices', body: b)).map;
  Future<void> updateDevice(String id, Json b) async =>
      _api.patch('/v3/biohub/devices/$id', body: b);
  Future<void> deleteDevice(String id) async =>
      _api.delete('/v3/biohub/devices/$id');
  Future<String> rotateKey(String id) async =>
      (await _api.post('/v3/biohub/devices/$id/rotate-key')).map.s('deviceKey');
  Future<void> forceSync() async => _api.post('/v5/biohub/force-sync');

  // PAR-Q
  Future<Json> parqForm() async => (await _api.get('/v5/parq-form')).map;
  Future<List<String>> parqAreas() async =>
      (await _api.get('/v5/parq-form/areas')).stringList;
  Future<Json> parqGenerate(List<String> areas) async =>
      (await _api.post('/v5/parq-form/generate', body: {'areas': areas})).map;
  Future<Json> parqSave(Json b) async =>
      (await _api.put('/v5/parq-form', body: b)).map;
  Future<Json> parqStatus() async => (await _api.get('/v5/parq/status')).map;
  Future<List<Json>> parqSubmissions(String memberId) async => (await _api.get(
    '/v5/parq/submissions',
    query: {'memberId': memberId},
  )).list;
  Future<Json> parqSign(String memberId, Json b) async =>
      (await _api.post('/v5/members/$memberId/parq/sign', body: b)).map;

  // Push token
  Future<void> registerPushToken(String token, {String? deviceId}) async =>
      _api.post(
        '/v5/notifiers',
        body: {'fcmToken': token, 'platform': 'android', 'deviceId': ?deviceId},
        gym: false,
      );
}
