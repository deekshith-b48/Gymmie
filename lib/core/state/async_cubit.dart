import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../network/api_client.dart';
import '../network/api_exception.dart';
import '../util/json.dart';

enum LoadStatus { loading, data, error }

/// Loading / data / error state for a single async value.
class AsyncState<T> {
  const AsyncState._(this.status, this.data, this.error, this.refreshing);
  const AsyncState.loading() : this._(LoadStatus.loading, null, null, false);
  const AsyncState.data(T data, {bool refreshing = false})
    : this._(LoadStatus.data, data, null, refreshing);
  const AsyncState.failure(ApiException error, {T? previous})
    : this._(LoadStatus.error, previous, error, false);

  final LoadStatus status;
  final T? data;
  final ApiException? error;
  final bool refreshing;

  bool get isLoading => status == LoadStatus.loading;
  bool get hasData => data != null;
}

ApiException toApiException(Object e) => e is ApiException
    ? e
    : ApiException.unexpected(
        kDebugMode ? '$e' : 'Something went wrong. Please try again later.',
      );

/// Cubit that loads one value with [loader]; `refresh()` keeps showing the previous value.
class AsyncCubit<T> extends Cubit<AsyncState<T>> {
  AsyncCubit(this.loader, {bool autoLoad = true})
    : super(const AsyncState.loading()) {
    if (autoLoad) load();
  }

  final Future<T> Function() loader;
  int _gen = 0;

  Future<void> load() async {
    final gen = ++_gen;
    emit(const AsyncState.loading());
    await _run(gen);
  }

  Future<void> refresh() async {
    final gen = ++_gen;
    final prev = state.data;
    if (prev != null) emit(AsyncState.data(prev, refreshing: true));
    await _run(gen);
  }

  /// Replace the value locally (optimistic update after a successful mutation).
  void set(T value) => emit(AsyncState.data(value));

  Future<void> _run(int gen) async {
    try {
      final v = await loader();
      if (gen == _gen && !isClosed) emit(AsyncState.data(v));
    } catch (e) {
      if (gen == _gen && !isClosed) {
        emit(AsyncState.failure(toApiException(e), previous: state.data));
      }
    }
  }
}

/// State for a server-paginated list.
class PagedState<T> {
  const PagedState({
    this.items = const [],
    this.page = 0,
    this.totalPages = 1,
    this.total = 0,
    this.status = LoadStatus.loading,
    this.loadingMore = false,
    this.error,
    this.meta = const {},
  });

  final List<T> items;
  final int page;
  final int totalPages;
  final int total;
  final LoadStatus status;
  final bool loadingMore;
  final ApiException? error;
  final Json meta;

  bool get hasMore => page < totalPages;
  bool get isLoading => status == LoadStatus.loading;

  PagedState<T> copyWith({
    List<T>? items,
    int? page,
    int? totalPages,
    int? total,
    LoadStatus? status,
    bool? loadingMore,
    ApiException? error,
    bool clearError = false,
    Json? meta,
  }) => PagedState<T>(
    items: items ?? this.items,
    page: page ?? this.page,
    totalPages: totalPages ?? this.totalPages,
    total: total ?? this.total,
    status: status ?? this.status,
    loadingMore: loadingMore ?? this.loadingMore,
    error: clearError ? null : (error ?? this.error),
    meta: meta ?? this.meta,
  );
}

/// Cubit for paginated lists with a mutable query (search / filter / sort).
class PagedCubit<T> extends Cubit<PagedState<T>> {
  PagedCubit({
    required this.fetch,
    required this.parse,
    Json query = const {},
    this.pageSize = 20,
    bool autoLoad = true,
  }) : _query = Map.of(query),
       super(const PagedState()) {
    if (autoLoad) reload();
  }

  final Future<ApiResponse> Function(int page, int limit, Json query) fetch;
  final T Function(Json) parse;
  final int pageSize;
  Json _query;
  int _gen = 0;

  Json get query => Map.unmodifiable(_query);

  Future<void> setQuery(Json q) {
    _query = Map.of(q);
    return reload();
  }

  Future<void> updateQuery(Json patch) {
    _query = {..._query, ...patch}
      ..removeWhere((k, v) => v == null || (v is String && v.isEmpty));
    return reload();
  }

  Future<void> reload() async {
    final gen = ++_gen;
    emit(PagedState<T>(status: LoadStatus.loading, items: state.items));
    try {
      final r = await fetch(1, pageSize, _query);
      if (gen != _gen || isClosed) return;
      emit(
        PagedState<T>(
          items: r.list.map(parse).toList(),
          page: r.page,
          totalPages: r.totalPages,
          total: r.total,
          status: LoadStatus.data,
          meta: r.meta,
        ),
      );
    } catch (e) {
      if (gen != _gen || isClosed) return;
      emit(PagedState<T>(status: LoadStatus.error, error: toApiException(e)));
    }
  }

  Future<void> loadMore() async {
    if (state.loadingMore ||
        !state.hasMore ||
        state.status != LoadStatus.data) {
      return;
    }
    final gen = _gen;
    emit(state.copyWith(loadingMore: true));
    try {
      final r = await fetch(state.page + 1, pageSize, _query);
      if (gen != _gen || isClosed) return;
      emit(
        state.copyWith(
          items: [...state.items, ...r.list.map(parse)],
          page: r.page,
          totalPages: r.totalPages,
          total: r.total,
          loadingMore: false,
          meta: r.meta,
        ),
      );
    } catch (e) {
      if (gen != _gen || isClosed) return;
      emit(state.copyWith(loadingMore: false, error: toApiException(e)));
    }
  }

  /// Local helpers for optimistic updates.
  void replaceWhere(bool Function(T) test, T Function(T) update) => emit(
    state.copyWith(
      items: [for (final i in state.items) test(i) ? update(i) : i],
    ),
  );
  void removeWhere(bool Function(T) test) {
    final next = state.items.where((i) => !test(i)).toList();
    emit(
      state.copyWith(
        items: next,
        total: (state.total - (state.items.length - next.length)).clamp(
          0,
          1 << 30,
        ),
      ),
    );
  }
}
