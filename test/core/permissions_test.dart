import 'package:flutter_test/flutter_test.dart';
import 'package:gym_book_app/core/auth/permissions.dart';

void main() {
  group('roleCan', () {
    test('owner can do everything', () {
      expect(roleCan('owner', Perm.financeWrite), isTrue);
      expect(roleCan('owner', 'anything.at.all'), isTrue);
    });
    test('manager cannot read trainer-self area', () {
      expect(roleCan('manager', Perm.membersWrite), isTrue);
      expect(roleCan('manager', Perm.trainerSelf), isFalse);
    });
    test('staff cannot write plans or manage staff', () {
      expect(roleCan('staff', Perm.plansWrite), isFalse);
      expect(roleCan('staff', Perm.staffWrite), isFalse);
      expect(roleCan('staff', Perm.membersWrite), isTrue);
    });
    test('trainer is limited', () {
      expect(roleCan('trainer', Perm.financeRead), isFalse);
      expect(roleCan('trainer', Perm.plansetsWrite), isTrue);
    });
    test('membership requests: the front desk reads them, only the owner and managers decide, trainers see none', () {
      expect(roleCan('owner', Perm.requestsWrite), isTrue);
      expect(roleCan('manager', Perm.requestsWrite), isTrue);
      expect(roleCan('staff', Perm.requestsRead), isTrue);
      expect(roleCan('staff', Perm.requestsWrite), isFalse);
      expect(roleCan('trainer', Perm.requestsRead), isFalse);
    });
    test('unknown or null role gets nothing', () {
      expect(roleCan(null, Perm.membersRead), isFalse);
      expect(roleCan('intruder', Perm.membersRead), isFalse);
    });
  });
}
