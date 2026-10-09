typedef Json = Map<String, dynamic>;

/// Tolerant accessors for decoded JSON. Server responses are validated server-side;
/// the client never crashes on a missing optional field.
extension JsonX on Map<String, dynamic> {
  String? str(String k) {
    final v = this[k];
    if (v == null) return null;
    return v is String ? v : '$v';
  }

  String s(String k, [String d = '']) => str(k) ?? d;

  int? intOrNull(String k) {
    final v = this[k];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  int i(String k, [int d = 0]) => intOrNull(k) ?? d;

  double? dblOrNull(String k) {
    final v = this[k];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  double d(String k, [double d = 0]) => dblOrNull(k) ?? d;

  bool b(String k, [bool d = false]) {
    final v = this[k];
    return v is bool ? v : d;
  }

  List<Json> list(String k) {
    final v = this[k];
    if (v is! List) return const [];
    return [
      for (final e in v)
        if (e is Map) e.cast<String, dynamic>(),
    ];
  }

  List<String> strings(String k) {
    final v = this[k];
    if (v is! List) return const [];
    return [
      for (final e in v)
        if (e != null) '$e',
    ];
  }

  Json? obj(String k) {
    final v = this[k];
    return v is Map ? v.cast<String, dynamic>() : null;
  }
}

/// Removes null values so PATCH bodies only carry the fields the user touched.
Json compact(Json j) => {
  for (final e in j.entries)
    if (e.value != null) e.key: e.value,
};
