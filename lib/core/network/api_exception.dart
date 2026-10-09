import '../util/json.dart';

enum ApiFailure {
  network,
  unauthorized,
  forbidden,
  notFound,
  conflict,
  validation,
  rateLimited,
  server,
  unknown,
}

/// A failed API call, normalised from the backend's `{ error: { code, message, details } }` envelope.
class ApiException implements Exception {
  ApiException({
    required this.status,
    required this.code,
    required this.message,
    this.details,
    this.retryAfterSec,
  });

  final int status;
  final String code;
  final String message;
  final Json? details;
  final int? retryAfterSec;

  factory ApiException.network([String? detail]) => ApiException(
    status: 0,
    code: 'NETWORK',
    message: 'Please check your internet connection. Your internet connection is either very slow or unavailable. Please try again.',
    details: detail == null ? null : {'cause': detail},
  );

  factory ApiException.unexpected(String m) =>
      ApiException(status: -1, code: 'UNEXPECTED', message: m);

  ApiFailure get kind {
    if (status == 0) return ApiFailure.network;
    return switch (status) {
      401 => ApiFailure.unauthorized,
      403 => ApiFailure.forbidden,
      404 => ApiFailure.notFound,
      409 => ApiFailure.conflict,
      422 || 400 => ApiFailure.validation,
      429 => ApiFailure.rateLimited,
      >= 500 => ApiFailure.server,
      _ => ApiFailure.unknown,
    };
  }

  bool get isNetwork => status == 0;
  bool get isInsufficientCredits => code == 'INSUFFICIENT_CREDITS';

  /// Per-field messages from the backend validator, when present.
  Map<String, String> get fieldErrors => {
    if (details != null)
      for (final e in details!.entries)
        if (e.value is String) e.key: e.value as String,
  };

  @override
  String toString() => 'ApiException($status $code: $message)';
}
