import 'package:flutter_test/flutter_test.dart';
import 'package:gym_book_app/core/util/format.dart';

void main() {
  test('plural', () {
    expect(Fmt.plural(1, 'day'), '1 day');
    expect(Fmt.plural(3, 'day'), '3 days');
    expect(Fmt.plural(2, 'person', 'people'), '2 people');
  });
  test('initials', () {
    expect(Fmt.initials('Iron Temple'), 'IT');
    expect(Fmt.initials(''), isNotNull);
  });
  test('money uses Indian digit grouping', () {
    expect(Fmt.money(1234567), contains('12,34,567'));
  });
  test('ymd', () => expect(Fmt.ymd(DateTime(2026, 3, 5)), '2026-03-05'));
}
