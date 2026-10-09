import 'package:flutter_test/flutter_test.dart';
import 'package:gym_book_app/core/network/api_exception.dart';

void main() {
  test('status maps to failure kind', () {
    ApiException e(int s) => ApiException(status: s, code: 'X', message: 'm');
    expect(e(401).kind, ApiFailure.unauthorized);
    expect(e(403).kind, ApiFailure.forbidden);
    expect(e(404).kind, ApiFailure.notFound);
    expect(e(409).kind, ApiFailure.conflict);
    expect(ApiException.network().kind, ApiFailure.network);
  });
}
