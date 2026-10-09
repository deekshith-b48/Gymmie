import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../storage/token_store.dart';
import '../util/json.dart';
import 'api_exception.dart';

/// Decoded `{ data, meta }` envelope.
class ApiResponse {
  ApiResponse(this.data, this.meta, {this.headers});

  final Object? data;
  final Json meta;
  final Map<String, List<String>>? headers;

  Json get map =>
      data is Map ? (data as Map).cast<String, dynamic>() : <String, dynamic>{};
  List<Json> get list => data is List
      ? [
          for (final e in data as List)
            if (e is Map) e.cast<String, dynamic>(),
        ]
      : const [];
  List<String> get stringList =>
      data is List ? [for (final e in data as List) '$e'] : const [];
  bool get isEmpty => data == null;
  int get total => meta.i('total', list.length);
  int get page => meta.i('page', 1);
  int get totalPages => meta.i('totalPages', 1);
}

/// REST client for the DGymBook API.
///
///  * Adds `Authorization: Bearer` and `x-gym-id` (gym-scoped routes).
///  * On a 401, refreshes the session ONCE (single-flight) and retries the request
///    (the original app tracks this as `retriedAfter401`).
///  * Normalises failures to [ApiException].
class ApiClient {
  ApiClient({
    required this.config,
    required this.tokens,
    Dio? dio,
    Dio? refreshDio,
  }) : _dio = dio ?? Dio(_baseOptions()),
       _refreshDio = refreshDio ?? Dio(_baseOptions());

  final AppConfig config;
  final TokenStore tokens;
  final Dio _dio;
  final Dio _refreshDio;

  Future<bool>? _refreshing;
  final _sessionExpired = StreamController<void>.broadcast();

  /// Emits when the refresh token was rejected: the UI must send the user to sign-in.
  Stream<void> get onSessionExpired => _sessionExpired.stream;

  static BaseOptions _baseOptions() => BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    sendTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(seconds: 45),
    headers: {'Accept': 'application/json'},
    validateStatus: (_) => true, // we map statuses ourselves
  );

  Future<ApiResponse> get(
    String path, {
    Json? query,
    bool auth = true,
    bool gym = true,
  }) => _send('GET', path, query: query, auth: auth, gym: gym);
  Future<ApiResponse> post(
    String path, {
    Object? body,
    Json? query,
    bool auth = true,
    bool gym = true,
  }) => _send(
    'POST',
    path,
    body: body ?? const <String, dynamic>{},
    query: query,
    auth: auth,
    gym: gym,
  );
  Future<ApiResponse> put(String path, {Object? body, bool gym = true}) =>
      _send('PUT', path, body: body ?? const <String, dynamic>{}, gym: gym);
  Future<ApiResponse> patch(String path, {Object? body, bool gym = true}) =>
      _send('PATCH', path, body: body ?? const <String, dynamic>{}, gym: gym);
  Future<ApiResponse> delete(String path, {Json? query, bool gym = true}) =>
      _send('DELETE', path, query: query, gym: gym);

  /// Raw bytes with auth (CSV exports, images).
  Future<Uint8List> bytes(
    String pathOrUrl, {
    Json? query,
    bool gym = true,
  }) async {
    final r = await _raw(
      'GET',
      pathOrUrl,
      query: query,
      auth: true,
      gym: gym,
      responseType: ResponseType.bytes,
    );
    final d = r.data;
    return d is Uint8List ? d : Uint8List.fromList(List<int>.from(d as List));
  }

  Map<String, String> authHeaders({bool gym = true}) => {
    if (tokens.access != null) 'Authorization': 'Bearer ${tokens.access}',
    if (gym && tokens.gymId != null) 'x-gym-id': tokens.gymId!,
  };

  Future<ApiResponse> _send(
    String method,
    String path, {
    Object? body,
    Json? query,
    bool auth = true,
    bool gym = true,
  }) async {
    final r = await _raw(
      method,
      path,
      body: body,
      query: query,
      auth: auth,
      gym: gym,
    );
    final d = r.data;
    if (d is Map && d.containsKey('data')) {
      final meta = d['meta'];
      return ApiResponse(
        d['data'],
        meta is Map ? meta.cast<String, dynamic>() : <String, dynamic>{},
        headers: r.headers.map,
      );
    }
    return ApiResponse(d is Map || d is List ? d : null, <String, dynamic>{});
  }

  Future<Response<dynamic>> _raw(
    String method,
    String path, {
    Object? body,
    Json? query,
    bool auth = true,
    bool gym = true,
    ResponseType responseType = ResponseType.json,
    bool retried = false,
  }) async {
    if (!config.isConfigured) {
      throw ApiException.unexpected('Backend URL is not configured');
    }
    Response<dynamic> res;
    try {
      res = await _dio.request<dynamic>(
        config.absolute(path),
        data: body,
        queryParameters: query == null
            ? null
            : {
                for (final e in query.entries)
                  if (e.value != null && '${e.value}'.isNotEmpty)
                    e.key: '${e.value}',
              },
        options: Options(
          method: method,
          responseType: responseType,
          headers: auth ? authHeaders(gym: gym) : null,
          contentType: body == null ? null : Headers.jsonContentType,
        ),
      );
    } on DioException catch (e) {
      throw _mapTransport(e);
    }
    final status = res.statusCode ?? 0;
    if (status == 401 && auth && !retried && tokens.hasSession) {
      final ok = await _refreshOnce();
      if (ok) {
        return _raw(
          method,
          path,
          body: body,
          query: query,
          auth: auth,
          gym: gym,
          responseType: responseType,
          retried: true,
        );
      }
    }
    if (status >= 400) throw _mapError(res);
    return res;
  }

  Future<bool> _refreshOnce() =>
      _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<bool> _doRefresh() async {
    final rt = tokens.refresh;
    if (rt == null) return false;
    try {
      final r = await _refreshDio.post<dynamic>(
        config.absolute('/v5/auth/refresh'),
        data: {'refreshToken': rt},
        options: Options(contentType: Headers.jsonContentType),
      );
      if (r.statusCode == 200 &&
          r.data is Map &&
          (r.data as Map)['data'] is Map) {
        final d = ((r.data as Map)['data'] as Map).cast<String, dynamic>();
        await tokens.saveTokens(
          accessToken: d.s('accessToken'),
          refreshToken: d.s('refreshToken'),
        );
        return true;
      }
      if (r.statusCode == 401 || r.statusCode == 403) {
        await tokens.clear();
        _sessionExpired.add(null);
      }
      return false;
    } on DioException {
      // Offline: keep the session, let the original request fail as a network error.
      return false;
    }
  }

  ApiException _mapTransport(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return ApiException.network(e.message);
      default:
        if (kDebugMode) {
          debugPrint('API transport error: ${e.type} ${e.message}');
        }
        return ApiException.network(e.message);
    }
  }

  ApiException _mapError(Response<dynamic> res) {
    final status = res.statusCode ?? 500;
    final d = res.data;
    if (d is Map && d['error'] is Map) {
      final e = (d['error'] as Map).cast<String, dynamic>();
      final details = e['details'];
      return ApiException(
        status: status,
        code: e.s('code', 'ERROR'),
        message: e.s(
          'message',
          'Something went wrong. Please try again later.',
        ),
        details: details is Map ? details.cast<String, dynamic>() : null,
        retryAfterSec: details is Map
            ? (details['retryAfterSec'] as num?)?.toInt()
            : null,
      );
    }
    return ApiException(
      status: status,
      code: 'HTTP_$status',
      message: status >= 500
          ? 'Something went wrong. Please try again later.'
          : 'Request failed ($status)',
    );
  }

  void dispose() => _sessionExpired.close();
}
