import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_book_app/core/network/api_exception.dart';
import 'package:gym_book_app/core/state/async_cubit.dart';

void main() {
  blocTest<AsyncCubit<int>, AsyncState<int>>(
    'emits loading then data',
    build: () => AsyncCubit<int>(() async => 7, autoLoad: false),
    act: (c) => c.load(),
    expect: () => [
      isA<AsyncState<int>>().having((s) => s.isLoading, 'loading', true),
      isA<AsyncState<int>>().having((s) => s.data, 'data', 7),
    ],
  );
  blocTest<AsyncCubit<int>, AsyncState<int>>(
    'emits failure with ApiException and keeps no data',
    build: () => AsyncCubit<int>(
      () async => throw ApiException(status: 500, code: 'E', message: 'boom'),
      autoLoad: false,
    ),
    act: (c) => c.load(),
    expect: () => [
      isA<AsyncState<int>>(),
      isA<AsyncState<int>>().having((s) => s.error?.message, 'message', 'boom'),
    ],
  );
  test('refresh keeps previous data while reloading', () async {
    var n = 0;
    final c = AsyncCubit<int>(() async => ++n, autoLoad: false);
    await c.load();
    final seen = <AsyncState<int>>[];
    final sub = c.stream.listen(seen.add);
    await c.refresh();
    await sub.cancel();
    expect(seen.first.data, 1);
    expect(seen.first.refreshing, isTrue);
    expect(c.state.data, 2);
    await c.close();
  });
  test('stale responses are discarded', () async {
    final slow = <int>[];
    var call = 0;
    final c = AsyncCubit<int>(() async {
      final mine = ++call;
      if (mine == 1) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      slow.add(mine);
      return mine;
    }, autoLoad: false);
    final a = c.load();
    final b = c.load();
    await Future.wait([a, b]);
    expect(c.state.data, 2);
    await c.close();
  });
}
